function build_pulse_heating_official_spine_v04b3(overwrite)
%BUILD_PULSE_HEATING_OFFICIAL_SPINE_V04B3 MCB FOC controller migration.
%
% V4-B3 copies the Control_System subsystem from the official MCB FOC model
% into the V4 controller boundary. It establishes feedback adaptation
% (Feedbacks_sim -> Iab_meas + Pos + EnClosedLoop), a 3-duty to 6-gate
% adapter (Relational Operator + complementary), Idq_ref pass-through,
% parameter override (V4 drive params replace MCB defaults), and
% ControlKPI output. Unit Delays break the algebraic loop between the
% discrete controller and the continuous Simscape plant.

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

    build_pulse_heating_official_spine_v04b2(overwrite);
    open_system(modelPath);
    configureCallbacks(modelName, officialPaths);

    mcbSubsys = modelName + "/MCB_SIUnits_FOC_Controller";
    clearBoundaryContents(mcbSubsys);
    copyControlSystem(mcbSubsys, officialPaths.controllerModelName);
    connectFeedbackAdapter(mcbSubsys);
    connectDutyGateAdapter(mcbSubsys);
    connectIdqRef(mcbSubsys);
    createDataStores(mcbSubsys);
    connectControlKPI(mcbSubsys);
    updateAnnotation(mcbSubsys);

    set_param(modelName, "StopTime", "1");
    save_system(modelName, modelPath);
    fprintf("Built V4-B3 MCB FOC controller migration: %s\n", modelPath);
end

function paths = prepareOfficialExamplePaths()
    paths.batteryDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\BatteryThermalManagementExample";
    paths.controllerDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\mcb\SIUnitsExample";
    paths.driveDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\PMSMDriveThermalExample";
    paths.driveModelName = "PMSMDriveThermal";
    paths.controllerModelName = "mcb_pmsm_foc_qep_f28379d_SIUnit";

    requiredDirs = [paths.batteryDir, paths.controllerDir, paths.driveDir];
    for idx = 1:numel(requiredDirs)
        if ~isfolder(requiredDirs(idx))
            error("V4B3:MissingDir", "Directory not found: %s", requiredDirs(idx));
        end
        addpath(requiredDirs(idx));
    end

    load_system(paths.driveModelName);
    load_system(paths.controllerModelName);
    evalin("base", "PMSMDriveThermalData");
    evalin("base", "mcb_pmsm_foc_qep_f28379d_SIUnit_data");
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
        "PMSMDriveThermalData;", ...
        "mcb_pmsm_foc_qep_f28379d_SIUnit_data;", ...
        "pmsm.Rs = Rs; pmsm.Ld = Ld; pmsm.Lq = Lq; pmsm.p = N; pmsm.FluxPM = PM;", ...
        "inverter.V_dc = 48; dataType = 'double';" ...
    ];
    set_param(modelName, "InitFcn", strjoin(initLines, newline));
end

