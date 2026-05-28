%% chain_test.m — 串联验证: Dry → AmpSim → CabSim
clear; clc; close all;

%% ========== 参数 ==========
SAMPLE_RATE = 32000;
BLOCK_SIZE  = 128;

%% ========== 1. 读取 IR ==========
IR_FILE = '../../IR/OwnHammer_412_32k.wav';
[ir_raw, fs] = audioread(IR_FILE);
ir = ir_raw(:, 1);

IR_LENGTH = 2048;
ir = ir(1:min(IR_LENGTH, length(ir)));
if length(ir) < IR_LENGTH
    ir = [ir; zeros(IR_LENGTH - length(ir), 1)];
end
ir = ir / max(abs(ir)) * 0.5;

%% ========== 2. 读取吉他干声 ==========
[guitar_raw, fs_g] = audioread('../fusion_test.wav');
guitar = guitar_raw(:, 1);
if fs_g ~= fs
    guitar = resample(guitar, fs, fs_g);
end
N = length(guitar);

%% ========== 3. AmpSim ==========
TWO_PI_F  = 2 * pi;
HPF_FC    = 80.0;
LPF_FC    = 4500.0;
DRIVE_MAX = 25.0;
drive     = 0.15;
volume    = 0.7;

lo_cut_a = 1.0 - exp(-TWO_PI_F * HPF_FC / SAMPLE_RATE);
hi_cut_a = 1.0 - exp(-TWO_PI_F * LPF_FC / SAMPLE_RATE);
g = drive * DRIVE_MAX + 1.0;
lo_cut_z = 0; hi_cut_z1 = 0; hi_cut_z2 = 0;

amp_out = zeros(N, 1);
for i = 1:N
    s = guitar(i);
    lo_cut_z = lo_cut_z + lo_cut_a * (s - lo_cut_z);
    s = s - lo_cut_z;
    s = tanh(s * g);
    hi_cut_z1 = hi_cut_z1 + hi_cut_a * (s - hi_cut_z1);
    s = hi_cut_z1;
    hi_cut_z2 = hi_cut_z2 + hi_cut_a * (s - hi_cut_z2);
    s = hi_cut_z2 * volume;
    if s >  1, s =  1; end
    if s < -1, s = -1; end
    amp_out(i) = s;
end
fprintf('AmpSim: peak=%.4f\n', max(abs(amp_out)));

%% ========== 4. CabSim (Overlap-Save 卷积) ==========
M = length(amp_out);
Ni = length(ir);
K = 2^(floor(log2(Ni + BLOCK_SIZE - 1)) + 1);
num_blocks = ceil(M / BLOCK_SIZE) + ceil(K / BLOCK_SIZE) - 1;
H = fft([ir; zeros(K - Ni, 1)], K);

% AmpSim → CabSim
xp = [amp_out; zeros(num_blocks * BLOCK_SIZE - M, 1)];
xw = zeros(K, 1);
ret = zeros(num_blocks * BLOCK_SIZE + Ni - 1, 1);
tic;
for n = 0:num_blocks-1
    xb = xp(n*BLOCK_SIZE+1 : n*BLOCK_SIZE+BLOCK_SIZE);
    xw = circshift(xw, -BLOCK_SIZE);
    xw(end-BLOCK_SIZE+1 : end) = xb;
    X = fft(xw, K);
    Y = X .* H;
    u = real(ifft(Y));
    ret(n*BLOCK_SIZE+1 : n*BLOCK_SIZE+BLOCK_SIZE) = u(end-BLOCK_SIZE+1 : end);
end
cab_out = ret(1:M);
fprintf('Amp+Cab 卷积耗时: %.2f 秒\n', toc);

% 单独 CabSim
xp2 = [guitar; zeros(num_blocks * BLOCK_SIZE - M, 1)];
xw2 = zeros(K, 1);
ret2 = zeros(num_blocks * BLOCK_SIZE + Ni - 1, 1);
for n = 0:num_blocks-1
    xb = xp2(n*BLOCK_SIZE+1 : n*BLOCK_SIZE+BLOCK_SIZE);
    xw2 = circshift(xw2, -BLOCK_SIZE);
    xw2(end-BLOCK_SIZE+1 : end) = xb;
    X = fft(xw2, K);
    Y = X .* H;
    u = real(ifft(Y));
    ret2(n*BLOCK_SIZE+1 : n*BLOCK_SIZE+BLOCK_SIZE) = u(end-BLOCK_SIZE+1 : end);
