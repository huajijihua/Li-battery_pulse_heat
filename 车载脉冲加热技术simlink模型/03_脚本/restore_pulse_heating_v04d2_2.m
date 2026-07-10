function restore_pulse_heating_v04d2_2(overwrite)
%RESTORE_PULSE_HEATING_V04D2_2 Restore the V4-D2.2 active model state.
%
% This script rebuilds the committed V4-B3 spine, then reapplies the
% documented V4-B4..V4-D2.2 thin adaptation layers. It intentionally stops
% before the unverified V4-D3 DC sensor work.

    if nargin < 1
        overwrite = true;
    end

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    modelName = "pulse_heating_official_spine_v04";
    modelPath = fullfile(modelDir, modelName + ".slx");

    oldDir = string(pwd);
    cleanupDir = onCleanup(@() cd(oldDir));
    cd(scriptDir);
    addpath(scriptDir);

    fprintf("=== Restore V4-D2.2 from reusable scripts and documented layers ===\n");
    build_pulse_heating_official_spine_v04b3(overwrite);
    open_system(modelPath);

    configureCallbacksAndWorkspace(modelName);
    restoreBatteryBoundary(modelName);
    restoreDcLinkBoundary(modelName);
    restorePulseCommandBoundary(modelName);
    restoreLimitAndKpiBoundary(modelName);
    restoreDriveCurrentKpi(modelName);
    restoreControlDutyKpiAndPwm(modelName);
    restoreTopLevelTerminators(modelName);

    set_param(modelName, "StopTime", "1");
    save_system(modelName, modelPath, "OverwriteIfChangedOnDisk", true);
    fprintf("Restored V4-D2.2 model: %s\n", modelPath);
end

function configureCallbacksAndWorkspace(modelName)
    batteryDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\BatteryThermalManagementExample";
    controllerDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\mcb\SIUnitsExample";
    driveDir = "C:\Users\ADMIN\Documents\MATLAB\Examples\R2025b\simscapeelectrical\PMSMDriveThermalExample";

    addpath(batteryDir);
    addpath(controllerDir);
    addpath(driveDir);
    load_system("BatteryThermalManagementModel");
    load_system("PMSMDriveThermal");
    load_system("mcb_pmsm_foc_qep_f28379d_SIUnit");

    preloadLines = [ ...
        "addpath('" + batteryDir + "');", ...
        "addpath('" + controllerDir + "');", ...
        "addpath('" + driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "set_param('PMSMDriveThermal','SimscapeLogType','none','SimscapeLogSimulationStatistics','off');", ...
        "set_param('PMSMDriveThermal','Dirty','off');" ...
    ];
    set_param(modelName, "PreLoadFcn", strjoin(preloadLines, newline));

    initLines = [ ...
        "addpath('" + batteryDir + "');", ...
        "addpath('" + controllerDir + "');", ...
        "addpath('" + driveDir + "');", ...
        "load_system('PMSMDriveThermal');", ...
        "PMSMDriveThermalData;", ...
        "mcb_pmsm_foc_qep_f28379d_SIUnit_data;", ...
        "bw_i = (PI_params.Kp_i + pmsm.Rs) / pmsm.Ld;", ...
        "pmsm.Rs = Rs; pmsm.Ld = Ld; pmsm.Lq = Lq; pmsm.p = N; pmsm.FluxPM = PM;", ...
        "pmsm.J = J; pmsm.Ke = PM*N; pmsm.Kt = 1.5*N*PM;", ...
        "PI_params.Kp_i = bw_i * Ld - Rs; PI_params.Ki_i = bw_i * Rs; PI_params.Ti_i = 1/bw_i;", ...
        "PI_params.Kp_id = PI_params.Kp_i; PI_params.Ki_id = PI_params.Ki_i; PI_params.Ti_id = PI_params.Ti_i;", ...
        "inverter.V_dc = 48; dataType = 'double';", ...
        "BatteryThermalManagementInitialization;" ...
    ];
    set_param(modelName, "InitFcn", strjoin(initLines, newline));

    mw = get_param(modelName, "ModelWorkspace");
    assignVars(mw, struct( ...
        "pulse_id_amplitude_A", 1, ...
        "pulse_iq_amplitude_A", 0, ...
        "diagnostic_frequency_Hz", 1250, ...
        "pulse_duty_percent", 50, ...
        "pulse_phase_delay_s", 0, ...
        "pulse_mode_code", 4, ...
        "pulse_command_status_code", 6, ...
        "limit_margin_unknown_value", NaN, ...
        "limit_factor_unknown_code", 99, ...
        "limit_status_v4c_code", 5, ...
        "kpi_value_unknown", NaN, ...
        "kpi_status_v4d2_partial_numeric_code", 6, ...
        "drive_status_v4d2_partial_current_code", 6, ...
        "control_status_v4d2_partial_duty_code", 6));
