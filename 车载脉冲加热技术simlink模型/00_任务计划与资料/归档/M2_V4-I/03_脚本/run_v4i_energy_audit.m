function results = run_v4i_energy_audit()
%RUN_V4I_ENERGY_AUDIT V4-I energy balance closed-loop verification.
%
% Runs a 10A/50Hz/2s simulation, extracts formula-based loss values
% (from Energy_Balance_Audit and Compute_P_xxx blocks) and simlog
% precise values (18 power_dissipated variables), then compares them
% to identify residual sources.

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

    fromBlocks = {};
    twBlocks = {};

    % Clean up any residual TmpEA blocks from previous runs
    allBlks = find_system(modelName, "SearchDepth", 1);
    for k = 1:numel(allBlks)
        nm = get_param(allBlks{k}, "Name");
        if startsWith(nm, "TmpEA")
            try
                lines = get_param(allBlks{k}, "LineHandles");
                if isfield(lines, "Inport") && ~isempty(lines.Inport) && lines.Inport(1) ~= -1
                    delete_line(lines.Inport(1));
                end
                if isfield(lines, "Outport") && ~isempty(lines.Outport) && lines.Outport(1) ~= -1
                    delete_line(lines.Outport(1));
                end
                delete_block(allBlks{k});
            catch
            end
        end
    end

    fromBlocks{1} = addFromBlock(modelName, "TmpEA_Pcu", "P_cu_V4E");
    twBlocks{1} = addToWorkspace(modelName, "TmpEA_Pcu_TW", "ea_pcu");
    add_line(modelName, "TmpEA_Pcu/1", "TmpEA_Pcu_TW/1", "autorouting", "on");

    fromBlocks{2} = addFromBlock(modelName, "TmpEA_Pinv", "P_inv_V4E");
    twBlocks{2} = addToWorkspace(modelName, "TmpEA_Pinv_TW", "ea_pinv");
    add_line(modelName, "TmpEA_Pinv/1", "TmpEA_Pinv_TW/1", "autorouting", "on");

    fromBlocks{3} = addFromBlock(modelName, "TmpEA_Piron", "P_iron_V4E");
    twBlocks{3} = addToWorkspace(modelName, "TmpEA_Piron_TW", "ea_piron");
    add_line(modelName, "TmpEA_Piron/1", "TmpEA_Piron_TW/1", "autorouting", "on");

    fromBlocks{4} = addFromBlock(modelName, "TmpEA_Pbheat", "P_batt_heat_V4E");
    twBlocks{4} = addToWorkspace(modelName, "TmpEA_Pbheat_TW", "ea_pbheat");
    add_line(modelName, "TmpEA_Pbheat/1", "TmpEA_Pbheat_TW/1", "autorouting", "on");

    fromBlocks{5} = addFromBlock(modelName, "TmpEA_Ipack", "I_dc_meas");
    twBlocks{5} = addToWorkspace(modelName, "TmpEA_Ipack_TW", "ea_ipack");
    add_line(modelName, "TmpEA_Ipack/1", "TmpEA_Ipack_TW/1", "autorouting", "on");

    fromBlocks{6} = addFromBlock(modelName, "TmpEA_Vpack", "V_pack_meas");
    twBlocks{6} = addToWorkspace(modelName, "TmpEA_Vpack_TW", "ea_vpack");
    add_line(modelName, "TmpEA_Vpack/1", "TmpEA_Vpack_TW/1", "autorouting", "on");

    cleanupBlocks = onCleanup(@() removeBlocks(modelName, fromBlocks, twBlocks));

    fprintf("Starting 10A/50Hz/2s simulation for energy audit...\n");
    simOut = sim(modelName, "StopTime", "2", "ReturnWorkspaceOutputs", "on");
    fprintf("Simulation complete: finalTime=%.4f\n", simOut.tout(end));

    P_cu_formula = mean(simOut.ea_pcu);
    P_inv_formula = mean(simOut.ea_pinv);
    P_iron_formula = mean(simOut.ea_piron);
    P_batt_heat_formula = mean(simOut.ea_pbheat);
    I_pack = simOut.ea_ipack;
    V_pack = simOut.ea_vpack;
    P_batt_terminal = mean(V_pack .* I_pack);
    P_mech = 0;

    P_loss_formula = P_inv_formula + P_cu_formula + P_iron_formula + P_batt_heat_formula;
    residual_formula = P_batt_terminal - P_loss_formula - P_mech;
    residual_pct_formula = abs(residual_formula) / max(abs(P_batt_terminal), 1e-6) * 100;

    sl = simOut.simlog_v4e;
    drvNode = sl.child("PMSMDriveThermal_Inverter_And_Motor");
    batNode = sl.child("BatteryThermalManagement_BatteryPack");

    pmsmPD = mean(drvNode.child("PMSM").get("power_dissipated").series.values);
    igbtSwitchPD = 0;
    igbtDiodePD = 0;
    igbtNames = ["IGBT_AH"; "IGBT_AL"; "IGBT_BH"; "IGBT_BL"; "IGBT_CH"; "IGBT_CL"];
    for i = 1:numel(igbtNames)
        igbtSwitchPD = igbtSwitchPD + mean(drvNode.child("Three_phase_inverter").child(igbtNames{i}).child("ideal_switch").get("power_dissipated").series.values);
        igbtDiodePD = igbtDiodePD + mean(drvNode.child("Three_phase_inverter").child(igbtNames{i}).child("diode").get("power_dissipated").series.values);
    end
    cablePD = 0;
    cableNames = ["R12"; "R23"; "R34"; "neg_cable"; "pos_cable"];
    for i = 1:numel(cableNames)
        cablePD = cablePD + mean(batNode.child("Battery_pack").child(cableNames{i}).get("power_dissipated").series.values);
    end

    P_loss_simlog = pmsmPD + igbtSwitchPD + igbtDiodePD + cablePD;
    residual_simlog = P_batt_terminal - P_loss_simlog - P_mech;
    residual_pct_simlog = abs(residual_simlog) / max(abs(P_batt_terminal), 1e-6) * 100;

    fprintf("\n=== Energy Balance Audit (10A/50Hz/2s, -10C) ===\n");
    fprintf("\n--- Formula Values (from Compute_P_xxx blocks) ---\n");
    fprintf("P_batt_terminal (V_pack*I_pack):  %.6f W\n", P_batt_terminal);
    fprintf("P_cu (formula):                   %.6f W\n", P_cu_formula);
    fprintf("P_iron (formula):                 %.6f W\n", P_iron_formula);
    fprintf("P_inv (formula, conduction only): %.6f W\n", P_inv_formula);
    fprintf("P_batt_heat (formula):            %.6f W\n", P_batt_heat_formula);
    fprintf("P_loss_total (formula):           %.6f W\n", P_loss_formula);
    fprintf("residual (formula):               %.6f W (%.1f%%)\n", residual_formula, residual_pct_formula);

    fprintf("\n--- simlog Precise Values (18 power_dissipated) ---\n");
    fprintf("PMSM (total):                     %.6f W\n", pmsmPD);
    fprintf("IGBT ideal_switch (6):            %.6f W\n", igbtSwitchPD);
    fprintf("IGBT diode (6):                   %.6f W\n", igbtDiodePD);
    fprintf("Cables (5):                       %.6f W\n", cablePD);
    fprintf("P_loss_total (simlog):            %.6f W\n", P_loss_simlog);
    fprintf("residual (simlog):                %.6f W (%.1f%%)\n", residual_simlog, residual_pct_simlog);

    fprintf("\n--- Comparison ---\n");
    fprintf("P_inv: formula=%.6f vs simlog=%.6f (diff=%.6f W = switch+diode losses)\n", ...
        P_inv_formula, igbtSwitchPD + igbtDiodePD, (igbtSwitchPD + igbtDiodePD) - P_inv_formula);
    fprintf("P_cu:  formula=%.6f vs simlog PMSM=%.6f (diff=%.6f W = iron loss in PMSM)\n", ...
        P_cu_formula, pmsmPD, pmsmPD - P_cu_formula);
    fprintf("Cable: formula=0 (not computed) vs simlog=%.6f W\n", cablePD);
    fprintf("\nResidual improvement: %.1f%% -> %.1f%%\n", residual_pct_formula, residual_pct_simlog);

    fprintf("\n--- Residual Source Breakdown ---\n");
    fprintf("Formula residual:           %.6f W\n", residual_formula);
    fprintf(" - Cable losses (missing):  %.6f W\n", -cablePD);
    fprintf(" - Switch losses (missing): %.6f W\n", -(igbtSwitchPD + igbtDiodePD - P_inv_formula));
    fprintf(" - PMSM iron loss (in PMSM pd): %.6f W\n", -(pmsmPD - P_cu_formula));
    fprintf(" - Reactive power + RC network + other: remainder\n");

    results = struct();
    results.P_batt_terminal = P_batt_terminal;
    results.P_cu_formula = P_cu_formula;
    results.P_iron_formula = P_iron_formula;
    results.P_inv_formula = P_inv_formula;
    results.P_batt_heat_formula = P_batt_heat_formula;
    results.P_loss_formula = P_loss_formula;
    results.residual_formula = residual_formula;
    results.residual_pct_formula = residual_pct_formula;
    results.pmsm_simlog = pmsmPD;
    results.igbt_switch_simlog = igbtSwitchPD;
    results.igbt_diode_simlog = igbtDiodePD;
    results.cable_simlog = cablePD;
    results.P_loss_simlog = P_loss_simlog;
    results.residual_simlog = residual_simlog;
    results.residual_pct_simlog = residual_pct_simlog;

    resultsFile = fullfile(outputDir, "v4i_energy_audit_results.mat");
    save(resultsFile, "results", "-v7.3");
    fprintf("\nResults saved to: %s\n", resultsFile);
