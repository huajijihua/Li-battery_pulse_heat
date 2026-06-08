function safety = eval_safety_limits(p, ~, T_C, SOC, f_Hz, current_limits, spec_ref)
%EVAL_SAFETY_LIMITS Electrical and battery safety references for screening.
% Spec-window and plating limits are displayed as references until calibrated
% high-frequency cell data are available.

    frequency_margin = inf;
    if isfield(p, 'f_control_max_Hz') && isfinite(p.f_control_max_Hz)
        frequency_margin = p.f_control_max_Hz / max(f_Hz, eps);
    end
    frequency_ok = frequency_margin >= 1.0;

    motor_rms_ok = current_limits.motor_rms_margin >= 1.0;
    motor_peak_ok = current_limits.motor_peak_margin >= 1.0;
    branch_peak_ok = current_limits.branch_peak_margin >= 1.0;
    hard_current_scaled = isfield(current_limits, 'current_scale') && ...
        current_limits.current_scale < 0.999;
    electrical_ok = motor_rms_ok && motor_peak_ok && branch_peak_ok && frequency_ok;

    battery_ref = calc_battery_reference_limit(p, f_Hz, T_C, SOC);
    I_branch_peak = current_limits.I_branch_peak_A;
    spec_30s_charge_margin = spec_ref.charge_30s_A / max(I_branch_peak, eps);
    spec_30s_discharge_margin = spec_ref.discharge_30s_A / max(I_branch_peak, eps);
    spec_60s_charge_margin = spec_ref.charge_60s_A / max(I_branch_peak, eps);
    spec_60s_discharge_margin = spec_ref.discharge_60s_A / max(I_branch_peak, eps);
    plating_reference_margin = battery_ref.plating_charge_peak_A / max(I_branch_peak, eps);
    plating_reference_ok = plating_reference_margin >= 1.0;

    status = strings(1, 0);
    if electrical_ok && ~hard_current_scaled
        status(end+1) = "电气硬限制满足";
    elseif electrical_ok && hard_current_scaled
        status(end+1) = "已按电流硬限制缩放";
    else
        if ~frequency_ok
            status(end+1) = "频率超控制器参考上限";
        end
        if hard_current_scaled || ~motor_rms_ok || ~motor_peak_ok || ~branch_peak_ok
            status(end+1) = "已触发电流硬限制缩放";
        end
    end

    if plating_reference_ok
        status(end+1) = "析锂参考边界未触发";
    else
        status(end+1) = "析锂参考边界提示";
    end
    status(end+1) = "30s/60s规格窗口仅作低频参考";

    safety = struct();
    safety.enabled = true;
    safety.status = char(join(status, '; '));
    safety.electrical_ok = electrical_ok;
    safety.frequency_ok = frequency_ok;
    safety.motor_rms_ok = motor_rms_ok;
    safety.motor_peak_ok = motor_peak_ok;
    safety.branch_peak_ok = branch_peak_ok;
    safety.plating_ok = plating_reference_ok;
    safety.plating_hard_limit_enabled = false;
    safety.frequency_margin = frequency_margin;
    safety.spec_30s_charge_margin = spec_30s_charge_margin;
    safety.spec_30s_discharge_margin = spec_30s_discharge_margin;
    safety.spec_60s_charge_margin = spec_60s_charge_margin;
    safety.spec_60s_discharge_margin = spec_60s_discharge_margin;
    safety.plating_reference_margin = plating_reference_margin;
    safety.spec_charge_30s_A = spec_ref.charge_30s_A;
    safety.spec_discharge_30s_A = spec_ref.discharge_30s_A;
    safety.spec_charge_60s_A = spec_ref.charge_60s_A;
    safety.spec_discharge_60s_A = spec_ref.discharge_60s_A;
    safety.plating_charge_reference_A = battery_ref.plating_charge_peak_A;
    safety.battery_reference_mode = battery_ref.model;
    safety.note = ['电机/控制器电流和配置的电池高频峰值为硬限制; ', ...
        '规格书30s/60s窗口与析锂模型当前仅作参考展示, 未作为0528目标车型硬限流。'];
end

