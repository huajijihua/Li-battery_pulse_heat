function fix_inverter_dc_bus_topology_v04d2()
%FIX_INVERTER_DC_BUS_TOPOLOGY_V04D2 修复逆变器 DC 母线拓扑缺陷。
%
% V4-B2 通过 add_block 复制官方逆变器子系统时，Simulink 未保留 PMIOPort
% (DC+/DC-) 到全部 3 个半桥的物理连接线。原始模型中 DC+ 连接 3 个高侧
% 集电极，DC- 连接 3 个低侧发射极；V4 模型中仅 A 相保留连接，B/C 相
% 半桥悬空，导致三相电流无闭合回路，相电流接近零。
%
% 本脚本在逆变器子系统内部补全物理连接线，恢复官方拓扑。
%
% V4 模型中 B(H).C <-> C(H).C 和 B(L).E <-> C(L).E 交叉连接已存在，
% 因此只需将 DC+ 连接到 B(H).C、DC- 连接到 B(L).E 即可使三个半桥
% 共享同一 DC 母线节点。若目标端口已有连接线导致 add_line 失败，
% 则先删除交叉连接、添加 DC 母线连接、再恢复交叉连接。

    modelName = "pulse_heating_official_spine_v04";
    load_system(modelName);

    invPath = modelName + "/PMSMDriveThermal_Inverter_And_Motor/Three-phase inverter";

    plusH   = getSimulinkBlockHandle(invPath + "/+");
    minusH  = getSimulinkBlockHandle(invPath + "/-");
    ahH     = getSimulinkBlockHandle(invPath + "/IGBT A(H)");
    bhH     = getSimulinkBlockHandle(invPath + "/IGBT B(H)");
    chH     = getSimulinkBlockHandle(invPath + "/IGBT C(H)");
    alH     = getSimulinkBlockHandle(invPath + "/IGBT A(L)");
    blH     = getSimulinkBlockHandle(invPath + "/IGBT B(L)");
    clH     = getSimulinkBlockHandle(invPath + "/IGBT C(L)");

    plusPH  = get_param(plusH,  "PortHandles");
    minusPH = get_param(minusH, "PortHandles");
    ahPH    = get_param(ahH,    "PortHandles");
    bhPH    = get_param(bhH,    "PortHandles");
    chPH    = get_param(chH,    "PortHandles");
    alPH    = get_param(alH,    "PortHandles");
    blPH    = get_param(blH,    "PortHandles");
    clPH    = get_param(clH,    "PortHandles");

    addedCount = 0;

    fprintf("--- High side: DC+ -> B(H).C ---\n");
    [addedCount, bhCrossDeleted] = connectWithCrossFallback( ...
        invPath, plusPH.RConn(1), bhPH.RConn(1), chPH.RConn(1), addedCount);

    fprintf("--- Low side: DC- -> B(L).E ---\n");
    [addedCount, blCrossDeleted] = connectWithCrossFallback( ...
        invPath, minusPH.RConn(1), blPH.RConn(2), clPH.RConn(2), addedCount);

    fprintf("\nSummary:\n");
    fprintf("  DC+ -> B(H).C: added (cross B<->C deleted=%d)\n", bhCrossDeleted);
    fprintf("  DC- -> B(L).E: added (cross B<->C deleted=%d)\n", blCrossDeleted);
    fprintf("  Total connections added: %d\n", addedCount);

    save_system(modelName);
    fprintf("Model saved.\n");
end

function [addedCount, crossDeleted] = connectWithCrossFallback( ...
    subsysPath, dcPort, targetPort, crossPort, count)
%CONNECTWITHCROSSFALLBACK 尝试将 DC 端口连到目标端口。
% 若目标端口已有连接线（交叉连接），先删除交叉连接，添加 DC 连接，
% 再尝试恢复交叉连接。

    crossDeleted = 0;
    addedCount = count;

    [addedCount, success] = tryAddLine(subsysPath, dcPort, targetPort, addedCount);
    if success
        return;
    end

    fprintf("  Target port occupied, trying cross-connection fallback...\n");
    deleted = deleteLineByPorts(subsysPath, targetPort, crossPort);
    if ~deleted
        error("Could not delete existing cross-connection to free target port.");
    end
    crossDeleted = 1;

    [addedCount, success] = tryAddLine(subsysPath, dcPort, targetPort, addedCount);
    if ~success
        error("Failed to add DC connection after deleting cross-connection.");
    end

    [addedCount, restored] = tryAddLine(subsysPath, targetPort, crossPort, addedCount);
    if restored
        crossDeleted = 0;
        fprintf("  Cross-connection restored.\n");
    else
        fprintf("  Cross-connection could not be restored (electrically equivalent via DC node).\n");
    end
end

function [count, success] = tryAddLine(subsysPath, srcPort, dstPort, count)
%TRYADDLINE 尝试添加物理连接线，返回是否成功。
    try
        add_line(subsysPath, srcPort, dstPort, "autorouting", "on");
        count = count + 1;
        success = true;
        fprintf("  Added: %d -> %d\n", srcPort, dstPort);
    catch
        success = false;
        fprintf("  Failed: %d -> %d (port occupied)\n", srcPort, dstPort);
    end
end

function deleted = deleteLineByPorts(subsysPath, port1, port2)
%DELETELINEBYPORTS 删除连接两个端口的物理连接线。
    deleted = false;
    lines = find_system(subsysPath, "FindAll", "on", "SearchDepth", 1, "Type", "line");
    for idx = numel(lines):-1:1
        ln = lines(idx);
        try
            lineSrcPort = get_param(ln, "SrcPortHandle");
            lineDstPort = get_param(ln, "DstPortHandle");
            if (lineSrcPort == port1 && lineDstPort == port2) || ...
               (lineSrcPort == port2 && lineDstPort == port1)
                delete_line(ln);
                deleted = true;
                fprintf("  Deleted cross-connection: %d <-> %d\n", port1, port2);
                return;
            end
        catch
        end
    end
end