end

function assignVars(modelWorkspace, vars)
    names = fieldnames(vars);
    for k = 1:numel(names)
        modelWorkspace.assignin(names{k}, vars.(names{k}));
    end
end

function restoreBatteryBoundary(modelName)
    bat = modelName + "/BatteryThermalManagement_BatteryPack";
    clearSubsystemContents(bat, true);

    add_block("BatteryThermalManagementModel/Battery pack", bat + "/Battery_pack");
    add_block("BatteryThermalManagementModel/Coolant control", bat + "/Coolant_control");
    add_block(findRootBlock("BatteryThermalManagementModel", "Controlled Current Source"), bat + "/Controlled_Current_Source");
    add_block(findRootBlock("BatteryThermalManagementModel", "Solver Configuration"), bat + "/Solver_Configuration");
    add_block(findRootBlock("BatteryThermalManagementModel", "Electrical Reference"), bat + "/Electrical_Reference");

    addMatlabFunction(bat + "/BatteryLoad_NaN_to_Zero", [ ...
        "function y = f(u)", newline, ...
        "if isnan(u)", newline, ...
        "    y = 0;", newline, ...
        "else", newline, ...
        "    y = u;", newline, ...
        "end", newline, ...
        "end"]);
    add_block("nesl_utility/Simulink-PS Converter", bat + "/BatteryLoad_to_PS");
    add_block("simulink/Sources/Constant", bat + "/Ambient_Temp", "Value", "ambient");
    add_block("simulink/Sources/Constant", bat + "/Coolant_Temp", "Value", "coolantTemp");
    add_block("simulink/Sources/Constant", bat + "/Flowrate_vec", "Value", "Flowrate_vec");
    add_block("simulink/Sources/Constant", bat + "/V_pack_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/I_pack_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/T_min_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/SOC_limit_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/Charge_limit_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/Discharge_limit_UNKNOWN", "Value", "NaN");
    add_block("simulink/Sources/Constant", bat + "/Battery_status_code", "Value", "4");
    add_block("simulink/Signal Routing/Selector", bat + "/Sel_SOC_1", ...
        "InputPortWidth", "42", "Indices", "1");
    add_block("simulink/Signal Routing/Selector", bat + "/Sel_T_1", ...
        "InputPortWidth", "42", "Indices", "1");
    add_block("simulink/Signal Routing/Mux", bat + "/Mux_BatteryDC", "Inputs", "4");
    add_block("simulink/Signal Routing/Mux", bat + "/Mux_BatteryStatus", "Inputs", "8");
    add_block("simulink/Sinks/Terminator", bat + "/Term_Coolant_Temp");
    add_block("simulink/Sinks/Terminator", bat + "/Term_Coolant_SOC");

    connectBatteryBoundary(bat);
end

