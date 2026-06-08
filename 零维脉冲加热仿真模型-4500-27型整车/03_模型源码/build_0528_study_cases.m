function study = build_0528_study_cases(p)
%BUILD_0528_STUDY_CASES Study settings for pulse-heating screening.
% Keeps scan conditions separate from physical parameters.

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
    study.branch_mismatch_sets = p.branch_mismatch_sets;
    study.branch_mismatch_labels = p.branch_mismatch_labels;
    study.t_end_min = p.t_end_min;
    study.dt_s = p.dt_s;
end
