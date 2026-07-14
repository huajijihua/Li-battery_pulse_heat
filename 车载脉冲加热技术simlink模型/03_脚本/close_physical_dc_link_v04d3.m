function close_physical_dc_link_v04d3()
%CLOSE_PHYSICAL_DC_LINK_V04D3 Physical DC-link closure for V4-D3.
%
% Replaces signal-level DC-link bridge with real electrical connection
% between battery pack and inverter DC bus.

    modelName = "pulse_heating_official_spine_v04";
    scriptDir = fileparts(mfilename("fullpath"));
    modelDir = fullfile(fileparts(scriptDir), "02_模型");
    modelPath = fullfile(modelDir, modelName + ".slx");

    if ~bdIsLoaded(modelName)
        load_system(modelPath);
    end
    fprintf("=== V4-D3: Physical DC-link closure ===\n");

    bat = modelName + "/BatteryThermalManagement_BatteryPack";
    drv = modelName + "/PMSMDriveThermal_Inverter_And_Motor";

    phase1_battery_boundary(bat);
    phase2_drive_boundary(drv);
    phase3_root_connection(modelName);
    phase4_signal_routing(bat);
    phase5_voltage_params(modelName);

    save_system(modelName, modelPath, "OverwriteIfChangedOnDisk", true);
    fprintf("\nV4-D3 physical DC-link closure complete. Model saved.\n");
end

function deletePhysLines(sys, blkName)
%DELETEPHYSLINES Delete all physical connection lines from a block.

    blk = sprintf('%s/%s', sys, blkName);
    lh = get_param(blk, "LineHandles");
    for i = 1:numel(lh.LConn)
        if lh.LConn(i) ~= -1; try; delete_line(lh.LConn(i)); catch; end; end
    end
    for i = 1:numel(lh.RConn)
        if lh.RConn(i) ~= -1; try; delete_line(lh.RConn(i)); catch; end; end
    end
    for i = 1:numel(lh.Inport)
        if lh.Inport(i) ~= -1; try; delete_line(lh.Inport(i)); catch; end; end
    end
    for i = 1:numel(lh.Outport)
        if lh.Outport(i) ~= -1; try; delete_line(lh.Outport(i)); catch; end; end
    end
end

function physConnect(sys, srcBlock, srcPort, dstBlock, dstPort)
%PHYSCONNECT Connect two physical ports using string-based port spec.

    src = sprintf('%s/%s', srcBlock, srcPort);
    dst = sprintf('%s/%s', dstBlock, dstPort);
    add_line(sys, src, dst, "autorouting", "on");
end

