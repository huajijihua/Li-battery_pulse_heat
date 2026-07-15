function results = run_v4i_behavior_matrix()
%RUN_V4I_BEHAVIOR_MATRIX V4-I behavior matrix regression (6 cases).
%
% Validates SystemKPI 24/24 numeric, LimitStatus 10/10 numeric, and
% behavior assertions across 6 operating points including current
% limiting and zero-command verification.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupDir = onCleanup(@() cd(oldDir));
    cd(modelDir);

    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");
    assert(isfile(modelPath), "V4I:MissingModel", "Model file is missing: %s", modelPath);

    wasLoaded = bdIsLoaded(modelName);
    load_system(modelPath);
    modelCleanup = onCleanup(@() closeIfNeeded(modelName, wasLoaded));

    set_param(modelName, "Solver", "ode23tb");
    set_param(modelName, "FixedStep", "5e-5");
    set_param(modelName, "MaxStep", "5e-5");

    modelWorkspace = get_param(modelName, "ModelWorkspace");
    originalAmp = modelWorkspace.getVariable("pulse_id_amplitude_A");
    originalFreq = modelWorkspace.getVariable("diagnostic_frequency_Hz");
    restoreVars = onCleanup(@() restoreOriginalVars(modelWorkspace, originalAmp, originalFreq));

    instrumentation = addTemporaryLogging(modelName);
    loggingCleanup = onCleanup(@() removeTemporaryLogging(instrumentation));

    cases = [
        struct("name", "zero_cmd", "amp", 0, "freq", 1250, "stopTime", 0.01)
        struct("name", "low_freq_small", "amp", 1, "freq", 50, "stopTime", 0.1)
        struct("name", "diagnostic_freq", "amp", 1, "freq", 1250, "stopTime", 0.01)
        struct("name", "medium_current", "amp", 5, "freq", 50, "stopTime", 1)
        struct("name", "high_current_limit", "amp", 20, "freq", 50, "stopTime", 0.1)
        struct("name", "long_10A", "amp", 10, "freq", 50, "stopTime", 2)
    ];

    results = repmat(emptyCaseResult(), numel(cases), 1);
    for k = 1:numel(cases)
        c = cases(k);
        modelWorkspace.assignin("pulse_id_amplitude_A", c.amp);
        modelWorkspace.assignin("diagnostic_frequency_Hz", c.freq);

        in = Simulink.SimulationInput(modelName);
        in = in.setModelParameter("StopTime", num2str(c.stopTime, "%.15g"), ...
            "ReturnWorkspaceOutputs", "on");
        fprintf("[%d/%d] %s (amp=%g, freq=%g, stop=%gs)...\n", ...
            k, numel(cases), c.name, c.amp, c.freq, c.stopTime);
        out = sim(in);

        limitStatus = getFinalTimeseriesVector(out.get("v4i_LimitStatus_ts"), 10);

        kpiData = squeeze(out.get("v4i_SystemKPI_ts").Data);
        kpiInitial = kpiData(1, :);
        kpiFinal = kpiData(end, :);

        r = emptyCaseResult();
        r.caseName = c.name;
        r.pulse_id_amplitude_A = c.amp;
        r.diagnostic_frequency_Hz = c.freq;
        r.stopTime_s = c.stopTime;
        r.stopEvent = string(out.SimulationMetadata.ExecutionInfo.StopEvent);
        r.finalTime_s = out.tout(end);

        r.T_batt_initial_K = kpiInitial(13);
        r.T_batt_final_K = kpiFinal(13);
        r.T_stator_initial_C = kpiInitial(14);
        r.T_stator_final_C = kpiFinal(14);
        r.I_motor_rms_A = kpiFinal(3);
        r.I_limit_margin_A = kpiFinal(19);
        r.track_err_rms_A = kpiFinal(16);
        r.limit_factor = kpiFinal(23);
        r.safety_margin_A = kpiFinal(22);

        paData = squeeze(out.get("v4i_protection_action_ts").Data);
        r.protection_action_max = max(paData);
        r.protection_action_final = paData(end);

        r.structural_pass = r.stopEvent == "ReachedStopTime" && ...
            abs(r.finalTime_s - c.stopTime) < 1e-6;
        r.all_numeric_pass = all(isfinite(kpiFinal)) && all(isfinite(limitStatus));

        charge_limit = 13.5;
        paFinal = paData(end);
        if c.amp == 0
            r.limit_behavior_pass = abs(r.I_motor_rms_A) < 5.0;
        elseif c.amp >= charge_limit
            r.limit_behavior_pass = r.I_limit_margin_A <= 0.1;
        else
            % For non-saturating cases, transient protection trips are
            % allowed (PI startup overshoot), but final state must be normal.
            r.limit_behavior_pass = r.I_limit_margin_A > 0 && paFinal == 0;
        end

        if c.stopTime >= 0.5
            r.thermal_behavior_pass = r.T_batt_final_K >= r.T_batt_initial_K - 0.001 && ...
                r.T_stator_final_C >= r.T_stator_initial_C - 0.001;
        else
            r.thermal_behavior_pass = true;
        end

        r.zero_cmd_pass = c.amp ~= 0 || abs(r.I_motor_rms_A) < 5.0;

        r.passed = r.structural_pass && r.all_numeric_pass && ...
            r.limit_behavior_pass && r.thermal_behavior_pass && r.zero_cmd_pass;
        results(k) = r;
        printCase(r);
    end

    fprintf("\n=== Summary ===\n");
    for k = 1:numel(results)
        r = results(k);
        fprintf("%s: passed=%d (struct=%d numeric=%d limit=%d thermal=%d zero=%d)\n", ...
            r.caseName, r.passed, r.structural_pass, r.all_numeric_pass, ...
            r.limit_behavior_pass, r.thermal_behavior_pass, r.zero_cmd_pass);
    end
    fprintf("\nTotal: %d/%d passed\n", sum([results.passed]), numel(results));
