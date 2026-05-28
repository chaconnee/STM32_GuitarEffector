#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#define ARM_MATH_CM4
#include "arm_math.h"
#include "arm_const_structs.h"

#define CAB_SIM_BLOCK_SIZE 128
#define CAB_SIM_IR_SIZE    1024
#define CAB_SIM_FFT_SIZE   2048

typedef struct {
    arm_rfft_fast_instance_f32 fft;
    float ir_fft[2 * CAB_SIM_FFT_SIZE];
    float input_fft[2 * CAB_SIM_FFT_SIZE];
    float input_buf[CAB_SIM_FFT_SIZE];
} cab_sim_data_t;

static cab_sim_data_t cab_data;

void init() {
    arm_rfft_fast_init_f32(&cab_data.fft, CAB_SIM_FFT_SIZE);
    memset(cab_data.ir_fft, 0, sizeof(cab_data.ir_fft));
    memset(cab_data.input_buf, 0, sizeof(cab_data.input_buf));
    
    // Create impulse IR
    cab_data.ir_fft[0] = 1.0f; 
    arm_rfft_fast_f32(&cab_data.fft, cab_data.ir_fft, cab_data.ir_fft + CAB_SIM_FFT_SIZE, 0);
}

void process(float *in, float *out) {
    const uint32_t move_size = CAB_SIM_FFT_SIZE - CAB_SIM_BLOCK_SIZE;

    memmove(cab_data.input_buf, cab_data.input_buf + CAB_SIM_BLOCK_SIZE, move_size * sizeof(float));
    memcpy(cab_data.input_buf + move_size, in, CAB_SIM_BLOCK_SIZE * sizeof(float));

    memcpy(cab_data.input_fft, cab_data.input_buf, CAB_SIM_FFT_SIZE * sizeof(float));
    arm_rfft_fast_f32(&cab_data.fft, cab_data.input_fft, cab_data.input_fft + CAB_SIM_FFT_SIZE, 0);

    arm_cmplx_mult_cmplx_f32(cab_data.ir_fft + CAB_SIM_FFT_SIZE, 
                             cab_data.input_fft + CAB_SIM_FFT_SIZE, 
                             cab_data.input_fft, 
                             CAB_SIM_FFT_SIZE / 2);
    
    cab_data.input_fft[0] = cab_data.ir_fft[CAB_SIM_FFT_SIZE] * cab_data.input_fft[CAB_SIM_FFT_SIZE];
    cab_data.input_fft[1] = cab_data.ir_fft[CAB_SIM_FFT_SIZE + 1] * cab_data.input_fft[CAB_SIM_FFT_SIZE + 1];

    arm_rfft_fast_f32(&cab_data.fft, cab_data.input_fft, cab_data.input_fft + CAB_SIM_FFT_SIZE, 1);

    memcpy(out, cab_data.input_fft + (2 * CAB_SIM_FFT_SIZE) - CAB_SIM_BLOCK_SIZE, CAB_SIM_BLOCK_SIZE * sizeof(float));
}

int main() {
    init();
    
    float buf[128];
    for(int b=0; b<10; b++) {
        for(int i=0; i<128; i++) {
            buf[i] = sinf(2.0 * 3.1415926 * 440.0 * (b * 128 + i) / 32000.0);
        }
        process(buf, buf);
        printf("Block %d, sample 0: %f\n", b, buf[0]);
    }

    return 0;
}
