# STM32 吉他效果器音频流与 DSP 架构设计

## 1. 核心底座：32kHz 零误差 + DMA 硬件乒乓缓冲

音频系统底层绝不使用普通的单数组或者软件 FIFO 拷贝，而是利用 STM32 DMA 提供的 **Circular (循环) 模式** 加上 `Half-Transfer (HT)` 和 `Transfer-Complete (TC)` 双中断，构成**硬件级双缓冲 (Ping-Pong Buffer)**。

### 1.1 时钟与同步策略
* 通过配置 I2S 专用锁相环 PLLI2S 实现绝对无畸变的 `32.000 kHz` 播放频率。
* 调节与匹配 TIM2 的定时器频率到严格对应的 `32000 Hz` 用于触发 ADC 采样。
* 彻底解决两个时钟域不同步造成的“滑音”、“丢帧咔哒声”。

### 1.2 内存布局 (基于单帧 128 采样点)
- **ADC 半字缓冲区 (uint16_t)**：容量 `128 * 2 = 256`。
- **DSP 浮点缓冲区 (float)**：用来进行精度极高的浮点效果换算，位于 SRAM 核心区。需要两块等大的 `dsp_buffer`。
- **I2S 立体声缓冲区 (int16_t)**：容量 `128 * 2个通道 * 2(双缓冲块) = 512`。这是当前项目中因未对齐引发内存越界宕机的关键修复点。

## 2. DSP 效果器链架构 (Effect Chain)

为了实现吉他效果链，我们提炼了业内标准的**动态双层接力链架构** (In-place Swap) 作为本项目最佳实践：

**1. 模块化标准接口**
定义一个统一的结构体：
```c
typedef void (*EffectProcess_t)(float* input, float* output, uint16_t length);
typedef struct {
    uint8_t is_bypassed;
    EffectProcess_t process;
    void* params; // 指向具体效果器的参数结构
} EffectModule;
```

**2. 核心魔法：指向互换的 Buffer**
准备两块尺寸同为 128 的浮点数组 `float bufA[128]` 和 `float bufB[128]`。
* 当系统捕获到一帧干音，送入 `bufA`。
* 设置工作游标：`float* current_input = bufA;` , `float* current_output = bufB;`
* **循环遍历整个效果器大名单**：
  ```c
  for (int i = 0; i < effect_count; i++) {
      if (!effects[i].is_bypassed) {
          // 当前效果器读取 input 的波形，加上效果后写入 output
          effects[i].process(current_input, current_output, 128);
          // 【核心】：交换指针，让刚才的输出变成下个节点的输入
          float* temp = current_input;
          current_input = current_output;
          current_output = temp;
      }
  }
  ```
* 循环结束后，游标 `current_input` 指向的那块内存，就是完全叠加后的最终波形。随后即可将其转为整型并经 DMA 馈入 I2S。

---

## 3. 参考项目 A 深度解析：`audio-multieffect` (现代 C++ 架构)
该项目采用现代 DSP 插件级别的架构思路，是**高度成熟、可扩展商业级固件的首选模式典范**。

### 3.1 核心实现特点：
1. **面向对象与多态接口**：将所有效果器（`tuner`, `chorus`, `reverb`, `phaser` 等）全部继承自统一的一个基类或接口 `effect_interface`。
2. **动态容器挂载**：在 `effect_processor` 控制类中，维护着一个标准动态容器：`std::vector<std::unique_ptr<effect>> effects;`
3. **块状批量处理 (Block Processing)**：该项目是严格基于 Buffer Size 分块运算的，不使用低效的点对点处理运算。
4. **事件驱动 (RTOS Event, IPC)**：底层的外设 DMA 中断 (I2S DMA回调) 只负责释放信号量，而极其消耗 CPU 的 DSP 代码放在专属的 `effect_processor` 中断外部独立任务中执行。