end

function blk = addFromBlock(modelName, name, gotoTag)
    persistent posIdx;
    if isempty(posIdx), posIdx = 0; end
    posIdx = posIdx + 1;
    blk = modelName + "/" + name;
    y = 680 + posIdx * 30;
    add_block("simulink/Signal Routing/From", char(blk), ...
        "GotoTag", gotoTag, "Position", [100, y, 250, y+20]);
end

function blk = addToWorkspace(modelName, name, varName)
    persistent posIdx2;
    if isempty(posIdx2), posIdx2 = 0; end
    posIdx2 = posIdx2 + 1;
    blk = modelName + "/" + name;
    y = 680 + posIdx2 * 30;
    add_block("simulink/Sinks/To Workspace", char(blk), ...
        "VariableName", varName, "SaveFormat", "Array", ...
        "Position", [300, y, 400, y+40]);
end

function removeBlocks(~, fromBlocks, twBlocks)
    for k = numel(twBlocks):-1:1
        try
            lines = get_param(char(twBlocks{k}), "LineHandles");
            if isfield(lines, "Inport") && ~isempty(lines.Inport) && lines.Inport(1) ~= -1
                delete_line(lines.Inport(1));
            end
            delete_block(char(twBlocks{k}));
        catch
        end
    end
    for k = numel(fromBlocks):-1:1
        try delete_block(char(fromBlocks{k})); catch; end
    end
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
