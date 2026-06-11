function op = eval_circuit_operating_point(p, c, T_C, SOC, f_Hz, duty, mismatch, current_amplitude_scale, motor_sync_correlation)
%EVAL_CIRCUIT_OPERATING_POINT Electrical, loss, thermal, and limit snapshot.

    if nargin < 8 || isempty(current_amplitude_scale)
        current_amplitude_scale = 1.0;
    end
    if nargin < 9 || isempty(motor_sync_correlation)
        motor_sync_correlation = 1.0;
    end

    R_branch = interp_branch_resistance(p, T_C, SOC) .* mismatch(:)';
    V_branch = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap');

    n = c.branch_count;

    switch c.type
        case 'whole_branch_sync'
            motor_count = get_case_motor_count(c, p);
            R_eq = 1 / sum(1 ./ R_branch);
            R_loop = p.motor_Rs_ohm + motor_count * R_eq;
            raw = calc_pwm_operating_current(V_branch, R_loop, ...
                p.motor_Ld_H, f_Hz, duty);
            raw.i_rms = raw.i_rms * current_amplitude_scale;
            raw.i_max = raw.i_max * current_amplitude_scale;
            raw.i_min = raw.i_min * current_amplitude_scale;
            raw.i_pp = raw.i_pp * current_amplitude_scale;
            raw.i_peak = raw.i_peak * current_amplitude_scale;
            motor_sync_correlation = clamp_motor_sync_correlation( ...
                motor_sync_correlation, motor_count);

            conductance_share = (1 ./ R_branch) ./ sum(1 ./ R_branch);
            raw_pack_rms = calc_pack_rms_from_motor_rms(raw.i_rms, ...
                motor_count, motor_sync_correlation);
            raw_pack_peak = motor_count * raw.i_peak;
            raw_branch_rms = raw_pack_rms .* conductance_share;
            raw_branch_peak = raw_pack_peak .* conductance_share;
            limits_raw = eval_current_limits(p, raw.i_rms, raw.i_peak, ...
                max(raw_branch_rms), max(raw_branch_peak));

            i_motor_rms = raw.i_rms * limits_raw.current_scale;
            i_motor_peak = raw.i_peak * limits_raw.current_scale;
            i_pack_rms = calc_pack_rms_from_motor_rms(i_motor_rms, ...
                motor_count, motor_sync_correlation);
            i_pack_peak = motor_count * i_motor_peak;
            branch_rms = i_pack_rms .* conductance_share;
            branch_pk = i_pack_peak .* conductance_share;
            P_branch = branch_rms.^2 .* R_branch;

            losses = eval_losses(p, i_motor_rms, f_Hz, V_branch, motor_count);
            P_motor_W = losses.P_motor_W;
            P_inverter_W = losses.P_inverter_W;
            I_bus_rms_A = i_pack_rms;
            I_switch_rms_sq = i_motor_rms^2;
            I_motor_rms_ref = i_motor_rms;
            I_motor_peak_ref = i_motor_peak;
            current_scale = limits_raw.current_scale;
            effective_current_scale = current_amplitude_scale * current_scale;
            limiting_factor = limits_raw.limiting_factor;
            branch_rms_sq = branch_rms.^2;
            branch_peak = branch_pk;
            battery_current_sync_factor = calc_sync_current_factor( ...
                motor_count, motor_sync_correlation);
            battery_heating_sync_factor = battery_current_sync_factor^2;

        otherwise
            error('未知架构类型: %s', c.type);
    end

    heat = eval_heat_balance(p, P_branch, T_C * ones(1, n), n);
    P_total_electric_W = heat.P_battery_W + P_motor_W + P_inverter_W;
    branch_heat_energy_30min_kWh = P_branch * p.t_end_min / 60 / 1000;
    spec_ref = get_branch_current_window_ref(p, T_C);
    current_limits = eval_current_limits(p, I_motor_rms_ref, I_motor_peak_ref, ...
        max(sqrt(branch_rms_sq)), max(branch_peak));
    current_limits.current_scale = current_scale;
    current_limits.limiting_factor = char(limiting_factor);
    safety = eval_safety_limits(p, c, T_C, SOC, f_Hz, current_limits, spec_ref);

    op = struct();
    op.P_branch_W = P_branch;
    op.P_battery_W = heat.P_battery_W;
    op.P_loss_branch_W = heat.P_loss_branch_W;
    op.P_loss_W = heat.P_loss_W;
    op.P_net_W = heat.P_net_W;
    op.P_motor_W = P_motor_W;
    op.P_inverter_W = P_inverter_W;
    op.P_total_electric_W = P_total_electric_W;
    op.heating_efficiency = heat.P_battery_W / max(P_total_electric_W, eps);
    op.dTdt_C_per_min = heat.dTdt_C_per_min;
    op.time_to_target_min = estimate_target_time_from_rate(p, T_C, heat.dTdt_C_per_min);
    op.I_motor_rms_A = I_motor_rms_ref;
    op.I_motor_peak_A = I_motor_peak_ref;
    op.I_branch_rms_A = sqrt(branch_rms_sq);
    op.I_branch_peak_A = branch_peak;
    op.I_branch_rms_max_A = max(op.I_branch_rms_A);
    op.I_branch_peak_max_A = max(op.I_branch_peak_A);
    op.I_bus_rms_A = I_bus_rms_A;
    op.I_switch_rms_A = sqrt(I_switch_rms_sq);
    op.current_amplitude_scale = current_amplitude_scale;
    op.motor_sync_correlation = motor_sync_correlation;
    op.battery_current_sync_factor = battery_current_sync_factor;
    op.battery_heating_sync_factor = battery_heating_sync_factor;
    op.R_heat_factor = get_R_heat_factor(p);
    op.motor_rms_limit_A = p.I_motor_rms_limit_A;
    op.current_scale = current_scale;
    op.effective_current_scale = effective_current_scale;
    op.limiting_factor = char(limiting_factor);
    op.branch_heat_spread_pct = spread_pct(P_branch);
    op.branch_energy_spread_30min_kWh = ...
        max(branch_heat_energy_30min_kWh) - min(branch_heat_energy_30min_kWh);
    op.current_limits = current_limits;
    op.safety = safety;
    op.branch_charge_30s_ref_A = spec_ref.charge_30s_A;
    op.branch_discharge_30s_ref_A = spec_ref.discharge_30s_A;
    op.branch_charge_60s_ref_A = spec_ref.charge_60s_A;
    op.branch_discharge_60s_ref_A = spec_ref.discharge_60s_A;
    op.branch_peak_margin = current_limits.branch_peak_margin;
    op.frequency_margin = safety.frequency_margin;
    op.plating_reference_margin = safety.plating_reference_margin;
    op.note = build_note(p, c, op, spec_ref);
