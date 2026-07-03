function losses = eval_losses(p, I_rms, f_Hz, V_dc, motor_count)
%EVAL_LOSSES Motor copper loss and simplified inverter losses.
% 中文说明:
% 本函数估算电机铜耗和逆变器损耗。它用于能量口径和效率粗筛，
% 不是逆变器结温或器件寿命模型。

    if nargin < 5 || isempty(motor_count)
        motor_count = 1;
    end

    % 电机铜耗按I_rms^2*R估算，并乘以电机数量。
    % 结果对motor_Rs_ohm解释很敏感，需要确认供应商14mOhm的测量口径。
    losses = struct();
    losses.P_motor_W = motor_count * I_rms^2 * p.motor_Rs_ohm;
    losses.P_inverter_W = motor_count * calc_inverter_loss(p, I_rms, f_Hz, V_dc);
end

function P_inv = calc_inverter_loss(p, I_rms, f, V_dc)
    % 简化逆变器损耗:
    % P_cond为导通损耗占位，P_sw为开关损耗占位。参数未来自目标硬件损耗图。
    if I_rms <= 0
        P_inv = 0;
        return;
    end
    I_avg = 2 / pi * I_rms;
    P_cond = 2 * (p.V_ce0 * I_avg + p.r_ce * I_rms^2) + ...
             2 * (p.V_f0 * I_avg + p.r_f * I_rms^2);
    E_sw_total = p.E_on + p.E_off + p.E_rr;
    P_sw = 2 * f * E_sw_total * (I_rms / p.I_ref_sw) * ...
        (V_dc / p.V_ref_sw);
    P_inv = max(P_cond + P_sw, 0);
end
