function plot_pulse_heating_results(result, p, study, topology)
%PLOT_PULSE_HEATING_RESULTS Displays compact figures for one topology group.

    summary = result.summary;
    results = result.results;
    sims = result.sims;

    plot_overview(summary, p, topology);
    plot_transient_case(summary, sims, p, topology);
    plot_frequency_and_balance(results, topology, study);
end

function plot_overview(summary, p, topology)
    figure('Name', [topology.short_name, ' 图1 方案对比总览'], ...
        'Color', 'w', 'Position', [60 60 1460 760]);
    tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
    labels = ordered_case_labels(summary.case_id);

    nexttile;
    bar(labels, summary.dTdt_initial_C_per_min, 'FaceColor', [0.18 0.42 0.70]);
    ylabel('初始温升速率 (C/min)');
    title('加热能力');
    grid on;
    xtickangle(15);
    add_value_labels(summary.dTdt_initial_C_per_min, '%.2f');

    nexttile;
    power_data = [summary.P_battery_kW, summary.P_motor_kW, summary.P_inverter_kW];
    bar(labels, power_data, 'grouped');
    ylabel('功率 (kW)');
    title('功率分解');
    legend({'电池内阻发热', '电机铜耗', '逆变器损耗'}, ...
        'Location', 'northwest');
    grid on;
    xtickangle(15);

    nexttile;
    energy_data = [summary.E_battery_heat_30min_kWh, ...
        summary.E_motor_loss_30min_kWh, summary.E_inverter_loss_30min_kWh];
    bar(labels, energy_data, 'stacked');
    ylabel('30min累计能量 (kWh)');
    title('能量消耗');
    legend({'电池发热', '电机铜耗', '控制器损耗'}, ...
        'Location', 'northwest');
    grid on;
    xtickangle(15);

    nexttile([1 2]);
    current_data = [summary.I_motor_rms_A, ...
        summary.I_branch_rms_max_A, summary.I_bus_rms_A];
    bar(labels, current_data, 'grouped');
    hold on;
    yline(p.I_motor_rms_limit_A, '--r', '电机/MCU RMS限值', 'LineWidth', 1.2);
    hold off;
    ylabel('电流 (A rms)');
    title('电机、支路和母线电流');
    legend({'电机/MCU', '电池支路最大', '母线等效'}, ...
        'Location', 'northwest');
    grid on;
    xtickangle(15);

    nexttile;
    plot_safety_text(summary, p);
end

