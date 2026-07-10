function build_pulse_heating_official_spine_v04b2(overwrite)
%BUILD_PULSE_HEATING_OFFICIAL_SPINE_V04B2 Port-level subsystem migration.
%
% V4-B2 copies core subsystems from PMSMDriveThermal.slx into the V4 drive
% boundary. DC-link, gate mapping, feedbacks and KPI are connected to real
% physical/signal paths. Battery is copied as temporary DC source until
% V4-B4 closes the energy path. I_dc, P_dc, I_rms, I_peak, P_cu, P_iron
% and P_inv remain NaN until sensors and losses are added.

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
    configureCallbacks(modelName, officialPaths);
    updateDutyCyclesDimension(modelName);

    driveSubsys = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    clearBoundaryContents(driveSubsys);
    copyCoreSubsystems(driveSubsys, officialPaths.driveModelName);
    connectDCPath(driveSubsys);
    connectGatePath(driveSubsys);
    connectThreePhasePath(driveSubsys);
    connectMechanicalPath(driveSubsys);
    connectThermalPath(driveSubsys);
    connectFeedbacksSim(driveSubsys);
    connectInverterDCFeedback(driveSubsys);
    connectDriveKPI(driveSubsys);
    updateBoundaryAnnotation(driveSubsys);

    set_param(modelName, "StopTime", "1");
    save_system(modelName, modelPath);
    fprintf("Built V4-B2 drive port-level migration: %s\n", modelPath);
end

function paths = prepareOfficialExamplePaths()
    paths.batteryDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\BatteryThermalManagementExample";
    paths.controllerDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\mcb\SIUnitsExample";
    paths.driveDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\PMSMDriveThermalExample";
    paths.driveModelName = "PMSMDriveThermal";

    requiredDirs = [paths.batteryDir, paths.controllerDir, paths.driveDir];
    for idx = 1:numel(requiredDirs)
        if ~isfolder(requiredDirs(idx))
            error("V4B2:MissingOfficialExampleDir", "Official example directory does not exist: %s", requiredDirs(idx));
        end
        addpath(requiredDirs(idx));
    end

    requiredSymbols = ["BatteryThermalManagementInitialization", "BatteryModule", "PMSMDriveThermalData"];
    for idx = 1:numel(requiredSymbols)
        if strlength(which(requiredSymbols(idx))) == 0
            error("V4B2:MissingOfficialDependency", "Required official dependency is not on path: %s", requiredSymbols(idx));
        end
    end

    load_system(paths.driveModelName);
    evalin("base", "PMSMDriveThermalData");
end

function configureCallbacks(modelName, paths)
    preLoadLines = [ ...
        "addpath('" + paths.batteryDir + "');", ...
        "addpath('" + paths.controllerDir + "');", ...
        "addpath('" + paths.driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "set_param('PMSMDriveThermal','SimscapeLogType','none','SimscapeLogSimulationStatistics','off');", ...
        "set_param('PMSMDriveThermal','Dirty','off');" ...
    ];
    set_param(modelName, "PreLoadFcn", strjoin(preLoadLines, newline));

    initLines = [ ...
        "addpath('" + paths.batteryDir + "');", ...
        "addpath('" + paths.controllerDir + "');", ...
        "addpath('" + paths.driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "PMSMDriveThermalData;" ...
    ];
    set_param(modelName, "InitFcn", strjoin(initLines, newline));

    load_system(paths.driveModelName);
    set_param(modelName, "UnderspecifiedInitializationDetection", ...
        get_param(paths.driveModelName, "UnderspecifiedInitializationDetection"));
    set_param(paths.driveModelName, "SimscapeLogType", "none", ...
        "SimscapeLogSimulationStatistics", "off");
    set_param(paths.driveModelName, "Dirty", "off");
end

function updateDutyCyclesDimension(modelName)
    mcbDutyConst = modelName + "/MCB_SIUnits_FOC_Controller/Duty_Cycles_zero_PLACEHOLDER";
    set_param(mcbDutyConst, "Value", "[0;0;0;0;0;0]");
end

