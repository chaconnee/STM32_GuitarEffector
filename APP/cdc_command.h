//
// Created by chaconne on 2026/6/1.
//

#ifndef GUITAR_EFFECT_CDC_COMMAND_H
#define GUITAR_EFFECT_CDC_COMMAND_H
#include <stdint.h>


void cdc_rx(uint8_t* buf,uint32_t Len);
void process_cdc_cmd(void);
#endif //GUITAR_EFFECT_CDC_COMMAND_H