function phase1_battery_boundary(bat)
%PHASE1_BATTERY_BOUNDARY Remove CCS chain, expose Battery_pack pos/neg.

    fprintf("\n--- Phase 1: Battery boundary cleanup ---\n");

    batPack   = bat + "/Battery_pack";
    ccs       = bat + "/Controlled_Current_Source";
    solverCfg = bat + "/Solver_Configuration";
    elecRef   = bat + "/Electrical_Reference";
    nanToZero = bat + "/BatteryLoad_NaN_to_Zero";
    batToPs   = bat + "/BatteryLoad_to_PS";

    % --- Disconnect and delete CCS, Solver, ElecRef ---
    deletePhysLines(bat, "Controlled_Current_Source");
    deletePhysLines(bat, "Solver_Configuration");
    deletePhysLines(bat, "Electrical_Reference");

    % Signal lines for NaN_to_Zero and BatteryLoad_to_PS
    nanLH = get_param(nanToZero, "LineHandles");
    for i = 1:numel(nanLH.Inport); if nanLH.Inport(i) ~= -1; try; delete_line(nanLH.Inport(i)); catch; end; end; end
    for i = 1:numel(nanLH.Outport); if nanLH.Outport(i) ~= -1; try; delete_line(nanLH.Outport(i)); catch; end; end; end
    psLH = get_param(batToPs, "LineHandles");
    for i = 1:numel(psLH.Inport); if psLH.Inport(i) ~= -1; try; delete_line(psLH.Inport(i)); catch; end; end; end
    for i = 1:numel(psLH.Outport); if psLH.Outport(i) ~= -1; try; delete_line(psLH.Outport(i)); catch; end; end; end

    batLoadLH = get_param(bat + "/BatteryLoad", "LineHandles");
    for i = 1:numel(batLoadLH.Outport); if batLoadLH.Outport(i) ~= -1; try; delete_line(batLoadLH.Outport(i)); catch; end; end; end

    delete_block(ccs);
    delete_block(solverCfg);
    delete_block(elecRef);
    delete_block(nanToZero);
    delete_block(batToPs);
    fprintf("  Deleted: CCS, Solver, ElecRef, NaN_to_Zero, BatteryLoad_to_PS\n");

    % --- Terminate BatteryLoad Inport ---
    termPath = bat + "/Term_BatteryLoad";
    if getSimulinkBlockHandle(termPath) == -1
        add_block("simulink/Sinks/Terminator", termPath);
    end
    batLoadPH = get_param(bat + "/BatteryLoad", "PortHandles");
    termPH    = get_param(termPath, "PortHandles");
    add_line(bat, batLoadPH.Outport(1), termPH.Inport(1), "autorouting", "on");
    fprintf("  Terminated BatteryLoad Inport\n");

    % --- Add PMIOPort blocks ---
    posPortPath = bat + "/Battery_pos";
    negPortPath = bat + "/Battery_neg";
    if getSimulinkBlockHandle(posPortPath) == -1
        add_block("built-in/PMIOPort", posPortPath, "Position", [100, 200, 120, 220]);
    end
    if getSimulinkBlockHandle(negPortPath) == -1
        add_block("built-in/PMIOPort", negPortPath, "Position", [100, 300, 120, 320]);
    end
    fprintf("  Added PMIOPorts: Battery_pos, Battery_neg\n");

    % --- Connect Battery_pack pos/neg to PMIOPorts ---
    % Battery_pack: LConn1 = pos, RConn1 = neg
    % PMIOPort: RConn1 = physical connection
    physConnect(bat, "Battery_pack", "LConn1", "Battery_pos", "RConn1");
    physConnect(bat, "Battery_pack", "RConn1", "Battery_neg", "RConn1");
    fprintf("  Connected: Battery_pack.pos -> Battery_pos, .neg -> Battery_neg\n");

    % --- Replace V_pack_UNKNOWN and I_pack_UNKNOWN with From blocks ---
    replaceUnknownWithFrom(bat, "V_pack_UNKNOWN", "V_pack_meas", "V_pack_from_drive", [400, 30], 1);
    replaceUnknownWithFrom(bat, "I_pack_UNKNOWN", "I_dc_meas",   "I_pack_from_drive", [400, 70], 2);
    fprintf("  Replaced V_pack_UNKNOWN and I_pack_UNKNOWN with From blocks\n");
end