function clearBoundaryContents(subsystemPath)
    lineHandles = find_system(subsystemPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
    for idx = numel(lineHandles):-1:1
        try
            delete_line(lineHandles(idx));
        catch
        end
    end

    blockPaths = find_system(subsystemPath, "SearchDepth", 1, "Type", "Block");
    for idx = numel(blockPaths):-1:1
        blkPath = string(blockPaths{idx});
        if blkPath == subsystemPath
            continue;
        end
        blockType = string(get_param(blockPaths{idx}, "BlockType"));
        if blockType == "Inport" || blockType == "Outport"
            continue;
        end
        delete_block(blockPaths{idx});
    end
end

function copyCoreSubsystems(driveSubsys, srcModel)
    coreBlocks = ["Three-phase inverter", "PMSM", "Thermal model", "Encoder", ...
        "Sensing currents", "Scopes", "Solver Configuration", ...
        "Electrical Reference", "Mechanical Rotational Reference1", ...
        "Motor & load inertia", "Ambient Temperature", ...
        "Temperature Source", "ThRef", "Battery"];

    for idx = 1:numel(coreBlocks)
        src = srcModel + "/" + coreBlocks(idx);
        dst = driveSubsys + "/" + coreBlocks(idx);
        if coreBlocks(idx) == "Battery"
            dst = driveSubsys + "/Battery_DC_Source";
        end
        add_block(src, dst);
    end
end

function connectDCPath(driveSubsys)
    batBlk = driveSubsys + "/Battery_DC_Source";
    invBlk = driveSubsys + "/Three-phase inverter";
    erBlk = driveSubsys + "/Electrical Reference";
    scBlk = driveSubsys + "/Solver Configuration";

    batPH = get_param(batBlk, "PortHandles");
    invPH = get_param(invBlk, "PortHandles");
    erPH = get_param(erBlk, "PortHandles");
    scPH = get_param(scBlk, "PortHandles");

    add_line(driveSubsys, batPH.LConn(1), invPH.LConn(1));
    add_line(driveSubsys, batPH.RConn(1), invPH.LConn(2));
    add_line(driveSubsys, batPH.RConn(1), erPH.LConn(1));
    add_line(driveSubsys, batPH.LConn(1), scPH.RConn(1));
end

function connectGatePath(driveSubsys)
    dcBlk = driveSubsys + "/Duty_Cycles";
    invBlk = driveSubsys + "/Three-phase inverter";
    dcPH = get_param(dcBlk, "PortHandles");
    invPH = get_param(invBlk, "PortHandles");
    add_line(driveSubsys, dcPH.Outport(1), invPH.Inport(1));
end

function connectThreePhasePath(driveSubsys)
    invBlk = driveSubsys + "/Three-phase inverter";
    scBlk = driveSubsys + "/Sensing currents";
    pmsmBlk = driveSubsys + "/PMSM";

    invPH = get_param(invBlk, "PortHandles");
    scPH = get_param(scBlk, "PortHandles");
    pmsmPH = get_param(pmsmBlk, "PortHandles");

    add_line(driveSubsys, invPH.RConn(1), scPH.LConn(1));
    add_line(driveSubsys, scPH.RConn(1), pmsmPH.LConn(1));
end

function connectMechanicalPath(driveSubsys)
    pmsmBlk = driveSubsys + "/PMSM";
    encBlk = driveSubsys + "/Encoder";
    inertiaBlk = driveSubsys + "/Motor & load inertia";
    mrrBlk = driveSubsys + "/Mechanical Rotational Reference1";

    pmsmPH = get_param(pmsmBlk, "PortHandles");
    encPH = get_param(encBlk, "PortHandles");
    inertiaPH = get_param(inertiaBlk, "PortHandles");
    mrrPH = get_param(mrrBlk, "PortHandles");

    add_line(driveSubsys, pmsmPH.RConn(1), encPH.LConn(1));
    add_line(driveSubsys, pmsmPH.RConn(2), encPH.LConn(2));
    add_line(driveSubsys, encPH.RConn(1), inertiaPH.LConn(1));
    add_line(driveSubsys, encPH.RConn(2), mrrPH.LConn(1));
    add_line(driveSubsys, inertiaPH.LConn(1), mrrPH.LConn(1));
end

function connectThermalPath(driveSubsys)
    pmsmBlk = driveSubsys + "/PMSM";
    tmBlk = driveSubsys + "/Thermal model";
    tsBlk = driveSubsys + "/Temperature Source";
    atBlk = driveSubsys + "/Ambient Temperature";
    thRefBlk = driveSubsys + "/ThRef";

    pmsmPH = get_param(pmsmBlk, "PortHandles");
    tmPH = get_param(tmBlk, "PortHandles");
    tsPH = get_param(tsBlk, "PortHandles");
    atPH = get_param(atBlk, "PortHandles");
    thRefPH = get_param(thRefBlk, "PortHandles");

    add_line(driveSubsys, pmsmPH.LConn(2), tmPH.LConn(1));
    add_line(driveSubsys, pmsmPH.RConn(3), tmPH.RConn(3));
    add_line(driveSubsys, pmsmPH.RConn(4), tmPH.RConn(2));
    add_line(driveSubsys, pmsmPH.RConn(5), tmPH.RConn(1));
    add_line(driveSubsys, tsPH.LConn(1), tmPH.LConn(2));
    add_line(driveSubsys, atPH.RConn(1), tsPH.RConn(1));
    add_line(driveSubsys, tsPH.RConn(2), thRefPH.LConn(1));
end

function connectFeedbacksSim(driveSubsys)
    dcBusBlk = driveSubsys + "/DCBus";
    encBlk = driveSubsys + "/Encoder";
    fbOutBlk = driveSubsys + "/Feedbacks_sim";

    add_block("simulink/Signal Routing/From", driveSubsys + "/From_i_abc", ...
        "GotoTag", "i", "Position", [500 50 560 65]);
    add_block("simulink/Signal Routing/From", driveSubsys + "/From_w_motor", ...
        "GotoTag", "wMotor", "Position", [500 80 560 95]);
    add_block("simulink/Signal Routing/Demux", driveSubsys + "/Meas_Demux", ...
        "Outputs", "2", "Position", [500 110 505 150]);
    add_block("simulink/Sinks/Terminator", driveSubsys + "/Term_Demux_w", ...
        "Position", [520 110 540 125]);
    add_block("simulink/Signal Routing/Mux", driveSubsys + "/Mux_Feedbacks_sim", ...
        "Inputs", "4", "Position", [600 50 605 120]);

    dcBusPH = get_param(dcBusBlk, "PortHandles");
    encPH = get_param(encBlk, "PortHandles");
    demuxPH = get_param(driveSubsys + "/Meas_Demux", "PortHandles");
    termPH = get_param(driveSubsys + "/Term_Demux_w", "PortHandles");
    muxPH = get_param(driveSubsys + "/Mux_Feedbacks_sim", "PortHandles");
    fromIPH = get_param(driveSubsys + "/From_i_abc", "PortHandles");
    fromWPH = get_param(driveSubsys + "/From_w_motor", "PortHandles");
    fbOutPH = get_param(fbOutBlk, "PortHandles");

    add_line(driveSubsys, encPH.Outport(1), demuxPH.Inport(1));
    add_line(driveSubsys, demuxPH.Outport(1), termPH.Inport(1));
    add_line(driveSubsys, fromIPH.Outport(1), muxPH.Inport(1));
    add_line(driveSubsys, fromWPH.Outport(1), muxPH.Inport(2));
    add_line(driveSubsys, demuxPH.Outport(2), muxPH.Inport(3));
    add_line(driveSubsys, dcBusPH.Outport(1), muxPH.Inport(4));
    add_line(driveSubsys, muxPH.Outport(1), fbOutPH.Inport(1));
end

function connectInverterDCFeedback(driveSubsys)
    dcBusBlk = driveSubsys + "/DCBus";
    invDcOutBlk = driveSubsys + "/InverterDCFeedback";

    add_block("simulink/Sources/Constant", driveSubsys + "/I_dc_UNKNOWN", ...
        "Value", "NaN", "Position", [520 220 570 235]);
    add_block("simulink/Sources/Constant", driveSubsys + "/P_dc_UNKNOWN", ...
        "Value", "NaN", "Position", [520 245 570 260]);
    add_block("simulink/Sources/Constant", driveSubsys + "/InvDC_status", ...
        "Value", "1", "Position", [520 270 570 285]);
    add_block("simulink/Signal Routing/Mux", driveSubsys + "/Mux_InverterDCFeedback", ...
        "Inputs", "4", "Position", [600 200 605 270]);

    dcBusPH = get_param(dcBusBlk, "PortHandles");
    muxPH = get_param(driveSubsys + "/Mux_InverterDCFeedback", "PortHandles");
    invDcOutPH = get_param(invDcOutBlk, "PortHandles");

    add_line(driveSubsys, dcBusPH.Outport(1), muxPH.Inport(1));
    add_line(driveSubsys, get_param(driveSubsys + "/I_dc_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(2));
    add_line(driveSubsys, get_param(driveSubsys + "/P_dc_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(3));
    add_line(driveSubsys, get_param(driveSubsys + "/InvDC_status", "PortHandles").Outport(1), muxPH.Inport(4));
    add_line(driveSubsys, muxPH.Outport(1), invDcOutPH.Inport(1));
end

function connectDriveKPI(driveSubsys)
    kpiOutBlk = driveSubsys + "/DriveKPI";

    add_block("simulink/Sources/Constant", driveSubsys + "/I_rms_UNKNOWN", ...
        "Value", "NaN", "Position", [600 350 650 365]);
    add_block("simulink/Sources/Constant", driveSubsys + "/I_peak_UNKNOWN", ...
        "Value", "NaN", "Position", [600 375 650 390]);
    add_block("simulink/Sources/Constant", driveSubsys + "/P_cu_UNKNOWN", ...
        "Value", "NaN", "Position", [600 400 650 415]);
    add_block("simulink/Sources/Constant", driveSubsys + "/P_iron_UNKNOWN", ...
        "Value", "NaN", "Position", [600 425 650 440]);
    add_block("simulink/Sources/Constant", driveSubsys + "/P_inv_UNKNOWN", ...
        "Value", "NaN", "Position", [600 450 650 465]);
    add_block("simulink/Signal Routing/From", driveSubsys + "/From_TA", ...
        "GotoTag", "TA", "Position", [600 475 650 488]);
    add_block("simulink/Signal Routing/From", driveSubsys + "/From_TB", ...
        "GotoTag", "TB", "Position", [600 490 650 503]);
    add_block("simulink/Signal Routing/From", driveSubsys + "/From_TC", ...
        "GotoTag", "TC", "Position", [600 505 650 518]);
    add_block("simulink/Signal Routing/From", driveSubsys + "/From_TR", ...
        "GotoTag", "TR", "Position", [600 530 650 543]);
    add_block("simulink/Math Operations/MinMax", driveSubsys + "/T_stator_max", ...
        "Function", "max", "Inputs", "3", "Position", [670 475 700 520]);
    add_block("simulink/Sources/Constant", driveSubsys + "/DriveKPI_status", ...
        "Value", "2", "Position", [600 555 650 570]);
    add_block("simulink/Signal Routing/Mux", driveSubsys + "/Mux_DriveKPI", ...
        "Inputs", "8", "Position", [700 350 705 520]);

    muxPH = get_param(driveSubsys + "/Mux_DriveKPI", "PortHandles");
    maxPH = get_param(driveSubsys + "/T_stator_max", "PortHandles");
    kpiOutPH = get_param(kpiOutBlk, "PortHandles");

    add_line(driveSubsys, get_param(driveSubsys + "/I_rms_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(1));
    add_line(driveSubsys, get_param(driveSubsys + "/I_peak_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(2));
    add_line(driveSubsys, get_param(driveSubsys + "/P_cu_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(3));
    add_line(driveSubsys, get_param(driveSubsys + "/P_iron_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(4));
    add_line(driveSubsys, get_param(driveSubsys + "/P_inv_UNKNOWN", "PortHandles").Outport(1), muxPH.Inport(5));
    add_line(driveSubsys, get_param(driveSubsys + "/From_TA", "PortHandles").Outport(1), maxPH.Inport(1));
    add_line(driveSubsys, get_param(driveSubsys + "/From_TB", "PortHandles").Outport(1), maxPH.Inport(2));
    add_line(driveSubsys, get_param(driveSubsys + "/From_TC", "PortHandles").Outport(1), maxPH.Inport(3));
    add_line(driveSubsys, maxPH.Outport(1), muxPH.Inport(6));
    add_line(driveSubsys, get_param(driveSubsys + "/From_TR", "PortHandles").Outport(1), muxPH.Inport(7));
    add_line(driveSubsys, get_param(driveSubsys + "/DriveKPI_status", "PortHandles").Outport(1), muxPH.Inport(8));
    add_line(driveSubsys, muxPH.Outport(1), kpiOutPH.Inport(1));
end

function updateBoundaryAnnotation(driveSubsys)
    oldAnns = find_system(driveSubsys, "SearchDepth", 1, "Type", "Annotation");
    for idx = numel(oldAnns):-1:1
        try
            delete(oldAnns(idx));
        catch
        end
    end

    text = "V4-B2 drive boundary (port-level subsystem migration)" + newline + ...
        "Official reference: PMSMDriveThermal.slx" + newline + ...
        "Copied: Three-phase inverter, PMSM, Thermal model, Encoder, Sensing currents, Scopes" + newline + ...
        "DC path: Battery (copied from official) -> Inverter +/-" + newline + ...
        "Gate path: Duty_Cycles(6x1) -> Inverter G (6 IGBT gates)" + newline + ...
        "Feedbacks_sim = [i_abc(3); w_motor; theta; V_dc] (6x1)" + newline + ...
        "InverterDCFeedback = [V_dc; I_dc(NaN); P_dc(NaN); status=1]" + newline + ...
        "DriveKPI = [I_rms(NaN); I_peak(NaN); P_cu(NaN); P_iron(NaN); P_inv(NaN); T_stator; T_rotor; status=2]" + newline + ...
        "status_code=2 means core subsystems connected; I_dc/P_dc/losses still UNKNOWN.";
    annotation = Simulink.Annotation(driveSubsys, text);
    annotation.Position = [35 600 760 720];
end