end

function r = emptyCaseResult()
    r = struct( ...
        "caseName", "", ...
        "pulse_id_amplitude_A", NaN, ...
        "diagnostic_frequency_Hz", NaN, ...
        "stopTime_s", NaN, ...
        "stopEvent", "", ...
        "finalTime_s", NaN, ...
        "T_batt_initial_K", NaN, ...
        "T_batt_final_K", NaN, ...
        "T_stator_initial_C", NaN, ...
        "T_stator_final_C", NaN, ...
        "I_motor_rms_A", NaN, ...
        "I_limit_margin_A", NaN, ...
        "track_err_rms_A", NaN, ...
        "limit_factor", NaN, ...
        "safety_margin_A", NaN, ...
        "protection_action_max", NaN, ...
        "protection_action_final", NaN, ...
        "structural_pass", false, ...
        "all_numeric_pass", false, ...
        "limit_behavior_pass", false, ...
        "thermal_behavior_pass", false, ...
        "zero_cmd_pass", false, ...
        "passed", false);
end

function instrumentation = addTemporaryLogging(modelName)
    instrumentation = struct();
    instrumentation.blocks = [modelName + "/Tmp_V4I_LimitStatus_TW"; ...
        modelName + "/Tmp_V4I_SystemKPI_TW"; ...
        modelName + "/Tmp_V4I_ProtectionAction_TW"];
    for k = 1:numel(instrumentation.blocks)
        deleteTemporaryBlock(instrumentation.blocks(k));
    end

    add_block("simulink/Sinks/To Workspace", char(instrumentation.blocks(1)), ...
        "VariableName", "v4i_LimitStatus_ts", ...
        "SaveFormat", "Timeseries", ...
        "Position", [760 530 900 560]);
    add_block("simulink/Sinks/To Workspace", char(instrumentation.blocks(2)), ...
        "VariableName", "v4i_SystemKPI_ts", ...
        "SaveFormat", "Timeseries", ...
        "Position", [760 590 900 620]);

    add_block("simulink/Signal Routing/From", char(modelName + "/Tmp_V4I_PA_From"), ...
        "GotoTag", "protection_action_V4H", ...
        "Position", [100, 660, 250, 680]);
    add_block("simulink/Sinks/To Workspace", char(instrumentation.blocks(3)), ...
        "VariableName", "v4i_protection_action_ts", ...
        "SaveFormat", "Timeseries", ...
        "Position", [300, 660, 400, 700]);
    instrumentation.fromBlock = char(modelName + "/Tmp_V4I_PA_From");

    add_line(modelName, "KPI_And_Logging/1", "Tmp_V4I_LimitStatus_TW/1", "autorouting", "on");
    add_line(modelName, "KPI_And_Logging/2", "Tmp_V4I_SystemKPI_TW/1", "autorouting", "on");
    add_line(modelName, "Tmp_V4I_PA_From/1", "Tmp_V4I_ProtectionAction_TW/1", "autorouting", "on");
end

function removeTemporaryLogging(instrumentation)
    for k = numel(instrumentation.blocks):-1:1
        deleteTemporaryBlock(instrumentation.blocks(k));
    end
    if isfield(instrumentation, "fromBlock")
        deleteTemporaryBlock(instrumentation.fromBlock);
    end
end

function deleteTemporaryBlock(blockPath)
    blockPath = char(blockPath);
    if getSimulinkBlockHandle(blockPath) == -1
        return;
    end
    lines = get_param(blockPath, "LineHandles");
    if isfield(lines, "Inport") && ~isempty(lines.Inport) && lines.Inport(1) ~= -1
        delete_line(lines.Inport(1));
    end
    if isfield(lines, "Outport") && ~isempty(lines.Outport) && lines.Outport(1) ~= -1
        delete_line(lines.Outport(1));
    end
    delete_block(blockPath);
end

function vector = getFinalTimeseriesVector(values, expectedWidth)
    data = squeeze(values.Data);
    if isvector(data)
        vector = data(:).';
    elseif size(data, 2) == expectedWidth
        vector = data(end, :);
    elseif size(data, 1) == expectedWidth
        vector = data(:, end).';
    else
        error("V4I:UnexpectedLoggedShape", ...
            "Logged data shape does not match width %d.", expectedWidth);
    end
    assert(numel(vector) == expectedWidth, "V4I:LoggedWidthMismatch", ...
        "Expected width %d, got %d.", expectedWidth, numel(vector));
end

function printCase(r)
    fprintf("  %s: t=%.4f I_rms=%.4f margin=%.4f prot=%d T_batt=%.2f->%.2f T_stator=%.2f->%.2f\n", ...
        r.caseName, r.finalTime_s, r.I_motor_rms_A, r.I_limit_margin_A, ...
        r.protection_action_max, r.T_batt_initial_K, r.T_batt_final_K, ...
        r.T_stator_initial_C, r.T_stator_final_C);
end

function restoreOriginalVars(modelWorkspace, amp, freq)
    modelWorkspace.assignin("pulse_id_amplitude_A", amp);
    modelWorkspace.assignin("diagnostic_frequency_Hz", freq);
end

function closeIfNeeded(modelName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
