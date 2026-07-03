function limits = eval_current_limits(p, I_motor_rms_A, I_motor_peak_A, I_branch_rms_A, I_branch_peak_A)
%EVAL_CURRENT_LIMITS Current scaling and margins for motor and branch limits.
% 中文说明:
% 本函数统一处理电流硬限制。输入是未缩放或已缩放后的电机/支路电流，
% 输出current_scale和各类裕度。裕度>=1表示未超过对应限制。

    % 如果没有单独给支路电流，就用电机电流代替，兼容单支路或旧调用方式。
    if nargin < 4 || isempty(I_branch_rms_A)
        I_branch_rms_A = I_motor_rms_A;
    end
    if nargin < 5 || isempty(I_branch_peak_A)
        I_branch_peak_A = I_motor_peak_A;
    end

    scale = 1;
    factor = "none";

    % 电机RMS电流限制，通常对应MCU/电机短时热电流能力。
    if isfinite(p.I_motor_rms_limit_A) && I_motor_rms_A > p.I_motor_rms_limit_A
        scale = min(scale, p.I_motor_rms_limit_A / I_motor_rms_A);
        factor = "motor_rms";
    end
    % 电机峰值电流限制，防止瞬时峰值超过器件或控制器保护边界。
    if isfinite(p.I_motor_peak_limit_A) && I_motor_peak_A > p.I_motor_peak_limit_A
        new_scale = p.I_motor_peak_limit_A / I_motor_peak_A;
        if new_scale < scale
            factor = "motor_peak";
        elseif new_scale == scale && factor ~= "none"
            factor = factor + "+motor_peak";
        end
        scale = min(scale, new_scale);
    end
    % 电池支路高频峰值限制。当前4500-27参数中为inf，表示尚未收到BMS高频硬限值。
    if isfield(p, 'branch_hf_peak_limit_A') && ...
            isfinite(p.branch_hf_peak_limit_A) && I_branch_peak_A > p.branch_hf_peak_limit_A
        new_scale = p.branch_hf_peak_limit_A / I_branch_peak_A;
        if new_scale < scale
            factor = "battery_hf_peak";
        end
        scale = min(scale, new_scale);
    end

    % 输出缩放系数、触发来源和裕度。注意: 30s/60s规格窗口和析锂参考不在这里做硬限流。
    limits = struct();
    limits.current_scale = scale;
    limits.limiting_factor = char(factor);
    limits.I_motor_rms_A = I_motor_rms_A;
    limits.I_motor_peak_A = I_motor_peak_A;
    limits.I_branch_rms_A = I_branch_rms_A;
    limits.I_branch_peak_A = I_branch_peak_A;
    limits.motor_rms_margin = p.I_motor_rms_limit_A / max(I_motor_rms_A, eps);
    limits.motor_peak_margin = p.I_motor_peak_limit_A / max(I_motor_peak_A, eps);
    if isfield(p, 'branch_hf_peak_limit_A') && isfinite(p.branch_hf_peak_limit_A)
        limits.branch_peak_margin = p.branch_hf_peak_limit_A / max(I_branch_peak_A, eps);
    else
        limits.branch_peak_margin = inf;
    end
end