function phase2_drive_boundary(drv)
%PHASE2_DRIVE_BOUNDARY Remove Battery_DC_Source, add sensors, expose DC+/-

    fprintf("\n--- Phase 2: Drive boundary - sensors and DC ports ---\n");

    batDc     = drv + "/Battery_DC_Source";
    elecRef   = drv + "/Electrical Reference";
    solverCfg = drv + "/Solver Configuration";
    inverter  = drv + "/Three-phase inverter";

    % --- Disconnect and delete Battery_DC_Source ---
    % Also clean residual connections on Solver and ElecRef
    deletePhysLines(drv, "Battery_DC_Source");
    deletePhysLines(drv, "Solver Configuration");
    deletePhysLines(drv, "Electrical Reference");
    fprintf("  Disconnected Battery_DC_Source + residual lines\n");
    delete_block(batDc);
    fprintf("  Deleted: Battery_DC_Source\n");

    % Clean residual physical connections on inverter DC ports only
    invLH = get_param(inverter, "LineHandles");
    for i = 1:numel(invLH.LConn)
        if invLH.LConn(i) ~= -1; try; delete_line(invLH.LConn(i)); catch; end; end
    end

    % --- Add PMIOPort blocks ---
    dcPlusPath  = drv + "/DC_plus";
    dcMinusPath = drv + "/DC_minus";
    if getSimulinkBlockHandle(dcPlusPath) == -1
        add_block("built-in/PMIOPort", dcPlusPath, "Position", [60, 150, 80, 170]);
    end
    if getSimulinkBlockHandle(dcMinusPath) == -1
        add_block("built-in/PMIOPort", dcMinusPath, "Position", [60, 300, 80, 320]);
    end
    fprintf("  Added PMIOPorts: DC_plus, DC_minus\n");

    % --- Add Current Sensor ---
    iSensorPath = drv + "/DC_Current_Sensor";
    if getSimulinkBlockHandle(iSensorPath) == -1
        add_block("fl_lib/Electrical/Electrical Sensors/Current Sensor", iSensorPath, ...
            "Position", [150, 145, 180, 175]);
    end
    deletePhysLines(drv, "DC_Current_Sensor");
    fprintf("  Added Current Sensor\n");

    % --- Add Voltage Sensor ---
    vSensorPath = drv + "/DC_Voltage_Sensor";
    if getSimulinkBlockHandle(vSensorPath) == -1
        add_block("fl_lib/Electrical/Electrical Sensors/Voltage Sensor", vSensorPath, ...
            "Position", [220, 200, 250, 230]);
    end
    deletePhysLines(drv, "DC_Voltage_Sensor");
    fprintf("  Added Voltage Sensor\n");

    % --- Connect DC+ path: PMIOPort -> Current Sensor.p -> Inverter DC+ ---
    % Current Sensor: LConn1=p(+), RConn1=I(signal), RConn2=n(-)
    % Inverter: LConn1=DC+, LConn2=DC-
    physConnect(drv, "DC_plus", "RConn1", "DC_Current_Sensor", "LConn1");
    physConnect(drv, "DC_Current_Sensor", "RConn2", "Three-phase inverter", "LConn1");
    physConnect(drv, "DC_Current_Sensor", "RConn2", "Solver Configuration", "RConn1");
    fprintf("  Connected: DC+ -> I_Sensor -> Inverter DC+ + Solver\n");

    % --- Connect DC- path: PMIOPort -> Inverter DC- + ElecRef ---
    physConnect(drv, "DC_minus", "RConn1", "Three-phase inverter", "LConn2");
    physConnect(drv, "DC_minus", "RConn1", "Electrical Reference", "LConn1");
    fprintf("  Connected: DC- -> Inverter DC- + ElecRef\n");

    % --- Connect Voltage Sensor (parallel: DC+ to DC-) ---
    % Voltage Sensor: LConn1=+(electrical), RConn1=V(signal), RConn2=-(electrical)
    physConnect(drv, "DC_Current_Sensor", "RConn2", "DC_Voltage_Sensor", "LConn1");
    physConnect(drv, "Three-phase inverter", "LConn2", "DC_Voltage_Sensor", "RConn2");
    fprintf("  Connected: Voltage Sensor parallel to DC bus\n");

    % --- Add PS-Simulink Converters ---
    vConvPath = drv + "/V_pack_meas";
    if getSimulinkBlockHandle(vConvPath) == -1
        add_block("nesl_utility/PS-Simulink Converter", vConvPath, "Position", [300, 205, 330, 225]);
    end
    iConvPath = drv + "/I_dc_meas";
    if getSimulinkBlockHandle(iConvPath) == -1
        add_block("nesl_utility/PS-Simulink Converter", iConvPath, "Position", [300, 150, 330, 170]);
    end
    % Connect sensor signal outputs to converters
    % V_sensor RConn1 = V signal, I_sensor RConn1 = I signal
    physConnect(drv, "DC_Voltage_Sensor", "RConn1", "V_pack_meas", "LConn1");
    physConnect(drv, "DC_Current_Sensor", "RConn1", "I_dc_meas", "LConn1");
    fprintf("  Added PS-Simulink Converters: V_pack_meas, I_dc_meas\n");

    % --- Add Goto blocks ---
    vGotoPath = drv + "/V_pack_goto";
    if getSimulinkBlockHandle(vGotoPath) == -1
        add_block("simulink/Signal Routing/Goto", vGotoPath, ...
            "GotoTag", "V_pack_meas", "Position", [360, 205, 420, 225]);
    end
    vConvPH = get_param(vConvPath, "PortHandles");
    vGotoPH = get_param(vGotoPath, "PortHandles");
    add_line(drv, vConvPH.Outport(1), vGotoPH.Inport(1), "autorouting", "on");

    iGotoPath = drv + "/I_dc_goto";
    if getSimulinkBlockHandle(iGotoPath) == -1
        add_block("simulink/Signal Routing/Goto", iGotoPath, ...
            "GotoTag", "I_dc_meas", "Position", [360, 150, 420, 170]);
    end
    iConvPH = get_param(iConvPath, "PortHandles");
    iGotoPH = get_param(iGotoPath, "PortHandles");
    add_line(drv, iConvPH.Outport(1), iGotoPH.Inport(1), "autorouting", "on");
    fprintf("  Added Goto blocks: V_pack_meas, I_dc_meas\n");

    % --- Replace NaN constants in InverterDCFeedback ---
    replaceDriveNaN(drv, "I_dc_UNKNOWN", "I_dc_meas", "I_dc_from_sensor", [380, 190], 2);
    replacePdcNaN(drv);
    replaceVdcInFeedback(drv);
    replaceVdcInInvDC(drv);
