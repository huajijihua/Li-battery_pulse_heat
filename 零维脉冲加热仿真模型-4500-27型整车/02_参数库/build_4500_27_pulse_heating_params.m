function p = build_4500_27_pulse_heating_params()
%BUILD_4500_27_PULSE_HEATING_PARAMS Updated 4500-27 vehicle parameters.
% Values are taken from 零维脉冲加热_参数需求.xlsx updated on 2026-06-08.
% 中文说明:
% 本函数集中定义4500-27整车零维模型所需的所有参数。输出p是一个结构体，
% 后续电路、电热、限流和安全边界计算都从p读取参数。这里既包含已收到的
% 目标车型数据，也包含用于粗筛的占位假设；占位项均应在报告中保留边界说明。

    % 基本项: 研究名称和参数状态，用于命令行和输出表标识当前参数版本。
    p = struct();
    p.study_name = '4500-27型整车零维脉冲加热仿真';
    p.parameter_status = 'target_vehicle_updated_20260608';
    p.parameter_status_cn = ['4500-27更新参数: 811.44V高压平台, ', ...
        '3个252S/278Ah电池包并联输出, 双CAM255PT56电机'];

    % 电池包/支路基础参数:
    % 参数表给出3个电池包并联输出且非独立输出。零维模型把每个电池包视作
    % 一个并联支路；当前4500-27实车方案不假设单包可独立接入电驱。
    p.N_series = 252;
    p.V_cell_nom = 811.44 / 252;
    p.V_pack_nom_V = 811.44;
    p.V_pack_min_V = 630;
    p.V_pack_max_V = 919.8;
    p.pack_count_vehicle = 3;
    p.C_branch_Ah = 278;
    p.E_branch_nom_kWh = 225.6;
    p.branch_mass_kg = 1370;
    p.Cp_battery_J_per_kgK = 1000;
    p.Cth_branch_J_per_K = p.branch_mass_kg * p.Cp_battery_J_per_kgK;
    p.branch_area_m2 = 8.0;
    p.h_conv_W_per_m2K = 5.0;
    p.h_conv_scan_W_per_m2K = [0 2 5 10 20];
    p.enable_heat_loss = true;
    p.thermal_boundary = 'convection';
    p.R_th_branch_K_per_W = 1 / (p.h_conv_W_per_m2K * p.branch_area_m2);
    p.thermal_assumption_cn = ['电池包比热容、低温预热时冷却液/泵阀状态未提供; ', ...
        '当前按Cp=1000J/kg/K和弱对流散热作粗筛占位'];

    % OCV表:
    % 根据SOC插值得到单体开路电压，再乘以串数得到电池包电压。当前未加入OCV温度修正。
    p.ocv_soc_bp = [0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 ...
        0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 ...
        0.90 0.95 1.00];
    p.ocv_cell_V = [2.688 3.166 3.203 3.222 3.249 3.267 3.285 ...
        3.288 3.289 3.290 3.291 3.296 3.326 3.329 3.329 ...
        3.329 3.329 3.330 3.332 3.334 3.484];

    % 电池内阻表:
    % 附件1给的是电芯级1s BOL放电DCR，这里换算成一个252S1P电池包支路电阻。
    % 这不是高频AC阻抗Re(Z)，所以只能作为高频脉冲发热粗筛的保守参考。
    p.R_data_SOC = [0.10 0.20 0.50 0.90];
    p.R_data_T_C = [-20 25];
    R_cell_1s_mOhm = [ ...
        2.36 2.32 2.23 2.09; ...
        0.33 0.33 0.31 0.29];
    p.R_branch_table_ohm = R_cell_1s_mOhm * 1e-3 * p.N_series;
    p.R_heat_factor_default = 1.00;
    p.R_heat_factor_scan = [0.30 0.50 0.70 1.00];
    p.R_branch_source = ['附件1 1s BOL放电DCR, 电芯mOhm换算为252S1P支路; ', ...
        '未获得高频AC阻抗/HPPC温度-SOC全表; R_heat_factor用于高频阻抗敏感性'];

    % 电机/逆变器约束:
    % Ld用于当前零速/堵转RL近似计算，Lq暂作参考。电机RMS和峰值电流用于硬限流缩放。
    % motor_Rs_ohm按“三相14mOhm为三相总等效”解释，因此除以3得到每相等效值；
    % 该解释需要供应商资料最终确认。
    p.motor_count = 2;
    p.motor_Ld_H = 0.2605e-3;     % 附件2, 550A附近Ld均值
    p.motor_Lq_H = 0.3927e-3;     % 附件2, 550A附近Lq均值, for reference
    p.motor_Rs_ohm = 14e-3 / 3;   % 三相14mOhm@25C interpreted as total three-phase
    p.motor_Rs_source_cn = '三相14±0.5mOhm@25C, 模型按每相等效约4.67mOhm处理';
    p.I_motor_rms_limit_A = 550;  % 550Arms short-time electrical boundary
    p.I_motor_peak_limit_A = sqrt(2) * p.I_motor_rms_limit_A;
    p.I_motor_rms_continuous_A = 320;
    p.I_motor_rms_short_A = 550;
    p.I_motor_rms_limit_default_A = 550;
    p.I_motor_rms_limit_scan_A = [320 450 550];
    p.motor_current_limit_note_cn = ['550Arms来自60s/30s等级约束, ', ...
        '320Arms为>=30min持续电流; 当前图表显示电气能力, 长时热耐久需单独验证'];

    p.inverter_V_nom_V = 800;
    p.inverter_V_min_V = 600;
    p.inverter_V_max_V = 910;
    p.inverter_UV_protect_V = 580;
    p.inverter_OV_protect_V = 930;
    p.f_default_Hz = 1250;
    p.f_control_min_Hz = 1250;
    p.f_control_max_Hz = 4000;
    p.duty_default = 0.50;
    p.branch_hf_peak_limit_A = inf;  % BMS high-frequency limit not supplied.
    p.current_amplitude_scale_default = 1.00;
    p.current_amplitude_scale_scan = [0.40 0.60 0.80 1.00 1.20];

    % 逆变器损耗占位参数:
    % 当前没有目标硬件损耗图或器件热模型，因此这些参数只用于损耗量级估算，
    % 不能用于逆变器结温、寿命或连续工作能力结论。
    p.V_ce0 = 0.8;
    p.r_ce = 2.5e-3;
    p.V_f0 = 0.7;
    p.r_f = 2.0e-3;
    p.E_on = 25e-3;
    p.E_off = 20e-3;
    p.E_rr = 15e-3;
    p.I_ref_sw = 400;
    p.V_ref_sw = 800;

    % 电池30s/60s参考窗口:
    % 这些窗口按SOC 50%参考整理，只用于低频/准直流规格参考展示，
    % 不是kHz脉冲回充半周的硬限流边界。
    p.current_window_T_C = [-20 -10 0 10];
    p.branch_charge_30s_ref_A = [3.6 13.4 47.4 136.0];
    p.branch_charge_60s_ref_A = [23 73 216 474] ./ 3.291;
    p.branch_discharge_30s_ref_A = [320 767 1515 2071] ./ 3.291;
    p.branch_discharge_60s_ref_A = p.branch_discharge_30s_ref_A;

    % 析锂风险参考接口:
    % 当前缺少目标电芯低温EIS、HPPC和析锂试验边界，因此该模型只输出风险参考裕度。
    % 它不应被解释为已标定的BMS硬保护逻辑。
    p.battery_current_limit_mode = 'plating_adaptive';
    p.apply_discharge_spec_limit_in_plating_mode = false;
    p.current_window_duration_s = 60;
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

    % 仿真默认工况与扫描范围:
    % temperature/frequency/duty/current_amplitude_scale用于全量粗筛；
    % branch_mismatch_sets用于检查三包支路阻抗不一致导致的不均流；
    % dual_motor_sync_correlation用于双电机电池侧电流同步风险边界。
    p.temperature_list_C = [-20 -10 0];
    p.SOC_default = 0.50;
    p.frequency_scan_Hz = [1250 2000 3000 4000];
    p.duty_scan = [0.40 0.50 0.60];
    p.branch_mismatch_sets = [ ...
        1.00 1.00 1.00; ...
        0.90 1.00 1.10];
    p.branch_mismatch_labels = {'nominal', 'R_90_100_110'};
    p.dual_motor_sync_correlation_default = 1.00;
    p.dual_motor_sync_correlation_scan = [1.00 0.75 0.50 0.00 -0.50];
    p.dual_motor_sync_note_cn = ['双电机同步相关系数rho仅用于L0.5控制风险边界: ', ...
        'rho=1表示电池侧电流理想同相合成, rho=0表示不同频/不锁相长期平均近似, ', ...
        'rho<0表示反相趋势风险; 该口径不替代真实PWM/dq控制仿真'];
    p.T_amb_C = -20;
    p.T_init_C = -20;
    p.T_target_C = 0;
    p.t_end_min = 30;
    p.dt_s = 5;
end
