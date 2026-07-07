function build_pulse_heating_single_pack_v03b()
%BUILD_PULSE_HEATING_SINGLE_PACK_V03B Add the minimal current-loop signal chain.
%
% v03-B starts from the verified v03-A physical network and replaces the
% direct three-phase modulation waves with a theta=0 Id/Iq current loop.

    scriptDir = string(fileparts(mfilename("fullpath")));
    projectDir = fileparts(scriptDir);
    modelDir = fullfile(projectDir, "02_模型");
    oldDir = string(pwd);
    cleanupObj = onCleanup(@() cd(oldDir));
    cd(modelDir);

    build_pulse_heating_single_pack_v03a(false);

    modelName = "pulse_heating_single_pack_v03";
    load_system(modelName);

    add_block("simulink/Math Operations/Gain", modelName + "/Iabc_to_IdIq_theta0", ...
        "Position", [90 500 210 550], ...
        "Gain", "[1 1/sqrt(3); 0 2/sqrt(3); 0 0]", ...
        "Multiplication", "Matrix(u*K)");
    add_block("simulink/Signal Routing/Demux", modelName + "/IdIq_demux", ...
        "Position", [250 500 280 550], "Outputs", "2");
    add_block("simulink/Discrete/Unit Delay", modelName + "/Id_fb_delay", ...
        "Position", [300 480 345 510], "SampleTime", "1e-4");
    add_block("simulink/Discrete/Unit Delay", modelName + "/Iq_fb_delay", ...
        "Position", [300 525 345 555], "SampleTime", "1e-4");

    add_block("simulink/Sources/Sine Wave", modelName + "/Id_ref_cmd", ...
        "Position", [90 620 145 650], ...
        "Amplitude", "20", ...
        "Frequency", "2*pi*1250", ...
        "Phase", "0");
    add_block("simulink/Sources/Constant", modelName + "/Iq_ref_cmd", ...
        "Position", [90 700 145 730], "Value", "0");

    add_block("simulink/Math Operations/Sum", modelName + "/Id_error", ...
        "Position", [330 610 360 650], "Inputs", "+-");
    add_block("simulink/Math Operations/Sum", modelName + "/Iq_error", ...
        "Position", [330 690 360 730], "Inputs", "+-");

    addPiBranch(modelName, "Id", [410 590 780 660]);
    addPiBranch(modelName, "Iq", [410 670 780 740]);

    add_block("simulink/Signal Routing/Mux", modelName + "/Mdq_mux", ...
        "Position", [825 635 855 715], "Inputs", "2");
    add_block("simulink/Math Operations/Gain", modelName + "/DQ_to_ModWave_theta0", ...
        "Position", [900 640 1040 710], ...
        "Gain", "[1 0; -0.5 sqrt(3)/2; -0.5 -sqrt(3)/2]", ...
        "Multiplication", "Matrix(K*u)");

    addToWorkspace(modelName, "Id_ref_log", [180 620 285 650]);
    addToWorkspace(modelName, "Iq_ref_log", [180 700 285 730]);
    addToWorkspace(modelName, "Id_fb_log", [370 480 475 510]);
    addToWorkspace(modelName, "Iq_fb_log", [370 525 475 555]);
    addToWorkspace(modelName, "Id_error_log", [390 610 500 640]);
    addToWorkspace(modelName, "Iq_error_log", [390 690 500 720]);
    addToWorkspace(modelName, "md_cmd_log", [790 590 895 620]);
    addToWorkspace(modelName, "mq_cmd_log", [790 735 895 765]);

    add_line(modelName, "PSS_Iabc/1", "Iabc_to_IdIq_theta0/1", "autorouting", "on");
    add_line(modelName, "Iabc_to_IdIq_theta0/1", "IdIq_demux/1", "autorouting", "on");
    add_line(modelName, "IdIq_demux/1", "Id_fb_delay/1", "autorouting", "on");
    add_line(modelName, "IdIq_demux/2", "Iq_fb_delay/1", "autorouting", "on");
    add_line(modelName, "Id_fb_delay/1", "Id_error/2", "autorouting", "on");
    add_line(modelName, "Iq_fb_delay/1", "Iq_error/2", "autorouting", "on");
    add_line(modelName, "Id_fb_delay/1", "Id_fb_log/1", "autorouting", "on");
    add_line(modelName, "Iq_fb_delay/1", "Iq_fb_log/1", "autorouting", "on");

    add_line(modelName, "Id_ref_cmd/1", "Id_error/1", "autorouting", "on");
    add_line(modelName, "Id_ref_cmd/1", "Id_ref_log/1", "autorouting", "on");
    add_line(modelName, "Iq_ref_cmd/1", "Iq_error/1", "autorouting", "on");
    add_line(modelName, "Iq_ref_cmd/1", "Iq_ref_log/1", "autorouting", "on");

    wirePiBranch(modelName, "Id", "Id_error", "Mdq_mux", 1);
    wirePiBranch(modelName, "Iq", "Iq_error", "Mdq_mux", 2);
    add_line(modelName, "Id_error/1", "Id_error_log/1", "autorouting", "on");
    add_line(modelName, "Iq_error/1", "Iq_error_log/1", "autorouting", "on");
    add_line(modelName, "Id_sat/1", "md_cmd_log/1", "autorouting", "on");
    add_line(modelName, "Iq_sat/1", "mq_cmd_log/1", "autorouting", "on");

    add_line(modelName, "Mdq_mux/1", "DQ_to_ModWave_theta0/1", "autorouting", "on");
    add_line(modelName, "DQ_to_ModWave_theta0/1", "SPS_ModWave/1", "autorouting", "on");

    save_system(modelName, modelName + ".slx");
    fprintf("Built v03-B current-loop signal chain in %s.slx\n", modelName);
