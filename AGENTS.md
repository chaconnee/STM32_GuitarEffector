# Guitar_Effect

STM32F411xE (Cortex-M4F) 吉他效果器踏板。裸机 C 项目，由 STM32CubeMX 生成，使用 CMake + Ninja + GNU Arm Embedded Toolchain 构建。

## 构建与烧录

```bash
cmake --preset Debug
cmake --build --preset Debug
```

- 输出文件: `build/Debug/Guitar_Effect.elf` (+ 通过 objcopy 后处理生成 `.hex`)
- 需要将 `arm-none-eabi-` 工具链添加到 PATH 环境变量
- CMake 生成器为 **Ninja** (通过 `CMakePresets.json` 设置)
- 可选 clang 工具链: 将 `cmake/gcc-arm-none-eabi.cmake` 替换为 `cmake/starm-clang.cmake`

## 项目结构

| 路径 | 用途 |
|---|---|
| `Core/Inc/`, `Core/Src/` | 应用代码 (用户 DSP 逻辑) |
| `USB_DEVICE/App/`, `USB_DEVICE/Target/` | USB CDC (虚拟串口) |
| `Drivers/STM32F4xx_HAL_Driver/` | STM32 HAL 驱动 |
| `Drivers/CMSIS/` | CMSIS 核心 + 设备头文件 |
| `Middlewares/ST/STM32_USB_Device_Library/` | USB 设备栈 (CDC 类) |
| `cmake/stm32cubemx/CMakeLists.txt` | CubeMX 生成的源文件列表 |
| `startup_stm32f411xe.s` | 启动代码 (位于仓库根目录) |
| `STM32F411XX_FLASH.ld` | 链接脚本 |

## 关键注意事项

- **Bootloader 偏移**: `main.c` 中设置 `SCB->VTOR = FLASH_BASE | 0x4000` (非默认配置 — 应用程序从 16KB 偏移处开始)
- **CubeMX 重新生成**: 用户代码必须保留在 `/* USER CODE BEGIN/END */` 块内，否则会被覆盖
- **使用的外设**: ADC1, I2S2 (音频编解码器), TIM2, USB (CDC), DMA, GPIO
- **无测试、无 lint、无 CI** — 这是一个裸机固件项目
- **clangd**: `compile_commands.json` 在 `build/Debug/` 目录生成 (通过 `.clangd` 配置)
- **C 标准**: C11，启用 GNU 扩展 (`CMAKE_C_EXTENSIONS ON`)
- **FPU**: 硬浮点 ABI，单精度 (`-mfpu=fpv4-sp-d16 -mfloat-abi=hard`)
- **链接器标志**: `--specs=nano.specs`, `--gc-sections`, 输出 map 文件
