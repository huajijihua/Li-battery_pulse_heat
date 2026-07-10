function build_pulse_heating_dc_link_v04d3()
%BUILD_PULSE_HEATING_DC_LINK_V04D3 Signal-level DC-link closure with sensors.
%
% V4-D3 adds Voltage and Current sensors inside the drive boundary,
% replaces NaN placeholders with real measurements, and updates the
% battery boundary to use real I_dc as load current.
%
% Approach: signal-level coupling (not physical DC-link closure).
% - Battery_DC_Source stays in drive boundary (updated Vnom to ~52.8V)
% - Voltage Sensor added inside drive boundary, parallel to DC source
% - Current Sensor added inside drive boundary, in series with DC source
% - V_pack and I_dc signals replace NaN constants
% - BatteryLoad signal uses real I_dc (through NaN_to_Zero protection removed)
% - Battery pack V_pack feeds to DCBus signal
% - Battery_DC_Source Vnom updated from 48 to 52.8 to match battery pack

    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(fileparts(fileparts(mfilename("fullpath"))), ...
        "02_模型", modelName + ".slx");

    load_system(modelPath);
    fprintf("=== V4-D3: Signal-level DC-link with sensors ===\n");

    % Phase 1: Add sensors inside drive boundary
    addDcSensors(modelName);

    % Phase 2: Replace NaN placeholders with real sensor signals
    replaceNaNPlaceholders(modelName);

    % Phase 3: Update battery boundary for real I_dc load
    updateBatteryLoad(modelName);

    % Phase 4: Update Battery_DC_Source voltage to match battery pack
    updateDcSourceVoltage(modelName);

    % Phase 5: Update DCBus signal to use real V_pack
    updateDcBusSignal(modelName);

    save_system(modelName, modelPath, "OverwriteIfChangedOnDisk", true);
    fprintf("\nV4-D3 build complete. Model saved.\n");
end

