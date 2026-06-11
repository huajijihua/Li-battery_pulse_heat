function plot_frequency_limit_demo()
%PLOT_FREQUENCY_LIMIT_DEMO Demonstrate frequency reduction with/without current limiting.
%
% This figure is an explanatory plot only. It contrasts the open-loop
% voltage-driven trend against the current-limited trend used by the L0.5
% screening model.

    project_root = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    addpath(fullfile(project_root, '02_参数库'));
    addpath(fullfile(project_root, '03_模型源码'));
    addpath(fullfile(project_root, '03_模型源码', 'core'));
    addpath(fullfile(project_root, '03_模型源码', 'limits'));

    p_limited = build_4500_27_pulse_heating_params();
    p_open = p_limited;
    p_open.I_motor_rms_limit_A = inf;
    p_open.I_motor_peak_limit_A = inf;
    p_open.branch_hf_peak_limit_A = inf;

    c = struct();
    c.name = '4500-27三包并联+双电机';
    c.type = 'whole_branch_sync';
    c.branch_count = p_limited.pack_count_vehicle;
    c.motor_count = p_limited.motor_count;

    T_C = p_limited.T_init_C;
    SOC = p_limited.SOC_default;
    duty = p_limited.duty_default;
    mismatch = ones(1, c.branch_count);
    amp_scale = p_limited.current_amplitude_scale_default;
    rho = p_limited.dual_motor_sync_correlation_default;
    f_list = [50 100 250 500 800 1000 1250 1500 2000 3000 4000];

    n = numel(f_list);
    I_open = zeros(n, 1);
    I_limited = zeros(n, 1);
    P_open = zeros(n, 1);
    P_limited = zeros(n, 1);
    eta_open = zeros(n, 1);
    eta_limited = zeros(n, 1);
    current_scale = zeros(n, 1);

    for i = 1:n
        op_open = eval_circuit_operating_point(p_open, c, T_C, SOC, ...
            f_list(i), duty, mismatch, amp_scale, rho);
        op_limited = eval_circuit_operating_point(p_limited, c, T_C, SOC, ...
            f_list(i), duty, mismatch, amp_scale, rho);

        I_open(i) = op_open.I_motor_rms_A;
        I_limited(i) = op_limited.I_motor_rms_A;
        P_open(i) = op_open.P_battery_W / 1000;
        P_limited(i) = op_limited.P_battery_W / 1000;
        eta_open(i) = op_open.heating_efficiency * 100;
        eta_limited(i) = op_limited.heating_efficiency * 100;
        current_scale(i) = op_limited.current_scale;
    end

    wave_100 = make_rl_waveform(p_limited, T_C, SOC, 100, duty, amp_scale);
    wave_1250 = make_rl_waveform(p_limited, T_C, SOC, 1250, duty, amp_scale);
    scale_100 = interp1(f_list, current_scale, 100);
    wave_100_limited = wave_100;
    wave_100_limited.i_A = wave_100_limited.i_A * scale_100;

    fig = figure('Color', 'w', 'Position', [80 80 1200 820]);
    layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', ...
        'Padding', 'compact');

    nexttile;
    semilogx(f_list, I_open, '-o', 'Color', [0.80 0.20 0.15], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.80 0.20 0.15]);
    hold on;
    semilogx(f_list, I_limited, '-s', 'Color', [0.10 0.32 0.70], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.10 0.32 0.70]);
    yline(p_limited.I_motor_rms_limit_A, '--', '550 A限流', ...
        'Color', [0.20 0.20 0.20], 'LineWidth', 1.2);
    xline(p_limited.f_control_min_Hz, ':', '1250 Hz当前下限', ...
        'Color', [0.25 0.25 0.25], 'LineWidth', 1.2);
    grid on;
    xlabel('频率 / Hz');
    ylabel('单电机 RMS 电流 / A');
    title('降频会推高开环电流，但闭环限流会截断');
    legend({'开环等效电压激励', '电控限流后'}, 'Location', 'best');

    nexttile;
    semilogx(f_list, P_open, '-o', 'Color', [0.85 0.38 0.06], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.85 0.38 0.06]);
    hold on;
    semilogx(f_list, P_limited, '-s', 'Color', [0.15 0.55 0.32], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.15 0.55 0.32]);
    xline(p_limited.f_control_min_Hz, ':', '1250 Hz当前下限', ...
        'Color', [0.25 0.25 0.25], 'LineWidth', 1.2);
    grid on;
    xlabel('频率 / Hz');
    ylabel('电池有效发热功率 / kW');
    title('限流后，低频不再等比例转化为加热收益');
    legend({'开环趋势', '限流后'}, 'Location', 'best');

    nexttile;
    plot(wave_100.t_ms, wave_100.i_A, '-', 'Color', [0.80 0.20 0.15], ...
        'LineWidth', 1.5);
    hold on;
    plot(wave_100_limited.t_ms, wave_100_limited.i_A, '--', ...
        'Color', [0.10 0.32 0.70], 'LineWidth', 1.5);
    plot(wave_1250.t_ms, wave_1250.i_A, '-', 'Color', [0.25 0.25 0.25], ...
        'LineWidth', 1.4);
    grid on;
    xlabel('时间 / ms');
    ylabel('等效回路电流 / A');
    title('同一电压占空比下，100 Hz 电流爬升更充分');
    legend({'100 Hz开环', '100 Hz限流缩放', '1250 Hz开环'}, ...
        'Location', 'best');

    ax4 = nexttile;
    yyaxis left;
    semilogx(f_list, current_scale, '-d', 'Color', [0.45 0.20 0.65], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.45 0.20 0.65]);
    ylabel('限流缩放系数');
    ylim([0 1.05]);
    yyaxis right;
    semilogx(f_list, eta_limited, '-^', 'Color', [0.10 0.55 0.60], ...
        'LineWidth', 1.8, 'MarkerFaceColor', [0.10 0.55 0.60]);
    ylabel('限流后加热效率 / %');
    xline(p_limited.f_control_min_Hz, ':', '1250 Hz当前下限', ...
        'Color', [0.25 0.25 0.25], 'LineWidth', 1.2);
    grid on;
    xlabel('频率 / Hz');
    title('低频收益被电流限幅吸收，风险仍保留');
    legend({'current\_scale', '加热效率'}, 'Location', 'best');
    ax4.YAxis(1).Color = [0.45 0.20 0.65];
    ax4.YAxis(2).Color = [0.10 0.55 0.60];

    sgtitle(['4500-27双电机脉冲加热: 降频与电控限流演示, D=', ...
        num2str(duty, '%.2f'), ', T=', num2str(T_C), '℃, SOC=', ...
        num2str(SOC * 100, '%.0f'), '%']);
    layout.Toolbar = [];
    ax_list = findall(fig, 'Type', 'axes');
    for i = 1:numel(ax_list)
        ax_list(i).Toolbar = [];
    end

    out_dir = fullfile(project_root, '05_仿真结果', '4500_27_screening');
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    exportgraphics(fig, fullfile(out_dir, ...
        '4500_27_fig05_frequency_limit_demo.png'), 'Resolution', 220);
