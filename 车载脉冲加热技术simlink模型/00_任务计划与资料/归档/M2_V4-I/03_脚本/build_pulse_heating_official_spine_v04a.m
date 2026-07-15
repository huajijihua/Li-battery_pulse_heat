function build_pulse_heating_official_spine_v04a(overwrite)
%BUILD_PULSE_HEATING_OFFICIAL_SPINE_V04A Build the V4-A official-example spine.
%
% V4-A is a structural, traceable integration shell. It records the fixed
% MathWorks example baselines and exposes the project-owned adaptation
% interfaces. Placeholder signals are 0 or NaN and are not behavioral proof.

    if nargin < 1
        overwrite = true;
    end

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");

    if ~isfolder(modelDir)
        error("V4A:MissingModelDir", "Model directory does not exist: %s", modelDir);
    end

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end

    if isfile(modelPath)
        if ~overwrite
            error("V4A:ModelExists", "Model already exists: %s", modelPath);
        end
        delete(modelPath);
    end

    new_system(modelName);
    open_system(modelName);

    addRootAnnotation(modelName);

    addBoundarySubsystem(modelName, "PulseHeating_Command_And_Limits", [], ...
        ["Idq_ref", "LimitConfig"], [40 210 250 310]);
    addBoundarySubsystem(modelName, "MCB_SIUnits_FOC_Controller", ...
        ["Idq_ref", "Feedbacks_sim"], ["Duty_Cycles", "ControlKPI"], [330 195 570 325]);
    addBoundarySubsystem(modelName, "BatteryThermalManagement_BatteryPack", ...
        "BatteryLoad", ["BatteryDC", "BatteryStatus"], [330 430 590 555]);
    addBoundarySubsystem(modelName, "DC_Link_And_Inverter_Interface", ...
        ["BatteryDC", "InverterDCFeedback"], ["DCBus", "BatteryLoad"], [670 420 910 555]);
    addBoundarySubsystem(modelName, "PMSMDriveThermal_Inverter_And_Motor", ...
        ["DCBus", "Duty_Cycles"], ["Feedbacks_sim", "InverterDCFeedback", "DriveKPI"], [670 175 955 340]);
    addBoundarySubsystem(modelName, "KPI_And_Logging", ...
        ["BatteryStatus", "DCBus", "ControlKPI", "DriveKPI", "LimitConfig"], [], [1030 300 1245 520]);

    connectRoot(modelName);
    populatePlaceholders(modelName);

    set_param(modelName, "StopTime", "1");
    save_system(modelName, modelPath);
    fprintf("Built V4-A official-example spine: %s\n", modelPath);
end

function addRootAnnotation(modelName)
    text = "V4-A official-example spine" + newline + ...
        "Battery baseline: BatteryThermalManagementModel.slx" + newline + ...
        "  C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\BatteryThermalManagementExample\BatteryThermalManagementModel.slx" + newline + ...
        "Controller baseline: mcb_pmsm_foc_qep_f28379d_SIUnit.slx" + newline + ...
        "  C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\mcb\SIUnitsExample\mcb_pmsm_foc_qep_f28379d_SIUnit.slx" + newline + ...
        "Drive baseline: PMSMDriveThermal.slx" + newline + ...
        "  C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\PMSMDriveThermalExample\PMSMDriveThermal.slx" + newline + ...
        "Scope: structural boundary and provenance only; 0/NaN placeholders are UNKNOWN, not pass results.";
    annotation = Simulink.Annotation(modelName, text);
    annotation.Position = [35 25 650 135];
end

function addBoundarySubsystem(modelName, blockName, inputs, outputs, position)
    blockPath = modelName + "/" + blockName;
    add_block("simulink/Ports & Subsystems/Subsystem", blockPath, "Position", position);
    delete_line(blockPath, "In1/1", "Out1/1");
    delete_block(blockPath + "/In1");
    delete_block(blockPath + "/Out1");

    for idx = 1:numel(inputs)
        add_block("simulink/Sources/In1", blockPath + "/" + inputs(idx), ...
            "Position", [40 35 + 55*(idx-1) 70 49 + 55*(idx-1)]);
    end

    for idx = 1:numel(outputs)
        add_block("simulink/Sinks/Out1", blockPath + "/" + outputs(idx), ...
            "Position", [250 35 + 55*(idx-1) 280 49 + 55*(idx-1)]);
    end
end

