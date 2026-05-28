#include "amp_sim.h"
#include <math.h>



#define TWO_PI_F    6.283185307179586f
#define SAMPLE_RATE 32000.0f
#define HPF_FC      80.0f       /* 低切频率 */
#define LPF_FC      4500.0f     /* 高切频率 */
#define DRIVE_MAX   25.0f       /* gain=1 时的放大倍数 */

/* ── 滤波器参数 ── */
static float lo_cut_z;              /* 低切: 内部一阶LPF状态 y[n-1] */
static float lo_cut_a;              /* 低切: 系数 1 - e^(-2π*fc/fs) */

static float hi_cut_z1, hi_cut_z2;  /* 高切: 两阶级联状态 */
static float hi_cut_a;              /* 高切: 共用系数 */

/* ── 用户参数 ── */
static float drive  = 0.50f;
static float volume = 0.4f;

static void amp_init(Effect *self)
{
    (void)self;
    lo_cut_z   = 0.0f;
    hi_cut_z1  = 0.0f;
    hi_cut_z2  = 0.0f;

    lo_cut_a   = 1.0f - expf(-TWO_PI_F * HPF_FC / SAMPLE_RATE);
    hi_cut_a   = 1.0f - expf(-TWO_PI_F * LPF_FC / SAMPLE_RATE);
}

static void amp_process(Effect *self, float *in, float *out, uint16_t len)
{
    (void)self;
    float g = drive * DRIVE_MAX + 1.0f;

    for (uint16_t i = 0; i < len; i++) {
        float s = in[i];

        /* 低切: s - LPF(s) → 去掉 80Hz 以下 */
        lo_cut_z += lo_cut_a * (s - lo_cut_z);
        s -= lo_cut_z;

        /* 增益 → 推入失真区 */
        s *= g;

        /* tanh 软削波 */
        s = tanhf(s);

        /* 高切 12dB/oct → 抹掉 4.5kHz 以上的削波毛刺 */
        hi_cut_z1 += hi_cut_a * (s - hi_cut_z1);
        s  = hi_cut_z1;
        hi_cut_z2 += hi_cut_a * (s - hi_cut_z2);
        s  = hi_cut_z2;

        /* 音量 + 限幅 */
        s *= volume;
        if (s >  1.0f) s =  1.0f;
        if (s < -1.0f) s = -1.0f;

        out[i] = s;
    }
}

static void amp_set_param(Effect *self, uint8_t param_id, float value)
{
    (void)self;
    switch (param_id) {
        case 0: drive  = value; break;
        case 1: volume = value; break;
    }
}

Effect amp_sim_effect = {
    .name      = "AmpSim",
    .bypassed  = 0,
    .process   = amp_process,
    .set_param = amp_set_param,
    .init      = amp_init,
    .destroy   = 0,
    .data      = 0
};