function clearBoundaryContents(subsystemPath)
    lineHandles = find_system(subsystemPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
    for idx = numel(lineHandles):-1:1
        try; delete_line(lineHandles(idx)); catch; end
    end

    blockPaths = find_system(subsystemPath, "SearchDepth", 1, "Type", "Block");
    for idx = numel(blockPaths):-1:1
        blkPath = string(blockPaths{idx});
        if blkPath == subsystemPath; continue; end
        bt = string(get_param(blockPaths{idx}, "BlockType"));
        if bt == "Inport" || bt == "Outport"; continue; end
        delete_block(blockPaths{idx});
    end
end

function copyControlSystem(mcbSubsys, controllerModelName)
    src = controllerModelName + "/Current Control/Control_System";
    dst = mcbSubsys + "/Control_System";
    add_block(src, dst);
end

function connectFeedbackAdapter(mcbSubsys)
    fbInBlk = mcbSubsys + "/Feedbacks_sim";
    csBlk = mcbSubsys + "/Control_System";
    csPH = get_param(csBlk, "PortHandles");

    % Unit Delay on feedback to break algebraic loop
    add_block("simulink/Discrete/Unit Delay", mcbSubsys + "/FB_UnitDelay", ...
        "SampleTime", "Tsc", "Position", [20 100 50 130]);
    fbUdPH = get_param(mcbSubsys + "/FB_UnitDelay", "PortHandles");
    add_line(mcbSubsys, get_param(fbInBlk,"PortHandles").Outport(1), fbUdPH.Inport(1));

    % Demux: [ia, ib, ic, w_motor, theta, V_dc]
    add_block("simulink/Signal Routing/Demux", mcbSubsys + "/FB_Demux", ...
        "Outputs", "6", "Position", [80 50 85 200]);
    demuxPH = get_param(mcbSubsys + "/FB_Demux", "PortHandles");
    add_line(mcbSubsys, fbUdPH.Outport(1), demuxPH.Inport(1));

    % Iab_meas = [ia, ib]
    add_block("simulink/Signal Routing/Mux", mcbSubsys + "/Iab_Mux", ...
        "Inputs", "2", "Position", [120 50 125 85]);
    iabPH = get_param(mcbSubsys + "/Iab_Mux", "PortHandles");
    add_line(mcbSubsys, demuxPH.Outport(1), iabPH.Inport(1));
    add_line(mcbSubsys, demuxPH.Outport(2), iabPH.Inport(2));
    add_line(mcbSubsys, iabPH.Outport(1), csPH.Inport(1));

    % Pos = theta (5th output)
    add_line(mcbSubsys, demuxPH.Outport(5), csPH.Inport(2));

    % EnClosedLoop = 1
    add_block("simulink/Sources/Constant", mcbSubsys + "/EnClosedLoop_Const", ...
        "Value", "1", "Position", [40 220 90 240]);
    add_line(mcbSubsys, get_param(mcbSubsys+"/EnClosedLoop_Const","PortHandles").Outport(1), csPH.Inport(3));

    % Terminate unused demux outputs
    for pIdx = [3 4 6]
        termName = mcbSubsys + "/Term_FB_" + string(pIdx);
        add_block("simulink/Sinks/Terminator", termName, "Position", [100 50+50*(pIdx-1) 120 65+50*(pIdx-1)]);
        add_line(mcbSubsys, demuxPH.Outport(pIdx), get_param(termName,"PortHandles").Inport(1));
    end

    % Terminate Idq_debug
    add_block("simulink/Sinks/Terminator", mcbSubsys + "/Term_Idq_debug", "Position", [300 300 320 315]);
    add_line(mcbSubsys, csPH.Outport(2), get_param(mcbSubsys+"/Term_Idq_debug","PortHandles").Inport(1));
end

function connectIdqRef(mcbSubsys)
    csBlk = mcbSubsys + "/Control_System";
    csPH = get_param(csBlk, "PortHandles");

    add_block("simulink/Discrete/Unit Delay", mcbSubsys + "/Idq_UnitDelay", ...
        "SampleTime", "Tsc", "Position", [20 260 50 290]);
    idqUdPH = get_param(mcbSubsys + "/Idq_UnitDelay", "PortHandles");
    add_line(mcbSubsys, get_param(mcbSubsys+"/Idq_ref","PortHandles").Outport(1), idqUdPH.Inport(1));
    add_line(mcbSubsys, idqUdPH.Outport(1), csPH.Inport(4));
end

function connectDutyGateAdapter(mcbSubsys)
    csBlk = mcbSubsys + "/Control_System";
    csPH = get_param(csBlk, "PortHandles");

    add_block("simulink/Signal Routing/Demux", mcbSubsys + "/Duty_Demux", ...
        "Outputs", "3", "Position", [300 50 305 150]);
    dutyDemuxPH = get_param(mcbSubsys + "/Duty_Demux", "PortHandles");
    add_line(mcbSubsys, csPH.Outport(1), dutyDemuxPH.Inport(1));

    gateHighNames = ["G1_A_H", "G3_B_H", "G5_C_H"];
    gateLowNames = ["G2_A_L", "G4_B_L", "G6_C_L"];

    for phase = 1:3
        % Gate High: Relational Operator (duty > 0.5)
        ghName = mcbSubsys + "/" + gateHighNames(phase);
        add_block("simulink/Logic and Bit Operations/Relational Operator", ghName, ...
            "Operator", ">", "Position", [380 30+80*(phase-1) 420 65+80*(phase-1)]);
        ghPH = get_param(ghName, "PortHandles");

        halfConst = mcbSubsys + "/Half_Const_" + string(phase);
        add_block("simulink/Sources/Constant", halfConst, "Value", "0.5", ...
            "Position", [320 60+80*(phase-1) 350 80+80*(phase-1)]);
        add_line(mcbSubsys, dutyDemuxPH.Outport(phase), ghPH.Inport(1));
        add_line(mcbSubsys, get_param(halfConst,"PortHandles").Outport(1), ghPH.Inport(2));

        % Data Type Conversion: boolean -> double
        dtcName = mcbSubsys + "/DTC_" + gateHighNames(phase);
        ghPos = get_param(ghName, "Position");
        add_block("simulink/Signal Attributes/Data Type Conversion", dtcName, ...
            "OutDataTypeStr", "double", "Position", [ghPos(3)+10 ghPos(2) ghPos(3)+60 ghPos(4)]);
        dtcPH = get_param(dtcName, "PortHandles");
        add_line(mcbSubsys, ghPH.Outport(1), dtcPH.Inport(1));

        % Gate Low: 1 - G_high
        glName = mcbSubsys + "/" + gateLowNames(phase);
        add_block("simulink/Math Operations/Sum", glName, "Inputs", "+-", ...
            "Position", [480 60+80*(phase-1) 520 90+80*(phase-1)]);
        glPH = get_param(glName, "PortHandles");

        oneConst = mcbSubsys + "/One_Const_" + string(phase);
        add_block("simulink/Sources/Constant", oneConst, "Value", "1", ...
            "Position", [430 90+80*(phase-1) 460 110+80*(phase-1)]);
        add_line(mcbSubsys, get_param(oneConst,"PortHandles").Outport(1), glPH.Inport(1));
        add_line(mcbSubsys, dtcPH.Outport(1), glPH.Inport(2));
    end

    % Mux 6 gates
    add_block("simulink/Signal Routing/Mux", mcbSubsys + "/Gate_Mux", ...
        "Inputs", "6", "Position", [560 30 565 280]);
    gateMuxPH = get_param(mcbSubsys + "/Gate_Mux", "PortHandles");

    allGateNames = ["G1_A_H", "G2_A_L", "G3_B_H", "G4_B_L", "G5_C_H", "G6_C_L"];
    for k = 1:2:5
        dtcBlk = mcbSubsys + "/DTC_" + allGateNames(k);
        add_line(mcbSubsys, get_param(dtcBlk,"PortHandles").Outport(1), gateMuxPH.Inport(k));
    end
    for k = 2:2:6
        glBlk = mcbSubsys + "/" + allGateNames(k);
        add_line(mcbSubsys, get_param(glBlk,"PortHandles").Outport(1), gateMuxPH.Inport(k));
    end

    % Unit Delay on output to break algebraic loop
    add_block("simulink/Discrete/Unit Delay", mcbSubsys + "/Duty_UnitDelay", ...
        "SampleTime", "Tsc", "Position", [600 130 640 160]);
    udPH = get_param(mcbSubsys + "/Duty_UnitDelay", "PortHandles");
    add_line(mcbSubsys, gateMuxPH.Outport(1), udPH.Inport(1));
    add_line(mcbSubsys, udPH.Outport(1), get_param(mcbSubsys+"/Duty_Cycles","PortHandles").Inport(1));
end

function createDataStores(mcbSubsys)
    add_block("simulink/Signal Routing/Data Store Memory", mcbSubsys + "/DSM_Enable", ...
        "DataStoreName", "Enable", "InitialValue", "1", "Position", [40 350 120 390]);
    add_block("simulink/Signal Routing/Data Store Memory", mcbSubsys + "/DSM_Speed_ref", ...
        "DataStoreName", "Speed_ref", "InitialValue", "0", "Position", [40 400 120 440]);
end

function connectControlKPI(mcbSubsys)
    add_block("simulink/Signal Routing/Mux", mcbSubsys + "/KPI_Mux", ...
        "Inputs", "5", "Position", [560 320 565 420]);
    kpiMuxPH = get_param(mcbSubsys + "/KPI_Mux", "PortHandles");

    kpiFields = ["KPI_tracking_NaN", "KPI_modindex_NaN", "KPI_sat_NaN", "KPI_enable", "KPI_status"];
    kpiVals = ["NaN", "NaN", "NaN", "1", "3"];
    kpiPos = {[480 320 530 335], [480 345 530 360], [480 370 530 385], [480 395 530 410], [480 420 530 435]};

    for k = 1:5
        add_block("simulink/Sources/Constant", mcbSubsys + "/" + kpiFields(k), ...
            "Value", kpiVals(k), "Position", kpiPos{k});
        add_line(mcbSubsys, get_param(mcbSubsys+"/"+kpiFields(k),"PortHandles").Outport(1), kpiMuxPH.Inport(k));
    end

    add_line(mcbSubsys, kpiMuxPH.Outport(1), get_param(mcbSubsys+"/ControlKPI","PortHandles").Inport(1));
end

function updateAnnotation(mcbSubsys)
    oldAnns = find_system(mcbSubsys, "SearchDepth", 1, "Type", "Annotation");
    for idx = numel(oldAnns):-1:1
        try; delete(oldAnns(idx)); catch; end
    end

    text = "V4-B3 MCB FOC controller boundary" + newline + ...
        "Official reference: mcb_pmsm_foc_qep_f28379d_SIUnit.slx" + newline + ...
        "Copied: Control_System (Closed Loop Control + Open Loop Start-Up + SVPWM)" + newline + ...
        "Feedback: Feedbacks_sim -> UnitDelay -> Demux -> Iab_meas + Pos + EnClosedLoop" + newline + ...
        "Gate: Duty_abc(3x1) -> RelOp(>0.5) -> DTC(double) -> complementary -> 6 gate -> UnitDelay -> Duty_Cycles" + newline + ...
        "Params: V4 drive (N=6, PM=0.03, Rs=0.013, 48V) overrides MCB defaults; MCB PI gains retained" + newline + ...
        "DataStores: Enable=1, Speed_ref=0 (stall)" + newline + ...
        "ControlKPI = [tracking_NaN; modindex_NaN; sat_NaN; enable=1; status=3]";
    annotation = Simulink.Annotation(mcbSubsys, text);
    annotation.Position = [35 450 760 570];
end