end

function R_branch = interp_branch_resistance(p, T_C, SOC)
    T_q = min(max(T_C, min(p.R_data_T_C)), max(p.R_data_T_C));
    SOC_q = min(max(SOC, min(p.R_data_SOC)), max(p.R_data_SOC));
    R_branch = interp2(p.R_data_SOC, p.R_data_T_C, ...
        p.R_branch_192S1P_table_ohm, SOC_q, T_q, 'linear');
    R_branch = R_branch * get_R_heat_factor(p);
end

function factor = get_R_heat_factor(p)
    if isfield(p, 'R_heat_factor_current')
        factor = p.R_heat_factor_current;
    elseif isfield(p, 'R_heat_factor_default')
        factor = p.R_heat_factor_default;
    else
        factor = 1.0;
    end
end

function ref = get_branch_current_window_ref(p, T_C)
    T_q = min(max(T_C, min(p.current_window_T_C)), max(p.current_window_T_C));
    ref = struct();
    ref.charge_30s_A = interp1(p.current_window_T_C, ...
        p.branch_charge_30s_ref_A, T_q, 'linear');
    ref.discharge_30s_A = interp1(p.current_window_T_C, ...
        p.branch_discharge_30s_ref_A, T_q, 'linear');
    ref.charge_60s_A = interp1(p.current_window_T_C, ...
        p.branch_charge_60s_ref_A, T_q, 'linear');
    ref.discharge_60s_A = interp1(p.current_window_T_C, ...
        p.branch_discharge_60s_ref_A, T_q, 'linear');
end

function raw = calc_pwm_operating_current(Vdc, R, L, f, D)
    [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D);
    raw = struct();
    raw.i_rms = i_rms;
    raw.i_max = i_max;
    raw.i_min = i_min;
    raw.i_pp = i_pp;
    raw.i_peak = max(abs([i_max i_min]));
