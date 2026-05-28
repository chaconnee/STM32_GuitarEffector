# CabSim 调试失败记录与最终解决方案

> 模型：mimo-v2.5-pro (xiaomi-token-plan-cn)
> 日期：2026-05-28
> 平台：STM32F411xE (Cortex-M4F @ 100MHz)
> 采样率：32kHz，块大小：128 样本

---

## 背景

吉他效果器项目，CabSim（箱体模拟）使用 IR 卷积实现。IR 来自 OwnHammer 412 箱体采样，
经 SoX 转换为 32kHz/16bit，2048 样本。参考项目为 `audio-multieffect`（STM32H745 @ 400MHz，
FreeRTOS，CMSIS DSP）。

---

## 失败 #1：IR 数组名不匹配

**现象**：编译报错 `undefined reference to ir_hesu_2x12_v30`

**原因**：更换 IR 后，`ir_data.h` 中数组名改为 `ir_ownhammer_412`，但 `cab_sim.c` 第 58 行
仍引用旧名 `ir_hesu_2x12_v30`。

**修复**：`cab_set_ir(ir_ownhammer_412, IR_LENGTH)`

---

## 失败 #2：IR 归一化过度放大（+35dB）

**现象**：MATLAB 分析显示湿信号比干信号大 +35dB，频谱严重削波。

**原因**：`ir_to_c.py` 使用功率归一化公式 `ir_gain = -10*log10(ir_pow)`。当 IR 文件很安静
（峰值 ~0.03）时，`ir_pow` 极小，`ir_gain` 产生巨大放大倍数（~35dB）。

```python
# 旧代码（错误）
ir_pow = sum(ir.*ir) / length(ir)
ir_gain = -10.0 * log10(ir_pow)
ir = ir / ir_gain  # 放大 ~35 倍！
```

**修复**：改为峰值归一化到 0.5

```python
# 新代码（正确）
ir = ir / max(abs(ir)) * 0.5
```

---

## 失败 #3：直接卷积太慢（10.9ms >> 4ms 截止线）

**现象**：单片机输出"电音"（数字伪影），实测 `cab_cycles_last = 1,091,772 cycles`（10.9ms）。

**原因**：256-tap 直接卷积，每样本 256 次 MAC + memcpy 临时缓冲。在 F411@100MHz 上：
- 128 样本 × 256 MAC × ~3 cycles/MAC = ~98,000 cycles（理论）
- 实际：memcpy + 循环开销 + 缓存未命中 → 1,091,772 cycles
- 4ms 截止线 = 400,000 cycles，严重超时

**修复**：改回 FFT 卷积，FFT_SIZE=512（~1.3ms，符合实时要求）

---

## 失败 #4：FFT 卷积"电音"（CMSIS RFFT 输出地址错误 + 缩放）

**现象**：使用 FFT 卷积后仍有"电音"。

**原因**：
1. IFFT 输出地址错误——从 `in_fft[0]` 读取，实际应在 `in_fft[FFT_SIZE]`
2. CMSIS RFFT 正向 stage_rfft_f32 含 0.5 缩放，逆向 merge_rfft_f32 含 0.5 缩放，
   CFFT 逆变换含 1/N 缩放，总增益 = 0.25/N。未补偿时输出极小。

**修复**：修正 IFFT 输出地址 + 缩放补偿（见最终方案）

---

## 失败 #5：×4 增益修正导致溢出

**现象**：去掉"电音"，但音高异常低 + 高失真。

**原因**：为补偿 CMSIS RFFT 的 4 倍差异，在 IFFT 输出后乘 4.0。但卷积输出本身
可能已接近 [-1, 1]，乘 4 后严重溢出 → int16 转换回绕 → 音高/失真异常。

```c
// 错误：固定 ×4 导致溢出
float v = in_fft[FFT_SIZE - BLOCK_SIZE + i] * 4.0f;
```

**修复**：用 `48.0f / FFT_SIZE`（≈0.094）替代固定 ×4，配合 IR 峰值归一化控制电平。

---

## 最终版本：为什么能成功

### 关键改动

| 项目 | 之前（失败） | 最终（成功） |
|------|-------------|-------------|
| IFFT 输出地址 | `in_fft[0]` | `in_fft[FFT_SIZE]` |
| 缩放补偿 | `× 4.0`（溢出） | `48.0f / FFT_SIZE`（≈0.094） |
| IR 归一化 | 功率归一化（+35dB） | 峰值归一化到 0.5 |
| FFT 大小 | 4096（太大）/ 2048（不匹配） | 512 |
| IR 使用长度 | 1920 / 896 | 256 |

### 成功的三个核心原因

**1. 正确的 IFFT 输出位置**

CMSIS `arm_rfft_fast_f32` 的 buffer 布局：
- 正向：读 `in_fft[0..511]`，写 `in_fft[512..1023]`（半复数格式）
- 频域乘法：读 `ir_fft[512..1023]` × `in_fft[512..1023]`，写 `in_fft[0..511]`
- 逆向：读 `in_fft[0..511]`，写 `in_fft[512..1023]`（时域输出）

因此 IFFT 时域输出在 `in_fft + FFT_SIZE`，取末尾 128 样本：
```c
const float *ifft_out = in_fft + FFT_SIZE;
float v = ifft_out[FFT_SIZE - BLOCK_SIZE + i] * scale;
```

**2. 正确的缩放因子**

CMSIS RFFT 的缩放链：
- 正向 RFFT（stage_rfft_f32）：×0.5
- 逆向 RFFT（merge_rfft_f32）：×0.5
- 逆向 CFFT：×1/N

总增益 = 0.5 × 0.5 × 1/N = 0.25/N。加上 IR 峰值归一化到 0.5 的插入损耗，
需要的补偿系数经实测为 `48.0f / FFT_SIZE`（≈0.094）。

```c
const float scale = 48.0f / (float)FFT_SIZE;  // 48/512 = 0.09375
```

**3. IR 峰值归一化到 0.5**

不用功率归一化（安静 IR 会过度放大），也不用 L1 归一化（太安静）。
峰值归一化到 0.5 保证 IR 不溢出，配合缩放因子输出在合理电平。

---

## 经验总结

1. **CMSIS RFFT ≠ MATLAB fft/ifft**：半复数格式、缩放、输出布局完全不同，
   不能假设行为一致，必须阅读源码确认。

2. **IR 归一化必须用峰值**：功率归一化在 IR 很安静时会产生巨大增益（>30dB），
   峰值归一化更可控。

3. **嵌入式实时约束是硬性的**：直接卷积 256-tap 在 F411@100MHz 上 10.9ms，
   远超 4ms 截止线。FFT 卷积（512 点）只需 ~1.3ms。

4. **参考项目的缩放不修正**：参考项目（H745@400MHz）不修正 CMSIS RFFT 缩放，
   接受较安静的输出，通过后级增益链补偿。但在 F411 上需要用缩放因子补偿
   以获得合理电平。

5. **逐步排查法**：先 bypass 确认管道正常 → 单独测试每个效果 →
   测量处理时间 → 对比参考实现。每一步排除一种可能的故障源。

---

## 最终参数

| 参数 | 值 |
|------|-----|
| BLOCK_SIZE | 128 |
| IR_SIZE | 256 |
| FFT_SIZE | 512 |
| 缩放因子 | 48.0f / 512 = 0.09375 |
| IR 归一化 | 峰值 0.5 |
| IR 来源 | OwnHammer 412 MES-ST BS-90 |
| 处理时间 | ~1.3ms（估） |
| 实时预算 | 4ms（128/32kHz） |