function connectBatteryBoundary(bat)
    inPH = get_param(bat + "/BatteryLoad", "PortHandles");
    guardPH = get_param(bat + "/BatteryLoad_NaN_to_Zero", "PortHandles");
    psPH = get_param(bat + "/BatteryLoad_to_PS", "PortHandles");
    ccsPH = get_param(bat + "/Controlled_Current_Source", "PortHandles");
    packPH = get_param(bat + "/Battery_pack", "PortHandles");
    coolPH = get_param(bat + "/Coolant_control", "PortHandles");
    solverPH = get_param(bat + "/Solver_Configuration", "PortHandles");
    erefPH = get_param(bat + "/Electrical_Reference", "PortHandles");

    add_line(bat, inPH.Outport(1), guardPH.Inport(1));
    add_line(bat, guardPH.Outport(1), psPH.Inport(1));
    add_line(bat, psPH.RConn(1), ccsPH.RConn(1));

    add_line(bat, ccsPH.LConn(1), packPH.LConn(1));
    add_line(bat, ccsPH.RConn(2), packPH.RConn(1));
    add_line(bat, ccsPH.RConn(2), erefPH.LConn(1));
    add_line(bat, solverPH.RConn(1), ccsPH.LConn(1));

    add_line(bat, getOut(bat, "Ambient_Temp"), coolPH.Inport(1));
    add_line(bat, getOut(bat, "Coolant_Temp"), coolPH.Inport(2));
    add_line(bat, getOut(bat, "Flowrate_vec"), coolPH.Inport(3));
    add_line(bat, packPH.Outport(2), coolPH.Inport(4));
    add_line(bat, packPH.Outport(1), coolPH.Inport(5));
    add_line(bat, coolPH.Outport(5), packPH.Inport(1));
    add_line(bat, coolPH.Outport(4), packPH.Inport(2));
    add_line(bat, coolPH.Outport(1), get_param(bat + "/Term_Coolant_Temp", "PortHandles").Inport(1));
    add_line(bat, coolPH.Outport(3), get_param(bat + "/Term_Coolant_SOC", "PortHandles").Inport(1));

    selSocPH = get_param(bat + "/Sel_SOC_1", "PortHandles");
    selTPH = get_param(bat + "/Sel_T_1", "PortHandles");
    add_line(bat, packPH.Outport(1), selSocPH.Inport(1));
    add_line(bat, packPH.Outport(2), selTPH.Inport(1));

    dcMuxPH = get_param(bat + "/Mux_BatteryDC", "PortHandles");
    add_line(bat, getOut(bat, "V_pack_UNKNOWN"), dcMuxPH.Inport(1));
    add_line(bat, getOut(bat, "I_pack_UNKNOWN"), dcMuxPH.Inport(2));
    add_line(bat, selSocPH.Outport(1), dcMuxPH.Inport(3));
    add_line(bat, selTPH.Outport(1), dcMuxPH.Inport(4));
    add_line(bat, dcMuxPH.Outport(1), get_param(bat + "/BatteryDC", "PortHandles").Inport(1));

    statusMuxPH = get_param(bat + "/Mux_BatteryStatus", "PortHandles");
    add_line(bat, selTPH.Outport(1), statusMuxPH.Inport(1));
    add_line(bat, getOut(bat, "T_min_UNKNOWN"), statusMuxPH.Inport(2));
    add_line(bat, getOut(bat, "SOC_limit_UNKNOWN"), statusMuxPH.Inport(3));
    add_line(bat, selSocPH.Outport(1), statusMuxPH.Inport(4));
    add_line(bat, coolPH.Outport(2), statusMuxPH.Inport(5));
    add_line(bat, getOut(bat, "Charge_limit_UNKNOWN"), statusMuxPH.Inport(6));
    add_line(bat, getOut(bat, "Discharge_limit_UNKNOWN"), statusMuxPH.Inport(7));
    add_line(bat, getOut(bat, "Battery_status_code"), statusMuxPH.Inport(8));
    add_line(bat, statusMuxPH.Outport(1), get_param(bat + "/BatteryStatus", "PortHandles").Inport(1));
end

function restoreDcLinkBoundary(modelName)
    dc = modelName + "/DC_Link_And_Inverter_Interface";
    clearSubsystemContents(dc, true);
    add_block("simulink/Signal Routing/Selector", dc + "/Sel_Battery_V_pack", ...
        "InputPortWidth", "4", "Indices", "1");
    add_block("simulink/Signal Routing/Selector", dc + "/Sel_Inverter_I_dc", ...
        "InputPortWidth", "4", "Indices", "2");

    batPH = get_param(dc + "/BatteryDC", "PortHandles");
    invPH = get_param(dc + "/InverterDCFeedback", "PortHandles");
    selVPH = get_param(dc + "/Sel_Battery_V_pack", "PortHandles");
    selIPH = get_param(dc + "/Sel_Inverter_I_dc", "PortHandles");
    add_line(dc, batPH.Outport(1), selVPH.Inport(1));
    add_line(dc, selVPH.Outport(1), get_param(dc + "/DCBus", "PortHandles").Inport(1));
    add_line(dc, invPH.Outport(1), selIPH.Inport(1));
    add_line(dc, selIPH.Outport(1), get_param(dc + "/BatteryLoad", "PortHandles").Inport(1));
