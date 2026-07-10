function build_pulse_heating_official_spine_v04b1(overwrite)
%BUILD_PULSE_HEATING_OFFICIAL_SPINE_V04B1 Add first-round official drive reference.
%
% V4-B1 keeps the V4-A boundary contract, then fills the drive boundary
% with a traceable PMSMDriveThermal model reference. DC-link, gate mapping,
% and control feedback remain explicitly UNKNOWN until later rounds.

    if nargin < 1
        overwrite = true;
    end

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");

    addpath(scriptDir);
    officialPaths = prepareOfficialExamplePaths();

    build_pulse_heating_official_spine_v04a(overwrite);
    open_system(modelPath);
    configureOfficialDrivePreLoad(modelName, officialPaths);
    configureOfficialDriveInitialization(modelName, officialPaths);
    configureParentModelForOfficialDrive(modelName, officialPaths.driveModelName);

    driveSubsys = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    resetBoundaryContents(driveSubsys);
    populateDriveBoundaryB1(driveSubsys, officialPaths.driveModelName);

    set_param(modelName, "StopTime", "1");
    save_system(modelName, modelPath);
    fprintf("Built V4-B1 official drive reference spine: %s\n", modelPath);
end

function paths = prepareOfficialExamplePaths()
    paths.batteryDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\BatteryThermalManagementExample";
    paths.controllerDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\mcb\SIUnitsExample";
    paths.driveDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\PMSMDriveThermalExample";
    paths.driveModelName = "PMSMDriveThermal";

    requiredDirs = [paths.batteryDir, paths.controllerDir, paths.driveDir];
    for idx = 1:numel(requiredDirs)
        if ~isfolder(requiredDirs(idx))
            error("V4B1:MissingOfficialExampleDir", "Official example directory does not exist: %s", requiredDirs(idx));
        end
        addpath(requiredDirs(idx));
    end

    requiredSymbols = ["BatteryThermalManagementInitialization", "BatteryModule", "PMSMDriveThermalData"];
    for idx = 1:numel(requiredSymbols)
        if strlength(which(requiredSymbols(idx))) == 0
            error("V4B1:MissingOfficialDependency", "Required official dependency is not on path: %s", requiredSymbols(idx));
        end
    end

    load_system(paths.driveModelName);
    evalin("base", "PMSMDriveThermalData");
end

function configureOfficialDrivePreLoad(modelName, paths)
    preLoadLines = [ ...
        "addpath('" + paths.batteryDir + "');", ...
        "addpath('" + paths.controllerDir + "');", ...
        "addpath('" + paths.driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "set_param('PMSMDriveThermal','SimscapeLogType','none','SimscapeLogSimulationStatistics','off');", ...
        "set_param('PMSMDriveThermal','Dirty','off');" ...
    ];
    set_param(modelName, "PreLoadFcn", strjoin(preLoadLines, newline));
end

function configureOfficialDriveInitialization(modelName, paths)
    initLines = [ ...
        "addpath('" + paths.batteryDir + "');", ...
        "addpath('" + paths.controllerDir + "');", ...
        "addpath('" + paths.driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "PMSMDriveThermalData;" ...
    ];
    set_param(modelName, "InitFcn", strjoin(initLines, newline));
end

function configureParentModelForOfficialDrive(modelName, driveModelName)
    load_system(driveModelName);
    set_param(modelName, "UnderspecifiedInitializationDetection", ...
        get_param(driveModelName, "UnderspecifiedInitializationDetection"));
    set_param(driveModelName, "SimscapeLogType", "none", ...
        "SimscapeLogSimulationStatistics", "off");
    set_param(driveModelName, "Dirty", "off");
end

function resetBoundaryContents(subsystemPath)
    lineHandles = find_system(subsystemPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
    for idx = 1:numel(lineHandles)
        delete_line(lineHandles(idx));
    end

    blockPaths = find_system(subsystemPath, "SearchDepth", 1, "Type", "Block");
    for idx = numel(blockPaths):-1:1
        blockPath = string(blockPaths{idx});
        if blockPath == subsystemPath
            continue;
        end

        blockType = string(get_param(blockPath, "BlockType"));
        if blockType == "Inport" || blockType == "Outport"
            continue;
        end

        delete_block(blockPath);
    end
end

function populateDriveBoundaryB1(subsystemPath, driveModelName)
    addModelReference(subsystemPath, driveModelName);
    addDriveBoundaryAnnotation(subsystemPath);

    addTerminator(subsystemPath, "DCBus", "Terminate_DCBus_B1_PENDING", [150 35 180 55]);
    addTerminator(subsystemPath, "Duty_Cycles", "Terminate_Duty_Cycles_B1_PENDING", [150 90 180 110]);

    addConstantToOut(subsystemPath, "Feedbacks_sim_UNKNOWN_B1", "NaN(6,1)", "Feedbacks_sim", [640 35 730 55]);
    addConstantToOut(subsystemPath, "InverterDCFeedback_UNKNOWN_B1", "NaN(4,1)", "InverterDCFeedback", [640 90 730 110]);
    addConstantToOut(subsystemPath, "DriveKPI_B1_STATUS", "[NaN;NaN;NaN;NaN;NaN;NaN;NaN;1]", "DriveKPI", [640 145 730 165]);
end

function addModelReference(subsystemPath, driveModelName)
    blockPath = subsystemPath + "/PMSMDriveThermal_Reference";
    add_block("simulink/Ports & Subsystems/Model", blockPath, ...
        "Position", [250 70 520 180]);
    set_param(blockPath, "ModelName", driveModelName);
end

function addDriveBoundaryAnnotation(subsystemPath)
    text = "V4-B1 drive boundary" + newline + ...
        "Official reference: PMSMDriveThermal.slx" + newline + ...
        "Core model is referenced for traceability only in this round." + newline + ...
        "DCBus, Duty_Cycles, gate mapping, Feedbacks_sim, and InverterDCFeedback remain UNKNOWN." + newline + ...
        "DriveKPI vector = [I_phase_rms; I_phase_peak; P_cu; P_iron; P_inv; T_stator; T_rotor; status_code], status_code=1 means official drive reference is present.";
    annotation = Simulink.Annotation(subsystemPath, text);
    annotation.Position = [35 185 760 285];
end

function addTerminator(subsystemPath, inportName, terminatorName, position)
    add_block("simulink/Sinks/Terminator", subsystemPath + "/" + terminatorName, ...
        "Position", position);
    add_line(subsystemPath, inportName + "/1", terminatorName + "/1", "autorouting", "on");
end

function addConstantToOut(subsystemPath, constantName, value, outportName, position)
    add_block("simulink/Sources/Constant", subsystemPath + "/" + constantName, ...
        "Position", position, "Value", value);
    add_line(subsystemPath, constantName + "/1", outportName + "/1", "autorouting", "on");
end
