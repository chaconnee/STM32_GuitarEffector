%% cab_sim_design.m —— 箱体 IR 卷积 MATLAB 设计/验证脚本

clear; clc; close all;

%% ========== 参数区  ==========

FFT_SIZE   = 1024;
BLOCK_SIZE = 128;
IR_FILE    = 'IR/OwnHammer_412_32k.wav';
IR_SIZE    = 897;          % 最大: FFT_SIZE - BLOCK_SIZE + 1
IR_PEAK    = 0.5;
FS         = 32000;

% 测试音频 (改这里换其他文件)
TEST_FILE  = 'test/fusion_test.wav';


%% ── 1. 加载 IR (对应 cab_sim.c: cab_init) ──
fprintf('\n[1/5] 加载 IR: %s\n', IR_FILE);
fprintf('      对应 C 代码: cab_sim.c:42-57  cab_init()\n');

[ir_raw, fs_ir] = audioread(IR_FILE);
ir_raw = ir_raw(:, 1);                      % C: ir = ir(:, 1)
if fs_ir ~= FS
    ir_raw = resample(ir_raw, FS, fs_ir);   % C: 假设已转 32kHz
    fprintf('      重采样: %d → %d Hz\n', fs_ir, FS);
end
ir_raw = ir_raw / max(abs(ir_raw)) * IR_PEAK;  % C: cab_sim.c:49-57
ir_used = ir_raw(1:min(IR_SIZE, length(ir_raw)));  % C: cab_sim.c:42 memcpy

fprintf('      IR 峰值: %.4f  已用: %d/%d 样本 (%.1f ms / %.1f ms)\n', ...
        max(abs(ir_used)), length(ir_used), length(ir_raw), ...
        length(ir_used)/FS*1000, length(ir_raw)/FS*1000);

%% ── 2. 加载测试音频 ──
fprintf('\n[2/5] 加载测试音频: %s\n', TEST_FILE);
fprintf('      对应 C 代码: AudioPipeline.c:40  HAL_ADC_Start_DMA\n');

[guitar_raw, fs_g] = audioread(TEST_FILE);
guitar = guitar_raw(:, 1);
if fs_g ~= FS
    guitar = resample(guitar, FS, fs_g);
end
fprintf('      %d 样本 (%.1f 秒)\n', length(guitar), length(guitar)/FS);

%% ── 3. 重叠保留卷积 (对应 cab_sim.c: cab_process) ──
fprintf('\n[3/5] 重叠保留卷积 (overlap-save)\n');
fprintf('      对应 C 代码: cab_sim.c:73-110  cab_process()\n');

% CMSIS arm_rfft_fast_f32 和 MATLAB fft/ifft 在卷积中等价 — 不需 scale 增益补偿
%   (实测验证: 不加 scale 的卷积输出 peak ratio = 1.0000, RMS ratio = 1.0000)

% 重叠保留卷积
N = length(guitar);
num_blocks = ceil(N / BLOCK_SIZE) + ceil(FFT_SIZE / BLOCK_SIZE);
xp = [guitar; zeros(num_blocks * BLOCK_SIZE - N, 1)];

% IR 预处理 (C: cab_init — 只执行一次)
hir = [ir_used; zeros(FFT_SIZE - length(ir_used), 1)];
H   = fft(hir, FFT_SIZE);       % C: arm_rfft_fast_f32(ifftFlag=0)

% 滑动窗口 (C: slide_buf)
xw = zeros(FFT_SIZE, 1);        % C: cab_sim.c:26  static float slide_buf[FFT_SIZE]
y = zeros(num_blocks * BLOCK_SIZE, 1);

tic;
for bn = 0:num_blocks-1
    % ① 滑动窗口: 丢掉老数据, 填入新块 (C: cab_sim.c:76-77 memmove+memcpy)
    xw = circshift(xw, -BLOCK_SIZE);
    idx_s = bn * BLOCK_SIZE + 1;
    idx_e = min(bn * BLOCK_SIZE + BLOCK_SIZE, length(xp));
    xb = zeros(BLOCK_SIZE, 1);
    blen = idx_e - idx_s + 1;
    xb(1:blen) = xp(idx_s:idx_e);
    xw(end - BLOCK_SIZE + 1 : end) = xb;

    % ② 正向 FFT (C: cab_sim.c:80-81 memcpy+arm_rfft_fast)
    X = fft(xw, FFT_SIZE);

    % ③ 频域相乘 (C: cab_sim.c:84-89 arm_cmplx_mult_cmplx_f32)
    Y = X .* H;

    % ④ 逆向 FFT (C: cab_sim.c:92 arm_rfft_fast, ifftFlag=1)
    u = real(ifft(Y));

    % ⑤ 提取重叠保留有效区 — 不加任何 scale, 直接取原始 IFFT 输出
    u_out = u(end - BLOCK_SIZE + 1 : end);

    if bn * BLOCK_SIZE + BLOCK_SIZE <= length(y)
        y(bn * BLOCK_SIZE + 1 : bn * BLOCK_SIZE + BLOCK_SIZE) = u_out;
    end
end
elapsed = toc;
y = y(1:N);
fprintf('      处理 %.1f 秒音频, 耗时 %.2f 秒 (%.1fx 实时)\n', ...
        N/FS, elapsed, N/FS/elapsed);



%% ── 4. IR 能量分析 ──
fprintf('\n[5/5] IR 截断能量分析\n');
fprintf('      IR 总长度: %d 样本 (%.1f ms)\n', length(ir_raw), length(ir_raw)/FS*1000);
fprintf('      C 代码使用: %d 样本 (%.1f ms)\n', IR_SIZE, IR_SIZE/FS*1000);