end

function restorePulseCommandBoundary(modelName)
    cmd = modelName + "/PulseHeating_Command_And_Limits";
    clearSubsystemContents(cmd, true);
    add_block("simulink/Sources/Pulse Generator", cmd + "/Id_Pulse_Stall", ...
        "Amplitude", "1", "Period", "1/diagnostic_frequency_Hz", ...
        "PulseWidth", "pulse_duty_percent", "PhaseDelay", "pulse_phase_delay_s");
    add_block("simulink/Math Operations/Gain", cmd + "/Scale_To_Bipolar_A", "Gain", "2*pulse_id_amplitude_A");
    add_block("simulink/Math Operations/Bias", cmd + "/Offset_To_Negative_A", "Bias", "-pulse_id_amplitude_A");
    add_block("simulink/Sources/Constant", cmd + "/Iq_ref_zero_A", "Value", "pulse_iq_amplitude_A");
    add_block("simulink/Signal Routing/Mux", cmd + "/Mux_Idq_ref", "Inputs", "2");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Id_A", "Value", "pulse_id_amplitude_A");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Frequency_Hz", "Value", "diagnostic_frequency_Hz");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Duty_Percent", "Value", "pulse_duty_percent");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Phase_Delay_s", "Value", "pulse_phase_delay_s");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Mode_Code", "Value", "pulse_mode_code");
    add_block("simulink/Sources/Constant", cmd + "/Limit_Status_Code", "Value", "pulse_command_status_code");
    add_block("simulink/Signal Routing/Mux", cmd + "/Mux_LimitConfig", "Inputs", "6");

    add_line(cmd, getOut(cmd, "Id_Pulse_Stall"), get_param(cmd + "/Scale_To_Bipolar_A", "PortHandles").Inport(1));
    add_line(cmd, getOut(cmd, "Scale_To_Bipolar_A"), get_param(cmd + "/Offset_To_Negative_A", "PortHandles").Inport(1));
    idqMuxPH = get_param(cmd + "/Mux_Idq_ref", "PortHandles");
    add_line(cmd, getOut(cmd, "Offset_To_Negative_A"), idqMuxPH.Inport(1));
    add_line(cmd, getOut(cmd, "Iq_ref_zero_A"), idqMuxPH.Inport(2));
    add_line(cmd, idqMuxPH.Outport(1), get_param(cmd + "/Idq_ref", "PortHandles").Inport(1));

    limitMuxPH = get_param(cmd + "/Mux_LimitConfig", "PortHandles");
    names = ["Limit_Id_A", "Limit_Frequency_Hz", "Limit_Duty_Percent", ...
        "Limit_Phase_Delay_s", "Limit_Mode_Code", "Limit_Status_Code"];
    for k = 1:numel(names)
        add_line(cmd, getOut(cmd, names(k)), limitMuxPH.Inport(k));
    end
    add_line(cmd, limitMuxPH.Outport(1), get_param(cmd + "/LimitConfig", "PortHandles").Inport(1));
end

