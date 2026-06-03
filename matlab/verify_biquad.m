%% verify_biquad.m
%  验证 biquad Tone Stack 对 Cab 输出的影响
%
%  四路对比:
%    A: 干声 → Cab (基准)
%    B: Bass +8dB → Cab
%    C: Mid -6dB → Cab
%    D: 全 Tone Stack (Bass+8,Mid-6,Treb+8) → Cab

clear; clc; close all;

%% ========== 参数 ==========
FFT_SIZE   = 1024;
BLOCK_SIZE = 128;
IR_SIZE    = 897;
SCALE_NUM  = 12;
FS         = 32000;

%% ========== 加载 IR ==========
[ir_raw, fs_ir] = audioread('IR/OwnHammer_412_32k.wav');
ir_raw = ir_raw(:, 1);
if fs_ir ~= FS, ir_raw = resample(ir_raw, FS, fs_ir); end
ir_raw = ir_raw / max(abs(ir_raw)) * 0.5;
ir_used = ir_raw(1:IR_SIZE);

%% ========== 加载测试音频 ==========
[guitar_raw, fs_g] = audioread('test/fusion_test.wav');
guitar = guitar_raw(:, 1);
if fs_g ~= FS, guitar = resample(guitar, FS, fs_g); end
N = min(length(guitar), FS * 10);
guitar = guitar(1:N);
fprintf('测试信号: %d 样本 (%.1f 秒)\n', N, N/FS);

%% ========== 重叠保留卷积 ==========
H = fft([ir_used; zeros(FFT_SIZE - IR_SIZE, 1)], FFT_SIZE);
num_blocks = ceil(N / BLOCK_SIZE) + ceil(FFT_SIZE / BLOCK_SIZE);
scale = SCALE_NUM / 16.0;

function y = overlap_save_conv(x, H, FFT_SIZE, BLOCK_SIZE, scale)
    N = length(x);
    num_blocks = ceil(N / BLOCK_SIZE) + ceil(FFT_SIZE / BLOCK_SIZE);
    xp = [x; zeros(num_blocks * BLOCK_SIZE - N, 1)];
    xw = zeros(FFT_SIZE, 1);
    y = zeros(num_blocks * BLOCK_SIZE, 1);
    for bn = 0:num_blocks-1
        xw = circshift(xw, -BLOCK_SIZE);
        xb = zeros(BLOCK_SIZE, 1);
        idx_s = bn * BLOCK_SIZE + 1;
        idx_e = min(idx_s + BLOCK_SIZE - 1, length(xp));
        xb_len = idx_e - idx_s + 1;
        xb(1:xb_len) = xp(idx_s:idx_e);
        xw(end - BLOCK_SIZE + 1 : end) = xb;
        Y = fft(xw, FFT_SIZE) .* H;
        u = real(ifft(Y));
        out_s = bn * BLOCK_SIZE + 1;
        out_e = min(out_s + BLOCK_SIZE - 1, N);
        if out_s <= N
            y(out_s:out_e) = u(end - BLOCK_SIZE + 1 : end - BLOCK_SIZE + (out_e - out_s + 1)) * scale;
        end
    end
    y = y(1:N);
end

%% ========== biquad 滤波器设计 (与 C 代码 amp_sim.c 完全一致) ==========
function [bq, aq] = biquad_low_shelf(fc, Q, dBgain, fs)
    w0 = 2 * pi * fc / fs;
    A  = 10^(dBgain / 40);
    alpha = sin(w0) / (2 * Q);
    cosw  = cos(w0);
    sqrtA = sqrt(A);

    a0 = (A+1) + (A-1)*cosw + 2*sqrtA*alpha;
    b0 = A * ((A+1) - (A-1)*cosw + 2*sqrtA*alpha) / a0;
    b1 = 2 * A * ((A-1) - (A+1)*cosw) / a0;
    b2 = A * ((A+1) - (A-1)*cosw - 2*sqrtA*alpha) / a0;
    a1 = -2 * ((A-1) + (A+1)*cosw) / a0;
    a2 = ((A+1) + (A-1)*cosw - 2*sqrtA*alpha) / a0;
    bq = [b0 b1 b2]; aq = [1 a1 a2];
end

function [bq, aq] = biquad_parametric(fc, Q, dBgain, fs)
    w0 = 2 * pi * fc / fs;
    A  = 10^(dBgain / 40);
    alpha = sin(w0) / (2 * Q);
    cosw  = cos(w0);

    a0 = 1 + alpha / A;
    b0 = (1 + alpha * A) / a0;
    b1 = (-2 * cosw) / a0;
    b2 = (1 - alpha * A) / a0;
    a1 = (-2 * cosw) / a0;
    a2 = (1 - alpha / A) / a0;
    bq = [b0 b1 b2]; aq = [1 a1 a2];
