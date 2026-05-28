#include "AudioPipeline.h"
#include "model/effect_chain.h"
#include "adc.h"
#include "i2s.h"

#include "effects/amp_sim/amp_sim.h"
#include "effects/cab_sim/cab_sim.h"

static uint16_t adc_buffer[AUDIO_BUFFER_SIZE * 2];
static int16_t  i2s_buffer[AUDIO_BUFFER_SIZE * 2 * 2];
static float    dsp_buffer[AUDIO_BUFFER_SIZE];

static volatile uint8_t adc_half;
static volatile uint8_t adc_pending;

static void Process_Half(uint8_t half)
{
    const uint16_t *src = &adc_buffer[half * AUDIO_BUFFER_SIZE];
    for (uint16_t i = 0; i < AUDIO_BUFFER_SIZE; i++)
    {
        dsp_buffer[i] = ((float)src[i] - 2048.0f) / 2048.0f;
    }

    EffectChain_Process(dsp_buffer, AUDIO_BUFFER_SIZE);

    int16_t *dst = &i2s_buffer[half * AUDIO_BUFFER_SIZE * 2];
    for (uint16_t i = 0; i < AUDIO_BUFFER_SIZE; i++)
    {
        int16_t s = (int16_t)(dsp_buffer[i] * 32767.0f);
        dst[i * 2]     = s;
        dst[i * 2 + 1] = s;
    }
}

void AudioPipeline_Init(void)
{
    EffectChain_Init();
    EffectChain_Add(&amp_sim_effect);
    EffectChain_Add(&cab_sim_effect);
    HAL_ADC_Start_DMA(&hadc1, (uint32_t *)adc_buffer, AUDIO_BUFFER_SIZE * 2);
    HAL_I2S_Transmit_DMA(&hi2s2, (uint16_t *)i2s_buffer, AUDIO_BUFFER_SIZE * 2 * 2);
}

void AudioPipeline_Tick(void)
{
    if (!adc_pending) return;
    adc_pending = 0;
    Process_Half(adc_half);
}

void HAL_ADC_ConvHalfCpltCallback(ADC_HandleTypeDef *hadc) { (void)hadc; adc_half = 0; adc_pending = 1; }
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc)     { (void)hadc; adc_half = 1; adc_pending = 1; }
