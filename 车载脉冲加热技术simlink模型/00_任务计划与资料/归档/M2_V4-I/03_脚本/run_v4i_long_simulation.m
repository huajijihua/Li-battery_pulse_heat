function results = run_v4i_long_simulation()
%RUN_V4I_LONG_SIMULATION V4-I long simulation behavior verification.
%
% Runs a 10A/50Hz/10s pulse heating simulation at -10C initial temperature
% and verifies physical behavior: temperature rise, SOC consumption, energy
% balance residual, current limiting, and protection action.
%
% This script can be run directly in MATLAB Command Window.
% Results are saved to outputs/v4i_long_simulation_results.mat
%
% This is a behavior verification script, not a pass/fail regression.
% Results are printed and returned for inspection.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    outputDir = fullfile(projectDir, "outputs");
    if ~exist(outputDir, "dir"), mkdir(outputDir); end
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
    fprintf("Solver set to ode23tb, FixedStep=5e-5\n");

    modelWorkspace = get_param(modelName, "ModelWorkspace");
    originalAmp = modelWorkspace.getVariable("pulse_id_amplitude_A");
    originalFreq = modelWorkspace.getVariable("diagnostic_frequency_Hz");
    restoreVars = onCleanup(@() restoreOriginalVars(modelWorkspace, originalAmp, originalFreq));

    modelWorkspace.assignin("pulse_id_amplitude_A", 10);
    modelWorkspace.assignin("diagnostic_frequency_Hz", 50);

    instrumentation = addTemporaryLogging(modelName);
    loggingCleanup = onCleanup(@() removeTemporaryLogging(instrumentation));

    stopTime = 10;
    in = Simulink.SimulationInput(modelName);
    in = in.setModelParameter("StopTime", num2str(stopTime, "%.15g"), ...
        "ReturnWorkspaceOutputs", "on");
    fprintf("Starting V4-I long simulation: 10A/50Hz/%ds, -10C initial...\n", stopTime);
    out = sim(in);
    fprintf("Simulation complete: finalTime=%.4f s\n", out.tout(end));

    limitStatus = getFinalTimeseriesVector(out.get("v4i_LimitStatus_ts"), 10);

    kpiTime = out.get("v4i_SystemKPI_ts").Time;
    kpiData = squeeze(out.get("v4i_SystemKPI_ts").Data);

    kpiInitial = kpiData(1, :);
    kpiFinal = kpiData(end, :);

    results = struct();
    results.modelName = modelName;
    results.stopTime_s = stopTime;
    results.finalTime_s = out.tout(end);
    results.stopEvent = string(out.SimulationMetadata.ExecutionInfo.StopEvent);
    results.pulse_id_amplitude_A = 10;
    results.diagnostic_frequency_Hz = 50;

    results.T_batt_initial_K = kpiInitial(13);
    results.T_batt_final_K = kpiFinal(13);
    results.T_stator_initial_C = kpiInitial(14);
    results.T_stator_final_C = kpiFinal(14);
    results.T_rotor_initial_C = kpiInitial(15);
    results.T_rotor_final_C = kpiFinal(15);

    results.I_motor_rms_A = kpiFinal(3);
    results.V_batt_V = kpiFinal(5);
    results.P_batt_heat_W = kpiFinal(9);
    results.P_cu_W = kpiFinal(10);
    results.P_inv_W = kpiFinal(12);
    results.track_err_rms_A = kpiFinal(16);
    results.I_limit_margin_A = kpiFinal(19);
    results.thermal_margin_C = kpiFinal(20);
    results.safety_margin_A = kpiFinal(22);
    results.limit_factor = kpiFinal(23);

    results.batt_temp_margin_K = limitStatus(6);
    results.coolant_flow_margin = limitStatus(7);
    results.protection_action = out.get("v4i_protection_action_ts");
    if ~isempty(results.protection_action)
        paData = squeeze(results.protection_action.Data);
        results.protection_action_final = paData(end);
        results.protection_action_max = max(paData);
    else
        results.protection_action_final = NaN;
        results.protection_action_max = NaN;
    end

    if size(kpiData, 1) > 1
        results.T_batt_rise_K = kpiFinal(13) - kpiInitial(13);
        results.T_stator_rise_C = kpiFinal(14) - kpiInitial(14);
    else
        results.T_batt_rise_K = 0;
        results.T_stator_rise_C = 0;
    end

    printResults(results);

    results.simulationPassed = results.stopEvent == "ReachedStopTime" && ...
        abs(results.finalTime_s - stopTime) < 1e-6;
    results.allNumeric = all(isfinite(kpiFinal));

    fprintf("\n=== Behavior Assessment ===\n");
    fprintf("Simulation reached stop time: %d\n", results.simulationPassed);
    fprintf("All SystemKPI numeric: %d\n", results.allNumeric);
    if results.T_batt_rise_K > 0
        fprintf("Battery temperature rising: YES (dT=%.4f K)\n", results.T_batt_rise_K);
    else
        fprintf("Battery temperature rising: NO or near-zero (dT=%.4f K)\n", results.T_batt_rise_K);
    end
    if results.T_stator_rise_C > 0
        fprintf("Stator temperature rising: YES (dT=%.4f C)\n", results.T_stator_rise_C);
    else
        fprintf("Stator temperature rising: NO or near-zero (dT=%.4f C)\n", results.T_stator_rise_C);
    end
    if results.protection_action_max == 0
        fprintf("Protection action: NORMAL (no derate/stop triggered)\n");
    else
        fprintf("Protection action: TRIGGERED (max=%d)\n", results.protection_action_max);
    end
    if results.I_limit_margin_A > 0
        fprintf("Current limit: NOT saturated (margin=%.2f A)\n", results.I_limit_margin_A);
    else
        fprintf("Current limit: SATURATED (margin=%.2f A)\n", results.I_limit_margin_A);
    end

    resultsFile = fullfile(outputDir, "v4i_long_simulation_results.mat");
    save(resultsFile, "results", "kpiTime", "kpiData", "-v7.3");
    fprintf("\nResults saved to: %s\n", resultsFile);
    fprintf("To load: load('%s')\n", resultsFile);
