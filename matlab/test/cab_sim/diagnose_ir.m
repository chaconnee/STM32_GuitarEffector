%% diagnose_ir.m — 诊断 IR 和吉他信号是否正常

clear; clc; close all;

%% 1. 读取 IR
[ir_raw, fs_ir] = audioread('../../IR/OwnHammer_412_32k.wav');
ir = ir_raw(:, 1);
fprintf('=== IR 文件 ===\n');
fprintf('采样率: %d Hz\n', fs_ir);
fprintf('长度: %d 样本 (%.2f ms)\n', length(ir), length(ir)/fs_ir*1000);
fprintf('峰值: %.6f\n', max(abs(ir)));

%% 2. 读取吉他干声
[guitar_raw, fs_g] = audioread('../riverdem.wav');
guitar = guitar_raw(:, 1);
fprintf('\n=== 吉他干声 ===\n');
fprintf('采样率: %d Hz\n', fs_g);
fprintf('长度: %d 样本 (%.2f 秒)\n', length(guitar), length(guitar)/fs_g);
fprintf('峰值: %.6f\n', max(abs(guitar)));

%% 3. IR 频率响应对比
Nfft = 8192;

figure('Name', 'IR 诊断', 'Position', [50 50 1400 900]);

% IR 波形
subplot(2,2,1);
t_ir = (0:length(ir)-1) / fs_ir * 1000;
plot(t_ir, ir, 'b');
xlabel('时间 (ms)'); ylabel('幅度');
title(sprintf('IR 波形 (fs=%d Hz)', fs_ir));
grid on;

% IR 频率响应
subplot(2,2,2);
H = fft(ir, Nfft);
f_ir = (0:Nfft/2-1) * fs_ir / Nfft;
mag_db = 20*log10(abs(H(1:Nfft/2)) + 1e-12);
semilogx(f_ir, mag_db, 'b', 'LineWidth', 1.5);
xlabel('频率 (Hz)'); ylabel('幅度 (dB)');
title('IR 频率响应');
xlim([20 fs_ir/2]); grid on;

% 吉他频谱
subplot(2,2,3);
G = fft(guitar(1:min(Nfft, length(guitar))), Nfft);
f_g = (0:Nfft/2-1) * fs_g / Nfft;
mag_g = 20*log10(abs(G(1:Nfft/2)) + 1e-12);
semilogx(f_g, mag_g, 'r', 'LineWidth', 0.5);
xlabel('频率 (Hz)'); ylabel('幅度 (dB)');
title('吉他干声频谱');
xlim([20 fs_g/2]); grid on;

% 吉他波形
subplot(2,2,4);
N_show = min(8000, length(guitar));
t_g = (0:N_show-1) / fs_g * 1000;
plot(t_g, guitar(1:N_show), 'r');
xlabel('时间 (ms)'); ylabel('幅度');
title('吉他干声波形');
grid on;

sgtitle('IR 与吉他信号诊断', 'FontSize', 14);

%% 4. 快速卷积试听 (截取前 5 秒)
dur = 5;
N_clip = min(dur * fs_ir, length(guitar));
if fs_g ~= fs_ir
    g_clip = resample(guitar(1:min(dur*fs_g, length(guitar))), fs_ir, fs_g);
else
    g_clip = guitar(1:N_clip);
end

% 用 filter 做卷积 (MATLAB 原生, 最可靠)
y_test = filter(ir, 1, g_clip);

fprintf('\n=== 5 秒快速测试 ===\n');
fprintf('输入峰值: %.6f, 输出峰值: %.6f\n', max(abs(g_clip)), max(abs(y_test)));
fprintf('增益: %.2f dB\n', 20*log10(max(abs(y_test))/max(abs(g_clip))));

audiowrite('diagnose_dry.wav', g_clip / max(abs(g_clip)) * 0.9, fs_ir);
audiowrite('diagnose_wet.wav', y_test / max(abs(y_test)) * 0.9, fs_ir);
fprintf('已保存: diagnose_dry.wav, diagnose_wet.wav\n');

%% 5. 对比: 用 delta 脉冲 (无滤波) vs IR
delta = [1; zeros(length(ir)-1, 1)];
y_delta = filter(delta, 1, g_clip);
fprintf('\n对比: delta 脉冲输出峰值 = %.6f (应等于输入)\n', max(abs(y_delta)));
