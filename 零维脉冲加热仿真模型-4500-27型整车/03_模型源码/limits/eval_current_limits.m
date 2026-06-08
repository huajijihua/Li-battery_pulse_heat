function limits = eval_current_limits(p, I_motor_rms_A, I_motor_peak_A, I_branch_rms_A, I_branch_peak_A)
%EVAL_CURRENT_LIMITS Current scaling and margins for motor and branch limits.

    if nargin < 4 || isempty(I_branch_rms_A)
        I_branch_rms_A = I_motor_rms_A;
    end
    if nargin < 5 || isempty(I_branch_peak_A)
        I_branch_peak_A = I_motor_peak_A;
    end

    scale = 1;
    factor = "none";

    if isfinite(p.I_motor_rms_limit_A) && I_motor_rms_A > p.I_motor_rms_limit_A
        scale = min(scale, p.I_motor_rms_limit_A / I_motor_rms_A);
        factor = "motor_rms";
    end
    if isfinite(p.I_motor_peak_limit_A) && I_motor_peak_A > p.I_motor_peak_limit_A
        new_scale = p.I_motor_peak_limit_A / I_motor_peak_A;
        if new_scale < scale
            factor = "motor_peak";
        elseif new_scale == scale && factor ~= "none"
            factor = factor + "+motor_peak";
        end
        scale = min(scale, new_scale);
    end
    if isfield(p, 'branch_hf_peak_limit_A') && ...
            isfinite(p.branch_hf_peak_limit_A) && I_branch_peak_A > p.branch_hf_peak_limit_A
        new_scale = p.branch_hf_peak_limit_A / I_branch_peak_A;
        if new_scale < scale
            factor = "battery_hf_peak";
        end
        scale = min(scale, new_scale);
    end

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
