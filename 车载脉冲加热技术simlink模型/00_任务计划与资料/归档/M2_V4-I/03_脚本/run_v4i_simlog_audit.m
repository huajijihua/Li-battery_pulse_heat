function results = run_v4i_simlog_audit()
%RUN_V4I_SIMLOG_AUDIT V4-I simlog post-processing: extract all power_dissipated.
%
% Runs a 10A/50Hz/2s simulation and extracts all 18 power_dissipated
% variables from the Simscape log. Produces a categorized loss table
% with mean/max/min for each component.

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

    modelWorkspace = get_param(modelName, "ModelWorkspace");
    originalAmp = modelWorkspace.getVariable("pulse_id_amplitude_A");
    originalFreq = modelWorkspace.getVariable("diagnostic_frequency_Hz");
    restoreVars = onCleanup(@() restoreOriginalVars(modelWorkspace, originalAmp, originalFreq));

    modelWorkspace.assignin("pulse_id_amplitude_A", 10);
    modelWorkspace.assignin("diagnostic_frequency_Hz", 50);

    fprintf("Starting 10A/50Hz/2s simulation for simlog audit...\n");
    simOut = sim(modelName, "StopTime", "2", "ReturnWorkspaceOutputs", "on");
    fprintf("Simulation complete: finalTime=%.4f, steps=%d\n", simOut.tout(end), numel(simOut.tout));

    sl = simOut.simlog_v4e;
    drvNode = sl.child("PMSMDriveThermal_Inverter_And_Motor");
    batNode = sl.child("BatteryThermalManagement_BatteryPack");

    results = struct();
    results.modelName = modelName;
    results.stopTime_s = 2;
    results.finalTime_s = simOut.tout(end);

    pdEntries = cell(18, 1);
    pdIndex = 0;

    fprintf("\n=== PMSM ===\n");
    pmsmPD = drvNode.child("PMSM").get("power_dissipated");
    pmsmVals = pmsmPD.series.values;
    pmsmVal = mean(pmsmVals);
    pmsmMax = max(pmsmVals);
    pmsmMin = min(pmsmVals);
    fprintf("  PMSM.power_dissipated: mean=%.6f W, max=%.6f W, min=%.6f W\n", pmsmVal, pmsmMax, pmsmMin);
    pdIndex = pdIndex + 1;
    pdEntries{pdIndex} = struct("category", "PMSM", "name", "PMSM", "mean", pmsmVal, "max", pmsmMax, "min", pmsmMin);

    fprintf("\n=== IGBT (12 components) ===\n");
    igbtNames = ["IGBT_AH"; "IGBT_AL"; "IGBT_BH"; "IGBT_BL"; "IGBT_CH"; "IGBT_CL"];
    subNames = ["ideal_switch"; "diode"];
    igbtSwitchTotal = 0;
    igbtDiodeTotal = 0;
    for i = 1:numel(igbtNames)
        for j = 1:numel(subNames)
            path = sprintf("Three_phase_inverter.%s.%s", igbtNames(i), subNames(j));
            node = drvNode.child("Three_phase_inverter").child(igbtNames{i}).child(subNames{j});
            pd = node.get("power_dissipated");
            vals = pd.series.values;
            m = mean(vals); mx = max(vals); mn = min(vals);
            fprintf("  %s: mean=%.6f W, max=%.6f W\n", path, m, mx);
            pdIndex = pdIndex + 1;
            pdEntries{pdIndex} = struct("category", "IGBT_" + subNames{j}, "name", path, "mean", m, "max", mx, "min", mn);
            if strcmp(subNames{j}, "ideal_switch")
                igbtSwitchTotal = igbtSwitchTotal + m;
            else
                igbtDiodeTotal = igbtDiodeTotal + m;
            end
        end
    end
    fprintf("  IGBT ideal_switch total mean: %.6f W\n", igbtSwitchTotal);
    fprintf("  IGBT diode total mean: %.6f W\n", igbtDiodeTotal);

    fprintf("\n=== Battery Cables (5 components) ===\n");
    cableNames = ["R12"; "R23"; "R34"; "neg_cable"; "pos_cable"];
    cableTotal = 0;
    for i = 1:numel(cableNames)
        node = batNode.child("Battery_pack").child(cableNames{i});
        pd = node.get("power_dissipated");
        vals = pd.series.values;
        m = mean(vals); mx = max(vals); mn = min(vals);
        fprintf("  Battery_pack.%s: mean=%.6f W, max=%.6f W\n", cableNames{i}, m, mx);
        pdIndex = pdIndex + 1;
        pdEntries{pdIndex} = struct("category", "Cable", "name", "Battery_pack." + cableNames{i}, "mean", m, "max", mx, "min", mn);
        cableTotal = cableTotal + m;
    end
    fprintf("  Cable total mean: %.6f W\n", cableTotal);

    pmsmTotal = pmsmVal;
    igbtTotal = igbtSwitchTotal + igbtDiodeTotal;
    simlogTotal = pmsmTotal + igbtTotal + cableTotal;

    fprintf("\n=== Summary ===\n");
    fprintf("PMSM:              %.6f W\n", pmsmTotal);
    fprintf("IGBT (switch+diode): %.6f W (switch=%.6f, diode=%.6f)\n", igbtTotal, igbtSwitchTotal, igbtDiodeTotal);
    fprintf("Cables:            %.6f W\n", cableTotal);
    fprintf("simlog Total:      %.6f W\n", simlogTotal);

    results.pdEntries = pdEntries(1:pdIndex);
    results.pmsm_mean = pmsmTotal;
    results.igbt_switch_mean = igbtSwitchTotal;
    results.igbt_diode_mean = igbtDiodeTotal;
    results.igbt_total_mean = igbtTotal;
    results.cable_total_mean = cableTotal;
    results.simlog_total_mean = simlogTotal;

    resultsFile = fullfile(outputDir, "v4i_simlog_audit_results.mat");
    save(resultsFile, "results", "-v7.3");
    fprintf("\nResults saved to: %s\n", resultsFile);
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
