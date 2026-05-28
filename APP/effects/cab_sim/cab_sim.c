#include "cab_sim.h"
#include "arm_math.h"
#include <string.h>
#include "main.h"

#include "effects/cab_sim/ir_data.h"

/*
 * Overlap-save fast convolution
 *
 * CMSIS arm_rfft_fast_f32 正/反向均不做 1/N 缩放, 频域相乘后
 * 累积增益为 N^n, 导致 int16 输出饱和. IFFT 后除以 N 消除.
 *
 * IR 峰值归一化到 0.5, 结合 RFFT 缩放, 输出控制在 int16 范围内
 */

#define BLOCK_SIZE  128
#define IR_SIZE     256
#define FFT_SIZE    512
#define FFT_SIZE_X2 (FFT_SIZE * 2)

static arm_rfft_fast_instance_f32 fft_inst;

static float ir_fft   [FFT_SIZE_X2];
static float in_fft   [FFT_SIZE_X2];
static float slide_buf[FFT_SIZE];

static volatile uint32_t cab_cycles_max;
static volatile uint32_t cab_cycles_last;
static volatile float    cab_out_peak;

static void cab_init(Effect *self)
{
    (void)self;

    arm_rfft_fast_init_f32(&fft_inst, FFT_SIZE);

    /* 加载 IR: 取前 IR_SIZE 个样本, 峰值归一化到 0.5 */
    float ir_tmp[FFT_SIZE];
    memset(ir_tmp, 0, sizeof(ir_tmp));
    uint32_t copy_len = IR_LENGTH < IR_SIZE ? IR_LENGTH : IR_SIZE;
    memcpy(ir_tmp, ir_ownhammer_412, copy_len * sizeof(float));

    float peak = 0.0f;
    for (uint32_t i = 0; i < copy_len; i++) {
        float a = ir_tmp[i] > 0.0f ? ir_tmp[i] : -ir_tmp[i];
        if (a > peak) peak = a;
    }
    if (peak > 0.0f) {
        float scale = 0.5f / peak;
        for (uint32_t i = 0; i < copy_len; i++)
            ir_tmp[i] *= scale;
    }

    /* 预计算 IR 的 FFT */
    memset(ir_fft, 0, sizeof(ir_fft));
    memcpy(ir_fft, ir_tmp, FFT_SIZE * sizeof(float));
    arm_rfft_fast_f32(&fft_inst, ir_fft, ir_fft + FFT_SIZE, 0);

    memset(slide_buf, 0, sizeof(slide_buf));
    memset(in_fft, 0, sizeof(in_fft));

    CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
    DWT->CYCCNT = 0;
    DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

static void cab_process(Effect *self, float *in, float *out, uint16_t len)
{
    (void)self;
    (void)len;

    uint32_t t0 = DWT->CYCCNT;

    /* 1. 滑动窗口 */
    memmove(slide_buf, slide_buf + BLOCK_SIZE, (FFT_SIZE - BLOCK_SIZE) * sizeof(float));
    memcpy(slide_buf + (FFT_SIZE - BLOCK_SIZE), in, BLOCK_SIZE * sizeof(float));

    /* 2. 正向 FFT */
    memcpy(in_fft, slide_buf, FFT_SIZE * sizeof(float));
    arm_rfft_fast_f32(&fft_inst, in_fft, in_fft + FFT_SIZE, 0);

    /* 3. 频域乘法 */
    arm_cmplx_mult_cmplx_f32(
        ir_fft + FFT_SIZE,
        in_fft + FFT_SIZE,
        in_fft,
        FFT_SIZE / 2
    );

    /* 4. 逆 FFT */
    arm_rfft_fast_f32(&fft_inst, in_fft, in_fft + FFT_SIZE, 1);

    /* 消除 CMSIS RFFT 累积增益 + IR 插入损耗补偿 */
    const float scale = 48.0f / (float)FFT_SIZE;

    /* 5. 提取有效输出 (IFFT 输出在 in_fft + 512, 取末尾 128 样本) */
    const float *ifft_out = in_fft + FFT_SIZE;
    float peak = 0.0f;
    for (uint16_t i = 0; i < BLOCK_SIZE; i++) {
        float v = ifft_out[FFT_SIZE - BLOCK_SIZE + i] * scale;
        float a = v > 0.0f ? v : -v;
        if (a > peak) peak = a;
        out[i] = v;
    }
    cab_out_peak = peak;

    uint32_t elapsed = DWT->CYCCNT - t0;
    cab_cycles_last = elapsed;
    if (elapsed > cab_cycles_max) cab_cycles_max = elapsed;
}

static void cab_set_param(Effect *self, uint8_t param_id, float value)
{
    (void)self;
    (void)param_id;
    (void)value;
}

Effect cab_sim_effect = {
    .name = "CabSim",
    .bypassed = 0,
    .process = cab_process,
    .set_param = cab_set_param,
    .init = cab_init,
    .destroy = 0,
    .data = 0
};
