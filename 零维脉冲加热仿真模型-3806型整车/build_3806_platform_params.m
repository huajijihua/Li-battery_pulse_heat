function [p, use_demo_values] = build_3806_platform_params(model_variant)
%BUILD_3806_PLATFORM_PARAMS Shared 3806 pulse-heating parameters.
% Supported variants:
%   dual_inphase
%   dual_inphase_lowtemp_window
%   single_motor_isolated

    if nargin < 1 || isempty(model_variant)
        model_variant = 'dual_inphase_lowtemp_window';
    end

    model_variant = lower(string(model_variant));
    use_demo_values = false;

    switch model_variant
        case "dual_inphase"
            motor_count = 2;
            use_current_window_limits = false;
            battery_current_limit_mode = 'off';
        case "dual_inphase_lowtemp_window"
            motor_count = 2;
            use_current_window_limits = true;
            battery_current_limit_mode = 'plating_adaptive';
        case "single_motor_isolated"
            motor_count = 1;
            use_current_window_limits = true;
            battery_current_limit_mode = 'plating_adaptive';
        otherwise
            error('未支持的3806模型变体: %s。', model_variant);
    end

    p = struct();
    p.model_variant = char(model_variant);

    % 车辆/电池系统参数
    p.vehicle_name = '3806 6x4 BEV';
    p.drive_form = '6x4';
    p.cab = 'J6G';
    p.pack_name = 'CATL L324D06';
    p.controller_name = '9335020-3806-C0';
    p.motor_name = 'CAM255PT52';
    p.motor_count = motor_count;
    p.single_pack_N_series = 96;
    p.single_pack_N_parallel = 1;
    p.single_pack_count = 4;
    p.pack_series_count = 2;
    p.pack_parallel_count = 2;
    p.single_pack_V_nom = 309.12;
    p.single_pack_E_kWh = 100.15488;
    p.single_pack_mass_kg = 622;
    p.N_series = 192;
    p.N_parallel = 2;
    p.cell_count = 384;
    p.V_cell_nom = 3.22;
    p.C_cell = 324;
    p.cell_mass_kg = 5.55;
    p.C_pack_Ah = p.C_cell * p.N_parallel;
    p.V_pack_nom = p.N_series * p.V_cell_nom;
    p.E_pack_kWh = p.V_pack_nom * p.C_pack_Ah / 1000;
    p.pack_count = 4;
    p.V_cell_min_warm = 2.5;
    p.V_cell_min_cold = 2.0;
    p.V_cell_max = 3.65;
    p.V_pack_min_warm = p.N_series * p.V_cell_min_warm;
    p.V_pack_min_cold = p.N_series * p.V_cell_min_cold;
    p.V_pack_max = p.N_series * p.V_cell_max;
    p.inverter_V_min = 450;
    p.inverter_V_max = 750;
    p.zero_speed_enable_known = true;

    % 电池内阻与窗口表
    p.R_data_SOC = [0.10 0.20 0.50 0.90];
    p.R_data_T = [-20 25];
    p.R_pack_1s_table = [ ...
        209.95 206.21 198.43 186.14; ...
         33.50  33.12  31.20  28.90] * 1e-3;
    p.R_data_source = 'AD02 cell window table, converted to 192S2P vehicle battery system';
    p.R_cell_1kHz_25C_40SOC = 0.21e-3;
    p.R_cell_1kHz_tol = 0.06e-3;
    p.use_frequency_resistance_correction = false;
    p.current_window_SOC_ref = 0.50;
    p.current_window_N_parallel_ref = 2;
    p.current_window_T = [-10 -5 0 5 10];
    p.current_window_charge_60s = [0 194.4 226.8 272.2 523.8];
    p.current_window_discharge_60s = [777.6 1380.2 1412.6 1458.0 1723.6];
    p.current_window_charge_30s = [194.4 252.7 298.1 349.9 680.4];
    p.current_window_discharge_30s = [777.6 1380.2 1412.6 1458.0 1723.6];
    p.current_window_duration_s = 30;
    p.use_current_window_limits = use_current_window_limits;
    p.battery_current_limit_mode = battery_current_limit_mode;
    p.apply_discharge_spec_limit_in_plating_mode = false;

    % 析锂模型与连续倍率边界
    p.plating_R_ct_ref = 0.12e-3;
    p.plating_Ea_ct = 3600;
    p.plating_R_SEI_ref = 0.015e-3;
    p.plating_Ea_SEI = 2500;
    p.plating_C_dl = 1.5;
    p.plating_k_safety = 0.85;
    p.cont_charge_C_25C = 1.0;
    p.cont_discharge_C_25C = 1.0;
    p.low_temp_capacity_T = [-20 0];
    p.low_temp_capacity_retention = [0.75 0.85];

    % 热参数
    p.M_bat = 2488;
    p.M_cell_total = 2131;
    p.Cp_bat = 1000;
    p.Cth_bat = p.M_bat * p.Cp_bat;
    p.thermal_boundary = 'convection_radiation';
    p.A_pack_ext = 18.0;
    p.h_pack_conv = 8.0;
    p.epsilon_pack = 0.85;
    p.sigma_sb = 5.670374419e-8;
    p.R_th_pack = 1 / (p.h_pack_conv * p.A_pack_ext);

    % BMS/整车与多合一边界
    p.I_pack_peak_limit = inf;
    p.I_pack_rms_limit = inf;
    p.I_motor_rms_limit = 550;
    p.I_motor_peak_limit = 778;

    % 电机参数
    motor_data = build_cam255pt52_motor_data();
    p.motor_data_source = motor_data.param_source;
    p.Rs_ref_temp_C = motor_data.Rs_ref_temp_C;
    p.Rs_copper_alpha_per_C = 0.00393;
    p.Rs_phase_ref_ohm = motor_data.Rs_phase_ref_ohm;
    p.R_s = apply_copper_temp_correction_local( ...
        p.Rs_phase_ref_ohm, p.Rs_ref_temp_C, motor_data.Ld_table_temp_C, p.Rs_copper_alpha_per_C);
    p.Ld_map_temp_C = motor_data.Ld_table_temp_C;
    p.Ld_current_bp_A = motor_data.Ld_table_current_A;
    p.Ld_map_H = motor_data.Ld_table_H;
    p.L_d = motor_data.Ld_nominal_H;
    p.use_ld_lookup = true;

    % 平均效率与频率边界
    p.use_average_loss_model = false;
    p.eta_motor_ctrl_avg = 0.90;
    p.eta_ctrl_avg = 0.96;
    p.eta_motor_only_avg = p.eta_motor_ctrl_avg / p.eta_ctrl_avg;
    p.f_normal_run_min = 3300;
    p.f_normal_run_max = 4000;
    p.f_stall_carrier_max = 1250;
    p.f_sw = p.f_stall_carrier_max;
    p.D = 0.50;
    p.f_control_min = 100;
    p.f_control_max = p.f_stall_carrier_max;
    p.f_postprocess_max = 3000;
    p.fig2_I_pack_rms_clim = [0, 1200];
    p.fig2_L_display_mH = [0.05, 0.80];
    p.fig6_dTdt_clim = [0, 2.0];
    p.fig6_L_display_mH = [0.05, 0.40];

    % 逆变器简化损耗参数
    p.V_ce0 = 0.8;
    p.r_ce = 2.5e-3;
    p.V_f0 = 0.7;
    p.r_f = 2.0e-3;
    p.E_on = 25e-3;
    p.E_off = 20e-3;
    p.E_rr = 15e-3;
    p.I_ref_sw = 400;
    p.V_ref_sw = 600;

    % 默认仿真工况
    p.T_amb = -20;
    p.T_init = -20;
    p.T_target = 0;
    p.SOC_init = 0.50;
    p.t_end_min = 30;
    p.dt = 1.0;
end

function R_hot = apply_copper_temp_correction_local(R_ref, T_ref_C, T_hot_C, alpha_per_C)
    R_hot = R_ref * (1 + alpha_per_C * (T_hot_C - T_ref_C));
end
