#include <stdio.h>
#include <stdint.h>
#include <string.h>
#define ARM_MATH_CM4

#include "arm_math.h"
#include "arm_const_structs.h"

int main() {
    arm_rfft_fast_instance_f32 fft;
    arm_status status = arm_rfft_fast_init_f32(&fft, 2048);
    
    float h[2048] = {0};
    h[0] = 1.0f; // Impulse filter
    float H_fft[2048] = {0};
    arm_rfft_fast_f32(&fft, h, H_fft, 0); 
    
    float x[2048] = {0};
    for(int i=0; i<128; i++) x[1920+i] = 1.0f; // Input signal block
    
    float X_fft[2048] = {0};
    arm_rfft_fast_f32(&fft, x, X_fft, 0); 
    
    // Multiply
    float Y_fft[2048] = {0};
    arm_cmplx_mult_cmplx_f32(H_fft + 2, X_fft + 2, Y_fft + 2, 1023);
    Y_fft[0] = H_fft[0] * X_fft[0];
    Y_fft[1] = H_fft[1] * X_fft[1];
    
    float y[2048] = {0};
    arm_rfft_fast_f32(&fft, Y_fft, y, 1); 
    
    printf("y[1920] = %f, y[1921] = %f, y[2047] = %f\n", y[1920], y[1921], y[2047]);
    return 0;
}
