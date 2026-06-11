function plot_pulse_heating_results(result, p, study, topology)
%PLOT_PULSE_HEATING_RESULTS Report-oriented figures for 4500-27 screening.

    summary = result.summary;
    results = result.results;
    sens = result.sensitivity;
    sims = result.sims;

    plot_principle_and_default_case(summary, sims, p, study, topology);
    plot_dual_motor_sensitivity(sens, results, p, study, topology);
    plot_single_motor_comparison(summary, results, sens, p, study, topology);
end

function plot_principle_and_default_case(summary, sims, p, study, topology)
    figure('Name', [topology.short_name, ' 汇报图1 原理与默认工况'], ...
        'Color', 'w', 'Position', [40 40 1600 920]);
    tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile([1 1]);
    draw_equivalent_circuit(p, study);

    waveform = build_default_waveform(p, study);

    nexttile;
    yyaxis left;
    plot(waveform.t_ms, waveform.i_motor_A, 'LineWidth', 1.8);
    hold on;
    yline(p.I_motor_peak_limit_A, '--r', ...
        sprintf('550Arms -> %.0fApeak', p.I_motor_peak_limit_A), ...
        'LineWidth', 1.1);
    yline(-p.I_motor_peak_limit_A, '--r', 'HandleVisibility', 'off', ...
        'LineWidth', 1.1);
    ylabel('电机电流 (A)');
    yyaxis right;
    stairs(waveform.t_ms, waveform.v_motor_V, 'LineWidth', 1.4);
    ylabel('电机端等效电压 (V)');
    hold off;
    xlabel('时间 (ms)');
    title('双电机同步: 单台电机两周期电压/电流');
    grid on;

    nexttile;
    yyaxis left;
    plot(waveform.t_ms, waveform.i_branch_A, 'LineWidth', 1.8);
    ylabel('单包支路电流 (A)');
    yyaxis right;
    plot(waveform.t_ms, waveform.i_bus_A, '--', 'LineWidth', 1.4);
    hold on;
    hold off;
    ylabel('双电机母线等效电流 (A)');
    xlabel('时间 (ms)');
    title('电池侧电流: 三包分流后单包电流更小');
    legend({'单包支路电流', '双电机母线等效电流'}, 'Location', 'best');
    grid on;

    nexttile([1 2]);
    plot_default_temperature(sims, p, summary, study);

    nexttile;
    plot_energy_pie(summary);
end

