function results = diagnose_pulse_heating_v03b3()
%DIAGNOSE_PULSE_HEATING_V03B3 Run v03-B3 control-tuning audit cases.
%
% The diagnostic keeps the v03-B2 evidence intact and adds small-signal
% direction checks plus minimal KPI v02 fields needed before v03-C limits.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(modelDir);

    modelName = "pulse_heating_single_pack_v03";
    modulationLimit = 0.95;

    cases = [
        struct("name", "zero_cmd", "mode", "closed_loop", "amp", 0)
        struct("name", "small_cmd_5A", "mode", "closed_loop", "amp", 5)
        struct("name", "small_cmd_20A", "mode", "closed_loop", "amp", 20)
        struct("name", "medium_cmd_100A", "mode", "closed_loop", "amp", 100)
        struct("name", "large_cmd_200A", "mode", "closed_loop", "amp", 200)
        struct("name", "direct_mod_0p2", "mode", "direct_mod", "amp", 0.2)
        struct("name", "direct_mod_0p8", "mode", "direct_mod", "amp", 0.8)
    ];

    results = [];
    for k = 1:numel(cases)
        c = cases(k);
        if c.mode == "closed_loop"
            build_pulse_heating_single_pack_v03b();
            load_system(modelName);
            set_param(modelName, "StopTime", "0.05");
            set_param(modelName + "/Id_ref_cmd", "Amplitude", num2str(c.amp));
        else
            build_pulse_heating_single_pack_v03a(true);
            load_system(modelName);
            set_param(modelName, "StopTime", "0.05");
            set_param(modelName + "/ma_cmd", "Amplitude", num2str(c.amp));
            set_param(modelName + "/mb_cmd", "Amplitude", num2str(c.amp));
            set_param(modelName + "/mc_cmd", "Amplitude", num2str(c.amp));
        end

        simOut = sim(modelName, "ReturnWorkspaceOutputs", "on");
        caseResult = compute_kpi_v02(simOut, c.name, c.mode, c.amp, modulationLimit);
        results = [results; caseResult]; %#ok<AGROW>
        printCase(caseResult);
    end

    % Leave the working model in the closed-loop v03-B state after diagnostics.
    build_pulse_heating_single_pack_v03b();
end

function printCase(r)
    fprintf(['%s mode=%s amp=%.6g VbatRMS=%.6g IbatRMS=%.6g ', ...
        'IabcRMS=%.6g IabcPeak=%.6g IdRefRMS=%.6g IdFbRMS=%.6g ', ...
        'IdErrRMS=%.6g mdRMS=%.6g mqRMS=%.6g mabcPeak=%.6g saturated=%d limit=%s\n'], ...
        r.caseName, r.mode, r.commandAmplitude, r.V_battery_terminal_rms_V, ...
        r.I_battery_terminal_rms_A, r.I_motor_phase_rms_A, r.I_motor_phase_peak_A, ...
        r.Id_ref_rms_A, r.Id_fb_rms_A, r.tracking_error_rms_A, r.md_rms, r.mq_rms, ...
        r.mabc_peak, r.is_modulation_saturated, r.limiting_factor);
end