end

function phase3_root_connection(modelName)
%PHASE3_ROOT_CONNECTION Connect battery pos/neg to drive DC+/- at root.

    fprintf("\n--- Phase 3: Root level physical connection ---\n");

    bat = modelName + "/BatteryThermalManagement_BatteryPack";
    drv = modelName + "/PMSMDriveThermal_Inverter_And_Motor";

    batPH = get_param(bat, "PortHandles");
    drvPH = get_param(drv, "PortHandles");
    fprintf("  Battery LConn=%d, Drive LConn=%d\n", numel(batPH.LConn), numel(drvPH.LConn));

    % Connect battery pos (LConn1) -> drive DC+ (LConn1)
    physConnect(modelName, "BatteryThermalManagement_BatteryPack", "LConn1", ...
                         "PMSMDriveThermal_Inverter_And_Motor", "LConn1");
    fprintf("  Connected: Battery_pos -> DC_plus\n");
    % Connect battery neg (LConn2) -> drive DC- (LConn2)
    physConnect(modelName, "BatteryThermalManagement_BatteryPack", "LConn2", ...
                         "PMSMDriveThermal_Inverter_And_Motor", "LConn2");
    fprintf("  Connected: Battery_neg -> DC_minus\n");
end

function phase4_signal_routing(bat)
%PHASE4_SIGNAL_ROUTING Verify From blocks.

    fprintf("\n--- Phase 4: Signal routing verification ---\n");
    vFrom = bat + "/V_pack_from_drive";
    iFrom = bat + "/I_pack_from_drive";
    if getSimulinkBlockHandle(vFrom) ~= -1
        fprintf("  V_pack_from_drive: OK\n");
    else
        fprintf("  WARNING: V_pack_from_drive not found\n");
    end
    if getSimulinkBlockHandle(iFrom) ~= -1
        fprintf("  I_pack_from_drive: OK\n");
    else
        fprintf("  WARNING: I_pack_from_drive not found\n");
    end
end