function draw_equivalent_circuit(p, ~)
    axis off;
    hold on;
    title('当前L0.5模型等效电路原理');
    xlim([0 12]);
    ylim([0 10]);

    % DC buses.
    plot([2.5 8.1], [8.2 8.2], 'k-', 'LineWidth', 2.0);
    plot([2.5 8.1], [1.5 1.5], 'k-', 'LineWidth', 2.0);
    text(5.3, 8.55, sprintf('HV bus %.0fV nominal', p.V_pack_nom_V), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');

    % Three parallel battery packs.
    y_pack = [6.9 4.9 2.9];
    for k = 1:3
        draw_battery_branch(0.9, y_pack(k), sprintf('Pack %d\n252S 278Ah', k));
        plot([2.45 2.5], [y_pack(k) 8.2], 'k-', 'LineWidth', 1.0);
        plot([2.45 2.5], [y_pack(k) 1.5], 'k-', 'LineWidth', 1.0);
    end
    text(0.7, 9.35, sprintf('三包并联整体输出\n不可独立接入电驱'), ...
        'FontWeight', 'bold', 'Interpreter', 'none');

    % Two synchronized inverter-motor RL branches.
    draw_inverter_motor_branch(8.1, 6.6, 'MCU/Motor 1');
    draw_inverter_motor_branch(8.1, 3.4, 'MCU/Motor 2');
    text(8.8, 0.65, '双电机同步堵转脉冲; 电机等效R-L负载', ...
        'HorizontalAlignment', 'center');
    hold off;
end

function draw_battery_branch(x, y, label)
    plot([x x+0.25], [y y], 'k-', 'LineWidth', 1.2);
    plot([x+0.25 x+0.25], [y-0.45 y+0.45], 'k-', 'LineWidth', 1.8);
    plot([x+0.45 x+0.45], [y-0.25 y+0.25], 'k-', 'LineWidth', 1.8);
    rectangle('Position', [x+0.65, y-0.35, 0.35, 0.70], ...
        'Curvature', 0.1, 'EdgeColor', 'k', 'LineWidth', 1.2);
    text(x+0.82, y, 'R', 'HorizontalAlignment', 'center');
    plot([x+1.0 x+1.55], [y y], 'k-', 'LineWidth', 1.2);
    text(x+0.7, y-0.92, label, 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'Interpreter', 'none');
end

function draw_inverter_motor_branch(x, y, label)
    rectangle('Position', [x-0.15, y-0.75, 1.15, 1.5], ...
        'EdgeColor', [0.15 0.35 0.65], 'LineWidth', 1.5);
    text(x+0.42, y, 'Inverter', 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold');
    plot([x x], [8.4 y+0.75], 'k-', 'LineWidth', 1.2);
    plot([x x], [y-0.75 1.6], 'k-', 'LineWidth', 1.2);
    plot([x+1.0 x+1.55], [y y], 'k-', 'LineWidth', 1.2);
    rectangle('Position', [x+1.55, y-0.32, 0.45, 0.64], ...
        'Curvature', 0.2, 'EdgeColor', 'k', 'LineWidth', 1.2);
    text(x+1.78, y, 'R', 'HorizontalAlignment', 'center');
    plot([x+2.0 x+2.35], [y y], 'k-', 'LineWidth', 1.2);
    draw_inductor(x+2.35, y);
    text(x+2.35, y-0.95, label, 'HorizontalAlignment', 'center', ...
        'FontSize', 9);
end

function draw_inductor(x, y)
    theta = linspace(0, pi, 30);
    x0 = x;
    for k = 1:5
        xx = x0 + (k-1)*0.22 + 0.11 * (1 - cos(theta));
        yy = y + 0.18 * sin(theta);
        plot(xx, yy, 'k-', 'LineWidth', 1.2);
    end
    plot([x+1.1 x+1.45], [y y], 'k-', 'LineWidth', 1.2);
    text(x+0.58, y+0.55, 'L_d', 'HorizontalAlignment', 'center');
end

function waveform = build_default_waveform(p, study)
    SOC = study.SOC;
    T_C = study.default_temperature_C;
    f = study.default_frequency_Hz;
    D = study.default_duty;
    motor_count = 2;

    V_oc = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, SOC, ...
        'linear', 'extrap');
    R_branch = interp2(p.R_data_SOC, p.R_data_T_C, ...
        p.R_branch_192S1P_table_ohm, SOC, T_C, 'linear') * ...
        p.R_heat_factor_default;
    R_eq = R_branch / 3;
    R_loop = p.motor_Rs_ohm + motor_count * R_eq;
    L = p.motor_Ld_H;
    T_period = 1 / f;
    t_on = D * T_period;
    tau = L / R_loop;
    Vs = V_oc / R_loop;

    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp((T_period - t_on) / tau);
    denom = exp_a - 1;
    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;

    t = linspace(0, 2 * T_period, 900);
    t_mod = mod(t, T_period);
    i_motor = zeros(size(t));
    v_motor = zeros(size(t));
    on = t_mod <= t_on;
    i_motor(on) = Vs + (i_min - Vs) .* exp(-t_mod(on) / tau);
    v_motor(on) = V_oc;
    t_off = t_mod(~on) - t_on;
    i_motor(~on) = -Vs + (i_max + Vs) .* exp(-t_off / tau);
    v_motor(~on) = -V_oc;

    i_bus = motor_count * i_motor;
    i_branch = i_bus / 3;

    waveform = struct();
    waveform.t_ms = t * 1000;
    waveform.i_motor_A = i_motor;
    waveform.v_motor_V = v_motor;
    waveform.i_bus_A = i_bus;
    waveform.i_branch_A = i_branch;
end

function plot_default_temperature(sims, p, summary, study)
    hold on;
    for k = 1:numel(sims)
        sim = sims(k).data;
        plot(sim.t_min, sim.T_mean_C, 'LineWidth', 2.2, ...
            'DisplayName', sims(k).case_name);
    end
    yline(p.T_target_C, 'k:', '0C目标', 'LineWidth', 1.2, ...
        'HandleVisibility', 'off');
    xline(20, '--', '20min参考', 'LineWidth', 1.1, ...
        'HandleVisibility', 'off');
    hold off;
    xlabel('时间 (min)');
    ylabel('平均电池温度 (C)');
    row = summary(strcmp(summary.case_id, '三包并联双电机'), :);
    default_text = sprintf(['默认工况: -20C, SOC %.0f%%, %.0fHz, D=%.2f, ', ...
        '单电机 %.0fArms, 电池包OCV %.0fV, 逆变器额定 %.0fV'], ...
        study.SOC * 100, study.default_frequency_Hz, study.default_duty, ...
        row.I_motor_rms_A, p.N_series * interp1(p.ocv_soc_bp, ...
        p.ocv_cell_V, study.SOC, 'linear', 'extrap'), p.inverter_V_nom_V);
    title({'默认工况Time-temperature曲线', default_text});
    legend('Location', 'northwest');
    grid on;
end

function plot_energy_pie(summary)
    row = summary(strcmp(summary.case_id, '三包并联双电机'), :);
    energy = [row.E_battery_heat_30min_kWh, row.E_motor_loss_30min_kWh, ...
        row.E_inverter_loss_30min_kWh];
    total_electric = row.E_total_loss_equiv_30min_kWh;
    battery_heat_efficiency_pct = row.E_battery_heat_30min_kWh / ...
        max(total_electric, eps) * 100;
    labels = {sprintf('电池自身发热 %.1fkWh', energy(1)), ...
        sprintf('电机铜耗 %.1fkWh', energy(2)), ...
        sprintf('控制器损耗 %.1fkWh', energy(3))};
    pie(energy, labels);
    title({'默认双电机方案能量分布', ...
        sprintf('电池加热效率 %.1f%% = %.1f/%.1f kWh', ...
        battery_heat_efficiency_pct, row.E_battery_heat_30min_kWh, ...
        total_electric)});
end

function plot_dual_motor_sensitivity(~, ~, p, study, topology)
    figure('Name', [topology.short_name, ' 汇报图2 双电机性能敏感性'], ...
        'Color', 'w', 'Position', [60 60 1600 920]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_current_sensitivity(p, study);

    nexttile;
    plot_frequency_sensitivity(p, study);

    nexttile;
    plot_heat_boundary_sensitivity(p, study);

    nexttile;
    plot_resistance_sensitivity(p, study);
end

function plot_current_sensitivity(p, study)
    amp_list = p.current_amplitude_scale_scan;
    T20 = zeros(size(amp_list));
    SOC_per_C = zeros(size(amp_list));
    I_motor = zeros(size(amp_list));
    for k = 1:numel(amp_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, amp_list(k), study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
        I_motor(k) = m.I_motor_rms_A;
    end
    plot(I_motor, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.85 0.33 0.10]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(I_motor, T20, SOC_per_C);
    hold off;
    xlabel('实际单电机RMS电流 (Arms)');
    ylabel('20min终温 (C)');
    title('电流大小影响');
    subtitle('标注为单位温升等效SOC消耗: %SOC/C');
    grid on;
end

function plot_frequency_sensitivity(p, study)
    f_list = p.frequency_scan_Hz;
    T20 = zeros(size(f_list));
    SOC_per_C = zeros(size(f_list));
    for k = 1:numel(f_list)
        m = simulate_report_case(p, study, f_list(k), study.default_duty, ...
            study.default_current_amplitude_scale, study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(f_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.47 0.67 0.19]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(f_list, T20, SOC_per_C);
    hold off;
    xlabel('频率 (Hz)');
    ylabel('20min终温 (C)');
    title('频率大小影响');
    subtitle('当前固定电压幅值口径下, 高频会降低电流纹波');
    grid on;
end

function plot_heat_boundary_sensitivity(p, study)
    h_list = p.h_conv_scan_W_per_m2K;
    T20 = zeros(size(h_list));
    SOC_per_C = zeros(size(h_list));
    for k = 1:numel(h_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, study.default_current_amplitude_scale, ...
            study.SOC, p.R_heat_factor_default, ...
            p.I_motor_rms_limit_default_A, h_list(k));
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(h_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.18 0.42 0.70]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    xline(p.h_conv_W_per_m2K, '--', '默认h', 'LineWidth', 1.1);
    annotate_soc_per_C(h_list, T20, SOC_per_C);
    hold off;
    xlabel('等效换热系数 h (W/m^2/K)');
    ylabel('20min终温 (C)');
    title('电池加热环境边界影响');
    subtitle('液冷/泵阀/环境不确定性折算为等效对流换热系数');
    grid on;
end

function plot_resistance_sensitivity(p, study)
    R_list = p.R_heat_factor_scan;
    T20 = zeros(size(R_list));
    SOC_per_C = zeros(size(R_list));
    for k = 1:numel(R_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, study.default_current_amplitude_scale, ...
            study.SOC, R_list(k), p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(R_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.49 0.18 0.56]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(R_list, T20, SOC_per_C);
    hold off;
    xlabel('高频发热电阻系数 R_{heat}/DCR');
    ylabel('20min终温 (C)');
    title('高频电阻变化敏感性');
    subtitle('决定电池自身发热量级, 是当前最大不确定性');
    grid on;
end

function plot_single_motor_comparison(summary, results, sens, p, study, topology)
    figure('Name', [topology.short_name, ' 汇报图3 单电机对比'], ...
        'Color', 'w', 'Position', [80 80 1450 760]);
    tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_single_vs_dual_temperature(summary, sens, p);

    nexttile;
    plot_single_motor_limit_scan(results, study);
end

function plot_single_vs_dual_temperature(summary, sens, ~)
    rows = strcmp(sens.sensitivity_axis, 'R_heat_limit_matrix') & ...
        strcmp(sens.mismatch_label, 'nominal') & sens.R_heat_factor == 1 & ...
        sens.motor_rms_limit_A == 550;
    data = sens(rows, :);
    labels = categorical(data.case_id);
    labels = reordercats(labels, data.case_id);
    bar(labels, [data.T_20min_C, data.T_30min_C], 'grouped');
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    hold off;
    ylabel('平均电池温度 (C)');
    title('默认极限参考下: 单电机仍难以满足要求');
    legend({'20min', '30min'}, 'Location', 'northwest');
    grid on;

    row_single = summary(strcmp(summary.case_id, '三包并联单电机'), :);
    text(1, row_single.T_end_30min_C + 1.2, '30min仍未到0C', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

function plot_single_motor_limit_scan(results, study)
    rows = strcmp(results.case_id, '三包并联单电机') & ...
        results.T_init_C == study.default_temperature_C & ...
        strcmp(results.mismatch_label, 'nominal') & results.R_heat_factor == 1 & ...
        results.motor_rms_limit_A == 550 & results.duty == study.default_duty;
    data = results(rows, :);
    amp_vals = unique(data.current_amplitude_scale, 'stable');
    T20 = zeros(size(amp_vals));
    I_motor = zeros(size(amp_vals));
    for k = 1:numel(amp_vals)
        subset = data(data.current_amplitude_scale == amp_vals(k), :);
        [~, idx] = max(subset.dTdt_C_per_min);
        T20(k) = study.default_temperature_C + subset.dTdt_C_per_min(idx) * 20;
        I_motor(k) = subset.I_motor_rms_A(idx);
    end
    yyaxis left;
    plot(amp_vals, T20, '-o', 'LineWidth', 2.0);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    ylabel('最佳频率下20min终温估算 (C)');
    yyaxis right;
    plot(amp_vals, I_motor, '--s', 'LineWidth', 1.8);
    yline(550, '--r', '550Arms短时参考', 'LineWidth', 1.1);
    ylabel('单电机RMS电流 (A)');
    hold off;
    xlabel('单电机电流幅值系数');
    title('单电机推高幅值后的收益有限');
    grid on;
end

function annotate_soc_per_C(x, y, soc_per_C_pct)
    for k = 1:numel(x)
        if isnan(soc_per_C_pct(k)) || isinf(soc_per_C_pct(k))
            label = '-- %/C';
        else
            label = sprintf('%.2f%%/C', soc_per_C_pct(k));
        end
        text(x(k), y(k), ['  ', label], 'FontSize', 9, ...
            'VerticalAlignment', 'bottom');
    end
end

function m = simulate_report_case(p, study, f_Hz, duty, amp_scale, SOC0, ...
        R_heat_factor, motor_limit_A, h_conv)
    p_case = p;
    p_case.R_heat_factor_current = R_heat_factor;
    p_case.I_motor_rms_limit_A = motor_limit_A;
    p_case.I_motor_peak_limit_A = sqrt(2) * motor_limit_A;
    p_case.h_conv_W_per_m2K = h_conv;
    p_case.R_th_branch_K_per_W = 1 / max(h_conv * p_case.branch_area_m2, eps);
    c = struct('id', '三包并联双电机', ...
        'name', '三包并联整体输出，双电机脉冲', 'branch_count', 3, ...
        'motor_count', 2, 'type', 'whole_branch_sync');
    mismatch = ones(1, 3);
    dt_s = study.dt_s;
    t_end_s = 30 * 60;
    n_steps = floor(t_end_s / dt_s) + 1;
    t_s = (0:n_steps-1)' * dt_s;
    T_branch = zeros(n_steps, 3);
    SOC = zeros(n_steps, 1);
    E_total_kWh = zeros(n_steps, 1);
    I_motor = zeros(n_steps, 1);
    T_branch(1, :) = study.default_temperature_C;
    SOC(1) = SOC0;

    for k = 1:n_steps
        op = eval_circuit_operating_point(p_case, c, mean(T_branch(k, :)), ...
            SOC(k), f_Hz, duty, mismatch, amp_scale);
        heat = eval_heat_balance(p_case, op.P_branch_W, T_branch(k, :), 3);
        I_motor(k) = op.I_motor_rms_A;
        if k < n_steps
            E_total_kWh(k+1) = E_total_kWh(k) + ...
                op.P_total_electric_W / 1000 * dt_s / 3600;
            T_branch(k+1, :) = T_branch(k, :) + ...
                heat.P_net_branch_W / p_case.Cth_branch_J_per_K * dt_s;
            E_available_kWh = 3 * p_case.N_series * interp1( ...
                p_case.ocv_soc_bp, p_case.ocv_cell_V, SOC(k), ...
                'linear', 'extrap') * p_case.C_branch_Ah / 1000;
            SOC(k+1) = max(0, SOC(k) - op.P_total_electric_W * ...
                dt_s / 3.6e6 / max(E_available_kWh, eps));
        end
    end

    T_mean = mean(T_branch, 2);
    m = struct();
    m.T20_C = interp1(t_s / 60, T_mean, 20, 'linear', 'extrap');
    m.T30_C = T_mean(end);
    m.energy_equiv_SOC_delta_30min_pct = (SOC(1) - SOC(end)) * 100;
    m.delta_T_30min_C = m.T30_C - study.default_temperature_C;
    m.energy_equiv_SOC_delta_per_C_pct = m.energy_equiv_SOC_delta_30min_pct / ...
        max(m.delta_T_30min_C, eps);
    m.E_total_loss_equiv_30min_kWh = E_total_kWh(end);
    m.coulombic_SOC_delta_30min_pct = nan;
    m.I_motor_rms_A = I_motor(1);
end
