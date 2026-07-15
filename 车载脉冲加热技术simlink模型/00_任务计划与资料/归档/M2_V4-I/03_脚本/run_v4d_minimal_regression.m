function results = run_v4d_minimal_regression()
%RUN_V4D_MINIMAL_REGRESSION Check current V4-D KPI interface and smoke simulation.
%
% This regression validates the current V4-D KPI contract and minimum model
% executability. It does not treat NaN/UNKNOWN values as behavioral pass
% evidence while the physical DC sensors and safety limits are unresolved.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(modelDir);

    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");
    assert(isfile(modelPath), "V4D:MissingModel", "Model file is missing: %s", modelPath);

    wasLoaded = bdIsLoaded(modelName);
    load_system(modelPath);
    modelCleanup = onCleanup(@() closeIfNeeded(modelName, wasLoaded));

    kpiPath = modelName + "/KPI_And_Logging";
    outports = sort(getNamedBlocks(kpiPath, "Outport"));
    assert(isequal(outports, ["LimitStatus"; "SystemKPI"]), ...
        "V4D:UnexpectedKPIOutports", ...
        "KPI_And_Logging outports must be LimitStatus and SystemKPI.");

    assertBlockParam(kpiPath + "/Mux_LimitStatus", "Inputs", "10");
    assertBlockParam(kpiPath + "/Mux_SystemKPI", "Inputs", "24");

    expectedSelectors = [
        "Sel_Drive_P_cu", "3"
        "Sel_Drive_P_iron", "4"
        "Sel_Drive_P_inv", "5"
        "Sel_Drive_T_stator", "6"
        "Sel_Drive_T_rotor", "7"
        "Sel_Control_tracking", "1"
        "Sel_Control_sat", "3"
        "Sel_Control_enable", "4"
        "Sel_Battery_charge_limit", "6"
    ];
    selectorResults = strings(size(expectedSelectors, 1), 3);
    for k = 1:size(expectedSelectors, 1)
        blockName = expectedSelectors(k, 1);
        expectedIndex = expectedSelectors(k, 2);
        actualIndex = string(get_param(kpiPath + "/" + blockName, "Indices"));
        assert(actualIndex == expectedIndex, "V4D:SelectorMismatch", ...
            "%s expected Indices=%s, got %s", blockName, expectedIndex, actualIndex);
        selectorResults(k, :) = [blockName, expectedIndex, actualIndex];
    end

    % V4-G/V4-F/V4-H replaced most UNKNOWN constants with real computations.
    % Only check constants that still exist in the current model.
    candidateConstants = [
        "KPI_thermal_margin_UNKNOWN", "kpi_value_unknown"
        "KPI_status_V4D", "kpi_status_v4d2_partial_numeric_code"
    ];
    constantResults = strings(size(candidateConstants, 1), 3);
    constantResultCount = 0;
    for k = 1:size(candidateConstants, 1)
        blockName = candidateConstants(k, 1);
        expectedValue = candidateConstants(k, 2);
        blockPath = kpiPath + "/" + blockName;
        if ~isempty(find_system(kpiPath, "FollowLinks", "on", "LookUnderMasks", "all", "SearchDepth", 1, "Name", blockName))
            actualValue = string(get_param(blockPath, "Value"));
            assert(actualValue == expectedValue, "V4D:ConstantMismatch", ...
                "%s expected Value=%s, got %s", blockName, expectedValue, actualValue);
            constantResultCount = constantResultCount + 1;
            constantResults(constantResultCount, :) = [blockName, expectedValue, actualValue];
        end
    end
    constantResults = constantResults(1:constantResultCount, :);

    workspaceResults = struct();
    workspaceResults.kpi_value_unknown = readModelWorkspace(modelName, "kpi_value_unknown");
    workspaceResults.kpi_status_v4d2_partial_numeric_code = readModelWorkspace(modelName, "kpi_status_v4d2_partial_numeric_code");
    assert(isnan(workspaceResults.kpi_value_unknown), "V4D:KPIUnknownValue", ...
        "kpi_value_unknown must remain NaN.");
    assert(workspaceResults.kpi_status_v4d2_partial_numeric_code == 6, "V4D:KPIStatusCode", ...
        "kpi_status_v4d2_partial_numeric_code must be 6.");

    in = Simulink.SimulationInput(modelName);
    in = in.setModelParameter("StopTime", "0.001", "ReturnWorkspaceOutputs", "on");
    out = sim(in);

    tout = out.tout;
    finalTime = tout(end);
    stopEvent = string(out.SimulationMetadata.ExecutionInfo.StopEvent);
    assert(abs(finalTime - 0.001) < 1e-12, "V4D:UnexpectedStopTime", ...
        "Expected final time 0.001 s, got %.15g s.", finalTime);

    results = struct();
    results.modelName = modelName;
    results.modelPath = modelPath;
    results.checkedAt = string(datetime("now"));
    results.kpiOutports = outports;
    results.limitStatusWidth = 10;
    results.systemKPIWidth = 24;
    results.selectorResults = selectorResults;
    results.constantResults = constantResults;
    results.workspaceResults = workspaceResults;
    results.stopEvent = stopEvent;
    results.finalTime_s = finalTime;
    results.behaviorEvidence = "smoke_only_not_behavior_validated";
    results.passed = true;

    fprintf("V4-D minimal regression: passed\n");
    fprintf("  Model: %s\n", modelName);
    fprintf("  KPI_And_Logging outports: %s\n", strjoin(outports.', ", "));
    fprintf("  LimitStatus width: %d\n", results.limitStatusWidth);
    fprintf("  SystemKPI width: %d\n", results.systemKPIWidth);
    fprintf("  Stop event: %s, final time: %.6g s\n", stopEvent, finalTime);
    fprintf("  Behavior evidence: %s\n", results.behaviorEvidence);
end

function names = getNamedBlocks(parentPath, blockType)
    blocks = find_system(parentPath, "SearchDepth", 1, "BlockType", blockType);
    names = strings(numel(blocks), 1);
    for k = 1:numel(blocks)
        names(k) = string(get_param(blocks{k}, "Name"));
    end
end

function assertBlockParam(blockPath, paramName, expectedValue)
    actualValue = string(get_param(blockPath, paramName));
    assert(actualValue == expectedValue, "V4D:BlockParameterMismatch", ...
        "%s expected %s=%s, got %s", blockPath, paramName, expectedValue, actualValue);
end

function value = readModelWorkspace(modelName, variableName)
    modelWorkspace = get_param(modelName, "ModelWorkspace");
    value = modelWorkspace.getVariable(variableName);
end

function closeIfNeeded(modelName, wasLoaded)
    if ~wasLoaded && bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
end