function plot_transient_case(summary, sims, p, topology)
    [~, best_idx] = max(summary.dTdt_initial_C_per_min);
    sim = sims(best_idx).data;

    figure('Name', [topology.short_name, ' 图2 典型方案瞬态过程'], ...
        'Color', 'w', 'Position', [90 80 1460 760]);
    tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot(sim.t_min, sim.T_mean_C, 'k-', 'LineWidth', 2.0);
    hold on;
    plot(sim.t_min, sim.T_branch_C, '--', 'LineWidth', 1.0);
    yline(p.T_target_C, ':', '目标温度', 'LineWidth', 1.0);
    hold off;
    xlabel('时间 (min)');
    ylabel('温度 (C)');
    title(['温度: ', sims(best_idx).case_name]);
    grid on;

    nexttile;
    plot(sim.t_min, sim.dTdt_C_per_min, 'Color', [0.18 0.42 0.70], 'LineWidth', 1.8);
    xlabel('时间 (min)');
    ylabel('dT/dt (C/min)');
    title('净温升速率');
    grid on;

    nexttile;
    plot(sim.t_min, sim.I_motor_rms_A, 'LineWidth', 1.6);
    hold on;
    plot(sim.t_min, sim.I_branch_rms_max_A, 'LineWidth', 1.6);
    plot(sim.t_min, sim.I_bus_rms_A, 'LineWidth', 1.6);
    yline(p.I_motor_rms_limit_A, '--r', '电机RMS限值');
    hold off;
    xlabel('时间 (min)');
    ylabel('电流 (A rms)');
    title('电流过程');
    legend({'电机/MCU', '支路最大', '母线等效'}, 'Location', 'best');
    grid on;

    nexttile;
    plot(sim.t_min, sim.P_battery_W / 1000, 'LineWidth', 1.6);
    hold on;
    plot(sim.t_min, sim.P_motor_W / 1000, 'LineWidth', 1.6);
    plot(sim.t_min, sim.P_inverter_W / 1000, 'LineWidth', 1.6);
    plot(sim.t_min, sim.P_loss_W / 1000, '--', 'LineWidth', 1.4);
    hold off;
    xlabel('时间 (min)');
    ylabel('功率 (kW)');
    title('功率过程');
    legend({'电池发热', '电机铜耗', '逆变器损耗', '散热'}, 'Location', 'best');
    grid on;

    nexttile;
    plot(sim.t_min, sim.E_battery_heat_kWh, 'LineWidth', 1.6);
    hold on;
    plot(sim.t_min, sim.E_motor_loss_kWh, 'LineWidth', 1.6);
    plot(sim.t_min, sim.E_inverter_loss_kWh, 'LineWidth', 1.6);
    plot(sim.t_min, sim.E_total_electric_kWh, 'k-', 'LineWidth', 1.8);
    hold off;
    xlabel('时间 (min)');
    ylabel('累计能量 (kWh)');
    title('累计能量');
    legend({'电池发热', '电机铜耗', '控制器损耗', '总等效电耗'}, ...
        'Location', 'best');
    grid on;

    nexttile;
    plot(sim.t_min, sim.SOC * 100, 'Color', [0.00 0.30 0.85], 'LineWidth', 1.8);
    xlabel('时间 (min)');
    ylabel('SOC等效值 (%)');
    title('SOC等效消耗');
    grid on;
end