function connectRoot(modelName)
    add_line(modelName, "PulseHeating_Command_And_Limits/1", "MCB_SIUnits_FOC_Controller/1", "autorouting", "on");
    add_line(modelName, "MCB_SIUnits_FOC_Controller/1", "PMSMDriveThermal_Inverter_And_Motor/2", "autorouting", "on");
    add_line(modelName, "PMSMDriveThermal_Inverter_And_Motor/1", "MCB_SIUnits_FOC_Controller/2", "autorouting", "on");
    add_line(modelName, "BatteryThermalManagement_BatteryPack/1", "DC_Link_And_Inverter_Interface/1", "autorouting", "on");
    add_line(modelName, "DC_Link_And_Inverter_Interface/1", "PMSMDriveThermal_Inverter_And_Motor/1", "autorouting", "on");
    add_line(modelName, "PMSMDriveThermal_Inverter_And_Motor/2", "DC_Link_And_Inverter_Interface/2", "autorouting", "on");
    add_line(modelName, "DC_Link_And_Inverter_Interface/2", "BatteryThermalManagement_BatteryPack/1", "autorouting", "on");
    add_line(modelName, "BatteryThermalManagement_BatteryPack/2", "KPI_And_Logging/1", "autorouting", "on");
    add_line(modelName, "DC_Link_And_Inverter_Interface/1", "KPI_And_Logging/2", "autorouting", "on");
    add_line(modelName, "MCB_SIUnits_FOC_Controller/2", "KPI_And_Logging/3", "autorouting", "on");
    add_line(modelName, "PMSMDriveThermal_Inverter_And_Motor/3", "KPI_And_Logging/4", "autorouting", "on");
    add_line(modelName, "PulseHeating_Command_And_Limits/2", "KPI_And_Logging/5", "autorouting", "on");
end

function populatePlaceholders(modelName)
    addConstantToOut(modelName, "PulseHeating_Command_And_Limits", "Idq_ref_zero_PLACEHOLDER", "[0;0]", "Idq_ref");
    addConstantToOut(modelName, "PulseHeating_Command_And_Limits", "LimitConfig_UNKNOWN", "NaN", "LimitConfig");

    terminateInports(modelName, "MCB_SIUnits_FOC_Controller", ["Idq_ref", "Feedbacks_sim"]);
    addConstantToOut(modelName, "MCB_SIUnits_FOC_Controller", "Duty_Cycles_zero_PLACEHOLDER", "[0;0;0]", "Duty_Cycles");
    addConstantToOut(modelName, "MCB_SIUnits_FOC_Controller", "ControlKPI_UNKNOWN", "NaN", "ControlKPI");

    terminateInports(modelName, "BatteryThermalManagement_BatteryPack", "BatteryLoad");
    addConstantToOut(modelName, "BatteryThermalManagement_BatteryPack", "BatteryDC_UNKNOWN", "NaN", "BatteryDC");
    addConstantToOut(modelName, "BatteryThermalManagement_BatteryPack", "BatteryStatus_UNKNOWN", "NaN", "BatteryStatus");

    terminateInports(modelName, "DC_Link_And_Inverter_Interface", ["BatteryDC", "InverterDCFeedback"]);
    addConstantToOut(modelName, "DC_Link_And_Inverter_Interface", "DCBus_UNKNOWN", "NaN", "DCBus");
    addConstantToOut(modelName, "DC_Link_And_Inverter_Interface", "BatteryLoad_zero_PLACEHOLDER", "0", "BatteryLoad");

    terminateInports(modelName, "PMSMDriveThermal_Inverter_And_Motor", ["DCBus", "Duty_Cycles"]);
    addConstantToOut(modelName, "PMSMDriveThermal_Inverter_And_Motor", "Feedbacks_sim_UNKNOWN", "NaN", "Feedbacks_sim");
    addConstantToOut(modelName, "PMSMDriveThermal_Inverter_And_Motor", "InverterDCFeedback_UNKNOWN", "NaN", "InverterDCFeedback");
    addConstantToOut(modelName, "PMSMDriveThermal_Inverter_And_Motor", "DriveKPI_UNKNOWN", "NaN", "DriveKPI");

    terminateInports(modelName, "KPI_And_Logging", ["BatteryStatus", "DCBus", "ControlKPI", "DriveKPI", "LimitConfig"]);
end

function terminateInports(modelName, subsystemName, ports)
    blockPath = modelName + "/" + subsystemName;
    for idx = 1:numel(ports)
        name = "Terminate_" + ports(idx);
        add_block("simulink/Sinks/Terminator", blockPath + "/" + name, ...
            "Position", [135 32 + 55*(idx-1) 165 52 + 55*(idx-1)]);
        add_line(blockPath, ports(idx) + "/1", name + "/1", "autorouting", "on");
    end
end

function addConstantToOut(modelName, subsystemName, constantName, value, outportName)
    blockPath = modelName + "/" + subsystemName;
    outHandle = get_param(blockPath + "/" + outportName, "Handle");
    outPos = get_param(outHandle, "Position");
    add_block("simulink/Sources/Constant", blockPath + "/" + constantName, ...
        "Position", [outPos(1)-125 outPos(2)-3 outPos(1)-65 outPos(4)+3], ...
        "Value", value);
    add_line(blockPath, constantName + "/1", outportName + "/1", "autorouting", "on");
end
