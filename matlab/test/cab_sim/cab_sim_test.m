%% cab_sim_test.m — CabSim 验证
clear; clc; close all;

%% ========== 参数 ==========
BLOCK_SIZE = 128;
IR_FILE    = '../../IR/OwnHammer_412_32k.wav';

%% ========== 1. 读取并预处理 IR ==========
[ir_raw, fs] = audioread(IR_FILE);
ir = ir_raw(:, 1);

IR_LENGTH = 2048;
ir = ir(1:min(IR_LENGTH, length(ir)));
if length(ir) < IR_LENGTH
    ir = [ir; zeros(IR_LENGTH - length(ir), 1)];
end
ir = ir / max(abs(ir)) * 0.5;
fprintf('IR: peak=%.4f, len=%d\n', max(abs(ir)), IR_LENGTH);

%% ========== 2. 读取吉他干声 ==========
[guitar_raw, fs_g] = audioread('../fusion_test.wav');
guitar = guitar_raw(:, 1);
if fs_g ~= fs
    guitar = resample(guitar, fs, fs_g);
end
fprintf('Guitar: %d samples (%.2f s)\n', length(guitar), length(guitar)/fs);

%% ========== 3. Overlap-Save 卷积 ==========
M = length(guitar);
N = length(ir);

% FFT 大小: next power of 2 >= N + BLOCK_SIZE - 1
K = 2^(floor(log2(N + BLOCK_SIZE - 1)) + 1);

% 输入补零到 BLOCK_SIZE 的整数倍
num_blocks = ceil(M / BLOCK_SIZE) + ceil(K / BLOCK_SIZE) - 1;
xp = [guitar; zeros(num_blocks * BLOCK_SIZE - M, 1)];

% 滑动窗口
xw = zeros(K, 1);

% 预计算 IR 的 FFT
H = fft([ir; zeros(K - N, 1)], K);

% 逐块处理
ret = zeros(num_blocks * BLOCK_SIZE + N - 1, 1);
tic;
for n = 0:num_blocks-1
    xb = xp(n*BLOCK_SIZE + 1 : n*BLOCK_SIZE + BLOCK_SIZE);
    xw = circshift(xw, -BLOCK_SIZE);
    xw(end - BLOCK_SIZE + 1 : end) = xb;
    X = fft(xw, K);
    Y = X .* H;
    u = real(ifft(Y));
    ret(n*BLOCK_SIZE + 1 : n*BLOCK_SIZE + BLOCK_SIZE) = u(end - BLOCK_SIZE + 1 : end);
end
y = ret(1:M);
fprintf('卷积耗时: %.2f 秒\n', toc);

%% ========== 4. 直接 conv 对比 (可选) ==========
DO_CONV = false;
if DO_CONV
    tic;
    y_ref = conv(guitar, ir);
    y_ref = y_ref(1:M);
    fprintf('conv 耗时: %.2f 秒\n', toc);
    fprintf('max error: %.2e\n', max(abs(y - y_ref)));
end

%% ========== 5. 保存 ==========
y_out = y / max(abs(y)) * 0.9;
audiowrite('cab_sim_wet.wav', y_out, fs);
audiowrite('cab_sim_dry.wav', guitar / max(abs(guitar)) * 0.9, fs);
fprintf('已保存: cab_sim_dry.wav, cab_sim_wet.wav\n');

%% ========== 6. 画图 ==========
figure('Name', 'CabSim Test', 'Position', [50 50 1200 600]);
min_len = min(length(guitar), length(y_out));
t = (0:min_len-1) / fs;

subplot(2,1,1);
plot(t, guitar(1:min_len)/max(abs(guitar)), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on;
plot(t, y_out(1:min_len)/max(abs(y_out)), 'b', 'DisplayName', 'CabSim');
xlabel('Time (s)'); ylabel('Amplitude');
title('Dry vs CabSim'); legend; grid on;

subplot(2,1,2);
Nfft = 16384;
n_seg = min(Nfft, min_len);
freqs = (0:Nfft/2-1) * fs / Nfft;
D = fft(guitar(1:n_seg), Nfft);
W = fft(y(1:n_seg), Nfft);
semilogx(freqs, 20*log10(abs(D(1:Nfft/2))+1e-12), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on;
semilogx(freqs, 20*log10(abs(W(1:Nfft/2))+1e-12), 'b', 'DisplayName', 'CabSim');
xlabel('Frequency (Hz)'); ylabel('dB');
title('Spectrum'); xlim([20 fs/2]); legend; grid on;

sgtitle('CabSim Verification', 'FontSize', 14);
