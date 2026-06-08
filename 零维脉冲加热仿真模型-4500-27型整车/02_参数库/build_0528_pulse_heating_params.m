function p = build_0528_pulse_heating_params()
%BUILD_0528_PULSE_HEATING_PARAMS Parameters for the 0528 architecture screen.
% The current values are runnable engineering placeholders derived from the
% earlier 3806 zero-dimensional workflow. Replace them when target vehicle
% data are available.

    p = struct();
    p.study_name = '零维脉冲加热仿真模型0528';
    p.parameter_status = 'demo_from_3806_experience';
    p.parameter_status_cn = '当前为3806经验占位参数, 仅用于架构粗筛';

    % Battery branch basis. Each branch is treated as one 192S1P string.
    p.N_series = 192;
    p.V_cell_nom = 3.22;
    p.C_branch_Ah = 324;
    p.branch_mass_kg = 1244;
    p.Cp_battery_J_per_kgK = 1000;
    p.Cth_branch_J_per_K = p.branch_mass_kg * p.Cp_battery_J_per_kgK;
    p.branch_area_m2 = 9.0;
    p.h_conv_W_per_m2K = 8.0;
    p.enable_heat_loss = true;
    p.thermal_boundary = 'convection';
    p.R_th_branch_K_per_W = 1 / (p.h_conv_W_per_m2K * p.branch_area_m2);

    % OCV and low-temperature resistance lookup.
    p.ocv_soc_bp = [0.10 0.20 0.50 0.90];
    p.ocv_cell_V = [3.18 3.24 3.32 3.42];
    p.R_data_SOC = [0.10 0.20 0.50 0.90];
    p.R_data_T_C = [-20 25];
    R_pack_192S2P_ohm = [ ...
        209.95 206.21 198.43 186.14; ...
         33.50  33.12  31.20  28.90] * 1e-3;
    p.R_branch_192S1P_table_ohm = R_pack_192S2P_ohm * 2;
    p.R_branch_source = '3806 192S2P low-temperature table converted to one 192S1P branch';

    % Motor / MCU placeholders.
    p.motor_count = 2;
    p.motor_Ld_H = 0.26e-3;
    p.motor_Rs_ohm = 0.020;
    p.I_motor_rms_limit_A = 550;
    p.I_motor_peak_limit_A = 778;
    p.f_default_Hz = 1250;
    p.f_control_max_Hz = 1250;
    p.duty_default = 0.50;
    p.branch_hf_peak_limit_A = inf;  % Keep spec windows as references for now.
    p.current_amplitude_scale_default = 1.00;
    p.current_amplitude_scale_scan = [0.40 0.60 0.80 1.00];

    % Simplified inverter loss parameters, same meaning as the earlier model.
    p.V_ce0 = 0.8;
    p.r_ce = 2.5e-3;
    p.V_f0 = 0.7;
    p.r_f = 2.0e-3;
    p.E_on = 25e-3;
    p.E_off = 20e-3;
    p.E_rr = 15e-3;
    p.I_ref_sw = 400;
    p.V_ref_sw = 600;

    % Reference low-frequency current windows, branch-level values.
    p.current_window_T_C = [-10 -5 0 5 10];
    p.branch_charge_30s_ref_A = [97.2 126.35 149.05 174.95 340.2];
    p.branch_discharge_30s_ref_A = [388.8 690.1 706.3 729.0 861.8];
    p.branch_charge_60s_ref_A = [0 97.2 113.4 136.1 261.9];
    p.branch_discharge_60s_ref_A = [388.8 690.1 706.3 729.0 861.8];

    % Battery safety reference model. These are migrated engineering
    % placeholders from the earlier 3806 workflow and are references only.
    p.battery_current_limit_mode = 'plating_adaptive';
    p.apply_discharge_spec_limit_in_plating_mode = false;
    p.current_window_duration_s = 30;
    p.current_window_SOC_ref = 0.50;
    p.current_window_N_parallel_ref = 1;
    p.N_parallel_branch = 1;
    p.C_cell_Ah = p.C_branch_Ah;
    p.plating_R_ct_ref = 0.12e-3;
    p.plating_Ea_ct = 3600;
    p.plating_R_SEI_ref = 0.015e-3;
    p.plating_Ea_SEI = 2500;
    p.plating_C_dl = 1.5;
    p.plating_k_safety = 0.85;

    % Scenario defaults.
    p.temperature_list_C = [-20 -10 0];
    p.SOC_default = 0.50;
    p.frequency_scan_Hz = [500 800 1000 1250 1500 2000];
    p.duty_scan = [0.40 0.50 0.60];
    p.branch_mismatch_sets = [ ...
        1.00 1.00 1.00; ...
        0.90 1.00 1.10];
    p.branch_mismatch_labels = {'nominal', 'R_90_100_110'};
    p.T_amb_C = -20;
    p.T_init_C = -20;
    p.T_target_C = 0;
    p.t_end_min = 30;
    p.dt_s = 5;
end