function phase5_voltage_params(modelName)
%PHASE5_VOLTAGE_PARAMS Update inverter.V_dc.

    fprintf("\n--- Phase 5: Voltage parameter update ---\n");
    currentInit = get_param(modelName, "InitFcn");
    if contains(currentInit, "inverter.V_dc = 48")
        newInit = strrep(currentInit, "inverter.V_dc = 48", "inverter.V_dc = 66");
        set_param(modelName, "InitFcn", newInit);
        fprintf("  Updated InitFcn: inverter.V_dc = 48 -> 66\n");
    elseif contains(currentInit, "inverter.V_dc = 52.8")
        newInit = strrep(currentInit, "inverter.V_dc = 52.8", "inverter.V_dc = 66");
        set_param(modelName, "InitFcn", newInit);
        fprintf("  Updated InitFcn: inverter.V_dc = 52.8 -> 66\n");
    else
        fprintf("  Skip: inverter.V_dc not found or already updated\n");
    end
end

function replaceUnknownWithFrom(bat, unknownBlock, gotoTag, fromName, pos, muxInput)
%REPLACEUNKNOWNWITHFROM Replace a NaN constant with a From block.

    unknownPath = sprintf('%s/%s', bat, unknownBlock);
    if getSimulinkBlockHandle(unknownPath) == -1
        fprintf("  Skip: %s not found\n", unknownBlock);
        return;
    end
    lh = get_param(unknownPath, "LineHandles");
    if lh.Outport(1) ~= -1; delete_line(lh.Outport(1)); end
    delete_block(unknownPath);

    fromPath = sprintf('%s/%s', bat, fromName);
    add_block("simulink/Signal Routing/From", fromPath, ...
        "GotoTag", gotoTag, "Position", [pos(1), pos(2), pos(1)+60, pos(2)+15]);
    fromPH = get_param(fromPath, "PortHandles");
    muxDCPH = get_param(sprintf('%s/%s', bat, "Mux_BatteryDC"), "PortHandles");
    add_line(bat, fromPH.Outport(1), muxDCPH.Inport(muxInput), "autorouting", "on");
end

function replaceDriveNaN(drv, nanBlock, gotoTag, fromName, pos, muxInput)
%REPLACEDRIVENAN Replace a NaN constant in drive boundary with From block.

    nanPath = sprintf('%s/%s', drv, nanBlock);
    if getSimulinkBlockHandle(nanPath) == -1
        fprintf("  Skip: %s not found\n", nanBlock);
        return;
    end
    lh = get_param(nanPath, "LineHandles");
    if lh.Outport(1) ~= -1; delete_line(lh.Outport(1)); end
    delete_block(nanPath);

    fromPath = sprintf('%s/%s', drv, fromName);
    add_block("simulink/Signal Routing/From", fromPath, ...
        "GotoTag", gotoTag, "Position", [pos(1), pos(2), pos(1)+60, pos(2)+15]);
    fromPH = get_param(fromPath, "PortHandles");
    muxPH = get_param(sprintf('%s/%s', drv, "Mux_InverterDCFeedback"), "PortHandles");
    add_line(drv, fromPH.Outport(1), muxPH.Inport(muxInput), "autorouting", "on");
    fprintf("  Replaced %s with %s\n", nanBlock, fromName);
end