function plot_frequency_and_balance(results, topology, study)
    figure('Name', [topology.short_name, ' 图3 频率影响与支路均衡'], ...
        'Color', 'w', 'Position', [120 100 1320 720]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_frequency_scan_panel(results, study, topology);

    nexttile;
    plot_amplitude_scan_panel(results, study, topology);

    [nominal, mismatch] = get_default_mismatch_rows(results, study);

    nexttile;
    labels = ordered_case_labels(nominal.case_id);
    bar(labels, [nominal.branch_heat_spread_pct, mismatch.branch_heat_spread_pct], ...
        'grouped');
    ylabel('支路发热离散度 (%)');
    title('支路内阻不一致导致的发热差异');
    legend({'名义一致', '内阻不一致'}, 'Location', 'northwest');
    grid on;
    xtickangle(15);

    nexttile;
    heat_matrix = make_branch_heat_matrix(mismatch, topology);
    bar(ordered_case_labels({topology.cases.id}), heat_matrix, 'grouped');
    ylabel('支路发热 (kW)');
    title('内阻不一致工况下各支路发热');
    legend(make_branch_legend(size(heat_matrix, 2)), 'Location', 'northwest');
    grid on;
    xtickangle(15);
end

function plot_frequency_scan_panel(results, study, topology)
    mask = strcmp(results.mismatch_label, 'nominal') & ...
        results.T_init_C == study.default_temperature_C & ...
        results.duty == study.default_duty & ...
        abs(results.current_amplitude_scale - ...
            study.default_current_amplitude_scale) < 1e-12;
    scan = results(mask, :);

    hold on;
    case_ids = unique(scan.case_id, 'stable');
    for k = 1:numel(case_ids)
        rows = strcmp(scan.case_id, case_ids{k});
        case_name = scan.case_name{find(rows, 1, 'first')};
        plot(scan.frequency_Hz(rows), scan.dTdt_C_per_min(rows), '-o', ...
            'LineWidth', 1.6, 'DisplayName', case_name);
    end
    xline(study.default_frequency_Hz, '--', sprintf('%.0fHz参考', study.default_frequency_Hz), ...
        'LineWidth', 1.2, 'HandleVisibility', 'off');
    hold off;
    xlabel('频率 (Hz)');
    ylabel('初始温升速率 (C/min)');
    title(sprintf('%s 频率影响: %.0fC, SOC %.0f%%, D=%.2f', ...
        topology.short_name, study.default_temperature_C, study.SOC * 100, study.default_duty));
    legend('Location', 'northeast');
    grid on;
end

function plot_amplitude_scan_panel(results, study, topology)
    mask = strcmp(results.mismatch_label, 'nominal') & ...
        results.T_init_C == study.default_temperature_C & ...
        results.frequency_Hz == study.default_frequency_Hz & ...
        results.duty == study.default_duty;
    scan = results(mask, :);

    hold on;
    case_ids = unique(scan.case_id, 'stable');
    for k = 1:numel(case_ids)
        rows = strcmp(scan.case_id, case_ids{k});
        case_name = scan.case_name{find(rows, 1, 'first')};
        plot(scan.current_amplitude_scale(rows), scan.dTdt_C_per_min(rows), '-o', ...
            'LineWidth', 1.6, 'DisplayName', case_name);
    end
    xline(study.default_current_amplitude_scale, '--', '默认幅值', ...
        'LineWidth', 1.2, 'HandleVisibility', 'off');
    hold off;
    xlabel('电流幅值系数');
    ylabel('初始温升速率 (C/min)');
    title(sprintf('%s 幅值影响: %.0fC, %.0fHz, D=%.2f', ...
        topology.short_name, study.default_temperature_C, ...
        study.default_frequency_Hz, study.default_duty));
    legend('Location', 'northwest');
    grid on;
end

function [nominal, mismatch] = get_default_mismatch_rows(results, study)
    mask = results.T_init_C == study.default_temperature_C & ...
        results.frequency_Hz == study.default_frequency_Hz & ...
        results.duty == study.default_duty & ...
        abs(results.current_amplitude_scale - ...
            study.default_current_amplitude_scale) < 1e-12;
    base = results(mask, :);
    nominal = base(strcmp(base.mismatch_label, 'nominal'), :);
    mismatch = base(~strcmp(base.mismatch_label, 'nominal'), :);
end

function heat_matrix = make_branch_heat_matrix(mismatch, topology)
    max_branch_count = max([topology.cases.branch_count]);
    heat_matrix = nan(numel(topology.cases), max_branch_count);
    for i = 1:numel(topology.cases)
        row = mismatch(strcmp(mismatch.case_id, topology.cases(i).id), :);
        if isempty(row)
            continue;
        end
        heat_matrix(i, 1) = row.P_branch_1_kW;
        if max_branch_count >= 2
            heat_matrix(i, 2) = row.P_branch_2_kW;
        end
        if max_branch_count >= 3
            heat_matrix(i, 3) = row.P_branch_3_kW;
        end
    end
end

function labels = ordered_case_labels(case_ids)
    labels = categorical(case_ids);
    labels = reordercats(labels, case_ids);
end

function legends = make_branch_legend(n)
    legends = cell(1, n);
    for k = 1:n
        legends{k} = sprintf('支路%d', k);
    end
end

function add_value_labels(values, fmt)
    ax = gca;
    x = 1:numel(values);
    offset = 0.02 * max(values);
    if offset <= 0
        offset = 0.01;
    end
    for k = 1:numel(values)
        text(x(k), values(k) + offset, sprintf(fmt, values(k)), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'Parent', ax);
    end
end

function plot_safety_text(summary, p)
    axis off;
    lines = cell(height(summary) + 3, 1);
    lines{1} = '安全状态';
    lines{2} = sprintf('控制器频率上限: %.0f Hz', p.f_control_max_Hz);
    for k = 1:height(summary)
        lines{k+2} = sprintf('%s: %s', summary.case_id{k}, ...
            summary.safety_status{k});
    end
    lines{end} = '规格书/析锂边界为参考展示, 未作为目标车型硬结论';
    text(0.02, 0.98, strjoin(lines, newline), 'Units', 'normalized', ...
        'VerticalAlignment', 'top', 'FontSize', 9);
    title('安全限制摘要');
end