end

function [bq, aq] = biquad_high_shelf(fc, Q, dBgain, fs)
    w0 = 2 * pi * fc / fs;
    A  = 10^(dBgain / 40);
    alpha = sin(w0) / (2 * Q);
    cosw  = cos(w0);
    sqrtA = sqrt(A);

    a0 = (A+1) - (A-1)*cosw + 2*sqrtA*alpha;
    b0 = A * ((A+1) + (A-1)*cosw + 2*sqrtA*alpha) / a0;
    b1 = -2 * A * ((A-1) + (A+1)*cosw) / a0;
    b2 = A * ((A+1) + (A-1)*cosw - 2*sqrtA*alpha) / a0;
    a1 = 2 * ((A-1) - (A+1)*cosw) / a0;
    a2 = ((A+1) - (A-1)*cosw - 2*sqrtA*alpha) / a0;
    bq = [b0 b1 b2]; aq = [1 a1 a2];
end

%% ========== 四路处理 ==========
fprintf('biquad 滤波处理...\n');

% A: 无 EQ
sig_a = guitar;

% B: 只调 LOW SHELF (Bass +8dB)
[b_low, a_low] = biquad_low_shelf(60, 0.707, 8, FS);
sig_b = filter(b_low, a_low, guitar);
bass_peak = max(abs(sig_b));

% C: 只调 PARAMETRIC (Mid -6dB)
[b_para, a_para] = biquad_parametric(500, 1.0, -6, FS);
sig_c = filter(b_para, a_para, guitar);

% D: 全 Tone Stack (Bass+8, Mid-6, Treble+8)
[sig_d, ~] =  filter(b_low, a_low, guitar);           % 低搁架 +8dB
[sig_d, ~] =  filter(b_para, a_para, sig_d);           % 中参量 -6dB
[b_high, a_high] = biquad_high_shelf(2400, 0.707, 8, FS);
sig_d = filter(b_high, a_high, sig_d);                  % 高搁架 +8dB
% 音量 + 软限幅 (模拟 amp_process)
sig_d = sig_d * 0.9;
sig_d(sig_d > 1.0) = 1.0;
sig_d(sig_d < -1.0) = -1.0;

fprintf('卷积处理...\n');

% 四路卷积
y_a = overlap_save_conv(sig_a, H, FFT_SIZE, BLOCK_SIZE, scale);
y_b = overlap_save_conv(sig_b, H, FFT_SIZE, BLOCK_SIZE, scale);
y_c = overlap_save_conv(sig_c, H, FFT_SIZE, BLOCK_SIZE, scale);
y_d = overlap_save_conv(sig_d, H, FFT_SIZE, BLOCK_SIZE, scale);

%% ========== 图 1: 频域对比 ==========
figure('Name', 'Biquad Tone Stack 频域对比', 'Position', [50 50 1400 600]);

Nfft = 16384;
freqs = (0:Nfft/2-1) * FS / Nfft;
Ys_a = fft(y_a(1:min(N,Nfft)), Nfft);
Ys_b = fft(y_b(1:min(N,Nfft)), Nfft);
Ys_c = fft(y_c(1:min(N,Nfft)), Nfft);
Ys_d = fft(y_d(1:min(N,Nfft)), Nfft);

% 1a. 三路频谱对比
subplot(2,3,1);
semilogx(freqs, 20*log10(abs(Ys_a(1:Nfft/2))+1e-12), 'b', 'LineWidth', 1); hold on;
semilogx(freqs, 20*log10(abs(Ys_b(1:Nfft/2))+1e-12), 'r', 'LineWidth', 1);
semilogx(freqs, 20*log10(abs(Ys_c(1:Nfft/2))+1e-12), 'Color', [1 0.5 0], 'LineWidth', 1);
semilogx(freqs, 20*log10(abs(Ys_d(1:Nfft/2))+1e-12), 'Color', [0.5 0 0.8], 'LineWidth', 1.5);
xlabel('频率 (Hz)'); ylabel('幅度 (dB)');
title('Cab 输出频谱');
legend('无EQ', 'Bass+8', 'Mid-6', '全ToneStack', 'Location', 'southwest');
xlim([20 FS/2]); grid on;

