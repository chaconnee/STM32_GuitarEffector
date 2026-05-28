# Cab Sim 卷积"电音/静音"调试记录

**日期**: 2026-05-28  
**模型**: Claude (deepseek-v4-pro) via opencode

---

## 原始症状

开启 Amp+Cab 时输出"电音"（刺耳失真），仅 Amp 时正常。

---

## 错误诊断与修复历程

### 错误 1: 误判 I2S DMA 缓冲区竞争

**假设**: I2S TX DMA 自由运行无回调，主循环写入 `i2s_buffer` 时可能被 DMA 同时读取，产生撕裂(tearing)。

**为何错误**:  
- ADC 和 I2S 时钟同为 32kHz，频率锁定不漂移  
- **决定性的反证**: "只开amp_sim时没问题" → 如果是 I2S 竞态，Amp only 也会出现

**教训**: 先排除最简单变量（旁路某个模块）再下结论。

---

### 错误 2: 误算 FFT 增益为 N³

**假设**: `arm_rfft_fast_f32` 正/反均不做 1/N 缩放，总增益 = N³ = 512³。

**为何错误**:  
- `arm_cfft_f32.c:1174-1186` (非 MVE 路径): 逆变换**内置** `1/N_cfft` 缩放（`invL = 1.0f / L`）
- `stage_rfft_f32` 和 `merge_rfft_f32` 各有 ×0.5 因子

**精确推算**:

| 步骤 | 操作 | 增益 |
|------|------|------|
| 正向 RFFT | CFFT(256点,×256) × stage(×0.5) | **×128** |
| 频域相乘 | 128 × 128 | **×16,384** |
| 逆向 RIFFT | merge(×0.5) × CFFT⁻¹(÷256) | **÷512** |
| **总计** | 16384 / 512 | **×32** |

**修正**: scale = `16.0 / FFT_SIZE` = 1/32

**教训**: 不要根据文档描述推测，必须读 CMSIS-DSP **实际源码**——不同版本/编译路径缩放行为不同。

---

### 错误 3 (根因): 提取 IFFT 结果时读错 buffer

**原始代码** (`cab_sim.c:100`):
```c
float v = in_fft[FFT_SIZE - BLOCK_SIZE + i];  // in_fft[384..511]
```

**实际缓冲区布局**:
```
in_fft[0..511]    ← arm_cmplx_mult 写入 (频域乘积, 非时域)
in_fft[512..1023] ← arm_rfft_fast(ifftFlag=1) 输出 (时域音频) ← 应该读!
in_fft[384..511]  ← 当前代码读这里 (错误的 buffer)
```

`arm_rfft_fast_f32(&fft_inst, in_fft, in_fft + FFT_SIZE, 1)` 的**输出参数**是 `in_fft + FFT_SIZE` → IFFT 时域结果在 `in_fft[512..1023]`。

**为什么原始代码会有"电音"而非静音**:  
读的 `in_fft[384..511]` 是复数乘法结果尾部的**频域打包频谱**，值有 ×16,384 增益 → 转 int16 完全饱和 → 方波 → "电音"。

**修正**:
```c
const float *ifft_out = in_fft + FFT_SIZE;
float v = ifft_out[FFT_SIZE - BLOCK_SIZE + i] * scale;
// = in_fft[512 + 384 + i] = in_fft[896..1023]
```

**教训**: 最隐蔽的 bug——算法框架、调用接口都正确，唯独输出索引偏移了整个输出 buffer 的长度。验证方法是检查 CMSIS API 的输入/输出参数流向。

---

### 错误 4: 首次修正 scale 过度衰减

1/512 将 32× 信号压到 0.0625×（-24dB），叠加真实 IR 插入损耗后接近静音。

修正为 3/32 (48/512)，补偿 IR 损耗 ≈3×。

---

## 其他微调

- **按钮行为**: 从只 toggle cab_sim 改为同步 toggle amp_sim + cab_sim（`main.c:132-134`）
- **LED 状态**: ON(LOW) = 效果链激活, OFF(HIGH) = 旁路

---

## 总结

| # | 错误 | 类型 | 修复 |
|---|------|------|------|
| 1 | I2S 缓冲突 | 误判(架构猜测) | 用户反证排除 |
| 2 | FFT 增益 N³ | 数值估算错误 | 读源码 → 1/32 |
| 3 | **读错 buffer** | **索引偏移 bug** | `in_fft[i]` → `in_fft[512+i]` |
| 4 | scale 过度衰减 | 参数校准错误 | 16 → 48 |

**核心教训**: 只要去读 CMSIS-DSP 源码 (arm_cfft_f32.c, arm_rfft_fast_f32.c) 就能一次性解决 #2 和 #3——知道逆变换的输出 buffer 位置和缩放因子。