function restoreLimitAndKpiBoundary(modelName)
    kpi = modelName + "/KPI_And_Logging";
    clearSubsystemContents(kpi, true);
    ensureOutport(kpi, "LimitStatus", 1);
    ensureOutport(kpi, "SystemKPI", 2);
    add_block("simulink/Sinks/Terminator", kpi + "/Term_LimitConfig");

    addSelector(kpi, "Sel_Control_tracking", "1", "5");
    addSelector(kpi, "Sel_Control_mod", "2", "5");
    addSelector(kpi, "Sel_Control_sat", "3", "5");
    addSelector(kpi, "Sel_Control_enable", "4", "5");
    addSelector(kpi, "Sel_Drive_I_rms", "1", "8");
    addSelector(kpi, "Sel_Drive_I_peak", "2", "8");
    addSelector(kpi, "Sel_Drive_P_cu", "3", "8");
    addSelector(kpi, "Sel_Drive_P_iron", "4", "8");
    addSelector(kpi, "Sel_Drive_P_inv", "5", "8");
    addSelector(kpi, "Sel_Drive_T_stator", "6", "8");
    addSelector(kpi, "Sel_Drive_T_rotor", "7", "8");
    addSelector(kpi, "Sel_Battery_T", "1", "8");
    addSelector(kpi, "Sel_Battery_charge_limit", "6", "8");

    addConst(kpi, "Limit_voltage_UNKNOWN", "limit_margin_unknown_value");
    addConst(kpi, "Limit_battery_temperature_UNKNOWN", "limit_margin_unknown_value");
    addConst(kpi, "Limit_coolant_flow_UNKNOWN", "limit_margin_unknown_value");
    addConst(kpi, "Limit_unknown_safety_UNKNOWN", "limit_margin_unknown_value");
    addConst(kpi, "Limit_factor_UNKNOWN", "limit_factor_unknown_code");
    addConst(kpi, "Limit_status_V4C", "limit_status_v4c_code");
    addConst(kpi, "KPI_I_batt_rms_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_I_dc_rms_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_I_heat_equiv_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_V_batt_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_P_batt_heat_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_current_limit_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_thermal_margin_UNKNOWN", "kpi_value_unknown");
    addConst(kpi, "KPI_status_V4D", "kpi_status_v4d2_partial_numeric_code");
    add_block("simulink/Signal Routing/Mux", kpi + "/Mux_LimitStatus", "Inputs", "10");
    add_block("simulink/Signal Routing/Mux", kpi + "/Mux_SystemKPI", "Inputs", "24");

    connectKpiSelectors(kpi);
    add_line(kpi, get_param(kpi + "/LimitConfig", "PortHandles").Outport(1), ...
        get_param(kpi + "/Term_LimitConfig", "PortHandles").Inport(1), "autorouting", "on");
    connectLimitStatus(kpi);
    connectSystemKpi(kpi);
end

function connectKpiSelectors(kpi)
    connectInputToSelectors(kpi, "ControlKPI", ["Sel_Control_tracking", "Sel_Control_mod", "Sel_Control_sat", "Sel_Control_enable"]);
    connectInputToSelectors(kpi, "DriveKPI", ["Sel_Drive_I_rms", "Sel_Drive_I_peak", "Sel_Drive_P_cu", "Sel_Drive_P_iron", "Sel_Drive_P_inv", "Sel_Drive_T_stator", "Sel_Drive_T_rotor"]);
    connectInputToSelectors(kpi, "BatteryStatus", ["Sel_Battery_T", "Sel_Battery_charge_limit"]);
end

function connectInputToSelectors(parent, inputName, selectors)
    src = get_param(parent + "/" + inputName, "PortHandles");
    for k = 1:numel(selectors)
        dst = get_param(parent + "/" + selectors(k), "PortHandles");
        add_line(parent, src.Outport(1), dst.Inport(1), "autorouting", "on");
    end
end

function connectLimitStatus(kpi)
    muxPH = get_param(kpi + "/Mux_LimitStatus", "PortHandles");
    sources = [ ...
        "Limit_voltage_UNKNOWN", "Sel_Control_mod", "Sel_Drive_I_peak", "Sel_Drive_I_rms", ...
        "Sel_Battery_charge_limit", "Limit_battery_temperature_UNKNOWN", ...
        "Limit_coolant_flow_UNKNOWN", "Limit_unknown_safety_UNKNOWN", ...
        "Limit_factor_UNKNOWN", "Limit_status_V4C"];
    for k = 1:numel(sources)
        add_line(kpi, getOut(kpi, sources(k)), muxPH.Inport(k), "autorouting", "on");
    end
    add_line(kpi, muxPH.Outport(1), get_param(kpi + "/LimitStatus", "PortHandles").Inport(1));
end