### 3.2 截取关键代码 (乒乓指针 Swap 的真实例子)：
下面展示了 `audio-multieffect` 中 `effect_processor.cpp` 处理音频块的实现源码摘录：
```cpp
void effect_processor::event_handler(const events::process_audio &e) {
    // 绑定当前输入输出游标 (相当于上一节提到的 bufA 和 bufB)
    std::reference_wrapper<decltype(this->dsp_output)> current_output = this->dsp_output;
    std::reference_wrapper<decltype(this->dsp_main_input)> current_input = this->dsp_main_input;
    
    // 遍历动态效果器链
    for (auto &&effect : this->effects) {
        if (!effect->is_bypassed()) {
            effect->set_aux_input(this->dsp_aux_input);
            // 核心运算：从 input 读取，写入 output
            effect->process(current_input, current_output);
            
            // 【神来之笔】：Swap 交换指针，使得上一个效果器的输出作为下一个的输入
            std::swap(current_input, current_output);
        }
    }
    // 结束后修正指针，送往底层 I2S 发音
    current_output = current_input;
    // ... 后续为 Float 转 int 并赋值给 I2S 硬件缓冲的代码 ...
}
```
**总结**：设计极其优雅！它保证了内存利用率的最大化（永远只用两块缓冲，却能串联无数个效果器）。

---

## 4. 参考项目 B 深度解析：`guitar-effector-main` (传统 C 语言单点架构)
该项目采用的是业余单片机开发中常见的原始“过程式/中断阻塞式”写法，能出声，但隐患和性能瓶颈都很大。

### 4.1 核心实现特点：
1. **纯硬件中断层计算 (阻塞高)**：由于没有 RTOS 调度，项目直接在 I2S 的 `HAL_I2SEx_TxRxHalfCpltCallback` 硬件 DMA 中断里面完成了所有 DSP 计算，极其危险（会挤占整个系统响应或导致堆栈溢出甚至断音）。
2. **单点处理 (Point-by-point Processing)**：放弃了分块运算带来的 SIMD 指令优势，在中断里写了一个 for 循环，每次只处理 **1个音频采样点**。
3. **彻底锁死的硬编码效果链**：不具备动态交换顺序的可能，各个效果器的排布全靠大批的 `if ... else ...` 串联。

### 4.2 截取关键代码：
该项目的 `effect_chain.c` 源码摘录：
```c
// 中断内部直接做 for 循环
void HAL_I2SEx_TxRxHalfCpltCallback(I2S_HandleTypeDef *hi2s) {
    for (int i = 0; i < EFFECT_BUF_LEN / 2; i++) {
        effect_process(i); // 一次只调用一滴水，而不是处理一杯水
    }
}

static inline void effect_process(int index) {
    uint32_t rxfloatbuffer_idx = index;
    // ... [模数转换操作省略] ...
    
    // ======================================
    // 以下部分是彻底锁死的“硬编码接线”
    // ======================================
    // 第1层：永远插在最前列的调音表
    if (g_effect_controller.tune_switch) {
        tuner_function(rxfloatbuffer[rxfloatbuffer_idx].right_audio, g_effect_controller.tune_switch);
    } else {
        // 第2层：永远紧接在调音表之后的 Boost
        if (g_effect_controller.boost_switch) {
            rxfloatbuffer[rxfloatbuffer_idx].right_audio *= g_effect_controller.boost_level;
        }
        
        // 第3层：只能排在第三位的 Overdrive 过载模块
        if (g_effect_controller.od_switch) {
            // ... 经过一些滤波器操作 ...
        }
        
        // 第4层：放在最后面的 Tremolo 颤音或 Reverb 混响
        if (g_effect_controller.reberb_switch) {
            rxfloatbuffer[rxfloatbuffer_idx].right_audio *= update_tremolo(...);
        }
    }
}
```
**总结**：这是一种典型的面向初学者的单片机编码范式，优点是一目了然，结构简单。
但在音频 DSP 领域这是**致命反面素材**——如果未来增加了新的效果器，或者用户希望能把延时效果放在失真效果的前面，开发将毫无应对之力，因为底层架构被代码的上下文物理顺序完全霸穿了。此外，中断内执行导致 CPU 分配失衡。

---
**总体开发建议**：我们的项目应该**弃用**项目 B 的硬编码与点运算，坚定地**吸取与靠拢**项目 A 在主循环 (或 RTOS 线程) 中处理 128 采样块并采用动态双缓冲交换的设计。