function limit_params = build_3806_battery_limit_params(p, R_total_for_alpha, L_for_alpha)
%BUILD_3806_BATTERY_LIMIT_PARAMS Map shared platform fields to battery current limit inputs.

    if nargin < 2
        R_total_for_alpha = [];
    end
    if nargin < 3
        L_for_alpha = [];
    end

    limit_params = struct();
    limit_params.limit_mode = p.battery_current_limit_mode;
    if isfield(p, 'use_current_window_limits') && ~p.use_current_window_limits
        limit_params.limit_mode = 'off';
    end
    limit_params.apply_discharge_spec_limit_in_plating_mode = ...
        p.apply_discharge_spec_limit_in_plating_mode;
    limit_params.current_window_SOC_ref = p.current_window_SOC_ref;
    limit_params.current_window_N_parallel_ref = p.current_window_N_parallel_ref;
    limit_params.current_window_T = p.current_window_T;
    limit_params.current_window_charge_30s = p.current_window_charge_30s;
    limit_params.current_window_discharge_30s = p.current_window_discharge_30s;
    limit_params.current_window_charge_60s = p.current_window_charge_60s;
    limit_params.current_window_discharge_60s = p.current_window_discharge_60s;
    limit_params.current_window_duration_s = p.current_window_duration_s;
    limit_params.R_ct_ref = p.plating_R_ct_ref;
    limit_params.Ea_ct = p.plating_Ea_ct;
    limit_params.R_SEI_ref = p.plating_R_SEI_ref;
    limit_params.Ea_SEI = p.plating_Ea_SEI;
    limit_params.C_dl = p.plating_C_dl;
    limit_params.k_safety = p.plating_k_safety;
    limit_params.R_total_for_alpha = R_total_for_alpha;
    limit_params.L_for_alpha = L_for_alpha;
end
