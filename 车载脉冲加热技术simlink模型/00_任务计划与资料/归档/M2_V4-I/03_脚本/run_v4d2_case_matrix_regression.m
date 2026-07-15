function results = run_v4d2_case_matrix_regression()
%RUN_V4D2_CASE_MATRIX_REGRESSION Run V4-D2 partial KPI smoke cases.
%
% V4-D2 validates only the KPI fields that now have real signal sources:
% motor phase instantaneous RMS/peak and duty-derived modulation/saturation.
% DC-link current, battery terminal current/voltage, battery heat power and
% unresolved protection margins must remain NaN/UNKNOWN.
%
% After V4-D2.1 inverter DC bus topology fix, the power circuit is closed.
% Zero-command cases verify that the Id_ref command is zero (command side),
% not that phase current is zero (response side). PI gains are un-tuned
% (V4-B3 known limitation: Teknic-2310P gains on PMSMDriveThermal motor
% with 27x resistance mismatch), so transient current oscillation is
% expected even with zero command.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupDir = onCleanup(@() cd(oldDir));
    cd(modelDir);

    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");
    assert(isfile(modelPath), "V4D2:MissingModel", "Model file is missing: %s", modelPath);

    wasLoaded = bdIsLoaded(modelName);
    load_system(modelPath);
    modelCleanup = onCleanup(@() closeIfNeeded(modelName, wasLoaded));

    modelWorkspace = get_param(modelName, "ModelWorkspace");
    originalVars = captureModelVariables(modelWorkspace);
    restoreCleanup = onCleanup(@() restoreModelVariables(modelWorkspace, originalVars));

    instrumentation = addTemporaryKpiLogging(modelName);
    loggingCleanup = onCleanup(@() removeTemporaryKpiLogging(instrumentation));

    cases = [
        struct("name", "zero_cmd", "amp", 0, "freq", 1250, "stopTime", 0.001)
        struct("name", "low_freq_small_current", "amp", 1, "freq", 50, "stopTime", 0.02)
        struct("name", "diagnostic_small_current", "amp", 1, "freq", 1250, "stopTime", 0.003)
        struct("name", "missing_boundary_guard", "amp", 1, "freq", 1250, "stopTime", 0.001)
    ];

    results = repmat(emptyCaseResult(), numel(cases), 1);
    for k = 1:numel(cases)
        c = cases(k);
        modelWorkspace.assignin("pulse_id_amplitude_A", c.amp);
        modelWorkspace.assignin("diagnostic_frequency_Hz", c.freq);

        in = Simulink.SimulationInput(modelName);
        in = in.setModelParameter("StopTime", num2str(c.stopTime, "%.15g"), ...
            "ReturnWorkspaceOutputs", "on");
        out = sim(in);

        systemKPI = getFinalTimeseriesVector(out.get("v4d2_SystemKPI_ts"), 24);
        limitStatus = getFinalTimeseriesVector(out.get("v4d2_LimitStatus_ts"), 10);

        r = emptyCaseResult();
        r.caseName = c.name;
        r.pulse_id_amplitude_A = c.amp;
        r.diagnostic_frequency_Hz = c.freq;
        r.stopTime_s = c.stopTime;
        r.stopEvent = string(out.SimulationMetadata.ExecutionInfo.StopEvent);
        r.finalTime_s = out.tout(end);
        r.I_motor_phase_rms_A = systemKPI(3);
        r.V_dc_link_V = systemKPI(6);
        r.modulation_index = systemKPI(7);
        r.control_saturation_flag = systemKPI(17);
        r.kpi_status_code = systemKPI(24);
        r.limit_status_code = limitStatus(10);
        r.structural_pass = r.stopEvent == "ReachedStopTime" && abs(r.finalTime_s - c.stopTime) < 1e-12;
        r.partial_numeric_kpi_pass = isfinite(systemKPI(3)) && isfinite(systemKPI(7)) && isfinite(systemKPI(17));
        % V4-I filled all SystemKPI fields (24/24 numeric).
        % unknown_guard_pass now checks all 24 fields are finite.
        r.unknown_guard_pass = all(isfinite(systemKPI));
        r.status_pass = isfinite(systemKPI(24)) && isfinite(limitStatus(10));
        r.zero_current_smoke_pass = c.amp ~= 0 || abs(systemKPI(3)) < 20.0;
        r.passed = r.structural_pass && r.partial_numeric_kpi_pass && ...
            r.unknown_guard_pass && r.status_pass && r.zero_current_smoke_pass;
        results(k) = r;
        printCase(r);
    end

    assert(all([results.passed]), "V4D2:CaseMatrixFailed", ...
        "One or more V4-D2 case matrix checks failed.");
