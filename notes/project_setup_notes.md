# CMake 交叉编译器配置笔记

## 问题1：编译器未找到

```
arm-none-eabi-gcc is not a full path and was not found in the PATH
```

### 解决
将工具链路径添加到用户 PATH：
```
D:\STM32CubeCLT_1.21.0\GNU-tools-for-STM32\bin
```

PowerShell 命令：
```powershell
[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";D:\STM32CubeCLT_1.21.0\GNU-tools-for-STM32\bin", "User")
```

添加后需**重启 CLion**。

---

## 问题2：编译器测试失败

```
The CXX compiler is not able to compile a simple test program.
unrecognized option '--major-image-version'
```

CMake 尝试用 Windows 系库测试 ARM 交叉编译器，导致失败。

### 解决

修改 `cmake/gcc-arm-none-eabi.cmake`，在文件开头添加：

```cmake
# 跳过编译器测试
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
set(CMAKE_C_COMPILER_FORCED 1)
set(CMAKE_CXX_COMPILER_FORCED 1)
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
```

然后清除缓存重新配置：
- CLion: Tools -> CMake -> Reset Cache and Reload Project
- 或删除 `cmake-build-debug` 目录

---

## CMake 缓存说明

### 什么是缓存
CMake 第一次配置时，会把检测结果（编译器信息、路径、变量等）保存到 `cmake-build-debug/CMakeCache.txt`。之后重新配置时会复用缓存，不会重新检测。

### 为什么需要删缓存
修改了工具链文件或添加了新路径，缓存里的旧信息还在，CMake 不会自动更新。

### CLion 中删除缓存的方法

**方法1**（推荐）：
```
Tools → CMake → Reset Cache and Reload Project
```

**方法2**：
```
Tools → CMake → Delete Cache and Reload Project
```

**方法3**：手动删除 `cmake-build-debug` 文件夹，然后重新打开项目。

### 什么时候需要删缓存

| 场景 | 需要删缓存 |
|------|-----------|
| 修改了 `CMakeLists.txt` | 不需要，CLion 自动检测 |
| 修改了工具链文件 `gcc-arm-none-eabi.cmake` | **需要** |
| 添加/删除源文件 | 不需要 |
| 编译器测试失败 | **需要** |
| 修改了 `CMakePresets.json` | **需要** |

---

## C 语言指针笔记

### `*` 在声明和使用时的区别

| 场景 | `*` 的含义 | 例子 |
|------|-----------|------|
| **声明** | 类型修饰符（这是指针） | `int *p = &a;` |
| **使用** | 解引用运算符（访问指向的值） | `*p = 20;` |

### 示例

```c
int a = 10;

// 声明：* 表示"这是指针"
int *p = &a;        // p 是 int 类型的指针，指向 a 的地址

// 使用：* 表示"解引用"
*p = 20;            // 通过指针修改 a 的值，a 变成 20
```

### 取地址 `&` 和解引用 `*`

| 操作 | 符号 | 含义 | 例子 |
|------|------|------|------|
| 取地址 | `&` | 获取变量的内存地址 | `&a` → 指针 |
| 解引用 | `*` | 通过地址访问变量 | `*p` → 变量的值 |

### 常见错误

```c
int a = 10;
int *p;

*p = &a;      // 错误：*p 是 int，&a 是 int*，类型不匹配
p = &a;       // 正确：把 a 的地址赋值给 p
*p = 20;      // 正确：把 20 赋值给 p 指向的变量
```

---

## 双缓冲 vs 环形缓冲区选择

### 核心原则
- **同时钟系统** → 双缓冲
- **不同时钟系统** → 环形缓冲区

### 原因
- 同时钟：数据流同步，双缓冲足够
- 不同时钟：数据流不同步，需要环形缓冲区缓冲余量

### 项目示例

| 项目 | 时钟关系 | 推荐方案 |
|------|----------|----------|
| 吉他效果器 | ADC 和 I2S 同时钟（48kHz） | 双缓冲 |
| USB 音频 | USB 和本地时钟不同步 | 环形缓冲区 |

### 延迟对比
- 双缓冲：128 采样点 → 5.33ms
- 环形缓冲区：通常需要更大缓冲区 → 10.67ms+
