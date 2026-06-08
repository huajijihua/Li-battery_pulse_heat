function [limit, info] = battery_current_limit_model(f, T_celsius, SOC, N_parallel, C_cell, params)
% BATTERY_CURRENT_LIMIT_MODEL  高频脉冲加热电池侧电流限制模型。
%
% 本函数面向零维脉冲加热系统模型, 同时保留两类边界:
%   1) 电芯规格书30s/60s脉冲充放电窗口: 低频或准直流口径, 作为证据边界;
%   2) 高频交流/脉冲析锂边界: 基于负极阻抗和负极电位的回充半周限制。
%
% 推荐在高频脉冲加热中使用 plating_adaptive 模式:
%   充电/回充半周用析锂极化判据限制;
%   放电半周不以析锂为主约束, 由器件、电压或独立BMS边界限制。
%
% 参考机理:
%   - 析锂风险由负极电位是否低于Li/Li+控制;
%   - 高频下双电层电容分流电荷转移支路, 法拉第反应电流下降;
%   - 规格书30s/60s窗口不能直接外推为kHz级交变电流硬上限。

    if nargin < 6 || isempty(params)
        params = struct();
    end

    params = fill_default_params(params);

    spec = calc_spec_window(T_celsius, SOC, N_parallel, params);
    [I_plating_peak, plating] = calc_plating_limit(f, T_celsius, SOC, N_parallel, C_cell, params);

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

    if nargout > 1
        info = struct();
        info.spec = spec;
        info.plating = plating;
        info.params = params;
        info.charge_relaxation_vs_spec = I_plating_peak ./ max(spec.charge_peak, eps);
        info.C_rate_plating = I_plating_peak ./ (C_cell * N_parallel);
    end
end

function params = fill_default_params(params)
% 默认参数为可运行的工程初值, 后续应由三电极/EIS/低温脉冲试验校准。

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
        params.current_window_N_parallel_ref = 2;
    end

    if ~isfield(params, 'R_ct_ref')
        params.R_ct_ref = 0.12e-3;   % [ohm] 单芯负极Rct @25C
    end
    if ~isfield(params, 'Ea_ct')
        params.Ea_ct = 3600;         % [K]
    end
    if ~isfield(params, 'R_SEI_ref')
        params.R_SEI_ref = 0.015e-3; % [ohm] 单芯SEI电阻 @25C
    end
    if ~isfield(params, 'Ea_SEI')
        params.Ea_SEI = 2500;        % [K]
    end
    if ~isfield(params, 'C_dl')
        params.C_dl = 1.5;           % [F] 单芯负极双电层等效电容
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

function spec = calc_spec_window(T_celsius, SOC, N_parallel, params)
% 插值得到规格书30s/60s低温电流窗口。窗口为Pack峰值幅值口径。

    has_spec = isfield(params, 'current_window_T') && ...
        isfield(params, 'current_window_charge_30s') && ...
        isfield(params, 'current_window_discharge_30s') && ...
        isfield(params, 'current_window_charge_60s') && ...
        isfield(params, 'current_window_discharge_60s');

    if ~has_spec
        spec = struct('charge_peak', inf, 'discharge_peak', inf, ...
            'T_query', T_celsius, 'duration_s', params.current_window_duration_s);
        return;
    end

    T_query = min(max(T_celsius, min(params.current_window_T)), max(params.current_window_T));
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

    % 规格书窗口来自50%SOC。高SOC回充更易析锂, 这里只收紧, 不外推放宽。
    if SOC > params.current_window_SOC_ref
        charge_peak = charge_peak * max(0.25, 1 - 1.2*(SOC - params.current_window_SOC_ref));
    end

    spec = struct();
    spec.charge_peak = max(charge_peak, 0);
    spec.discharge_peak = max(discharge_peak, 0);
    spec.T_query = T_query;
    spec.duration_s = params.current_window_duration_s;
end

function [I_plating_limit, info] = calc_plating_limit(f, T_celsius, SOC, N_parallel, C_cell, params)
% 基于负极EEC阻抗的高频回充半周析锂限制。

    T_ref = 298.15;
    T_kelvin = T_celsius + 273.15;

    R_ct_T = params.R_ct_ref .* exp(params.Ea_ct .* (1./T_kelvin - 1/T_ref));
    R_SEI_T = params.R_SEI_ref .* exp(params.Ea_SEI .* (1./T_kelvin - 1/T_ref));
    f_ct_T = 1 ./ (2 * pi .* R_ct_T .* params.C_dl);
    Z_neg_mag = R_SEI_T + R_ct_T ./ sqrt(1 + (f ./ f_ct_T).^2);
    U_e = params.U_e_func(SOC);

    k_wave_sq = 4/pi;
    k_wave_tri = 8/pi^2;
    if ~isempty(params.L_for_alpha) && ~isempty(params.R_total_for_alpha)
        alpha = params.R_total_for_alpha .* (1 ./ f) ./ params.L_for_alpha;
        k_waveform = k_wave_tri + (k_wave_sq - k_wave_tri) .* (1 - exp(-alpha/2));
    else
        k_waveform = k_wave_sq;
        alpha = nan(size(f));
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
    info.C_rate_limit = I_plating_limit ./ (C_cell * N_parallel);
end
