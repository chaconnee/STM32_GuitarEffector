#include "model/effect_chain.h"
#include "main.h"
#include <string.h>

static Effect *chain[EFFECT_CHAIN_MAX];
static uint8_t chain_count = 0;
static float aux_buf[AUDIO_BUFFER_SIZE];

void EffectChain_Init(void)
{
    chain_count = 0;
}

bool EffectChain_Add(Effect *effect)
{
    if (effect == NULL || chain_count >= EFFECT_CHAIN_MAX)
        return false;
    chain[chain_count] = effect;
    if (chain[chain_count]->init)
        chain[chain_count]->init(chain[chain_count]);
    chain_count++;
    return true;
}

void EffectChain_RemoveAt(uint8_t index)
{
    if (index >= chain_count) return;
    if (chain[index]->destroy)
        chain[index]->destroy(chain[index]);
    for (uint8_t i = index; i < chain_count - 1; i++)
        chain[i] = chain[i + 1];
    chain[chain_count - 1] = NULL;
    chain_count--;
}

void EffectChain_Clear(void)
{
    for (uint8_t i = 0; i < chain_count; i++)
    {
        if (chain[i]->destroy)
            chain[i]->destroy(chain[i]);
        chain[i] = NULL;
    }
    chain_count = 0;
}

uint8_t EffectChain_GetCount(void)
{
    return chain_count;
}

Effect *EffectChain_GetAt(uint8_t index)
{
    if (index >= chain_count) return NULL;
    return chain[index];
}

void EffectChain_Process(float *buf, uint16_t len)
{
    float *current_in = buf;
    float *current_out = aux_buf;

    for (uint8_t i = 0; i < chain_count; i++)
    {
        if (chain[i]->bypassed)
            continue;

        bool is_last = true;
        for (uint8_t j = i + 1; j < chain_count; j++)
        {
            if (!chain[j]->bypassed)
            {
                is_last = false;
                break;
            }
        }
        if (is_last)
            current_out = buf;

        chain[i]->process(chain[i], current_in, current_out, len);

        float *tmp = current_in;
        current_in = current_out;
        current_out = tmp;
    }

    if (current_in != buf)
        memcpy(buf, current_in, len * sizeof(float));
}