function connectSystemKpi(kpi)
    muxPH = get_param(kpi + "/Mux_SystemKPI", "PortHandles");
    sources = [ ...
        "KPI_I_batt_rms_UNKNOWN", "KPI_I_dc_rms_UNKNOWN", "Sel_Drive_I_rms", ...
        "KPI_I_heat_equiv_UNKNOWN", "KPI_V_batt_UNKNOWN", "DCBus", ...
        "Sel_Control_mod", "Limit_voltage_UNKNOWN", "KPI_P_batt_heat_UNKNOWN", ...
        "Sel_Drive_P_cu", "Sel_Drive_P_iron", "Sel_Drive_P_inv", ...
        "Sel_Battery_T", "Sel_Drive_T_stator", "Sel_Drive_T_rotor", ...
        "Sel_Control_tracking", "Sel_Control_sat", "Sel_Control_enable", ...
        "KPI_current_limit_UNKNOWN", "KPI_thermal_margin_UNKNOWN", ...
        "Sel_Battery_charge_limit", "Limit_unknown_safety_UNKNOWN", ...
        "Limit_factor_UNKNOWN", "KPI_status_V4D"];
    for k = 1:numel(sources)
        add_line(kpi, getOut(kpi, sources(k)), muxPH.Inport(k), "autorouting", "on");
    end
    add_line(kpi, muxPH.Outport(1), get_param(kpi + "/SystemKPI", "PortHandles").Inport(1));
end

function restoreDriveCurrentKpi(modelName)
    drive = modelName + "/PMSMDriveThermal_Inverter_And_Motor";
    deleteIfExists(drive + "/I_rms_UNKNOWN");
    deleteIfExists(drive + "/I_peak_UNKNOWN");
    addMatlabFunction(drive + "/Compute_Current_KPI_V4D2", [ ...
        "function [i_rms, i_peak] = f(i_abc)", newline, ...
        "i = i_abc(:);", newline, ...
        "i_rms = sqrt(sum(i.^2)/numel(i));", newline, ...
        "i_peak = max(abs(i));", newline, ...
        "end"]);

    fromPH = get_param(drive + "/From_i_abc", "PortHandles");
    funPH = get_param(drive + "/Compute_Current_KPI_V4D2", "PortHandles");
    muxPH = get_param(drive + "/Mux_DriveKPI", "PortHandles");
    disconnectInport(muxPH.Inport(1));
    disconnectInport(muxPH.Inport(2));
    add_line(drive, fromPH.Outport(1), funPH.Inport(1), "autorouting", "on");
    add_line(drive, funPH.Outport(1), muxPH.Inport(1), "autorouting", "on");
    add_line(drive, funPH.Outport(2), muxPH.Inport(2), "autorouting", "on");
    set_param(drive + "/DriveKPI_status", "Value", "drive_status_v4d2_partial_current_code");
end

function restoreControlDutyKpiAndPwm(modelName)
    ctrl = modelName + "/MCB_SIUnits_FOC_Controller";
    restorePwmCarrier(ctrl);
    deleteIfExists(ctrl + "/KPI_modindex_NaN");
    deleteIfExists(ctrl + "/KPI_sat_NaN");
    addMatlabFunction(ctrl + "/Compute_Duty_KPI_V4D2", [ ...
        "function [mod_index, sat_flag] = f(duty_abc)", newline, ...
        "d = duty_abc(:);", newline, ...
        "mod_index = max(abs(2*d - 1));", newline, ...
        "sat_flag = double(any(d <= 0 | d >= 1));", newline, ...
        "end"]);

    csPH = get_param(ctrl + "/Control_System", "PortHandles");
    funPH = get_param(ctrl + "/Compute_Duty_KPI_V4D2", "PortHandles");
    muxPH = get_param(ctrl + "/KPI_Mux", "PortHandles");
    disconnectInport(muxPH.Inport(2));
    disconnectInport(muxPH.Inport(3));
    add_line(ctrl, csPH.Outport(1), funPH.Inport(1), "autorouting", "on");
    add_line(ctrl, funPH.Outport(1), muxPH.Inport(2), "autorouting", "on");
    add_line(ctrl, funPH.Outport(2), muxPH.Inport(3), "autorouting", "on");
    set_param(ctrl + "/KPI_status", "Value", "control_status_v4d2_partial_duty_code");
end