end
cab_only = ret2(1:M);

%% ========== 5. 保存 ==========
min_len = min([length(guitar), length(amp_out), length(cab_out), length(cab_only)]);
audiowrite('chain_dry.wav',          guitar(1:min_len)/max(abs(guitar(1:min_len)))*0.9, fs);
audiowrite('chain_amp_only.wav',     amp_out(1:min_len)/max(abs(amp_out(1:min_len)))*0.9, fs);
audiowrite('chain_cab_only.wav',     cab_only(1:min_len)/max(abs(cab_only(1:min_len)))*0.9, fs);
audiowrite('chain_amp_then_cab.wav', cab_out(1:min_len)/max(abs(cab_out(1:min_len)))*0.9, fs);
fprintf('已保存 4 个 WAV 文件\n');

%% ========== 6. 画图 ==========
figure('Name', 'Effect Chain', 'Position', [50 50 1400 900]);
t = (0:min_len-1) / fs;
Nfft = 16384;
n_seg = min(Nfft, min_len);
freqs = (0:Nfft/2-1) * fs / Nfft;

D  = fft(guitar(1:n_seg), Nfft);
A  = fft(amp_out(1:n_seg), Nfft);
C  = fft(cab_only(1:n_seg), Nfft);
CH = fft(cab_out(1:n_seg), Nfft);

subplot(2,2,1);
plot(t, guitar(1:min_len)/max(abs(guitar)), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on; plot(t, cab_out(1:min_len)/max(abs(cab_out)), 'r', 'DisplayName', 'Amp+Cab');
xlabel('Time (s)'); title('Waveform'); legend; grid on;

subplot(2,2,2);
semilogx(freqs, 20*log10(abs(D(1:Nfft/2))+1e-12), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on;
semilogx(freqs, 20*log10(abs(A(1:Nfft/2))+1e-12), 'b', 'DisplayName', 'AmpSim');
semilogx(freqs, 20*log10(abs(C(1:Nfft/2))+1e-12), 'g', 'DisplayName', 'CabSim');
semilogx(freqs, 20*log10(abs(CH(1:Nfft/2))+1e-12), 'r', 'LineWidth', 1.5, 'DisplayName', 'Amp+Cab');
xlabel('Frequency (Hz)'); ylabel('dB'); title('Spectrum');
xlim([20 fs/2]); legend; grid on;

subplot(2,2,3);
semilogx(freqs, 20*log10(abs(A(1:Nfft/2))./abs(D(1:Nfft/2))+1e-12), 'b', 'DisplayName', 'AmpSim');
hold on;
semilogx(freqs, 20*log10(abs(C(1:Nfft/2))./abs(D(1:Nfft/2))+1e-12), 'g', 'DisplayName', 'CabSim');
semilogx(freqs, 20*log10(abs(CH(1:Nfft/2))./abs(D(1:Nfft/2))+1e-12), 'r', 'LineWidth', 1.5, 'DisplayName', 'Amp+Cab');
xlabel('Frequency (Hz)'); ylabel('Gain (dB)'); title('Frequency Response');
xlim([20 fs/2]); legend; grid on;

subplot(2,2,4);
x_drive = linspace(-1,1,1000);
y_drive = tanh(x_drive * g) * volume;
plot(x_drive, x_drive, '--', 'Color', [0.7 0.7 0.7], 'DisplayName', 'Linear');
hold on; plot(x_drive, y_drive, 'r', 'LineWidth', 2, 'DisplayName', 'AmpSim');
xlabel('Input'); ylabel('Output'); title('Transfer Function');
axis([-1 1 -1 1]); legend; grid on;

sgtitle('Effect Chain: Dry → AmpSim → CabSim', 'FontSize', 14);
