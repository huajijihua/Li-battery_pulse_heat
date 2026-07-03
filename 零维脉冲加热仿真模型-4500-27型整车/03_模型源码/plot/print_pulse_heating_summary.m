function print_pulse_heating_summary(summary, topology)
%PRINT_PULSE_HEATING_SUMMARY Command-window summary for one topology group.
% 中文说明:
% 本函数只负责把默认工况摘要打印到命令行，不参与物理计算。
% 打印内容重点包括初始温升速率、到0C时间、30min温度、电池发热、电流和限制来源。

    % 表头。这里的“等效SOC”是总不可逆损耗折算口径，不是BMS库仑SOC。
    fprintf('\n--- %s ---\n', topology.name);
    fprintf('%s默认工况架构摘要:\n', topology.name);
    fprintf('%-18s %-34s %10s %10s %10s %10s %10s %10s %10s %12s\n', ...
        '方案', '名称', 'dT/dt', '到0Cmin', '到0C等效kWh', 'T30min', '电池kW', '到0C等效SOC%', '支路A', '限制');
    for k = 1:height(summary)
        % 每个拓扑方案打印一行，例如三包并联单电机、三包并联双电机。
        fprintf('%-18s %-34s %10.3f %10.2f %10.2f %10.2f %10.1f %10.3f %10.0f %12s\n', ...
            summary.case_id{k}, truncate_text(summary.case_name{k}, 34), ...
            summary.dTdt_initial_C_per_min(k), summary.time_to_0C_min(k), ...
            summary.E_total_loss_equiv_to_0C_kWh(k), summary.T_end_30min_C(k), ...
            summary.P_battery_kW(k), ...
            summary.energy_equiv_SOC_delta_to_0C_pct(k), ...
            summary.I_branch_rms_max_A(k), summary.limiting_factor{k});
    end
    % 用初始温升速率选出当前占位参数下的最高温升方案。它只是粗筛排序，不是安全结论。
    [~, best_idx] = max(summary.dTdt_initial_C_per_min);
    fprintf('\n%s当前占位参数下温升最高: %s\n', ...
        topology.short_name, summary.case_name{best_idx});
    fprintf('注意: 30s/60s规格窗口只作为低频参考边界, 不作为kHz脉冲硬限制。\n');
    fprintf('等效SOC为总不可逆损耗折算口径, 包含电池发热、电机损耗和逆变器损耗。\n');
    fprintf('库仑SOC/净Ah偏置当前未估算, 不能用等效SOC替代BMS真实SOC判断。\n');
    fprintf('安全接口: %s\n\n', summary.safety_status{best_idx});
end

function out = truncate_text(in, n)
    % 控制命令行表格宽度，避免长中文方案名破坏排版。
    s = char(in);
    if strlength(string(s)) > n
        out = char(extractBefore(string(s), n));
    else
        out = s;
    end
end
