#ifndef __EFFECT_H__
#define __EFFECT_H__

#include <stdint.h>
#include <stdbool.h>

#define EFFECT_CHAIN_MAX  8

typedef struct effect_s Effect;

struct effect_s
{
    const char *name;
    bool bypassed;

    void (*process)(Effect *self, float *in, float *out, uint16_t len);
    void (*set_param)(Effect *self, uint8_t param_id, float value);
    void (*init)(Effect *self);
    void (*destroy)(Effect *self);

    void *data;
};

#endif
