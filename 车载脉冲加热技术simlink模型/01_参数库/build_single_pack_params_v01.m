function p = build_single_pack_params_v01()
%BUILD_SINGLE_PACK_PARAMS_V01 单电池包-逆变器-PMSM 堵转脉冲加热第一版参数。
%
% 本脚本从 L0.5 零维模型 build_4500_27_pulse_heating_params.m 继承单包可复用值，
% 并为 Simscape 物理网络模型（BEC + Average-Value Inverter + PMSM）补充所需参数。
% 缺项用官方示例/文献默认值填充并标 PLACEHOLDER。
%
% 参数来源标注:
%   [L0.5]      = 从 4500-27 L0.5 参数表继承
%   [EE_LIB]    = ee_lib PMSM 块默认示例值（R2025b）
%   [BEC_LIB]   = batt_lib Battery Equivalent Circuit 默认示例值（R2025b）
%   [LITERATURE]= 文献典型值，非目标车型确认参数
%   [PLACEHOLDER]= 占位假设，待实验数据替换

    p = struct();
    p.study_name = '单电池包-逆变器-PMSM 堵转脉冲加热 Simscape 第一版';
    p.parameter_status = 'single_pack_v01_20260707';
    p.parameter_status_cn = ['单电池包第一版: 252S/278Ah单包 + ', ...
        '单PMSM堵转 + 平均值逆变器; 含 PLACEHOLDER 占位参数'];

    %% ========== 电池包参数（单包） ==========
    % 来源 [L0.5]: 3个252S/278Ah电池包并联整体输出; 第一版只用单包
    p.pack_count = 1;                  % [L0.5] 第一版单包
    p.N_series = 252;                  % [L0.5] 单包串联电芯数
    p.C_cell_Ah = 278;                 % [L0.5] 单体容量
    p.C_pack_Ah = p.C_cell_Ah;         % 单包容量（1P）

    % 电压平台 [L0.5]
    p.V_cell_nom_V = 811.44 / 252;     % [L0.5] 单体标称电压
    p.V_pack_nom_V = 811.44;           % [L0.5] 单包标称电压
    p.V_pack_min_V = 630;              % [L0.5]
    p.V_pack_max_V = 919.8;            % [L0.5]

    % OCV-SOC 表 [L0.5]
    p.ocv_soc_bp = [0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 ...
        0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 ...
        0.90 0.95 1.00];
    p.ocv_cell_V = [2.688 3.166 3.203 3.222 3.249 3.267 3.285 ...
        3.288 3.289 3.290 3.291 3.296 3.326 3.329 3.329 ...
        3.329 3.329 3.330 3.332 3.334 3.484];

    % 电池内阻（支路级）[L0.5]
    % 注意: 这是1s BOL放电DCR换算值，不是高频AC阻抗Re(Z,T,SOC,f)
    p.R_data_SOC = [0.10 0.20 0.50 0.90];
    p.R_data_T_C = [-20 25];
    R_cell_1s_mOhm = [ ...
        2.36 2.32 2.23 2.09; ...
        0.33 0.33 0.31 0.29];
    p.R_branch_table_ohm = R_cell_1s_mOhm * 1e-3 * p.N_series;
    p.R_bat_source_cn = '附件1 1s BOL放电DCR, 电芯mOhm换算为252S1P支路; 非高频AC阻抗';

    %% ========== BEC 块参数（Simscape Battery Equivalent Circuit） ==========
    % 来源 [BEC_LIB]: batt_lib BEC 块默认示例值 + [L0.5] 目标值混合

    % BEC 热模型配置
    p.bec_ThermalModel = 'LumpedTemperature';  % [PLAN] 第一版集总热质量模式
    p.bec_BatteryThermalMass_J_per_K = 1.37e6; % [L0.5] branch_mass*Cp = 1370kg*1000J/kgK
    p.bec_thermal_source_cn = 'L0.5 branch_mass_kg=1370, Cp=1000J/kgK';

    % BEC 温度断点 [BEC_LIB] 默认 [278, 293, 313] K，扩展低温段
    p.bec_T_breakpoints_K = [253, 278, 293, 313];  % [-20, 5, 20, 40] C

    % BEC OCV 温度依赖 [PLACEHOLDER]
    % 第一版先用 L0.5 OCV 表（不区分温度），温度依赖设为 0
    % 有 HPPC 数据后替换为 OCV(T,SOC) 表
    p.bec_ocv_thermal_placeholder = true;

    % BEC R0 温度依赖表 [L0.5] 换算到电芯级
    % L0.5 给的是支路级 mOhm，除以 N_series 得电芯级
    p.bec_R0_cell_ohm = R_cell_1s_mOhm * 1e-3;  % 电芯级 [Ohm]
    p.bec_R0_T_bp_K = [253, 298];  % [-20C, 25C] 对应 L0.5 表行
    p.bec_R0_SOC_bp = p.R_data_SOC;

    % BEC RC 网络 [PLACEHOLDER]
    % L0.5 无 RC 参数；第一版用 BEC 默认示例值或设为 0（纯 R0）
    % 有 HPPC/EIS 数据后填入 R1/Tau1, R2/Tau2
    p.bec_RCPairs = 0;               % [PLACEHOLDER] 第一版不用 RC，纯 R0 模型
    p.bec_R1_cell_ohm = 0;           % [PLACEHOLDER]
    p.bec_Tau1_s = 0;                % [PLACEHOLDER]
    p.bec_R2_cell_ohm = 0;           % [PLACEHOLDER]
    p.bec_Tau2_s = 0;                % [PLACEHOLDER]

    % BEC 初始状态
    p.bec_SOC_init = 0.50;           % [L0.5] 默认 SOC 50%
    p.bec_T_init_K = 253.15;         % [L0.5] -20C = 253.15K
    p.bec_T_amb_K = 253.15;          % [L0.5] 环境温度 -20C

    %% ========== PMSM 参数（ee_lib/Electromechanical/Permanent Magnet/PMSM） ==========
    % 来源 [L0.5]: 4500-27 双 CAM255PT56 电机参数（单电机）
    % 注意: L0.5 motor_Rs_ohm = 14e-3/3 是每相等效值，ee_lib PMSM 的 Rs 是每相

    p.pmsm_nPolePairs = 6;                    % [EE_LIB] 默认极对数，[PLACEHOLDER] 待确认
    p.pmsm_Ld_H = 0.2605e-3;                  % [L0.5] 附件2, 550A附近Ld均值
    p.pmsm_Lq_H = 0.3927e-3;                  % [L0.5] 附件2, 550A附近Lq均值
    p.pmsm_Rs_ohm = 14e-3 / 3;                % [L0.5] 三相14mOhm按每相等效4.67mOhm
    p.pmsm_pm_flux_linkage_Wb = 0.05;         % [PLACEHOLDER] 永磁体磁链，待供应商确认

    % PMSM 机械参数
    p.pmsm_J_kg_m2 = 0.01;                    % [PLACEHOLDER] 转动惯量
    p.pmsm_damping_N_m_s = 0;                 % [PLAN] 堵转阻尼设为0

    % PMSM 热参数 [PLACEHOLDER]
    p.pmsm_stator_thermal_mass_J_per_K = 500; % [LITERATURE] 典型定子热质量
    p.pmsm_rotor_thermal_mass_J_per_K = 200;  % [LITERATURE] 典型转子热质量
    p.pmsm_T_init_K = 253.15;                 % [L0.5] -20C

    % PMSM 堵转工况
    p.pmsm_stall_omega_rad_s = 0;             % [PLAN] 堵转零速
    p.pmsm_stall_T_load_N_m = 0;              % [PLAN] 堵转无负载转矩

    % PMSM 电流限制 [L0.5]
    p.pmsm_I_rms_limit_A = 550;               % [L0.5] 60s/30s等级
    p.pmsm_I_peak_limit_A = sqrt(2) * 550;    % [L0.5] 峰值

    %% ========== 逆变器参数（Average-Value Inverter Three-Phase） ==========
    % 来源 [EE_LIB]: ee_lib 默认值 + [L0.5] 电压约束

    p.inv_FRated_Hz = 60;                     % [EE_LIB] 默认，实际由PWM控制
    p.inv_PhaseShift = 0;                     % [EE_LIB] 默认
    p.inv_voltage_ratio = sqrt(6)/pi;         % [EE_LIB] 默认调制比
    p.inv_voltage_ratio_note = 'EE_LIB默认; 后续按实际调制策略调整';

    % 逆变器电压约束 [L0.5]
    p.inv_V_nom_V = 800;                      % [L0.5]
    p.inv_V_min_V = 600;                      % [L0.5]
    p.inv_V_max_V = 910;                      % [L0.5]
    p.inv_UV_protect_V = 580;                 % [L0.5]
    p.inv_OV_protect_V = 930;                 % [L0.5]

    %% ========== 控制参数（信号流 FOC + PWM） ==========
    % 来源 [PLACEHOLDER]: 第一版用工程默认值

    % PI 电流环参数 [PLACEHOLDER]
    p.ctrl_Id_ref_A = 100;                    % [PLAN] 第一版目标 d 轴电流
    p.ctrl_Iq_ref_A = 0;                      % [PLAN] 堵转 q 轴电流为0（零转矩）
    p.ctrl_Kp_d = 0.01;                       % [PLACEHOLDER] d轴PI比例
    p.ctrl_Ki_d = 100;                        % [PLACEHOLDER] d轴PI积分
    p.ctrl_Kp_q = 0.01;                       % [PLACEHOLDER] q轴PI比例
    p.ctrl_Ki_q = 100;                        % [PLACEHOLDER] q轴PI积分
    p.ctrl_Ts_s = 1e-4;                       % [PLACEHOLDER] 控制采样时间 100us

    % PWM 参数 [PLACEHOLDER]
    p.pwm_frequency_Hz = 1250;                % [L0.5] 目标脉冲频率
    p.pwm_duty = 0.50;                        % [L0.5] 默认占空比

    % 脉冲命令发生器 [PLAN]
    p.pulse_frequency_Hz = 1250;              % [L0.5] 高频双向脉冲频率
    p.pulse_duty = 0.50;                      % [L0.5]
    p.pulse_amplitude_A = 100;                % [PLAN] 第一版目标幅值
    p.pulse_bipolar = true;                   % [PLAN] 双向脉冲

    %% ========== 仿真工况 ==========
    % 来源 [L0.5]

    p.sim_T_init_C = -20;                     % [L0.5]
    p.sim_T_amb_C = -20;                      % [L0.5]
    p.sim_T_target_C = 0;                     % [L0.5]
    p.sim_SOC_init = 0.50;                    % [L0.5]
    p.sim_t_end_s = 30;                       % [PLAN] 第一版先跑30s走通
    p.sim_solver = 'ode23t';                  % [PLAN] Simscape 推荐刚性求解器
    p.sim_max_step = 1e-3;                    % [PLAN] 最大步长

    %% ========== KPI 输出口径（对齐逆变器调幅口径第5节） ==========
    p.kpi_fields = {'f_sw_Hz', 'duty', ...
        'I_raw_peak_A', 'I_raw_rms_A', ...
        'I_target_A', 'I_actual_peak_A', 'I_actual_rms_A', ...
        'V_required_V', 'V_available_V', ...
        'limiting_factor', ...
        'P_battery_W', 'P_motor_W', 'P_inverter_W'};
    p.kpi_note_cn = 'KPI 口径对齐逆变器调幅与简单开关建模口径.md 第5节统一输出字段';

    %% ========== 参数来源汇总 ==========
    p.source_summary = {
        'L0.5 build_4500_27_pulse_heating_params.m 继承单包参数';
        'BEC_LIB batt_lib Battery Equivalent Circuit R2025b 默认值';
        'EE_LIB ee_lib PMSM/Average-Value Inverter R2025b 默认值';
        'LITERATURE 文献典型值';
        'PLACEHOLDER 占位假设，待实验数据替换';
        'PLAN 本计划第一版设定值';
    };

    p.data_gaps = {
        '控制器电流环带宽/采样周期/PWM周期 [PLACEHOLDER]';
        '控制器最大调制比/电压限幅/最小脉宽/死区时间 [PLACEHOLDER]';
        'MCU峰值/RMS电流/过流阈值/热降额 [L0.5部分, 待确认]';
        '电机Ld(I,T)/Lq(I,T)/Rs(T)饱和表 [PLACEHOLDER]';
        '电池低温EIS/HPPC Re(Z,T,SOC,f) [PLACEHOLDER]';
        '电池高频/脉冲析锂试验边界 [PLACEHOLDER]';
        '逆变器损耗图或器件开关损耗参数 [PLACEHOLDER]';
        'PMSM永磁体磁链pm_flux_linkage [PLACEHOLDER]';
        'PMSM转动惯量J [PLACEHOLDER]';
    };
end
