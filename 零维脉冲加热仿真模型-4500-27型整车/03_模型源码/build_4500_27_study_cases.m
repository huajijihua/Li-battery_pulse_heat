function study = build_4500_27_study_cases(p)
%BUILD_4500_27_STUDY_CASES Study settings for the 4500-27 screening run.

    study = struct();
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
    study.default_motor_sync_correlation = p.dual_motor_sync_correlation_default;
    study.motor_sync_correlation_scan = p.dual_motor_sync_correlation_scan;
    study.t_end_min = p.t_end_min;
    study.dt_s = p.dt_s;
end