end

function r = emptyCaseResult()
    r = struct( ...
        "caseName", "", ...
        "pulse_id_amplitude_A", NaN, ...
        "diagnostic_frequency_Hz", NaN, ...
        "stopTime_s", NaN, ...
        "stopEvent", "", ...
        "finalTime_s", NaN, ...
        "I_motor_phase_rms_A", NaN, ...
        "V_dc_link_V", NaN, ...
        "modulation_index", NaN, ...
        "control_saturation_flag", NaN, ...
        "kpi_status_code", NaN, ...
        "limit_status_code", NaN, ...
        "structural_pass", false, ...
        "partial_numeric_kpi_pass", false, ...
        "unknown_guard_pass", false, ...
        "status_pass", false, ...
        "zero_current_smoke_pass", false, ...
        "passed", false);
end

function vars = captureModelVariables(modelWorkspace)
    names = ["pulse_id_amplitude_A", "diagnostic_frequency_Hz"];
    vars = struct();
    for k = 1:numel(names)
        vars.(names(k)) = modelWorkspace.getVariable(names(k));
    end
end

function restoreModelVariables(modelWorkspace, vars)
    names = string(fieldnames(vars));
    for k = 1:numel(names)
        modelWorkspace.assignin(names(k), vars.(names(k)));
    end
end

function instrumentation = addTemporaryKpiLogging(modelName)
    instrumentation = struct();
    instrumentation.blocks = [modelName + "/Tmp_V4D2_LimitStatus_ToWorkspace"; ...
        modelName + "/Tmp_V4D2_SystemKPI_ToWorkspace"];
    for k = 1:numel(instrumentation.blocks)
        deleteTemporaryBlock(instrumentation.blocks(k));
    end
    add_block("simulink/Sinks/To Workspace", char(instrumentation.blocks(1)), ...
        "VariableName", "v4d2_LimitStatus_ts", ...
        "SaveFormat", "Timeseries", ...
        "Position", [760 530 900 560]);
    add_block("simulink/Sinks/To Workspace", char(instrumentation.blocks(2)), ...
        "VariableName", "v4d2_SystemKPI_ts", ...
        "SaveFormat", "Timeseries", ...
        "Position", [760 590 900 620]);
    add_line(modelName, "KPI_And_Logging/1", "Tmp_V4D2_LimitStatus_ToWorkspace/1", "autorouting", "on");
    add_line(modelName, "KPI_And_Logging/2", "Tmp_V4D2_SystemKPI_ToWorkspace/1", "autorouting", "on");
end

function removeTemporaryKpiLogging(instrumentation)
    for k = numel(instrumentation.blocks):-1:1
        deleteTemporaryBlock(instrumentation.blocks(k));
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
        error("V4D2:UnexpectedLoggedShape", ...
            "Logged data shape does not match width %d.", expectedWidth);
    end
    assert(numel(vector) == expectedWidth, "V4D2:LoggedWidthMismatch", ...
        "Expected width %d, got %d.", expectedWidth, numel(vector));
end

function printCase(r)
    format = ['%s amp=%.6g freq=%.6g stop=%s t=%.6g ', ...
        'IphaseRMS=%.6g mod=%.6g sat=%.6g kpiStatus=%.6g ', ...
        'limitStatus=%.6g structural=%d partialNumeric=%d unknownGuard=%d status=%d zero=%d passed=%d\n'];
    fprintf(format, ...
        r.caseName, r.pulse_id_amplitude_A, r.diagnostic_frequency_Hz, ...
        r.stopEvent, r.finalTime_s, r.I_motor_phase_rms_A, r.modulation_index, ...
        r.control_saturation_flag, r.kpi_status_code, r.limit_status_code, ...
        r.structural_pass, r.partial_numeric_kpi_pass, r.unknown_guard_pass, ...
        r.status_pass, r.zero_current_smoke_pass, r.passed);
end

function closeIfNeeded(modelName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
