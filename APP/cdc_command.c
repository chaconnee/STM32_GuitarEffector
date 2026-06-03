//
// Created by chaconne on 2026/6/1.
//

#include "cdc_command.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "model/effect.h"
#include "model/effect_chain.h"


static uint8_t cdc_rx_flag = 0;
static uint8_t cdc_rx_len = 0;
uint8_t  cdc_cmd_buf[16];


 void cdc_rx(uint8_t* buf,uint32_t Len)
{
     memcpy(cdc_cmd_buf,buf,Len);
     cdc_rx_flag = 1;
    cdc_rx_len = Len;
}

void process_cdc_cmd(void)
 {
  if (cdc_rx_flag == 0) return;
  cdc_rx_flag = 0;

  cdc_cmd_buf[cdc_rx_len] = '\0';  // 确保字符串终止

  uint8_t effect_id, param_id;
  float value;

  // 格式: "0 0 0.8\n" → effect_id=0, param_id=0, value=0.8
  int n = sscanf((char*)cdc_cmd_buf, "%hhu %hhu %f", &effect_id, &param_id, &value);

  if (n < 2) return;  // 最少需要 effect_id + param_id

  Effect *eff = EffectChain_GetAt(effect_id);
  if (eff == NULL || eff->set_param == NULL) return;

  if (n == 3) {
   eff->set_param(eff, param_id, value);  // "0 0 0.8"
  }
 }