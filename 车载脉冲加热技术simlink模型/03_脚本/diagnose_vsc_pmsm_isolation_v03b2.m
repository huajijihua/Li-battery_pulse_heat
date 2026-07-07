function diagnose_vsc_pmsm_isolation_v03b2()
%DIAGNOSE_VSC_PMSM_ISOLATION_V03B2 Test VSC+PMSM without Battery_Pack.

    oldDir = string(pwd);
    cleanupObj = onCleanup(@() cd(oldDir));
    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    cd(fullfile(projectDir, "02_模型"));

    modelName = "tmp_vsc_pmsm_isolation";
    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    if isfile(modelName + ".slx")
        delete(modelName + ".slx");
    end

    new_system(modelName);
    open_system(modelName);
    set_param(modelName, "Solver", "ode23t", "StopTime", "0.01", "MaxStep", "1e-5");

    add_block("ee_lib/Sources/Voltage Source", modelName + "/DC_Source", "Position", [80 130 150 200]);
    set_param(modelName + "/DC_Source", "dc_voltage", "800");
    add_block("ee_lib/Passive/Capacitor", modelName + "/DC_Cap", "Position", [210 130 270 200]);
    add_block("fl_lib/Electrical/Electrical Elements/Electrical Reference", modelName + "/Elec_Ref", "Position", [210 250 260 300]);
    add_block("nesl_utility/Solver Configuration", modelName + "/Solver", "Position", [210 330 280 390]);
    add_block("ee_lib/Semiconductors & Converters/Converters/Average-Value Voltage Source Converter (Three-Phase)", modelName + "/VSC", "Position", [360 130 480 230]);
    set_param(modelName + "/VSC", "input_option", "Modulation waveforms");
    add_block("ee_lib/Sensors & Transducers/Current Sensor (Three-Phase)", modelName + "/Iabc_Sensor", "Position", [550 140 640 220]);
    add_block("ee_lib/Electromechanical/Permanent Magnet/PMSM", modelName + "/PMSM", "Position", [720 120 850 250]);
    add_block("fl_lib/Mechanical/Rotational Elements/Mechanical Rotational Reference", modelName + "/Mech_Ref", "Position", [920 240 980 290]);
    add_block("simulink/Sources/Sine Wave", modelName + "/ma", "Position", [80 450 130 480], "Amplitude", "0.8", "Frequency", "2*pi*1250", "Phase", "0");
    add_block("simulink/Sources/Sine Wave", modelName + "/mb", "Position", [80 500 130 530], "Amplitude", "0.8", "Frequency", "2*pi*1250", "Phase", "-2*pi/3");
    add_block("simulink/Sources/Sine Wave", modelName + "/mc", "Position", [80 550 130 580], "Amplitude", "0.8", "Frequency", "2*pi*1250", "Phase", "2*pi/3");
    add_block("simulink/Signal Routing/Mux", modelName + "/mux", "Position", [180 465 210 565], "Inputs", "3");
    add_block("nesl_utility/Simulink-PS Converter", modelName + "/SPS_Mod", "Position", [270 500 340 540]);
    add_block("nesl_utility/PS-Simulink Converter", modelName + "/PSS_Iabc", "Position", [670 430 740 460]);
    add_block("simulink/Sinks/To Workspace", modelName + "/Iabc_log", "Position", [790 430 900 460], "VariableName", "Iabc_log", "SaveFormat", "Timeseries");

    connectPhysical(modelName, "DC_Source", "LConn", 1, "DC_Cap", "LConn", 1);
    connectPhysical(modelName, "DC_Cap", "LConn", 1, "VSC", "RConn", 1);
    connectPhysical(modelName, "DC_Source", "RConn", 1, "DC_Cap", "RConn", 1);
    connectPhysical(modelName, "DC_Cap", "RConn", 1, "VSC", "RConn", 2);
    connectPhysical(modelName, "DC_Cap", "RConn", 1, "Elec_Ref", "LConn", 1);
    connectPhysical(modelName, "DC_Cap", "RConn", 1, "Solver", "RConn", 1);
    connectPhysical(modelName, "VSC", "LConn", 2, "Iabc_Sensor", "LConn", 1);
    connectPhysical(modelName, "Iabc_Sensor", "RConn", 2, "PMSM", "LConn", 1);
    connectPhysical(modelName, "PMSM", "LConn", 2, "DC_Cap", "RConn", 1);
    connectPhysical(modelName, "PMSM", "RConn", 1, "Mech_Ref", "LConn", 1);
    connectPhysical(modelName, "PMSM", "RConn", 2, "Mech_Ref", "LConn", 1);
    connectPhysical(modelName, "SPS_Mod", "RConn", 1, "VSC", "LConn", 1);
    connectPhysical(modelName, "Iabc_Sensor", "RConn", 1, "PSS_Iabc", "LConn", 1);

    add_line(modelName, "ma/1", "mux/1");
    add_line(modelName, "mb/1", "mux/2");
    add_line(modelName, "mc/1", "mux/3");
    add_line(modelName, "mux/1", "SPS_Mod/1");
    add_line(modelName, "PSS_Iabc/1", "Iabc_log/1");

    simOut = sim(modelName, "ReturnWorkspaceOutputs", "on");
    ts = simOut.get("Iabc_log");
    data = squeeze(ts.Data);
    if size(data, 1) < size(data, 2) && size(data, 2) == numel(ts.Time)
        data = data';
    end
    fprintf("isolation_vsc_pmsm IabcRMS=%.6g IabcMax=%.6g samples=%d\n", rms(data, "all"), max(abs(data), [], "all"), numel(ts.Time));
    close_system(modelName, 0);
end

function connectPhysical(modelName, srcBlock, srcGroup, srcIndex, dstBlock, dstGroup, dstIndex)
    srcPorts = get_param(modelName + "/" + srcBlock, "PortHandles");
    dstPorts = get_param(modelName + "/" + dstBlock, "PortHandles");
    add_line(modelName, srcPorts.(srcGroup)(srcIndex), dstPorts.(dstGroup)(dstIndex), "autorouting", "on");
end
