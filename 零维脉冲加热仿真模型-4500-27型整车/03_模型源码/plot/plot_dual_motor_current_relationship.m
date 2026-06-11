function fig = plot_dual_motor_current_relationship(result, p, ~)
%PLOT_DUAL_MOTOR_CURRENT_RELATIONSHIP Curves for dual-motor sync risk.
% The figure uses battery-side equivalent currents for L0.5 risk screening;
% it is not a three-phase PWM/dq waveform or DC-link dynamic model.

    if nargin < 1 || isempty(result)
        error('result table is required.');
    end

    sync_rows = result.sensitivity(strcmp(result.sensitivity.sensitivity_axis, ...
        'dual_motor_sync_correlation'), :);
    if isempty(sync_rows)
        error('dual_motor_sync_correlation rows are missing.');
    end
    sync_rows = sortrows(sync_rows, 'motor_sync_correlation');

    fig = figure('Name', '4500-27 双电机同步相关性曲线', ...
        'Color', 'w', 'Position', [80 80 1550 900]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_equivalent_current_waveforms(sync_rows);

    nexttile;
    plot_battery_heat_factor(sync_rows);

    nexttile;
    plot_temperature_and_heat(sync_rows, p);

    nexttile;
    plot_heating_efficiency(sync_rows);

    hide_axes_toolbars(fig);
end

function plot_equivalent_current_waveforms(sync_rows)
    I_rms = sync_rows.I_motor_rms_A(end);
    f = sync_rows.frequency_Hz(end);
    t = linspace(0, 2 / f, 1200);
    rho_list = [1 0.5 0 -0.5];
    colors = sync_colors(numel(rho_list));

    hold on;
    for k = 1:numel(rho_list)
        rho = rho_list(k);
        phi = acos(max(min(rho, 1), -1));
        i1 = sqrt(2) * I_rms * sin(2 * pi * f * t);
        i2 = sqrt(2) * I_rms * sin(2 * pi * f * t + phi);
        ibus = i1 + i2;
        plot(t * 1000, ibus, 'LineWidth', 1.8, 'Color', colors(k, :), ...
            'DisplayName', sprintf('rho=%.1f, Ibus RMS=%.0fA', ...
            rho, rms(ibus)));
    end
    hold off;
    xlabel('时间 (ms)');
    ylabel('母线合成等效电流 (A)');
    title('同一单电机RMS下, 同步相关性改变母线合成RMS');
    subtitle('正弦等效示意; PWM/不同频在L0.5中用rho表示平均交叉项');
    legend('Location', 'eastoutside');
    grid on;
end

function plot_battery_heat_factor(sync_rows)
    bar(sync_rows.motor_sync_correlation, ...
        sync_rows.battery_heating_sync_factor, 0.55, ...
        'FaceColor', [0.18 0.43 0.68]);
    xlabel('双电机电池侧同步相关系数 rho');
    ylabel('相对理想同步的电池发热系数');
    title('同步失配削弱电池I^2R热源');
    ylim([0 1.05]);
    grid on;
end

function plot_temperature_and_heat(sync_rows, p)
    rho = sync_rows.motor_sync_correlation;
    temp_color = [0.00 0.45 0.74];
    heat_color = [0.85 0.33 0.10];

    yyaxis left;
    ax = gca;
    ax.YColor = temp_color;
    plot(rho, sync_rows.T_30min_C, '-o', 'LineWidth', 2.0, ...
        'Color', temp_color, 'MarkerFaceColor', 'w');
    yline(p.T_target_C, 'k:', '0C目标', 'LineWidth', 1.1);
    ylabel('30min平均电池温度 (C)');

    yyaxis right;
    ax.YColor = heat_color;
    plot(rho, sync_rows.P_battery_initial_kW, '--s', 'LineWidth', 1.8, ...
        'Color', heat_color, 'MarkerFaceColor', 'w');
    ylabel('初始电池发热功率 (kW)');

    xlabel('双电机电池侧同步相关系数 rho');
    title('同步相关性下降后的温升和电池发热');
    grid on;
end

function plot_heating_efficiency(sync_rows)
    rho = sync_rows.motor_sync_correlation;
    eff_color = [0.49 0.18 0.56];
    loss_color = [0.47 0.67 0.19];

    yyaxis left;
    ax = gca;
    ax.YColor = eff_color;
    plot(rho, sync_rows.heating_efficiency_initial_pct, '-d', ...
        'LineWidth', 2.0, 'Color', eff_color, 'MarkerFaceColor', 'w');
    ylabel('电池加热效率 P_{batt}/P_{loss,total} (%)');

    yyaxis right;
    ax.YColor = loss_color;
    plot(rho, sync_rows.P_total_loss_equiv_initial_kW, '--o', ...
        'LineWidth', 1.8, 'Color', loss_color, 'MarkerFaceColor', 'w');
    ylabel('初始总损耗功率 (kW)');

    xlabel('双电机电池侧同步相关系数 rho');
    title('同步失配会降低电池加热效率');
    subtitle('电机/逆变器损耗未随rho同比下降, 热源从电池侧转向电驱侧');
    grid on;
end

function colors = sync_colors(n)
    base = [ ...
        0.00 0.45 0.74; ...
        0.85 0.33 0.10; ...
        0.93 0.69 0.13; ...
        0.49 0.18 0.56; ...
        0.47 0.67 0.19];
    colors = base(1:n, :);
end

function hide_axes_toolbars(fig)
    axes_handles = findall(fig, 'Type', 'axes');
    for k = 1:numel(axes_handles)
        try
            axtoolbar(axes_handles(k), {});
        catch
        end
    end
end