function ref = calc_battery_reference_limit(p, f_Hz, T_C, SOC)
    params = build_battery_limit_params(p);
    [limit, info] = battery_current_limit_model_0528( ...
        f_Hz, T_C, SOC, p.N_parallel_branch, p.C_cell_Ah, params);

    ref = struct();
    ref.model = limit.model;
    ref.charge_peak_A = limit.charge_peak;
    ref.discharge_peak_A = limit.discharge_peak;
    ref.spec_charge_peak_A = limit.spec_charge_peak;
    ref.spec_discharge_peak_A = limit.spec_discharge_peak;
    ref.plating_charge_peak_A = limit.plating_charge_peak;
    ref.C_rate_plating = info.C_rate_plating;
end

function params = build_battery_limit_params(p)
    params = struct();
    params.limit_mode = p.battery_current_limit_mode;
    params.apply_discharge_spec_limit_in_plating_mode = ...
        p.apply_discharge_spec_limit_in_plating_mode;
    params.current_window_duration_s = p.current_window_duration_s;
    params.current_window_SOC_ref = p.current_window_SOC_ref;
    params.current_window_N_parallel_ref = p.current_window_N_parallel_ref;
    params.current_window_T = p.current_window_T_C;
    params.current_window_charge_30s = p.branch_charge_30s_ref_A;
    params.current_window_discharge_30s = p.branch_discharge_30s_ref_A;
    params.current_window_charge_60s = p.branch_charge_60s_ref_A;
    params.current_window_discharge_60s = p.branch_discharge_60s_ref_A;
    params.R_ct_ref = p.plating_R_ct_ref;
    params.Ea_ct = p.plating_Ea_ct;
    params.R_SEI_ref = p.plating_R_SEI_ref;
    params.Ea_SEI = p.plating_Ea_SEI;
    params.C_dl = p.plating_C_dl;
    params.k_safety = p.plating_k_safety;
    params.R_total_for_alpha = [];
    params.L_for_alpha = [];
end

function [limit, info] = battery_current_limit_model_0528( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params)
    params = fill_default_params(params);

    spec = calc_spec_window(T_C, SOC, N_parallel, params);
    [I_plating_peak, plating] = calc_plating_limit( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params);

    mode = lower(string(params.limit_mode));
    switch mode
        case "off"
            charge_peak = inf;
            discharge_peak = inf;
            enabled_as_limit = false;
        case "spec_window"
            charge_peak = spec.charge_peak;
            discharge_peak = spec.discharge_peak;
            enabled_as_limit = true;
        case "plating_adaptive"
            charge_peak = I_plating_peak;
            if params.apply_discharge_spec_limit_in_plating_mode
                discharge_peak = spec.discharge_peak;
            else
                discharge_peak = inf;
            end
            enabled_as_limit = true;
        otherwise
            error('未知电池侧限流模式: %s。', params.limit_mode);
    end

    limit = struct();
    limit.charge_peak = max(charge_peak, 0);
    limit.discharge_peak = max(discharge_peak, 0);
    limit.enabled_as_limit = enabled_as_limit;
    limit.model = char(mode);
    limit.spec_charge_peak = spec.charge_peak;
    limit.spec_discharge_peak = spec.discharge_peak;
    limit.plating_charge_peak = I_plating_peak;

    info = struct();
    info.spec = spec;
    info.plating = plating;
    info.params = params;
    info.charge_relaxation_vs_spec = I_plating_peak ./ max(spec.charge_peak, eps);
    info.C_rate_plating = I_plating_peak ./ (C_cell_Ah * N_parallel);
end