function replacePdcNaN(drv)
%REPLACEPDCNAN Replace P_dc_UNKNOWN with Product(V_pack * I_dc).

    nanPath = sprintf('%s/%s', drv, "P_dc_UNKNOWN");
    if getSimulinkBlockHandle(nanPath) == -1
        fprintf("  Skip: P_dc_UNKNOWN not found\n");
        return;
    end
    lh = get_param(nanPath, "LineHandles");
    if lh.Outport(1) ~= -1; delete_line(lh.Outport(1)); end
    delete_block(nanPath);

    pDcPath = sprintf('%s/%s', drv, "P_dc_calc");
    add_block("simulink/Math Operations/Product", pDcPath, "Position", [450, 195, 480, 225]);
    vFromPath = sprintf('%s/%s', drv, "V_pack_for_Pdc");
    add_block("simulink/Signal Routing/From", vFromPath, ...
        "GotoTag", "V_pack_meas", "Position", [400, 180, 460, 195]);
    iFromPath = sprintf('%s/%s', drv, "I_dc_for_Pdc");
    add_block("simulink/Signal Routing/From", iFromPath, ...
        "GotoTag", "I_dc_meas", "Position", [400, 220, 460, 235]);

    pDcPH    = get_param(pDcPath,    "PortHandles");
    vFromPH  = get_param(vFromPath,  "PortHandles");
    iFromPH  = get_param(iFromPath,  "PortHandles");
    muxPH    = get_param(sprintf('%s/%s', drv, "Mux_InverterDCFeedback"), "PortHandles");

    add_line(drv, vFromPH.Outport(1), pDcPH.Inport(1), "autorouting", "on");
    add_line(drv, iFromPH.Outport(1), pDcPH.Inport(2), "autorouting", "on");
    add_line(drv, pDcPH.Outport(1), muxPH.Inport(3), "autorouting", "on");
    fprintf("  Replaced P_dc_UNKNOWN with P_dc_calc (V_pack * I_dc)\n");
end

function replaceVdcInFeedback(drv)
%REPLACEVDCINFEEDBACK Update Feedbacks_sim[4] to use V_pack sensor.

    % Disconnect DCBus from Mux_Feedbacks_sim input 4
    dcBusLH = get_param(drv + "/DCBus", "LineHandles");
    if dcBusLH.Outport(1) ~= -1
        delete_line(dcBusLH.Outport(1));
    end
    vFromPath = drv + "/V_dc_for_feedbacks";
    if getSimulinkBlockHandle(vFromPath) == -1
        add_block("simulink/Signal Routing/From", vFromPath, ...
            "GotoTag", "V_pack_meas", "Position", [500, 110, 560, 125]);
    end
    vFromPH = get_param(vFromPath, "PortHandles");
    muxFbPH = get_param(drv + "/Mux_Feedbacks_sim", "PortHandles");
    add_line(drv, vFromPH.Outport(1), muxFbPH.Inport(4), "autorouting", "on");
    fprintf("  Updated Feedbacks_sim[4] to use V_pack sensor\n");

    % Terminate DCBus Inport since it's no longer used
    termPath = drv + "/Term_DCBus";
    if getSimulinkBlockHandle(termPath) == -1
        add_block("simulink/Sinks/Terminator", termPath, "Position", [350, 85, 370, 100]);
    end
    dcBusPH = get_param(drv + "/DCBus", "PortHandles");
    termPH = get_param(termPath, "PortHandles");
    add_line(drv, dcBusPH.Outport(1), termPH.Inport(1), "autorouting", "on");
    fprintf("  Terminated DCBus Inport\n");
end

function replaceVdcInInvDC(drv)
%REPLACEVDCINVDC Update InverterDCFeedback[1] to use V_pack sensor.

    % DCBus Outport may already be disconnected by replaceVdcInFeedback
    % Just add the From block and connect it
    vFromPath = drv + "/V_dc_for_invDC";
    if getSimulinkBlockHandle(vFromPath) == -1
        add_block("simulink/Signal Routing/From", vFromPath, ...
            "GotoTag", "V_pack_meas", "Position", [380, 100, 440, 115]);
        vFromPH = get_param(vFromPath, "PortHandles");
        muxInvPH = get_param(drv + "/Mux_InverterDCFeedback", "PortHandles");
        add_line(drv, vFromPH.Outport(1), muxInvPH.Inport(1), "autorouting", "on");
        fprintf("  Updated InverterDCFeedback[1] to use V_pack sensor\n");
    else
        fprintf("  Skip: V_dc_for_invDC already exists\n");
    end
end