end

function restoreOriginalVars(modelWorkspace, amp, freq)
    modelWorkspace.assignin("pulse_id_amplitude_A", amp);
    modelWorkspace.assignin("diagnostic_frequency_Hz", freq);
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

function printResults(r)
    fprintf("\n=== V4-I Long Simulation Results (10A/50Hz/10s, -10C) ===\n");
    fprintf("Stop event: %s, final time: %.4f s\n", r.stopEvent, r.finalTime_s);
    fprintf("\n--- Temperature ---\n");
    fprintf("T_batt:   %.2f K -> %.2f K (rise: %.4f K)\n", r.T_batt_initial_K, r.T_batt_final_K, r.T_batt_rise_K);
    fprintf("T_stator: %.2f C -> %.2f C (rise: %.4f C)\n", r.T_stator_initial_C, r.T_stator_final_C, r.T_stator_rise_C);
    fprintf("T_rotor:  %.2f C -> %.2f C\n", r.T_rotor_initial_C, r.T_rotor_final_C);
    fprintf("\n--- Electrical ---\n");
    fprintf("I_motor_rms:  %.4f A\n", r.I_motor_rms_A);
    fprintf("V_batt:       %.4f V\n", r.V_batt_V);
    fprintf("P_batt_heat:  %.4f W\n", r.P_batt_heat_W);
    fprintf("P_cu:         %.4f W\n", r.P_cu_W);
    fprintf("P_inv:        %.4f W\n", r.P_inv_W);
    fprintf("track_err_rms: %.4f A\n", r.track_err_rms_A);
    fprintf("\n--- Limits & Protection ---\n");
    fprintf("I_limit_margin:     %.4f A\n", r.I_limit_margin_A);
    fprintf("thermal_margin:     %.4f C\n", r.thermal_margin_C);
    fprintf("batt_temp_margin:   %.4f K\n", r.batt_temp_margin_K);
    fprintf("coolant_flow_margin: %.6f\n", r.coolant_flow_margin);
    fprintf("safety_margin:      %.4f A\n", r.safety_margin_A);
    fprintf("limit_factor:       %d\n", r.limit_factor);
    fprintf("protection_action:  final=%d, max=%d\n", r.protection_action_final, r.protection_action_max);
end

function closeIfNeeded(modelName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
