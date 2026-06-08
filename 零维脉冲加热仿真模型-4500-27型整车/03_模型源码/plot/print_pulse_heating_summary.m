function print_pulse_heating_summary(summary, topology)
%PRINT_PULSE_HEATING_SUMMARY Command-window summary for one topology group.

    fprintf('\n--- %s ---\n', topology.name);
    fprintf('%s默认工况架构摘要:\n', topology.name);
    fprintf('%-18s %-34s %10s %10s %10s %10s %10s %10s %10s %12s\n', ...
        '方案', '名称', 'dT/dt', '到0Cmin', '到0CkWh', 'T30min', '电池kW', '到0CSOC%', '支路A', '限制');
    for k = 1:height(summary)
        fprintf('%-18s %-34s %10.3f %10.2f %10.2f %10.2f %10.1f %10.3f %10.0f %12s\n', ...
            summary.case_id{k}, truncate_text(summary.case_name{k}, 34), ...
            summary.dTdt_initial_C_per_min(k), summary.time_to_0C_min(k), ...
            summary.E_total_to_0C_kWh(k), summary.T_end_30min_C(k), ...
            summary.P_battery_kW(k), ...
            summary.SOC_delta_to_0C_pct(k), ...
            summary.I_branch_rms_max_A(k), summary.limiting_factor{k});
    end
    [~, best_idx] = max(summary.dTdt_initial_C_per_min);
    fprintf('\n%s当前占位参数下温升最高: %s\n', ...
        topology.short_name, summary.case_name{best_idx});
    fprintf('注意: 30s/60s规格窗口只作为低频参考边界, 不作为kHz脉冲硬限制。\n');
    fprintf('SOC为等效能量消耗口径, 不代表正负半周净电荷偏置已完成标定。\n');
    fprintf('安全接口: %s\n\n', summary.safety_status{best_idx});
end

function out = truncate_text(in, n)
    s = char(in);
    if strlength(string(s)) > n
        out = char(extractBefore(string(s), n));
    else
        out = s;
    end
end
