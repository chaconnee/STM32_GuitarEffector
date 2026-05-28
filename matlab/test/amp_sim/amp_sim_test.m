%% amp_sim_test.m — AmpSim 单独验证
clear; clc; close all;

%% ========== 参数 ==========
SAMPLE_RATE = 32000;
TWO_PI_F    = 2 * pi;
HPF_FC      = 80.0;
LPF_FC      = 4500.0;
DRIVE_MAX   = 25.0;
drive       = 0.15;
volume      = 0.7;

%% ========== 读取吉他干声 ==========
[guitar_raw, fs] = audioread('../riverdem.wav');
guitar = guitar_raw(:, 1);
if fs ~= SAMPLE_RATE
    guitar = resample(guitar, SAMPLE_RATE, fs);
    fs = SAMPLE_RATE;
end
N = length(guitar);
fprintf('Guitar: %d samples (%.2f s), peak=%.4f\n', N, N/fs, max(abs(guitar)));

%% ========== AmpSim 处理 ==========
lo_cut_a = 1.0 - exp(-TWO_PI_F * HPF_FC / SAMPLE_RATE);
hi_cut_a = 1.0 - exp(-TWO_PI_F * LPF_FC / SAMPLE_RATE);
g = drive * DRIVE_MAX + 1.0;
lo_cut_z = 0; hi_cut_z1 = 0; hi_cut_z2 = 0;

out = zeros(N, 1);
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
    out(i) = s;
end
fprintf('AmpSim: peak=%.4f, RMS=%.4f\n', max(abs(out)), sqrt(mean(out.^2)));

%% ========== 保存 ==========
audiowrite('amp_sim_dry.wav', guitar / max(abs(guitar)) * 0.9, fs);
audiowrite('amp_sim_wet.wav', out / max(abs(out)) * 0.9, fs);
fprintf('已保存: amp_sim_dry.wav, amp_sim_wet.wav\n');

%% ========== 画图 ==========
figure('Name', 'AmpSim Test', 'Position', [50 50 1200 600]);
t = (0:N-1) / fs;
Nfft = 16384;
n_seg = min(Nfft, N);
freqs = (0:Nfft/2-1) * fs / Nfft;
D = fft(guitar(1:n_seg), Nfft);
W = fft(out(1:n_seg), Nfft);

subplot(2,2,1);
n_show = min(round(0.1*fs), N);
t_ms = (0:n_show-1)/fs*1000;
plot(t_ms, guitar(1:n_show), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on; plot(t_ms, out(1:n_show), 'r', 'DisplayName', 'AmpSim');
xlabel('Time (ms)'); title('Waveform (100ms)'); legend; grid on;

subplot(2,2,2);
semilogx(freqs, 20*log10(abs(D(1:Nfft/2))+1e-12), 'Color', [0.7 0.7 0.7], 'DisplayName', 'Dry');
hold on;
semilogx(freqs, 20*log10(abs(W(1:Nfft/2))+1e-12), 'r', 'DisplayName', 'AmpSim');
xlabel('Frequency (Hz)'); ylabel('dB'); title('Spectrum');
xlim([20 fs/2]); legend; grid on;

subplot(2,2,3);
x_in = linspace(-1,1,1000);
y_out = tanh(x_in * g) * volume;
plot(x_in, x_in, '--', 'Color', [0.7 0.7 0.7], 'DisplayName', 'Linear');
hold on; plot(x_in, y_out, 'r', 'LineWidth', 2, 'DisplayName', sprintf('tanh(x*%.1f)*%.1f', g, volume));
xlabel('Input'); ylabel('Output'); title('Transfer Function');
axis([-1 1 -1 1]); legend; grid on;

subplot(2,2,4);
semilogx(freqs, 20*log10(abs(W(1:Nfft/2))./abs(D(1:Nfft/2))+1e-12), 'b', 'LineWidth', 1);
xlabel('Frequency (Hz)'); ylabel('Gain (dB)'); title('AmpSim Frequency Response');
xlim([20 fs/2]); grid on;

sgtitle(sprintf('AmpSim (drive=%.2f, volume=%.1f, gain=%.1fx)', drive, volume, g), 'FontSize', 14);
