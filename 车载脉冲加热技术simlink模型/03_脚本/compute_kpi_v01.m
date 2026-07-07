function kpi = compute_kpi_v01(simOut, p)
%COMPUTE_KPI_V01 计算脉冲加热第一版 KPI，对齐逆变器调幅口径第5节。
%
% 输入:
%   simOut - sim() 返回的 SimulationOutput 对象
%   p      - build_single_pack_params_v01() 返回的参数结构体
%
% 输出:
%   kpi - KPI 结构体，字段对齐逆变器调幅口径第5节统一输出字段

    kpi = struct();

    % ===== 基本工况 =====
    kpi.f_sw_Hz = p.pulse_frequency_Hz;
    kpi.duty = p.pulse_duty;
    kpi.simulation_time_s = simOut.tout(end);
    kpi.num_samples = length(simOut.tout);

    % ===== 电流数据提取 =====
    Iabc = simOut.Iabc_out;
    if ndims(Iabc) == 3
        Iabc_2d = squeeze(Iabc)';  % [Nx3]
    else
        Iabc_2d = Iabc;
    end

    t = simOut.tout;

    % 跳过前 20% 暂态
    startIdx = max(2, round(0.2 * size(Iabc_2d, 1)));
    Ia = Iabc_2d(startIdx:end, 1);
    Ib = Iabc_2d(startIdx:end, 2);
    Ic = Iabc_2d(startIdx:end, 3);

    % ===== 电流统计 =====
    kpi.I_actual_peak_A = max([max(abs(Ia)) max(abs(Ib)) max(abs(Ic))]);
    kpi.I_actual_rms_A = (rms(Ia) + rms(Ib) + rms(Ic)) / 3;
    kpi.Ia_rms_A = rms(Ia);
    kpi.Ib_rms_A = rms(Ib);
    kpi.Ic_rms_A = rms(Ic);
    kpi.Ia_peak_A = max(abs(Ia));
    kpi.Ib_peak_A = max(abs(Ib));
    kpi.Ic_peak_A = max(abs(Ic));

    % ===== 目标电流 =====
    kpi.I_target_A = p.pulse_amplitude_A;
    kpi.current_amplitude_scale = kpi.I_actual_rms_A / kpi.I_target_A;

    % ===== 开环原始电流（理论估算） =====
    % 堵转时 PMSM 等效为 RL 支路: Z = Rs + j*omega*Ld
    % 正弦电压驱动下: I_peak = V_peak / |Z|
    omega_elec = 2 * pi * p.pulse_frequency_Hz;
    Z_magnitude = sqrt(p.pmsm_Rs_ohm^2 + (omega_elec * p.pmsm_Ld_H)^2);
    V_peak = 300;  % Sine Wave 幅值
    kpi.I_raw_peak_A = V_peak / Z_magnitude;
    kpi.I_raw_rms_A = kpi.I_raw_peak_A / sqrt(2);

    % ===== 电压 =====
    kpi.V_required_V = V_peak;
    kpi.V_available_V = p.V_pack_nom_V;
    if kpi.V_required_V > kpi.V_available_V
        kpi.limiting_factor = 'voltage_saturation';
    elseif kpi.I_actual_peak_A > p.pmsm_I_peak_limit_A
        kpi.limiting_factor = 'motor_peak_current';
    elseif kpi.I_actual_rms_A > p.pmsm_I_rms_limit_A
        kpi.limiting_factor = 'motor_rms_current';
    else
        kpi.limiting_factor = 'none';
    end

    % ===== 功率估算 =====
    % 电池发热功率: P = I_rms^2 * R_bat
    R_bat_ohm = p.R_branch_table_ohm(1, 3);  % -20C, SOC=0.50 对应 R
    I_battery_rms = kpi.I_actual_rms_A;  % 简化: 母线电流 ≈ 相电流 RMS
    kpi.P_battery_W = I_battery_rms^2 * R_bat_ohm;

    % 电机铜耗: P = 3 * I_rms^2 * Rs (三相)
    kpi.P_motor_W = 3 * kpi.I_actual_rms_A^2 * p.pmsm_Rs_ohm;

    % 逆变器损耗: 占位估算 (无损耗图)
    kpi.P_inverter_W = 0;  % PLACEHOLDER: Controlled VS 是理想源，无损耗

    % ===== 频率验证 =====
    zero_crossings = find(diff(sign(Ia - mean(Ia))) ~= 0);
    if length(zero_crossings) > 2
        periods = diff(t(zero_crossings(1:2:min(20,length(zero_crossings)))));
        if ~isempty(periods)
            kpi.f_estimated_Hz = 1 / (2 * mean(periods));
        else
            kpi.f_estimated_Hz = NaN;
        end
    else
        kpi.f_estimated_Hz = NaN;
    end

    % ===== 安全边界检查 =====
    kpi.motor_rms_margin = p.pmsm_I_rms_limit_A / kpi.I_actual_rms_A;
    kpi.motor_peak_margin = p.pmsm_I_peak_limit_A / kpi.I_actual_peak_A;
    kpi.voltage_margin = kpi.V_available_V / kpi.V_required_V;

    % ===== 汇总标注 =====
    kpi.note_cn = ['第一版物质流验证: Vabc=300V@1250Hz 正弦波驱动, ', ...
        'PMSM 堵转, BEC LumpedThermalMass 热模型; ', ...
        '电流闭环未实现(仅开环电压驱动), 逆变器为理想受控源'];
    kpi.parameter_status = p.parameter_status;
    kpi.data_gaps_count = length(p.data_gaps);
end