end

function addPiBranch(modelName, axisName, pos)
    x0 = pos(1);
    y0 = pos(2);
    add_block("simulink/Math Operations/Gain", modelName + "/" + axisName + "_Kp", ...
        "Position", [x0 y0 x0+55 y0+30], "Gain", "0.02");
    add_block("simulink/Discrete/Discrete-Time Integrator", modelName + "/" + axisName + "_Integrator", ...
        "Position", [x0 y0+45 x0+80 y0+80], "SampleTime", "1e-4");
    add_block("simulink/Math Operations/Gain", modelName + "/" + axisName + "_Ki", ...
        "Position", [x0+115 y0+48 x0+170 y0+78], "Gain", "0.1");
    add_block("simulink/Math Operations/Sum", modelName + "/" + axisName + "_PI_sum", ...
        "Position", [x0+215 y0+18 x0+245 y0+62], "Inputs", "++");
    add_block("simulink/Discontinuities/Saturation", modelName + "/" + axisName + "_sat", ...
        "Position", [x0+290 y0+20 x0+350 y0+60], ...
        "UpperLimit", "0.2", "LowerLimit", "-0.2");
end

function wirePiBranch(modelName, axisName, errorBlock, muxBlock, muxPort)
    add_line(modelName, errorBlock + "/1", axisName + "_Kp/1", "autorouting", "on");
    add_line(modelName, errorBlock + "/1", axisName + "_Integrator/1", "autorouting", "on");
    add_line(modelName, axisName + "_Kp/1", axisName + "_PI_sum/1", "autorouting", "on");
    add_line(modelName, axisName + "_Integrator/1", axisName + "_Ki/1", "autorouting", "on");
    add_line(modelName, axisName + "_Ki/1", axisName + "_PI_sum/2", "autorouting", "on");
    add_line(modelName, axisName + "_PI_sum/1", axisName + "_sat/1", "autorouting", "on");
    add_line(modelName, axisName + "_sat/1", muxBlock + "/" + string(muxPort), "autorouting", "on");
end

function addToWorkspace(modelName, variableName, position)
    add_block("simulink/Sinks/To Workspace", modelName + "/" + variableName, ...
        "Position", position, ...
        "VariableName", variableName, ...
        "SaveFormat", "Timeseries");
end