end

function [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D)
    T_period = 1 / f;
    t_on = D * T_period;
    t_off = (1 - D) * T_period;

    if R <= 0 || L <= 0
        i_max = Vdc / max(R, eps);
        i_min = -i_max;
        i_pp = i_max - i_min;
        i_rms = abs(i_max);
        return;
    end

    tau = L / R;
    Vs = Vdc / R;
    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(t_off / tau);
    denom = exp_a - 1;

    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;
    i_pp = i_max - i_min;

    A1 = i_min - Vs;
    int_sq1 = Vs^2 * t_on + 2 * Vs * A1 * tau * (1 - exp(-t_on/tau)) + ...
        A1^2 * tau/2 * (1 - exp(-2*t_on/tau));
    A2 = i_max + Vs;
    int_sq2 = Vs^2 * t_off - 2 * Vs * A2 * tau * (1 - exp(-t_off/tau)) + ...
        A2^2 * tau/2 * (1 - exp(-2*t_off/tau));
    i_rms = sqrt(max((int_sq1 + int_sq2) / T_period, 0));
end

function motor_count = get_case_motor_count(c, p)
    if isfield(c, 'motor_count') && c.motor_count > 0
        motor_count = c.motor_count;
    else
        motor_count = p.motor_count;
    end
end

function rho = clamp_motor_sync_correlation(rho, motor_count)
    if motor_count <= 1
        rho = 1.0;
        return;
    end
    rho_min = -1 / (motor_count - 1);
    rho = min(max(rho, rho_min), 1.0);
end

function i_pack_rms = calc_pack_rms_from_motor_rms(i_motor_rms, motor_count, rho)
    if motor_count <= 1
        i_pack_rms = i_motor_rms;
        return;
    end
    rms_sq_factor = motor_count + motor_count * (motor_count - 1) * rho;
    i_pack_rms = i_motor_rms * sqrt(max(rms_sq_factor, 0));
end

function factor = calc_sync_current_factor(motor_count, rho)
    if motor_count <= 1
        factor = 1.0;
        return;
    end
    ideal_sync_factor = motor_count;
    actual_factor = sqrt(max(motor_count + motor_count * ...
        (motor_count - 1) * rho, 0));
    factor = actual_factor / ideal_sync_factor;
end

function pct = spread_pct(x)
    if isempty(x) || mean(abs(x)) <= eps
        pct = 0;
    else
        pct = (max(x) - min(x)) / mean(abs(x)) * 100;
    end
end

function t_target = estimate_target_time_from_rate(p, T_C, dTdt_C_per_min)
    if dTdt_C_per_min > 0 && T_C < p.T_target_C
        t_target = (p.T_target_C - T_C) / dTdt_C_per_min;
    else
        t_target = inf;
    end
end

function note = build_note(p, c, op, spec_ref)
    pieces = strings(1, 0);
    if op.dTdt_C_per_min >= 0.5
        pieces(end+1) = "温升有初步意义";
    else
        pieces(end+1) = "温升偏弱";
    end
    if op.current_scale < 0.999
        pieces(end+1) = "已触发电机/MCU限流";
    else
        pieces(end+1) = "未触发电机/MCU限流";
    end
    if op.I_branch_peak_max_A > spec_ref.discharge_30s_A || ...
            op.I_branch_peak_max_A > spec_ref.charge_30s_A
        pieces(end+1) = "支路峰值高于30s窗口参考, 高频边界需试验确认";
    end
    if c.branch_count == 1 && get_case_motor_count(c, p) >= 2
        pieces(end+1) = "双电机集中单支路, 需核对支路过流和高压盒路径";
    elseif c.branch_count >= 3
        pieces(end+1) = "三支路同步分流, 需核对支路均衡和母线压力";
    end
    if get_case_motor_count(c, p) >= 2 && op.motor_sync_correlation < 0.999
        pieces(end+1) = "双电机电池侧同步相关性低于理想同步, 用于控制风险边界";
    end
    if isfield(p, 'branch_hf_peak_limit_A') && isfinite(p.branch_hf_peak_limit_A)
        pieces(end+1) = "已启用电池高频峰值硬限制";
    end
    pieces(end+1) = string(op.safety.status);
    note = char(join(pieces, '; '));
end