function addDcSensors(modelName)
%ADDDCSENSORS Add Voltage and Current sensors inside drive boundary.

    drive = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    fprintf("\n--- Phase 1: Add DC sensors inside drive boundary ---\n");

    % Add Voltage Sensor (parallel to Battery_DC_Source)
    vSensorPath = drive + "/DC_Voltage_Sensor";
    if getSimulinkBlockHandle(vSensorPath) == -1
        add_block("fl_lib/Electrical/Electrical Sensors/Voltage Sensor", vSensorPath, ...
            "Position", [100, 250, 140, 300]);
        fprintf("  Added: DC_Voltage_Sensor\n");

        % Connect: V_sensor.p (+) to Battery_DC_Source.p
        % V_sensor.n (-) to Battery_DC_Source.n (which is Electrical Reference)
        batDcPath = drive + "/Battery_DC_Source";
        erPath = drive + "/Electrical Reference";

        batDcPH = get_param(batDcPath, "PortHandles");
        erPH = get_param(erPath, "PortHandles");
        vSensorPH = get_param(vSensorPath, "PortHandles");

        % Voltage sensor: LConn(1)=p, RConn(1)=n, RConn(2)=V(signal)
        % Connect p to Battery_DC_Source.p (same node as DC+)
        try
            add_line(drive, batDcPH.LConn(1), vSensorPH.LConn(1), "autorouting", "on");
            fprintf("  Connected: DC+ -> V_Sensor.p\n");
        catch
            fprintf("  Skip: DC+ -> V_Sensor.p (already connected)\n");
        end
        % Connect n to Battery_DC_Source.n (same node as DC-/ElecRef)
        try
            add_line(drive, erPH.LConn(1), vSensorPH.RConn(1), "autorouting", "on");
            fprintf("  Connected: DC- -> V_Sensor.n\n");
        catch
            fprintf("  Skip: DC- -> V_Sensor.n (already connected)\n");
        end
    else
        fprintf("  Skip: DC_Voltage_Sensor already exists\n");
    end

    % Add PS-Simulink Converter for V_pack
    vConvPath = drive + "/V_pack_meas";
    if getSimulinkBlockHandle(vConvPath) == -1
        add_block("nesl_utility/PS-Simulink Converter", vConvPath, ...
            "Position", [180, 255, 210, 275]);
        fprintf("  Added: V_pack_meas (PS-Simulink Converter)\n");

        vSensorPH = get_param(vSensorPath, "PortHandles");
        vConvPH = get_param(vConvPath, "PortHandles");
        try
            add_line(drive, vSensorPH.RConn(2), vConvPH.LConn(1), "autorouting", "on");
            fprintf("  Connected: V_Sensor.V -> V_pack_meas\n");
        catch e
            fprintf("  Failed: V_Sensor.V -> V_pack_meas: %s\n", e.message);
        end
    end

    % Add Current Sensor (in series between Battery_DC_Source.p and DC+)
    iSensorPath = drive + "/DC_Current_Sensor";
    if getSimulinkBlockHandle(iSensorPath) == -1
        add_block("fl_lib/Electrical/Electrical Sensors/Current Sensor", iSensorPath, ...
            "Position", [100, 150, 140, 200]);
        fprintf("  Added: DC_Current_Sensor\n");

        % Current sensor: LConn(1)=p, RConn(1)=n, RConn(2)=i(signal)
        % Need to insert in series: Battery_DC_Source.p -> Current_Sensor -> Inverter DC+
        % This requires disconnecting Battery_DC_Source.p from Solver Config/Inverter
        % and rerouting through the current sensor
        batDcPath = drive + "/Battery_DC_Source";
        scPath = drive + "/Solver Configuration";
        batDcPH = get_param(batDcPath, "PortHandles");
        scPH = get_param(scPath, "PortHandles");
        iSensorPH = get_param(iSensorPath, "PortHandles");

        % Delete existing connection from Battery_DC_Source.p
        batDcLH = get_param(batDcPath, "LineHandles");
        if batDcLH.LConn(1) ~= -1
            delete_line(batDcLH.LConn(1));
            fprintf("  Disconnected: Battery_DC_Source.p (old connection)\n");
        end

        % Connect: Battery_DC_Source.p -> Current_Sensor.p
        try
            add_line(drive, batDcPH.LConn(1), iSensorPH.LConn(1), "autorouting", "on");
            fprintf("  Connected: Battery_DC_Source.p -> I_Sensor.p\n");
        catch e
            fprintf("  Failed: DC_Source.p -> I_Sensor: %s\n", e.message);
        end

        % Connect: Current_Sensor.n -> Solver_Configuration (and Inverter DC+)
        try
            add_line(drive, iSensorPH.RConn(1), scPH.RConn(1), "autorouting", "on");
            fprintf("  Connected: I_Sensor.n -> Solver_Config\n");
        catch e
            fprintf("  Failed: I_Sensor.n -> Solver_Config: %s\n", e.message);
        end
    else
        fprintf("  Skip: DC_Current_Sensor already exists\n");
    end

    % Add PS-Simulink Converter for I_dc
    iConvPath = drive + "/I_dc_meas";
    if getSimulinkBlockHandle(iConvPath) == -1
        add_block("nesl_utility/PS-Simulink Converter", iConvPath, ...
            "Position", [180, 155, 210, 175]);
        fprintf("  Added: I_dc_meas (PS-Simulink Converter)\n");

        iSensorPH = get_param(iSensorPath, "PortHandles");
        iConvPH = get_param(iConvPath, "PortHandles");
        try
            add_line(drive, iSensorPH.RConn(2), iConvPH.LConn(1), "autorouting", "on");
            fprintf("  Connected: I_Sensor.i -> I_dc_meas\n");
        catch e
            fprintf("  Failed: I_Sensor.i -> I_dc_meas: %s\n", e.message);
        end
    end
end