end

function wave = make_rl_waveform(p, T_C, SOC, f_Hz, duty, amp_scale)
    R_branch = interp2(p.R_data_SOC, p.R_data_T_C, ...
        p.R_branch_192S1P_table_ohm, SOC, T_C, 'linear');
    R_eq = 1 / sum(1 ./ (R_branch * ones(1, p.pack_count_vehicle)));
    R_loop = p.motor_Rs_ohm + p.motor_count * R_eq;
    Vdc = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap');
    L = p.motor_Ld_H;
    period_s = 1 / f_Hz;
    t_s = linspace(0, period_s, 700);
    i_A = zeros(size(t_s));
    [~, i_max, i_min] = calc_pwm_current_for_wave(Vdc, R_loop, L, f_Hz, duty);
    t_on = duty * period_s;
    tau = L / R_loop;
    Vs = Vdc / R_loop;
    on_idx = t_s <= t_on;
    off_idx = ~on_idx;
    i_A(on_idx) = Vs + (i_min - Vs) .* exp(-t_s(on_idx) ./ tau);
    t_off = t_s(off_idx) - t_on;
    i_A(off_idx) = -Vs + (i_max + Vs) .* exp(-t_off ./ tau);
    wave = struct();
    wave.t_ms = t_s * 1000;
    wave.i_A = i_A * amp_scale;
end

function [i_rms, i_max, i_min] = calc_pwm_current_for_wave(Vdc, R, L, f, D)
    T_period = 1 / f;
    t_on = D * T_period;
    t_off = (1 - D) * T_period;
    tau = L / R;
    Vs = Vdc / R;
    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(t_off / tau);
    denom = exp_a - 1;
    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;

    A1 = i_min - Vs;
    int_sq1 = Vs^2 * t_on + 2 * Vs * A1 * tau * ...
        (1 - exp(-t_on/tau)) + A1^2 * tau/2 * ...
        (1 - exp(-2*t_on/tau));
    A2 = i_max + Vs;
    int_sq2 = Vs^2 * t_off - 2 * Vs * A2 * tau * ...
        (1 - exp(-t_off/tau)) + A2^2 * tau/2 * ...
        (1 - exp(-2*t_off/tau));
    i_rms = sqrt(max((int_sq1 + int_sq2) / T_period, 0));
end
