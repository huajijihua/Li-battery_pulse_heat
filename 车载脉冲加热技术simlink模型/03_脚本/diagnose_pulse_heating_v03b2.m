function results = diagnose_pulse_heating_v03b2()
%DIAGNOSE_PULSE_HEATING_V03B2 Locate where current response is blocked.
%
% The diagnostic separates battery/DC-link availability, controller output,
% VSC AC-side voltage generation, and PMSM current response. It also runs a
% direct modulation case to distinguish parameter magnitude issues from a
% closed-loop controller issue.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(modelDir);

    build_pulse_heating_single_pack_v03b();
    modelName = "pulse_heating_single_pack_v03";
    load_system(modelName);
    set_param(modelName, "StopTime", "0.05");

    cases = [
        struct("name", "zero_cmd", "mode", "closed_loop", "amp", 0)
        struct("name", "small_cmd_20A", "mode", "closed_loop", "amp", 20)
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
        caseResult = summarizeCase(c.name, c.mode, c.amp, simOut);
        results = [results; caseResult]; %#ok<AGROW>
        printCase(results(k));
    end

    % Leave the working model in the closed-loop v03-B state after diagnostics.
    build_pulse_heating_single_pack_v03b();
end

function r = summarizeCase(caseName, modeName, amplitude, simOut)
    r = struct();
    r.caseName = string(caseName);
    r.mode = string(modeName);
    r.commandAmplitude = amplitude;

    r.I_bat_rms_A = signalRms(simOut, "I_battery_terminal_log");
    r.V_bat_rms_V = signalRms(simOut, "V_battery_terminal_log");
    r.Iabc_rms_A = signalRms(simOut, "Iabc_motor_log");
    r.batteryVoltage_rms_V = signalRms(simOut, "batteryVoltage_log");
    r.batteryCurrent_rms_A = signalRms(simOut, "batteryCurrent_log");

    r.Id_ref_rms_A = signalRms(simOut, "Id_ref_log");
    r.Id_fb_rms_A = signalRms(simOut, "Id_fb_log");
    r.Iq_fb_rms_A = signalRms(simOut, "Iq_fb_log");
    r.Id_error_rms_A = signalRms(simOut, "Id_error_log");
    r.md_rms = signalRms(simOut, "md_cmd_log");
    r.mq_rms = signalRms(simOut, "mq_cmd_log");
end

function value = signalRms(simOut, signalName)
    names = simOut.who;
    if ~any(strcmp(names, signalName))
        value = NaN;
        return;
    end
    ts = simOut.get(signalName);
    data = squeeze(ts.Data);
    if isempty(data)
        value = NaN;
        return;
    end
    if isvector(data)
        data = data(:);
    elseif size(data, 1) < size(data, 2) && size(data, 2) == numel(ts.Time)
        data = data';
    end
    startIdx = max(1, round(0.2 * size(data, 1)));
    value = rms(data(startIdx:end, :), "all");
end

function printCase(r)
    fprintf(['%s mode=%s amp=%.6g ', ...
        'VbatRMS=%.6g IbatRMS=%.6g IabcRMS=%.6g ', ...
        'IdRefRMS=%.6g IdFbRMS=%.6g IdErrRMS=%.6g mdRMS=%.6g mqRMS=%.6g\n'], ...
        r.caseName, r.mode, r.commandAmplitude, r.V_bat_rms_V, r.I_bat_rms_A, r.Iabc_rms_A, ...
        r.Id_ref_rms_A, r.Id_fb_rms_A, r.Id_error_rms_A, r.md_rms, r.mq_rms);
end
