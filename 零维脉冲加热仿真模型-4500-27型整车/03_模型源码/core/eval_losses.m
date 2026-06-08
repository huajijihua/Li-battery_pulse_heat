function losses = eval_losses(p, I_rms, f_Hz, V_dc, motor_count)
%EVAL_LOSSES Motor copper loss and simplified inverter losses.

    if nargin < 5 || isempty(motor_count)
        motor_count = 1;
    end

    losses = struct();
    losses.P_motor_W = motor_count * I_rms^2 * p.motor_Rs_ohm;
    losses.P_inverter_W = motor_count * calc_inverter_loss(p, I_rms, f_Hz, V_dc);
end

function P_inv = calc_inverter_loss(p, I_rms, f, V_dc)
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