function replaceNaNPlaceholders(modelName)
%REPLACENANPLACEHOLDERS Replace NaN constants with real sensor signals.

    drive = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    fprintf("\n--- Phase 2: Replace NaN placeholders ---\n");

    % Replace I_dc_NaN with I_dc_meas signal
    iDcNaNPath = drive + "/I_dc_NaN";
    iDcMeasPath = drive + "/I_dc_meas";
    if getSimulinkBlockHandle(iDcNaNPath) ~= -1
        % Get the mux input that I_dc_NaN feeds into
        muxPath = drive + "/Mux_InverterDCFeedback";
        muxPH = get_param(muxPath, "PortHandles");

        % Delete I_dc_NaN block and its connections
        lh = get_param(iDcNaNPath, "LineHandles");
        if lh.Outport(1) ~= -1
            delete_line(lh.Outport(1));
        end
        delete_block(iDcNaNPath);
        fprintf("  Deleted: I_dc_NaN\n");

        % Connect I_dc_meas output to Mux_InverterDCFeedback input 2
        iDcMeasPH = get_param(iDcMeasPath, "PortHandles");
        try
            add_line(drive, iDcMeasPH.Outport(1), muxPH.Inport(2), "autorouting", "on");
            fprintf("  Connected: I_dc_meas -> InverterDCFeedback[2]\n");
        catch e
            fprintf("  Failed: I_dc_meas -> Mux: %s\n", e.message);
        end
    end

    % Replace P_dc_NaN with V_pack * I_dc product
    pDcNaNPath = drive + "/P_dc_NaN";
    pDcPath = drive + "/P_dc_calc";
    if getSimulinkBlockHandle(pDcNaNPath) ~= -1
        muxPath = drive + "/Mux_InverterDCFeedback";
        muxPH = get_param(muxPath, "PortHandles");

        lh = get_param(pDcNaNPath, "LineHandles");
        if lh.Outport(1) ~= -1
            delete_line(lh.Outport(1));
        end
        delete_block(pDcNaNPath);
        fprintf("  Deleted: P_dc_NaN\n");

        % Add Product block for P_dc = V_pack * I_dc
        add_block("simulink/Math Operations/Product", pDcPath, ...
            "Position", [250, 200, 280, 230]);
        fprintf("  Added: P_dc_calc (Product)\n");

        % Connect V_pack_meas and I_dc_meas to Product block
        vPackMeasPH = get_param(drive + "/V_pack_meas", "PortHandles");
        iDcMeasPH = get_param(iDcMeasPath, "PortHandles");
        pDcPH = get_param(pDcPath, "PortHandles");

        try
            add_line(drive, vPackMeasPH.Outport(1), pDcPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: V_pack -> P_dc_calc.u1\n");
        catch e
            fprintf("  Failed: V_pack -> P_dc: %s\n", e.message);
        end
        try
            add_line(drive, iDcMeasPH.Outport(1), pDcPH.Inport(2), "autorouting", "on");
            fprintf("  Connected: I_dc -> P_dc_calc.u2\n");
        catch e
            fprintf("  Failed: I_dc -> P_dc: %s\n", e.message);
        end

        % Connect P_dc output to Mux_InverterDCFeedback input 3
        try
            add_line(drive, pDcPH.Outport(1), muxPH.Inport(3), "autorouting", "on");
            fprintf("  Connected: P_dc_calc -> InverterDCFeedback[3]\n");
        catch e
            fprintf("  Failed: P_dc -> Mux: %s\n", e.message);
        end
    end
end

function updateBatteryLoad(modelName)
%UPDATEBATTERYLOAD Update battery boundary to use real I_dc signal.

    bat = modelName + "/BatteryThermalManagement_BatteryPack";
    fprintf("\n--- Phase 3: Update battery load signal ---\n");

    % The BatteryLoad_NaN_to_Zero currently converts NaN to 0.
    % Replace with direct passthrough (I_dc is now real).
    nanToZeroPath = bat + "/BatteryLoad_NaN_to_Zero";
    if getSimulinkBlockHandle(nanToZeroPath) ~= -1
        % Delete the NaN_to_Zero block
        lh = get_param(nanToZeroPath, "LineHandles");
        fields = fieldnames(lh);
        for f = 1:numel(fields)
            handles = lh.(fields{f});
            if ~isempty(handles)
                validHandles = handles(handles ~= -1);
                for j = numel(validHandles):-1:1
                    try delete_line(validHandles(j)); catch; end
                end
            end
        end
        delete_block(nanToZeroPath);
        fprintf("  Deleted: BatteryLoad_NaN_to_Zero\n");

        % Connect BatteryLoad Inport directly to BatteryLoad_to_PS
        batLoadPH = get_param(bat + "/BatteryLoad", "PortHandles");
        batToPsPH = get_param(bat + "/BatteryLoad_to_PS", "PortHandles");
        try
            add_line(bat, batLoadPH.Outport(1), batToPsPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: BatteryLoad -> BatteryLoad_to_PS (direct)\n");
        catch e
            fprintf("  Failed: BatteryLoad -> to_PS: %s\n", e.message);
        end
    end

    % Replace V_pack_UNKNOWN with real V_pack from drive boundary
    vPackUnknownPath = bat + "/V_pack_UNKNOWN";
    if getSimulinkBlockHandle(vPackUnknownPath) ~= -1
        % Get the mux that V_pack_UNKNOWN feeds into
        muxDCPH = get_param(bat + "/Mux_BatteryDC", "PortHandles");

        lh = get_param(vPackUnknownPath, "LineHandles");
        if lh.Outport(1) ~= -1
            delete_line(lh.Outport(1));
        end
        delete_block(vPackUnknownPath);
        fprintf("  Deleted: V_pack_UNKNOWN\n");

        % Add a Goto block for V_pack, fed from drive boundary V_pack_meas
        % Actually, we need V_pack from the drive boundary to reach here
        % The signal path is: drive V_pack_meas -> root -> DC_Link -> BatteryDC[1]
        % But DC_Link currently selects BatteryDC[1] for DCBus output
        % We need to feed V_pack_meas into BatteryDC[1]
        % This is handled in Phase 5 (updateDcBusSignal)
        % For now, add a From block that reads V_pack
        add_block("simulink/Signal Routing/From", bat + "/V_pack_from_drive", ...
            "GotoTag", "V_pack_drive", "Position", [400, 30, 460, 45]);
        fprintf("  Added: V_pack_from_drive (From block)\n");

        fromPH = get_param(bat + "/V_pack_from_drive", "PortHandles");
        try
            add_line(bat, fromPH.Outport(1), muxDCPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: V_pack_from_drive -> BatteryDC[1]\n");
        catch e
            fprintf("  Failed: V_pack_from -> Mux: %s\n", e.message);
        end
    end

    % Replace I_pack_UNKNOWN with I_pack = I_dc (same current)
    iPackUnknownPath = bat + "/I_pack_UNKNOWN";
    if getSimulinkBlockHandle(iPackUnknownPath) ~= -1
        muxDCPH = get_param(bat + "/Mux_BatteryDC", "PortHandles");

        lh = get_param(iPackUnknownPath, "LineHandles");
        if lh.Outport(1) ~= -1
            delete_line(lh.Outport(1));
        end
        delete_block(iPackUnknownPath);
        fprintf("  Deleted: I_pack_UNKNOWN\n");

        % Add From block for I_dc
        add_block("simulink/Signal Routing/From", bat + "/I_pack_from_drive", ...
            "GotoTag", "I_dc_drive", "Position", [400, 70, 460, 85]);
        fprintf("  Added: I_pack_from_drive (From block)\n");

        fromPH = get_param(bat + "/I_pack_from_drive", "PortHandles");
        try
            add_line(bat, fromPH.Outport(1), muxDCPH.Inport(2), "autorouting", "on");
            fprintf("  Connected: I_pack_from_drive -> BatteryDC[2]\n");
        catch e
            fprintf("  Failed: I_pack_from -> Mux: %s\n", e.message);
        end
    end
end

function updateDcSourceVoltage(modelName)
%UPDATEDCSOURCEVOLTAGE Update Battery_DC_Source Vnom to match battery pack.

    drive = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    fprintf("\n--- Phase 4: Update DC source voltage ---\n");

    % Update Battery_DC_Source Vnom from 48 to 52.8 (16s * 3.3V)
    batDcPath = drive + "/Battery_DC_Source";
    try
        set_param(batDcPath, "Vnom", "52.8");
        set_param(batDcPath, "V1", "470");  % Keep original V1
        fprintf("  Updated Battery_DC_Source Vnom: 48 -> 52.8\n");
    catch e
        fprintf("  Failed to update Vnom: %s\n", e.message);
    end

    % Update inverter.V_dc in InitFcn
    currentInit = get_param(modelName, "InitFcn");
    newInit = strrep(currentInit, "inverter.V_dc = 48;", "inverter.V_dc = 52.8;");
    if newInit ~= currentInit
        set_param(modelName, "InitFcn", newInit);
        fprintf("  Updated InitFcn: inverter.V_dc = 52.8\n");
    else
        fprintf("  Skip: InitFcn already updated or not found\n");
    end
end

function updateDcBusSignal(modelName)
%UPDATEDCBUSSIGNAL Route V_pack and I_dc signals via Goto/From.

    drive = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    fprintf("\n--- Phase 5: Route V_pack and I_dc signals ---\n");

    % Add Goto blocks in drive boundary for V_pack and I_dc
    vGotoPath = drive + "/V_pack_goto";
    if getSimulinkBlockHandle(vGotoPath) == -1
        add_block("simulink/Signal Routing/Goto", vGotoPath, ...
            "GotoTag", "V_pack_drive", "Position", [250, 255, 310, 270]);
        fprintf("  Added: V_pack_goto\n");

        vMeasPH = get_param(drive + "/V_pack_meas", "PortHandles");
        vGotoPH = get_param(vGotoPath, "PortHandles");
        try
            add_line(drive, vMeasPH.Outport(1), vGotoPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: V_pack_meas -> V_pack_goto\n");
        catch e
            fprintf("  Failed: V_pack_meas -> Goto: %s\n", e.message);
        end
    end

    iGotoPath = drive + "/I_dc_goto";
    if getSimulinkBlockHandle(iGotoPath) == -1
        add_block("simulink/Signal Routing/Goto", iGotoPath, ...
            "GotoTag", "I_dc_drive", "Position", [250, 155, 310, 170]);
        fprintf("  Added: I_dc_goto\n");

        iMeasPH = get_param(drive + "/I_dc_meas", "PortHandles");
        iGotoPH = get_param(iGotoPath, "PortHandles");
        try
            add_line(drive, iMeasPH.Outport(1), iGotoPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: I_dc_meas -> I_dc_goto\n");
        catch e
            fprintf("  Failed: I_dc_meas -> Goto: %s\n", e.message);
        end
    end

    % Also feed V_pack into Feedbacks_sim (replace DCBus input)
    % Currently DCBus Inport feeds into Mux_Feedbacks_sim input 4
    % We want to use V_pack_meas instead of DCBus (which comes from BatteryDC[1]=NaN)
    % Add a From block in drive boundary for V_pack to replace DCBus inport
    vFromPath = drive + "/V_dc_from_sensor";
    if getSimulinkBlockHandle(vFromPath) == -1
        add_block("simulink/Signal Routing/From", vFromPath, ...
            "GotoTag", "V_pack_drive", "Position", [500, 110, 560, 125]);
        fprintf("  Added: V_dc_from_sensor (From block)\n");

        % Disconnect DCBus Inport from Mux_Feedbacks_sim input 4
        dcBusPH = get_param(drive + "/DCBus", "PortHandles");
        dcBusLH = get_param(drive + "/DCBus", "LineHandles");
        if dcBusLH.Outport(1) ~= -1
            delete_line(dcBusLH.Outport(1));
            fprintf("  Disconnected: DCBus Inport -> Mux_Feedbacks_sim\n");
        end

        % Connect V_dc_from_sensor to Mux_Feedbacks_sim input 4
        muxFbPH = get_param(drive + "/Mux_Feedbacks_sim", "PortHandles");
        vFromPH = get_param(vFromPath, "PortHandles");
        try
            add_line(drive, vFromPH.Outport(1), muxFbPH.Inport(4), "autorouting", "on");
            fprintf("  Connected: V_dc_from_sensor -> Feedbacks_sim[4]\n");
        catch e
            fprintf("  Failed: V_dc_from -> Mux: %s\n", e.message);
        end
    end

    % Update InverterDCFeedback[1] (V_dc) to use V_pack sensor instead of DCBus Inport
    muxInvDCPH = get_param(drive + "/Mux_InverterDCFeedback", "PortHandles");
    dcBusPH = get_param(drive + "/DCBus", "PortHandles");
    % Check if DCBus is still connected to Mux_InverterDCFeedback input 1
    dcBusLH = get_param(drive + "/DCBus", "LineHandles");
    if dcBusLH.Outport(1) ~= -1
        delete_line(dcBusLH.Outport(1));
        fprintf("  Disconnected: DCBus -> InverterDCFeedback[1]\n");
    end
    % Connect V_pack_goto to InverterDCFeedback[1] as well
    % But Goto can only feed one From... Let me use the V_pack_meas output directly
    % Actually, we already have V_pack_goto sending to From blocks.
    % Add another From for InverterDCFeedback
    vFromInvPath = drive + "/V_dc_for_invDC";
    if getSimulinkBlockHandle(vFromInvPath) == -1
        add_block("simulink/Signal Routing/From", vFromInvPath, ...
            "GotoTag", "V_pack_drive", "Position", [480, 195, 540, 210]);
        fprintf("  Added: V_dc_for_invDC (From block)\n");

        vFromInvPH = get_param(vFromInvPath, "PortHandles");
        try
            add_line(drive, vFromInvPH.Outport(1), muxInvDCPH.Inport(1), "autorouting", "on");
            fprintf("  Connected: V_dc_for_invDC -> InverterDCFeedback[1]\n");
        catch e
            fprintf("  Failed: V_dc_for_invDC -> Mux: %s\n", e.message);
        end
    end
end