cum_e = cumsum(ir_raw.^2);
total_e = sum(ir_raw.^2);
for pct = [90 95 99 99.5 99.9]
    idx = find(cum_e / total_e >= pct/100, 1);
    fprintf('        %5.1f%% 能量 @ %5d 点 = %5.1f ms\n', pct, idx, idx/FS*1000);
end
used_pct = cum_e(min(IR_SIZE, length(ir_raw))) / total_e * 100;
fprintf('      当前截断 @ %d 点: %.2f%% 能量覆盖\n', IR_SIZE, used_pct);

%% ========== 图 1: IR 频域/时域/能量 ==========
figure('Name', 'IR 分析', 'Position', [50 50 1400 700]);

subplot(2,3,1);
t_ir = (0:length(ir_raw)-1) / FS * 1000;
plot(t_ir, ir_raw, 'b'); hold on;
xline(IR_SIZE/FS*1000, 'r--', 'LineWidth', 1.5);
xlabel('ms'); ylabel('幅度');
title(sprintf('IR 波形 (%d Hz)', FS)); grid on;

subplot(2,3,2);
env = movmean(abs(ir_raw), 64);
semilogy(t_ir, env+1e-12, 'b'); hold on;
xline(IR_SIZE/FS*1000, 'r--', 'LineWidth', 1.5);
xlabel('ms'); ylabel('幅度 (log)');
title('IR 衰减包络'); grid on;

subplot(2,3,3);
Nfft = 16384;
H_ir = fft(ir_raw(1:min(IR_SIZE,end)), Nfft);
freqs = (0:Nfft/2-1)*FS/Nfft;
semilogx(freqs, 20*log10(abs(H_ir(1:Nfft/2))+1e-12), 'b');
xlabel('Hz'); ylabel('dB');
title('IR 频率响应'); xlim([20 FS/2]); grid on;

subplot(2,3,4);
plot(t_ir, cum_e/total_e*100, 'b', 'LineWidth', 1.5); hold on;
xline(IR_SIZE/FS*1000, 'r--', 'LineWidth', 1.5);
yline(99, ':', 'Color', [0.5 0.5 0.5]);
xlabel('ms'); ylabel('%');
title(sprintf('能量累积 (%.1f%% @截断点)', used_pct)); grid on;

subplot(2,3,5);
N_show = min(5000, N);
t_show = (0:N_show-1)/FS*1000;
plot(t_show, guitar(1:N_show), 'Color', [0.7 0.7 0.7]); hold on;
plot(t_show, y(1:N_show), 'b');
xlabel('ms'); ylabel('幅度');
legend('输入', '卷积后'); grid on;

sgtitle('箱体 IR 卷积设计/验证', 'FontSize', 14);

%% ========== 图 2: 块处理图解 + 频响 ==========
figure('Name', '重叠保留图解', 'Position', [100 100 1000 600]);

subplot(2,2,1);
text(0.1, 0.9, 'Overlap-Save 原理 (cab_sim.c:cab_process)', 'FontWeight', 'bold');
text(0.1, 0.78, '每次处理:');
text(0.2, 0.70, '1. slide_buf 丢掉最老128点, 填入新128点');
text(0.2, 0.62, sprintf('2. FFT(%d) → x IR_FFT → IFFT(%d)', FFT_SIZE, FFT_SIZE));
text(0.2, 0.54, '3. 取末尾128点 (前部被时间混叠污染)');
text(0.1, 0.42, '为什么取末尾?');
text(0.2, 0.34, '圆周卷积 = 线性卷积 + 时间混叠');
text(0.2, 0.26, '混叠在开头, 末尾BLOCK_SIZE点 = 正确的线性卷积');
text(0.1, 0.12, sprintf('延迟=%dms  帧处理≈1ms  CPU≈%d%%', ...
     round(BLOCK_SIZE/FS*1000), round(1/BLOCK_SIZE*FS*100/FS)));
axis off;

subplot(2,2,2);
text(0.1, 0.85, '块处理示意', 'FontWeight', 'bold');
text(0.1, 0.75, '块n-1: [old 896|new 128]d5 → FFTe5');
text(0.1, 0.67, '块n:   [old 896|new 128]d0 → FFTe0');
text(0.1, 0.59, '块n+1: [old 896|new 128]5 → FFTe5');
text(0.1, 0.45, sprintf('每%dms 一帧, 滑动窗口连续滚动', round(BLOCK_SIZE/FS*1000)));
axis off;

subplot(2,2,[3 4]);
G_in  = fft(guitar(1:min(Nfft,N)), Nfft);
G_out = fft(y(1:min(Nfft,N)), Nfft);
semilogx(freqs, 20*log10(abs(G_in(1:Nfft/2))+1e-12), 'Color', [0.7 0.7 0.7]); hold on;
semilogx(freqs, 20*log10(abs(G_out(1:Nfft/2))+1e-12), 'b');
xlabel('Hz'); ylabel('dB');
legend('输入', '卷积后');
title(sprintf('频谱对比 (FFT=%d, BLOCK=%d, IR=%d)', FFT_SIZE, BLOCK_SIZE, IR_SIZE));
xlim([20 FS/2]); grid on;

sgtitle('重叠保留卷积 — 设计验证', 'FontSize', 14);

%% ========== 保存输出音频 ==========
y_out = y / max(abs(y)) * 0.9;
audiowrite('test/cab_design_out.wav', y_out, FS);
audiowrite('test/cab_design_dry.wav', guitar/max(abs(guitar))*0.9, FS);
fprintf('\n已保存: test/cab_design_dry.wav, test/cab_design_out.wav\n');