function params = fill_default_params(params)
    if ~isfield(params, 'limit_mode')
        params.limit_mode = 'plating_adaptive';
    end
    if ~isfield(params, 'apply_discharge_spec_limit_in_plating_mode')
        params.apply_discharge_spec_limit_in_plating_mode = false;
    end
    if ~isfield(params, 'current_window_duration_s')
        params.current_window_duration_s = 30;
    end
    if ~isfield(params, 'current_window_SOC_ref')
        params.current_window_SOC_ref = 0.50;
    end
    if ~isfield(params, 'current_window_N_parallel_ref')
        params.current_window_N_parallel_ref = 1;
    end
    if ~isfield(params, 'R_ct_ref')
        params.R_ct_ref = 0.12e-3;
    end
    if ~isfield(params, 'Ea_ct')
        params.Ea_ct = 3600;
    end
    if ~isfield(params, 'R_SEI_ref')
        params.R_SEI_ref = 0.015e-3;
    end
    if ~isfield(params, 'Ea_SEI')
        params.Ea_SEI = 2500;
    end
    if ~isfield(params, 'C_dl')
        params.C_dl = 1.5;
    end
    if ~isfield(params, 'k_safety')
        params.k_safety = 0.85;
    end
    if ~isfield(params, 'U_e_func')
        params.U_e_func = @(soc) max(0.04, 0.30 - 0.28 * soc);
    end
    if ~isfield(params, 'R_total_for_alpha')
        params.R_total_for_alpha = [];
    end
    if ~isfield(params, 'L_for_alpha')
        params.L_for_alpha = [];
    end
end

function spec = calc_spec_window(T_C, SOC, N_parallel, params)
    has_spec = isfield(params, 'current_window_T') && ...
        isfield(params, 'current_window_charge_30s') && ...
        isfield(params, 'current_window_discharge_30s') && ...
        isfield(params, 'current_window_charge_60s') && ...
        isfield(params, 'current_window_discharge_60s');

    if ~has_spec
        spec = struct('charge_peak', inf, 'discharge_peak', inf, ...
            'T_query', T_C, 'duration_s', params.current_window_duration_s);
        return;
    end

    T_query = min(max(T_C, min(params.current_window_T)), max(params.current_window_T));
    if params.current_window_duration_s <= 30
        charge_table = params.current_window_charge_30s;
        discharge_table = params.current_window_discharge_30s;
    else
        charge_table = params.current_window_charge_60s;
        discharge_table = params.current_window_discharge_60s;
    end

    scale = N_parallel / params.current_window_N_parallel_ref;
    charge_peak = interp1(params.current_window_T, charge_table, T_query, 'linear') * scale;
    discharge_peak = interp1(params.current_window_T, discharge_table, T_query, 'linear') * scale;

    if SOC > params.current_window_SOC_ref
        charge_peak = charge_peak * max(0.25, 1 - 1.2*(SOC - params.current_window_SOC_ref));
    end

    spec = struct();
    spec.charge_peak = max(charge_peak, 0);
    spec.discharge_peak = max(discharge_peak, 0);
    spec.T_query = T_query;
    spec.duration_s = params.current_window_duration_s;
end

function [I_plating_limit, info] = calc_plating_limit( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params)
    T_ref_K = 298.15;
    T_K = T_C + 273.15;

    R_ct_T = params.R_ct_ref .* exp(params.Ea_ct .* (1./T_K - 1/T_ref_K));
    R_SEI_T = params.R_SEI_ref .* exp(params.Ea_SEI .* (1./T_K - 1/T_ref_K));
    f_ct_T = 1 ./ (2 * pi .* R_ct_T .* params.C_dl);
    Z_neg_mag = R_SEI_T + R_ct_T ./ sqrt(1 + (f_Hz ./ f_ct_T).^2);
    U_e = params.U_e_func(SOC);

    k_wave_sq = 4/pi;
    k_wave_tri = 8/pi^2;
    if ~isempty(params.L_for_alpha) && ~isempty(params.R_total_for_alpha)
        alpha = params.R_total_for_alpha .* (1 ./ f_Hz) ./ params.L_for_alpha;
        k_waveform = k_wave_tri + (k_wave_sq - k_wave_tri) .* (1 - exp(-alpha/2));
    else
        k_waveform = k_wave_sq;
        alpha = nan(size(f_Hz));
    end

    I_plating_limit = N_parallel .* U_e ./ (k_waveform .* Z_neg_mag) .* params.k_safety;

    info = struct();
    info.U_e = U_e;
    info.R_ct_T = R_ct_T;
    info.R_SEI_T = R_SEI_T;
    info.f_ct_T = f_ct_T;
    info.Z_neg_mag = Z_neg_mag;
    info.k_waveform = k_waveform;
    info.alpha = alpha;
    info.C_rate_limit = I_plating_limit ./ (C_cell_Ah * N_parallel);
end
