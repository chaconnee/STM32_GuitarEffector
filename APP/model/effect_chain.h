#ifndef __EFFECT_CHAIN_H__
#define __EFFECT_CHAIN_H__

#include "model/effect.h"

void EffectChain_Init(void);
bool EffectChain_Add(Effect *effect);
void EffectChain_RemoveAt(uint8_t index);
void EffectChain_Clear(void);
uint8_t EffectChain_GetCount(void);
Effect *EffectChain_GetAt(uint8_t index);
void EffectChain_Process(float *buf, uint16_t len);

#endif