function restorePwmCarrier(ctrl)
    for k = 1:3
        deleteIfExists(ctrl + "/Half_Const_" + k);
    end
    deleteIfExists(ctrl + "/PWM_Carrier");
    add_block("simulink/Sources/Repeating Sequence", ctrl + "/PWM_Carrier", ...
        "rep_seq_t", "[0 1/fsw]", "rep_seq_y", "[0 1]");
    carrierPH = get_param(ctrl + "/PWM_Carrier", "PortHandles");
    for name = ["G1_A_H", "G3_B_H", "G5_C_H"]
        ghPH = get_param(ctrl + "/" + name, "PortHandles");
        disconnectInport(ghPH.Inport(2));
        add_line(ctrl, carrierPH.Outport(1), ghPH.Inport(2), "autorouting", "on");
    end
end

function restoreTopLevelTerminators(modelName)
    deleteIfExists(modelName + "/Terminate_LimitStatus");
    deleteIfExists(modelName + "/Terminate_SystemKPI");
    add_block("simulink/Sinks/Terminator", modelName + "/Terminate_LimitStatus");
    add_block("simulink/Sinks/Terminator", modelName + "/Terminate_SystemKPI");
    add_line(modelName, "KPI_And_Logging/1", "Terminate_LimitStatus/1", "autorouting", "on");
    add_line(modelName, "KPI_And_Logging/2", "Terminate_SystemKPI/1", "autorouting", "on");
end

function clearSubsystemContents(subsystemPath, keepPorts)
    lines = find_system(subsystemPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
    for k = numel(lines):-1:1
        try
            delete_line(lines(k));
        catch
        end
    end
    blocks = find_system(subsystemPath, "SearchDepth", 1, "Type", "Block");
    for k = numel(blocks):-1:1
        blockPath = string(blocks{k});
        if blockPath == subsystemPath
            continue;
        end
        blockType = string(get_param(blockPath, "BlockType"));
        if keepPorts && (blockType == "Inport" || blockType == "Outport")
            continue;
        end
        delete_block(blockPath);
    end
end

function blockPath = findRootBlock(modelName, blockKind)
    blocks = find_system(modelName, "SearchDepth", 1, "Type", "Block");
    wanted = normalizeWhitespace(blockKind);
    for k = 1:numel(blocks)
        name = normalizeWhitespace(get_param(blocks{k}, "Name"));
        ref = "";
        try
            ref = normalizeWhitespace(get_param(blocks{k}, "ReferenceBlock"));
        catch
        end
        if contains(name, wanted) || contains(ref, wanted)
            blockPath = string(blocks{k});
            return;
        end
    end
    error("V4Restore:MissingOfficialBlock", "Could not find %s in %s.", blockKind, modelName);
end

function text = normalizeWhitespace(text)
    text = regexprep(string(text), "\s+", " ");
end

function ensureOutport(parent, name, portNumber)
    deleteIfExists(parent + "/" + name);
    add_block("simulink/Sinks/Out1", parent + "/" + name, "Port", string(portNumber));
end

function addSelector(parent, name, index, inputWidth)
    add_block("simulink/Signal Routing/Selector", parent + "/" + name, ...
        "InputPortWidth", inputWidth, "Indices", index);
end

function addConst(parent, name, value)
    add_block("simulink/Sources/Constant", parent + "/" + name, "Value", value);
end

function out = getOut(parent, blockName)
    ph = get_param(parent + "/" + blockName, "PortHandles");
    out = ph.Outport(1);
end

function disconnectInport(portHandle)
    lineHandle = get_param(portHandle, "Line");
    if lineHandle ~= -1
        delete_line(lineHandle);
    end
end

function deleteIfExists(blockPath)
    blockPath = char(blockPath);
    if getSimulinkBlockHandle(blockPath) == -1
        return;
    end
    lines = get_param(blockPath, "LineHandles");
    fields = fieldnames(lines);
    for f = 1:numel(fields)
        handles = lines.(fields{f});
        for k = numel(handles):-1:1
            if handles(k) ~= -1
                try
                    delete_line(handles(k));
                catch
                end
            end
        end
    end
    delete_block(blockPath);
end

function addMatlabFunction(blockPath, scriptText)
    deleteIfExists(blockPath);
    add_block("simulink/User-Defined Functions/MATLAB Function", blockPath);
    root = sfroot;
    chart = root.find("-isa", "Stateflow.EMChart", "Path", char(blockPath));
    chart.Script = char(scriptText);
end
