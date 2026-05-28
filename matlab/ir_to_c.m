%% ir_to_c.m — 将 IR WAV 转换为 C 头文件 (ir_data.h)
%
% 用法:
%   ir_to_c                        % 使用默认 OwnHammer IR
%   ir_to_c('path/to/ir.wav')      % 指定 IR 文件
%
% 标准 IR 格式: 无前导静音, 峰值归一化到 0.5, 截取前 2048 个样本

function ir_to_c(ir_path)

    %% ========== 配置 ==========
    if nargin < 1
        ir_path = 'IR/OwnHammer_412_32k.wav';
    end
    IR_LENGTH = 2048;
    IR_NAME   = 'ir_ownhammer_412';
    OUT_PATH  = '../APP/effects/cab_sim/ir_data.h';

    %% ========== 读取 ==========
    [ir, fs] = audioread(ir_path);
    ir = ir(:, 1);  % 取单声道
    fprintf('采样率: %d Hz\n', fs);
    fprintf('长度: %d 样本 (%.2f ms)\n', length(ir), length(ir)/fs*1000);
    fprintf('峰值: %.6f\n', max(abs(ir)));

    %% ========== 截取/补零 ==========
    if length(ir) >= IR_LENGTH
        ir = ir(1:IR_LENGTH);
    else
        ir = [ir; zeros(IR_LENGTH - length(ir), 1)];
    end

    %% ========== 峰值归一化到 0.5 ==========
    ir = ir / max(abs(ir)) * 0.5;
    fprintf('处理后: %d 样本, 峰值 %.6f\n', IR_LENGTH, max(abs(ir)));

    %% ========== 写入 C 头文件 ==========
    fid = fopen(OUT_PATH, 'w');
    if fid == -1
        error('无法打开输出文件: %s', OUT_PATH);
    end

    fprintf(fid, '#ifndef IR_DATA_H\n');
    fprintf(fid, '#define IR_DATA_H\n\n');
    fprintf(fid, '#include <stdint.h>\n\n');
    fprintf(fid, '#define IR_LENGTH %d\n\n', IR_LENGTH);
    fprintf(fid, 'static const float %s[IR_LENGTH] = {\n', IR_NAME);

    cols = 6;
    for i = 1:IR_LENGTH
        if mod(i-1, cols) == 0
            fprintf(fid, '    ');
        end
        if i < IR_LENGTH
            fprintf(fid, '%.10ff,', ir(i));
        else
            fprintf(fid, '%.10ff', ir(i));
        end
        if mod(i, cols) == 0
            fprintf(fid, '\n');
        end
    end

    if mod(IR_LENGTH, cols) ~= 0
        fprintf(fid, '\n');
    end
    fprintf(fid, '};\n\n');
    fprintf(fid, '#endif /* IR_DATA_H */\n');

    fclose(fid);
    fprintf('已生成: %s\n', OUT_PATH);
end
