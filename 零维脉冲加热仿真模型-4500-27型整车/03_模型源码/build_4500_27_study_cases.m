function study = build_4500_27_study_cases(p)
%BUILD_4500_27_STUDY_CASES Study settings for the 4500-27 screening run.
% 中文说明:
% 本函数把参数库p中的“扫描范围”和“默认工况”整理成study结构体。
% p表示车型和部件参数，study表示本次仿真怎么扫。这样后续可以保持同一套车型参数，
% 只替换study来做不同的工况矩阵。

    study = struct();
    % 全量扫描维度: 温度、SOC、频率、占空比、电流幅值、内阻倍率、电机限流和支路不均衡。
    study.temperature_list_C = p.temperature_list_C;
    study.SOC = p.SOC_default;
    study.frequency_scan_Hz = p.frequency_scan_Hz;
    study.duty_scan = p.duty_scan;
    study.default_temperature_C = p.T_init_C;
    study.default_frequency_Hz = p.f_default_Hz;
    study.default_duty = p.duty_default;
    study.current_amplitude_scale_scan = p.current_amplitude_scale_scan;
    study.default_current_amplitude_scale = p.current_amplitude_scale_default;
    study.R_heat_factor_scan = p.R_heat_factor_scan;
    study.default_R_heat_factor = p.R_heat_factor_default;
    study.motor_rms_limit_scan_A = p.I_motor_rms_limit_scan_A;
    study.default_motor_rms_limit_A = p.I_motor_rms_limit_default_A;
    study.branch_mismatch_sets = p.branch_mismatch_sets;
    study.branch_mismatch_labels = p.branch_mismatch_labels;

    % 双电机同步相关性:
    % rho=1表示电池侧电流理想同相叠加；rho=0表示长期平均不锁相近似；
    % rho<0表示反相趋势风险边界。它不能替代真实PWM和电流环时域仿真。
    study.default_motor_sync_correlation = p.dual_motor_sync_correlation_default;
    study.motor_sync_correlation_scan = p.dual_motor_sync_correlation_scan;

    % 瞬态仿真时间设置，用于估算30min内平均温度和等效SOC变化。
    study.t_end_min = p.t_end_min;
    study.dt_s = p.dt_s;
end