% 1b. Bass 差值谱
subplot(2,3,2);
semilogx(freqs, 20*log10(abs(Ys_b(1:Nfft/2))+1e-12) - 20*log10(abs(Ys_a(1:Nfft/2))+1e-12), 'r');
xlabel('Hz'); ylabel('dB rel 无EQ');
title('Bass+8dB 差异');
xlim([20 2000]); ylim([-10 10]); grid on;

% 1c. Mid 差值谱
subplot(2,3,3);
semilogx(freqs, 20*log10(abs(Ys_c(1:Nfft/2))+1e-12) - 20*log10(abs(Ys_a(1:Nfft/2))+1e-12), 'Color', [1 0.5 0]);
xlabel('Hz'); ylabel('dB rel 无EQ');
title('Mid-6dB 差异');
xlim([100 2000]); ylim([-10 10]); grid on;

% 1d. 全 Tone Stack 差值谱
subplot(2,3,4);
semilogx(freqs, 20*log10(abs(Ys_d(1:Nfft/2))+1e-12) - 20*log10(abs(Ys_a(1:Nfft/2))+1e-12), 'Color', [0.5 0 0.8]);
xlabel('Hz'); ylabel('dB rel 无EQ');
title('全ToneStack (B+8,M-6,T+8) 差异');
xlim([20 FS/2]); ylim([-12 12]); grid on;

% 1e. 时域对比 (前 500ms)
subplot(2,3,5);
t_td = (0:min(16000,N)-1) / FS * 1000;
plot(t_td, y_a(1:min(16000,N)), 'b', 'LineWidth', 0.7); hold on;
plot(t_td, y_d(1:min(16000,N)), 'Color', [0.5 0 0.8], 'LineWidth', 0.7);
xlabel('ms'); ylabel('幅度');
title('波形对比 (无EQ vs 全ToneStack)');
legend('无EQ', 'ToneStack', 'Location', 'northeast');
grid on;

% 1f. biquad 频率响应 (理论曲线)
subplot(2,3,6);
[H_low, w] = freqz(b_low, a_low, 2048, FS);
[H_para, ~] = freqz(b_para, a_para, 2048, FS);
[H_high, ~] = freqz(b_high, a_high, 2048, FS);
H_total = H_low .* H_para .* H_high;
semilogx(w, 20*log10(abs(H_low)+1e-12), 'r', 'LineWidth', 1); hold on;
semilogx(w, 20*log10(abs(H_para)+1e-12), 'Color', [1 0.5 0], 'LineWidth', 1);
semilogx(w, 20*log10(abs(H_high)+1e-12), 'g', 'LineWidth', 1);
semilogx(w, 20*log10(abs(H_total)+1e-12), 'k', 'LineWidth', 2);
xlabel('Hz'); ylabel('dB');
title('biquad 理论频响 (B+8,M-6,T+8)');
legend('LowSelf 60Hz', 'Param 500Hz', 'HighSelf 2.4k', 'Total', 'Location', 'southwest');
xlim([20 FS/2]); ylim([-18 18]); grid on;

sgtitle('Biquad Tone Stack 验证 — 与 cab_sim 实际效果对比', 'FontSize', 14);

%% ========== 输出统计 ==========
fprintf('\n=== 输出统计 ===\n');
fprintf('无EQ  → Cab:           peak=%.4f, RMS=%.4f\n', max(abs(y_a)), rms(y_a));
fprintf('Bass+8 → Cab:          peak=%.4f, RMS=%.4f  (+%.1f%%)\n', ...
        max(abs(y_b)), rms(y_b), (rms(y_b)/rms(y_a)-1)*100);
fprintf('Mid-6  → Cab:          peak=%.4f, RMS=%.4f  (%.1f%%)\n', ...
        max(abs(y_c)), rms(y_c), (rms(y_c)/rms(y_a)-1)*100);
fprintf('ToneStack(B,M,T)→ Cab: peak=%.4f, RMS=%.4f  (+%.1f%%)\n', ...
        max(abs(y_d)), rms(y_d), (rms(y_d)/rms(y_a)-1)*100);

%% ========== 保存 ==========
audiowrite('test/biquad_noeq.wav', y_a / max(abs(y_a)) * 0.9, FS);
audiowrite('test/biquad_bass8.wav', y_b / max(abs(y_b)) * 0.9, FS);
audiowrite('test/biquad_midneg6.wav', y_c / max(abs(y_c)) * 0.9, FS);
audiowrite('test/biquad_full.wav', y_d / max(abs(y_d)) * 0.9, FS);
fprintf('\n已保存: biquad_noeq.wav, biquad_bass8.wav, biquad_midneg6.wav, biquad_full.wav\n');
