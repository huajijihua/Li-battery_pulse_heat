%% =========================================================================
% 双电机同相零维脉冲加热模型
% =========================================================================
%
% 适用对象:
%   3806型6x4纯电卡车, 宁德时代L324D06四包2串2并电池系统,
%   双电机 CAM255PT52 / CAM255PT52。
%
% 建模目的:
%   在原单电机零维脉冲加热模型基础上, 增加“双电机同相参与”的拓扑。
%   两台电机不是串联在同一个绕组回路中, 而是接在公共直流母线上的
%   两条并联“逆变器-电机绕组”支路。
%
% 同相假设:
%   两台逆变器输出相同频率、相同占空比、同相位的PWM电压。
%   若两台电机参数一致, 则两条支路电流相同且同相:
%   代码变量名中的pack均指192S2P整车电池组, 不是单个96S1P电池包。
%
%       I_pack(t) = I_motor_1(t) + I_motor_2(t)
%                 = 2 * I_branch(t)
%
% 关键区别:
%   电池内阻是两条支路共用的公共阻抗, 因此不能简单把单电机模型
%   算出来的电池发热功率乘以2。对于N台同相电机, 单支路等效方程为:
%
%       Vdc = Ld * di/dt + Rs * i + N * Rbat_eff * i
%
%   即单支路电流计算时使用:
%
%       R_branch_equiv = Rs + N_motor * Rbat_eff
%
%   然后再计算:
%
%       I_pack_rms = N_motor * I_branch_rms
%       P_bat      = I_pack_rms^2 * Rbat_eff
%
%   若启用平均效率口径, 则外部损耗按整车口径闭合:
%
%       eta_sys   = 90%
%       eta_ctrl  = 96%
%       eta_motor = eta_sys / eta_ctrl = 93.75%
%
%       P_in    = P_bat / eta_sys
%       P_inv   = P_in * (1 - eta_ctrl)
%       P_motor = P_in * eta_ctrl * (1 - eta_motor)
%
%   这样 P_motor + P_inv = P_in - P_bat, 与电池发热严格闭合。
%
% 注意:
%   本脚本是在原单电机系统模型基础上扩展为双电机同相模型。
%   因此后处理必须同时区分:
%     1) 单支路变量 vs 整车电池组总量
%     2) 整车电池组总电流 vs 单台电机支路电流
%   本脚本已切换为3806整车平台参数。电池串并联、能量、质量、内阻、
%   30s/60s低温电流窗口均来自参数汇总表中的实车/实验数据, 但当前
%   高频脉冲可行性计算暂不把低温充放电窗口作为限流约束。
%   电机Rs仍用于电流波形与时间常数; 外部损耗默认采用平均效率口径,
%   详细器件损耗模型保留用于结果诊断; 热边界仍为敏感参数保留。
% =========================================================================

clear; close all; clc;

fprintf('=== 双电机同相零维脉冲加热模型 ===\n');

%% =========================================================================
% 第1部分: 3806整车平台参数
% ==========================================================================

% 旧经验参数已停用。3806平台实车/汇总表参数统一由共享构造函数提供。
[p, USE_DEMO_VALUES] = build_3806_platform_params('dual_inphase');

assert_required_params(p, USE_DEMO_VALUES);

fprintf('平台: 3806 6x4 BEV | %.0fS%.0fP, %.0fV, %.0fkWh | %s x%d\n', ...
    p.N_series, p.N_parallel, p.V_pack_nom, p.E_pack_kWh, ...
    p.motor_name, p.motor_count);
fprintf('控制: f=%.0fHz, D=%.2f, Ld=%.1fuH | 电流窗口: %.0fs %s\n\n', ...
    p.f_sw, p.D, p.L_d*1e6, p.current_window_duration_s, ...
    ternary_text(p.use_current_window_limits, '限流', '仅参考'));

%% =========================================================================
% 第2部分: 单周期稳态电流解析解
% ==========================================================================

fprintf('[初始工作点]\n');

op_dual = calc_operating_point(p, p.motor_count, p.T_init, p.SOC_init);

print_operating_point('双电机同相参与', op_dual);

[t_wave, i_branch_wave_unlimited, v_pwm_wave] = calc_pwm_waveform( ...
    p.V_pack_nom, op_dual.R_branch_equiv, p.L_d, p.f_sw, p.D, 600);
i_branch_wave = i_branch_wave_unlimited * op_dual.current_scale;
i_pack_wave = p.motor_count * i_branch_wave;

figure(1); clf;
set(gcf, 'Position', [80 520 1050 450], 'Color', 'w');

subplot(1,2,1); hold on;
plot(t_wave*1000, i_pack_wave, 'r-', 'LineWidth', 2.0);
yline(op_dual.I_pack_rms, 'k--', sprintf('整车电池组RMS %.0fA', op_dual.I_pack_rms), 'LineWidth', 1.3);
yline(op_dual.I_pack_peak, 'r--', sprintf('整车电池组峰值 %.0fA', op_dual.I_pack_peak), 'LineWidth', 1.2);
yline(-op_dual.I_pack_peak, 'r--', '', 'LineWidth', 1.2);
yline(0, 'k-', 'LineWidth', 0.5);
xlabel('时间 (ms)'); ylabel('电流 (A)');
title('整车电池组实际脉冲电流');
ylim(padded_limits([i_pack_wave(:); op_dual.I_pack_peak; -op_dual.I_pack_peak], 0.10, true));
legend('整车电池组电流 I_{pack}(t)', '整车电池组RMS', '整车电池组峰值', 'Location', 'best');
grid on; hold off;

subplot(1,2,2);
yyaxis left;
stairs(t_wave*1000, v_pwm_wave, 'k-', 'LineWidth', 1.5);
ylabel('逆变器输出电压 (V)');
ylim(padded_limits([-p.V_pack_nom, p.V_pack_nom], 0.15, true));
yyaxis right;
plot(t_wave*1000, i_branch_wave, 'b-', 'LineWidth', 1.6);
yline(p.I_motor_rms_limit, 'g--', sprintf('单支路有效值限 %.0fArms', p.I_motor_rms_limit), 'LineWidth', 1.3);
yline(-p.I_motor_rms_limit, 'g--', '', 'LineWidth', 1.3);
yline(p.I_motor_peak_limit, 'b--', sprintf('单支路峰值限 %.0fApeak', p.I_motor_peak_limit), 'LineWidth', 1.2);
yline(-p.I_motor_peak_limit, 'b--', '', 'LineWidth', 1.2);
ylabel('单支路电流 (A)');
xlabel('时间 (ms)');
title(sprintf('单支路电流与电器限制: f=%.0fHz, L_d=%.1fuH, D=%.2f', ...
    p.f_sw, p.L_d*1e6, p.D));
ylim(padded_limits([i_branch_wave(:); p.I_motor_rms_limit; -p.I_motor_rms_limit; ...
    p.I_motor_peak_limit; -p.I_motor_peak_limit], 0.10, true));
grid on;

sgtitle(sprintf('图1: 双电机同相整车电池组实际脉冲电流 @ T_{init}=%.0f°C', p.T_init), ...
    'FontWeight', 'bold');

%% =========================================================================
% 第3部分: 参数扫描 — I_rms 多维敏感性分析
% ==========================================================================


f_scan = linspace(p.f_control_min, p.f_postprocess_max, 72);
L_scan = linspace(0.03e-3, 0.80e-3, 44);
T_scan = [-20, -10, 0];
[F_grid, L_grid] = meshgrid(f_scan, L_scan);

figure(2); clf;
set(gcf, 'Position', [80 160 1480 460], 'Color', 'w');

for idx_T = 1:numel(T_scan)
    T_cur = T_scan(idx_T);
    I_pack_rms_grid = zeros(size(F_grid));
    I_branch_rms_grid = zeros(size(F_grid));
    I_branch_peak_grid = zeros(size(F_grid));
    electrical_limit_grid = zeros(size(F_grid));
    dTdt_grid = zeros(size(F_grid));

    for i = 1:size(F_grid, 1)
        for j = 1:size(F_grid, 2)
            p_tmp = p;
            p_tmp.f_sw = F_grid(i,j);
            p_tmp.L_d = L_grid(i,j);
            p_tmp.use_ld_lookup = false;
            op_ij = calc_operating_point(p_tmp, p.motor_count, T_cur, p.SOC_init, true);
            I_pack_rms_grid(i,j) = op_ij.I_pack_rms;
            I_branch_rms_grid(i,j) = op_ij.I_branch_rms_raw;
            I_branch_peak_grid(i,j) = op_ij.I_branch_peak_raw;
            electrical_limit_grid(i,j) = max( ...
                op_ij.I_branch_rms_raw / p.I_motor_rms_limit, ...
                op_ij.I_branch_peak_raw / p.I_motor_peak_limit);
            dTdt_grid(i,j) = op_ij.dTdt;
        end
    end

    subplot(1,3,idx_T);
    I_pack_rms_plot = min(I_pack_rms_grid, p.fig2_I_pack_rms_clim(2));
    contourf(F_grid, L_grid*1000, I_pack_rms_plot, ...
        0:100:p.fig2_I_pack_rms_clim(2), ...
        'LineColor', 'none');
    colormap(gca, parula(256));
    cb = colorbar; ylabel(cb, '整车电池组 I_{rms} (A)');
    clim(p.fig2_I_pack_rms_clim);
    hold on;
    contour(F_grid, L_grid*1000, I_pack_rms_plot, ...
        200:200:p.fig2_I_pack_rms_clim(2), ...
        '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.45);
    contour(F_grid, L_grid*1000, dTdt_grid, [1.0 1.0], ...
        '--', 'Color', [0.00 0.95 0.15], 'LineWidth', 2.2);
    contour(F_grid, L_grid*1000, dTdt_grid, [0.5 0.5], ...
        '--', 'Color', [0.00 0.95 1.00], 'LineWidth', 2.0);
    contour(F_grid, L_grid*1000, electrical_limit_grid, [1.0 1.0], ...
        '-', 'Color', [1.00 0.05 0.05], 'LineWidth', 2.6);
    h_limit = xline(p.f_control_max, ':', sprintf('  堵转载频上限 %.0fHz', p.f_control_max), ...
        'Color', [1 1 1], 'LineWidth', 1.8, 'LabelOrientation', 'horizontal', ...
        'LabelVerticalAlignment', 'bottom');
    h_cur = plot(p.f_sw, p.L_d*1000, 'wp', 'MarkerSize', 12, ...
        'MarkerFaceColor', [1 1 1], 'LineWidth', 1.8);
    xlabel('频率 f (Hz)'); ylabel('D轴电感 L_d (mH)');
    title(sprintf('整车电池组 I_{rms} @ %.0f°C, 双电机同相(已计入约束)', T_cur));
    xlim(padded_limits([f_scan, p.f_sw], 0.03, false));
    ylim(p.fig2_L_display_mH);
    set(gca, 'XTick', [100 500 1000 1500 2000 2500 3000]);
    set(gca, 'YTick', [0.05 0.10 0.20 0.40 0.60 0.80]);

    h_leg = gobjects(1, 5);
    leg_labels = cell(1, 5);
    h_leg(1) = plot(nan, nan, '-', 'Color', [1.00 0.05 0.05], 'LineWidth', 2.4);
    leg_labels{1} = '电器限';
    h_leg(2) = plot(nan, nan, '--', 'Color', [0.00 0.95 0.15], 'LineWidth', 2.2);
    leg_labels{2} = '1°C/min';
    h_leg(3) = plot(nan, nan, '--', 'Color', [0.00 0.95 1.00], 'LineWidth', 2.0);
    leg_labels{3} = '0.5°C/min';
    h_leg(4) = h_limit;
    leg_labels{4} = 'f上限';
    h_leg(5) = h_cur;
    leg_labels{5} = '当前';
    lgd2 = legend(h_leg, leg_labels, 'Location', 'southwest', 'FontSize', 6, ...
        'TextColor', 'w', 'Color', [0.18 0.18 0.18], 'EdgeColor', [0.18 0.18 0.18]);
    lgd2.ItemTokenSize = [16 8];
    grid on;
    set(gca, 'GridLineStyle', '--', 'GridColor', [0.55 0.55 0.55], ...
        'GridAlpha', 0.35, 'LineWidth', 1.0, 'Layer', 'top', 'Box', 'on');
    hold off;
end

sgtitle(sprintf('图2: 双电机同相整车电池组 I_{rms}参数扫描 (扩展至%.0fHz, 550Arms/778Apeak电器限制)', p.f_postprocess_max), ...
    'FontWeight', 'bold');

%% =========================================================================
% 第4部分: 净加热判据 — 产热 vs 散热, 温升速率
% ==========================================================================


T_range = linspace(-20, 10, 100);
P_loss_curve = arrayfun(@(T) calc_pack_heat_loss(p, T), T_range);
figure(3); clf;
set(gcf, 'Position', [930 50 900 800], 'Color', 'w');

subplot(2,1,1); hold on;
plot(T_range, P_loss_curve/1000, 'k-', 'LineWidth', 2.4, ...
    'DisplayName', sprintf('散热 P_{loss} (T_{amb}=%.0f°C)', p.T_amb));
P_heat_curve = zeros(size(T_range));
P_motor_curve = zeros(size(T_range));
P_inv_curve = zeros(size(T_range));
P_net_curve = zeros(size(T_range));
for k = 1:numel(T_range)
    op_k = calc_operating_point(p, p.motor_count, T_range(k), p.SOC_init);
    P_heat_curve(k) = op_k.P_bat;
    P_motor_curve(k) = op_k.P_motor;
    P_inv_curve(k) = op_k.P_inv;
    P_net_curve(k) = op_k.P_net;
end
plot(T_range, P_heat_curve/1000, 'LineWidth', 2.0, ...
    'Color', [0.85 0.20 0.20], 'DisplayName', '整车电池组产热 P_{bat}');
plot(T_range, P_net_curve/1000, '--', 'LineWidth', 1.8, ...
    'Color', [0.00 0.55 0.20], 'DisplayName', '双电机净加热 P_{net}');
plot(T_range, P_motor_curve/1000, '-.', 'LineWidth', 1.5, ...
    'Color', [0.90 0.60 0.05], 'DisplayName', '电机铜耗 P_{motor} (主结果)');
plot(T_range, P_inv_curve/1000, '-.', 'LineWidth', 1.5, ...
    'Color', [0.55 0.10 0.80], 'DisplayName', '控制器损耗 P_{inv} (主结果)');
xlabel('电池温度 (°C)'); ylabel('功率 (kW)');
title('电池产热功率 vs 环境散热功率');
h_top = findobj(gca, '-property', 'DisplayName');
legend(flipud(h_top), 'Location', 'northeast');
all_power_curves = [P_loss_curve(:); P_heat_curve(:); P_net_curve(:); ...
    P_motor_curve(:); P_inv_curve(:)];
grid on;
xlim(padded_limits(T_range, 0.03, false));
ylim(padded_limits(all_power_curves/1000, 0.10, true));
hold off;

subplot(2,1,2); hold on;
dTdt_curve = zeros(size(T_range));
for k = 1:numel(T_range)
    op_k = calc_operating_point(p, p.motor_count, T_range(k), p.SOC_init);
    dTdt_curve(k) = op_k.dTdt;
end
plot(T_range, dTdt_curve, 'LineWidth', 2.0, ...
    'Color', [0.85 0.20 0.20], 'DisplayName', '双电机同相');
h_ref1 = yline(1.0, 'r--', '1°C/min', 'LineWidth', 1.4);
h_ref2 = yline(0.5, 'b--', '0.5°C/min', 'LineWidth', 1.4);
h_ref3 = yline(0.15, 'k--', '0.15°C/min', 'LineWidth', 1.2);
h_ref1.Annotation.LegendInformation.IconDisplayStyle = 'off';
h_ref2.Annotation.LegendInformation.IconDisplayStyle = 'off';
h_ref3.Annotation.LegendInformation.IconDisplayStyle = 'off';
xlabel('电池温度 (°C)'); ylabel('温升速率 dT/dt (°C/min)');
title('净温升速率 vs 电池温度');
h_bottom = findobj(gca, 'Type', 'line', '-not', 'LineStyle', '--');
h_bottom = h_bottom(arrayfun(@(x) ~isempty(x.DisplayName), h_bottom));
legend(flipud(h_bottom), 'Location', 'northeast');
grid on;
xlim(padded_limits(T_range, 0.03, false));
ylim(padded_limits([dTdt_curve(:); 1.0; 0.5; 0.15], 0.10, true));
hold off;

sgtitle(sprintf('图3: 净加热判据与温升速率 (T_{amb}=%.0f°C)', p.T_amb), ...
    'FontWeight', 'bold');

%% =========================================================================
% 第5部分: 全动态时域仿真 (电-热耦合)
% ==========================================================================


sim_dual = simulate_case(p, p.motor_count);

fprintf('\n[时域结果]\n');
fprintf('%.0fmin: T=%.2f°C, SOC=%.2f%%\n', ...
    p.t_end_min, sim_dual.T(end), sim_dual.SOC(end)*100);
fprintf('达到%.0f°C时间: %s\n', ...
    p.T_target, format_target_time(sim_dual.t, sim_dual.T, p.T_target));

figure(4); clf;
set(gcf, 'Position', [80 60 1280 850], 'Color', 'w');

subplot(3,2,1); hold on;
plot(sim_dual.t/60, sim_dual.T, 'Color', [0.85 0.20 0.20], 'LineWidth', 1.9);
yline(p.T_target, 'k--', sprintf('目标 %.0f°C', p.T_target));
xlabel('时间 (min)'); ylabel('电池温度 (°C)');
title('温度轨迹');
legend('双电机同相', 'Location', 'best');
grid on;
xlim(padded_limits(sim_dual.t/60, 0.03, false));
ylim(padded_limits([sim_dual.T; p.T_target], 0.08, true));
hold off;

subplot(3,2,2); hold on;
plot(sim_dual.t/60, sim_dual.dTdt, 'Color', [0.85 0.20 0.20], 'LineWidth', 1.8);
yline(1.0, 'r--', '1°C/min');
yline(0.5, 'b--', '0.5°C/min');
xlabel('时间 (min)'); ylabel('dT/dt (°C/min)');
title('瞬时温升速率');
legend('双电机同相', 'Location', 'best');
grid on;
xlim(padded_limits(sim_dual.t/60, 0.03, false));
ylim(padded_limits([sim_dual.dTdt; 1.0; 0.5], 0.12, true));
hold off;

subplot(3,2,3); hold on;
h_cur = [];
cur_labels = {};
h_cur(end+1) = plot(sim_dual.t/60, sim_dual.I_branch_peak, 'b-', 'LineWidth', 1.7);
cur_labels{end+1} = '双电机单支路峰值';
h_cur(end+1) = plot(sim_dual.t/60, sim_dual.I_branch_rms, '-', 'Color', [0.00 0.60 0.20], 'LineWidth', 1.7);
cur_labels{end+1} = '双电机单支路RMS';
h_cur(end+1) = plot(sim_dual.t/60, sim_dual.I_pack_peak, 'r-', 'LineWidth', 1.7);
cur_labels{end+1} = '整车电池组峰值';
h_cur(end+1) = plot(sim_dual.t/60, sim_dual.I_pack_rms, 'k--', 'LineWidth', 1.4);
cur_labels{end+1} = '整车电池组RMS';
if isfinite(p.I_motor_rms_limit)
    h_cur(end+1) = yline(p.I_motor_rms_limit, '--', '单支路RMS限值', 'Color', [0.00 0.60 0.20], 'LineWidth', 1.2);
    cur_labels{end+1} = '单支路RMS限值';
end
if isfinite(p.I_motor_peak_limit)
    h_cur(end+1) = yline(p.I_motor_peak_limit, ':', '单支路Peak限值', 'Color', [0.85 0.10 0.10], 'LineWidth', 1.2);
    cur_labels{end+1} = '单支路Peak限值';
end
if isfinite(p.I_pack_peak_limit)
    h_cur(end+1) = yline(p.I_pack_peak_limit, 'm--', '整车电池组限流');
    cur_labels{end+1} = '整车电池组限流';
end
xlabel('时间 (min)'); ylabel('电流 (A)');
title('电流与安全约束');
legend(h_cur, cur_labels, 'Location', 'best', 'FontSize', 8);
grid on;
xlim(padded_limits(sim_dual.t/60, 0.03, false));
ylim(padded_limits([sim_dual.I_branch_rms; sim_dual.I_branch_peak; ...
    sim_dual.I_pack_peak; sim_dual.I_pack_rms; p.I_motor_rms_limit; ...
    p.I_motor_peak_limit], 0.08, true));
hold off;

subplot(3,2,4); hold on;
plot(sim_dual.t/60, sim_dual.P_bat/1000, '-', 'Color', [0.85 0.20 0.20], 'LineWidth', 1.8);
plot(sim_dual.t/60, sim_dual.P_loss/1000, '-', 'Color', [0.05 0.05 0.05], 'LineWidth', 2.0);
plot(sim_dual.t/60, sim_dual.P_motor/1000, '-', 'Color', [0.90 0.60 0.05], 'LineWidth', 1.6);
plot(sim_dual.t/60, sim_dual.P_inv/1000, '-', 'Color', [0.55 0.10 0.80], 'LineWidth', 1.6);
plot(sim_dual.t/60, sim_dual.P_net/1000, '--', 'Color', [0.00 0.55 0.20], 'LineWidth', 1.8);
xlabel('时间 (min)'); ylabel('功率 (kW)');
title('双电机同相功率分解');
legend('P_{bat}', 'P_{loss}', 'P_{motor}', 'P_{inv}', 'P_{net}', 'Location', 'best');
grid on;
xlim(padded_limits(sim_dual.t/60, 0.03, false));
ylim(padded_limits([sim_dual.P_bat; sim_dual.P_loss; ...
    sim_dual.P_motor; sim_dual.P_inv; sim_dual.P_net]/1000, 0.12, true));
hold off;

subplot(3,2,5);
yyaxis left;
plot(sim_dual.t/60, sim_dual.P_net/1000, '-', 'Color', [0.00 0.55 0.20], 'LineWidth', 1.7);
ylabel('净加热功率 (kW)');
yyaxis right;
plot(sim_dual.t/60, sim_dual.E_cum_MJ, '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.7);
ylabel('累计电耗 (MJ)');
xlabel('时间 (min)');
title('净加热功率与累计电耗');
grid on;
xlim(padded_limits(sim_dual.t/60, 0.03, false));
legend('P_{net}', '累计电耗', 'Location', 'best');

subplot(3,2,6);
yyaxis left;
plot(sim_dual.t/60, sim_dual.SOC*100, '-', 'Color', [0.00 0.30 0.85], 'LineWidth', 1.7);
ylabel('SOC (%)');
yyaxis right;
plot(sim_dual.t/60, sim_dual.T - p.T_init, '-', 'Color', [0.85 0.33 0.10], 'LineWidth', 1.7);
ylabel('累计温升 (°C)');
xlabel('时间 (min)');
title('SOC消耗与累计温升');
grid on;
legend('SOC', '累计温升', 'Location', 'best');

sgtitle(sprintf('图4: 双电机同相全动态时域仿真 @ T_{init}=%.0f°C (%.0fmin)', ...
    p.T_init, p.t_end_min), 'FontWeight', 'bold');

% --- 图5: 能量分配饼图 ---
figure(5); clf;
set(gcf, 'Position', [260 160 720 520], 'Color', 'w');

dual_energy = summarize_energy(sim_dual, p);

pie(max(dual_energy.report.values, 0.001), dual_energy.report.labels);
title({sprintf('图5: %.0fmin能量分配 (显式损耗主结果)', p.t_end_min), ...
    sprintf('总电耗=%.2fMJ, 显式加热效率=%.1f%%', ...
    dual_energy.report.total_MJ, dual_energy.report.eta_sys)}, ...
    'FontWeight', 'bold', 'Interpreter', 'none');

%% =========================================================================
% 第5b部分: 加热效率与SOC电耗 vs 温度
% ==========================================================================


T_eff_scan = -20:2:10;
eta_dual = zeros(size(T_eff_scan));
soc_per_deg_dual = zeros(size(T_eff_scan));

for k = 1:numel(T_eff_scan)
    op2 = calc_operating_point(p, p.motor_count, T_eff_scan(k), p.SOC_init);
    P_total_2 = op2.P_elec;
    eta_dual(k) = op2.P_bat / max(P_total_2, eps) * 100;
    soc_per_deg_dual(k) = (P_total_2 / (p.E_pack_kWh * 3.6e6)) / ...
        max(op2.P_bat / p.Cth_bat, eps) * 100;
end

figure(55); clf;
set(gcf, 'Position', [180 130 1000 680], 'Color', 'w');

subplot(2,1,1); hold on;
plot(T_eff_scan, eta_dual, 'Color', [0.85 0.20 0.20], 'LineWidth', 1.8);
xlabel('电池温度 (°C)'); ylabel('电气加热效率 (%)');
title('电气加热效率 = 电池发热 / (电池发热+铜耗+控制器损耗)');
legend('双电机同相', 'Location', 'best');
grid on;
xlim(padded_limits(T_eff_scan, 0.03, false));
ylim(padded_limits(eta_dual(:), 0.08, false));
hold off;

subplot(2,1,2); hold on;
plot(T_eff_scan, soc_per_deg_dual, 'Color', [0.00 0.30 0.85], 'LineWidth', 1.8);
xlabel('电池温度 (°C)'); ylabel('SOC消耗 (%/°C)');
title('每升高1°C所需SOC消耗');
legend('双电机同相', 'Location', 'best');
grid on;
xlim(padded_limits(T_eff_scan, 0.03, false));
ylim(padded_limits(soc_per_deg_dual(:), 0.08, false));
hold off;

sgtitle(sprintf('图5b: 加热效率与SOC电耗 (显式损耗, f=%.0fHz, L_d=%.1fuH)', ...
    p.f_sw, p.L_d*1e6), 'FontWeight', 'bold');

%% =========================================================================
% 第6部分: 可行性边界图 — (L, f) 参数空间
% ==========================================================================


f_bnd = linspace(p.f_control_min, p.f_postprocess_max, 150);
L_bnd = linspace(p.fig6_L_display_mH(1), p.fig6_L_display_mH(2), 95) * 1e-3;
[F_B, L_B] = meshgrid(f_bnd, L_bnd);

dTdt_map = zeros(size(F_B));
I_branch_rms_map = zeros(size(F_B));
I_branch_peak_map = zeros(size(F_B));
electrical_limit_map = zeros(size(F_B));

for i = 1:size(F_B, 1)
    for j = 1:size(F_B, 2)
        p_tmp = p;
        p_tmp.f_sw = F_B(i,j);
        p_tmp.L_d = L_B(i,j);
        p_tmp.use_ld_lookup = false;
        op_ij = calc_operating_point(p_tmp, p.motor_count, p.T_init, p.SOC_init, true);
        dTdt_map(i,j) = op_ij.dTdt;
        I_branch_rms_map(i,j) = op_ij.I_branch_rms_raw;
        I_branch_peak_map(i,j) = op_ij.I_branch_peak_raw;
        electrical_limit_map(i,j) = max( ...
            op_ij.I_branch_rms_raw / p.I_motor_rms_limit, ...
            op_ij.I_branch_peak_raw / p.I_motor_peak_limit);
    end
end

figure(6); clf;
set(gcf, 'Position', [260 40 1120 760], 'Color', 'w');
hold on;
dTdt_plot = min(max(dTdt_map, p.fig6_dTdt_clim(1)), p.fig6_dTdt_clim(2));
contourf(F_B, L_B*1000, dTdt_plot, ...
    0:0.2:p.fig6_dTdt_clim(2), ...
    'LineColor', 'none');
colormap(gca, parula(256));
cb = colorbar; ylabel(cb, '初始温升速率 dT/dt (°C/min)');
clim(p.fig6_dTdt_clim);
contour(F_B, L_B*1000, dTdt_plot, ...
    0.2:0.2:p.fig6_dTdt_clim(2), ...
    '-', 'Color', [0.55 0.55 0.55], 'LineWidth', 0.45);
h_lines = gobjects(1, 6);
leg_labels = cell(1, 6);
n_lines = 0;
if min(electrical_limit_map(:)) <= 1.0 && max(electrical_limit_map(:)) >= 1.0
    [~, h_elec] = contour(F_B, L_B*1000, electrical_limit_map, [1.0 1.0], ...
        '-', 'Color', [1.00 0.05 0.05], 'LineWidth', 3.0);
    n_lines = n_lines + 1;
    h_lines(n_lines) = h_elec;
    leg_labels{n_lines} = '电器限';
end
if max(dTdt_map(:)) >= 1.0 && min(dTdt_map(:)) <= 1.0
    [~, h4] = contour(F_B, L_B*1000, dTdt_map, [1.0 1.0], '--', 'Color', [0.00 0.95 0.15], 'LineWidth', 2.8);
    n_lines = n_lines + 1;
    h_lines(n_lines) = h4;
    leg_labels{n_lines} = '1°C/min';
end
if max(dTdt_map(:)) >= 0.5 && min(dTdt_map(:)) <= 0.5
    [~, h5] = contour(F_B, L_B*1000, dTdt_map, [0.5 0.5], '--', 'Color', [0.00 0.95 1.00], 'LineWidth', 2.6);
    n_lines = n_lines + 1;
    h_lines(n_lines) = h5;
    leg_labels{n_lines} = '0.5°C/min';
end
h6 = plot(p.f_sw, p.L_d*1000, 'wp', 'MarkerSize', 16, 'MarkerFaceColor', [1 1 1], 'LineWidth', 2.4);
n_lines = n_lines + 1;
h_lines(n_lines) = h6;
leg_labels{n_lines} = '当前';
h_limit6 = xline(p.f_control_max, ':', sprintf('  堵转载频上限 %.0fHz', p.f_control_max), ...
    'Color', [1 1 1], 'LineWidth', 1.8, 'LabelOrientation', 'horizontal', ...
    'LabelVerticalAlignment', 'bottom');
n_lines = n_lines + 1;
h_lines(n_lines) = h_limit6;
leg_labels{n_lines} = 'f上限';
h7 = yline(p.L_d*1000, '-', sprintf('  L_d=%.1fuH', p.L_d*1e6), ...
    'LineWidth', 2.0, 'Color', [1 1 1]);
n_lines = n_lines + 1;
h_lines(n_lines) = h7;
leg_labels{n_lines} = sprintf('L_d %.1fuH', p.L_d*1e6);
h_lines = h_lines(1:n_lines);
leg_labels = leg_labels(1:n_lines);
xlabel('开关频率 f (Hz)'); ylabel('D轴电感 L_d (mH)');
title(sprintf('图6: 双电机同相可行性边界 (T_{init}=%.0f°C, T_{amb}=%.0f°C, SOC_0=%.0f%%)', ...
    p.T_init, p.T_amb, p.SOC_init*100), 'FontWeight', 'bold');
xlim([min(f_bnd), max(f_bnd)]);
ylim(p.fig6_L_display_mH);
set(gca, 'XTick', [100 500 1000 1500 2000 2500 3000]);
set(gca, 'YTick', [0.05 0.08 0.10 0.12 0.15 0.20 0.25 0.30]);
lgd6 = legend(h_lines, leg_labels, 'Location', 'southwest', 'FontSize', 8, ...
    'TextColor', 'w', 'Color', [0.18 0.18 0.18], 'EdgeColor', [0.18 0.18 0.18]);
lgd6.ItemTokenSize = [24 10];
grid on;
set(gca, 'GridLineStyle', '--', 'GridColor', [0.55 0.55 0.55], ...
    'GridAlpha', 0.35, 'LineWidth', 1.1, 'Layer', 'top', 'Box', 'on');
hold off;

%% =========================================================================
% 第7部分: 可行性总结与建议
% ==========================================================================

fprintf('\n图1-图6已生成。\n');
fprintf('口径: 公共电池/直流母线, 两条同相支路; 电池发热按整车电池组总电流, 电机限流按单支路。\n');
fprintf('=== 完成 ===\n');

%% =========================================================================
% 局部函数
% ==========================================================================

function op = calc_operating_point(p, motor_count, T_celsius, SOC, apply_limits)
% 计算给定电机数量下的单个工作点。

    if nargin < 5
        apply_limits = true;
    end

    T_kelvin = T_celsius + 273.15;
    p.current_SOC_for_resistance = SOC;
    R_bat_eff = calc_battery_resistance_eff(p, p.f_sw, T_kelvin);

    [L_d_eff, R_s_eff] = resolve_motor_branch_params(p, motor_count, R_bat_eff);

    % 同相并联支路的关键处理:
    % 单支路电流看到的公共电池内阻等效为 motor_count * R_bat_eff。
    R_branch_equiv = R_s_eff + motor_count * R_bat_eff;

    [I_branch_rms_raw, I_branch_max_raw, I_branch_min_raw, ~] = ...
        calc_pwm_current_v2(p.V_pack_nom, R_branch_equiv, L_d_eff, p.f_sw, p.D);

    I_branch_peak_raw = max(abs(I_branch_max_raw), abs(I_branch_min_raw));
    I_pack_rms_raw = motor_count * I_branch_rms_raw;
    I_pack_max_raw = motor_count * I_branch_max_raw;
    I_pack_min_raw = motor_count * I_branch_min_raw;
    I_pack_peak_raw = motor_count * I_branch_peak_raw;

    current_window = get_current_window_limit(p, T_celsius, SOC);

    current_scale = 1;
    if apply_limits
        scale_candidates = 1;
        if isfinite(p.I_motor_peak_limit) && I_branch_peak_raw > 0
            scale_candidates(end+1) = p.I_motor_peak_limit / I_branch_peak_raw;
        end
        if isfinite(p.I_motor_rms_limit) && I_branch_rms_raw > 0
            scale_candidates(end+1) = p.I_motor_rms_limit / I_branch_rms_raw;
        end
        if isfinite(p.I_pack_peak_limit) && I_pack_peak_raw > 0
            scale_candidates(end+1) = p.I_pack_peak_limit / I_pack_peak_raw;
        end
        if isfinite(p.I_pack_rms_limit) && I_pack_rms_raw > 0
            scale_candidates(end+1) = p.I_pack_rms_limit / I_pack_rms_raw;
        end
        current_scale = max(0, min(scale_candidates));
    end

    I_branch_rms = I_branch_rms_raw * current_scale;
    I_branch_peak = I_branch_peak_raw * current_scale;
    I_branch_max = I_branch_max_raw * current_scale;
    I_branch_min = I_branch_min_raw * current_scale;
    I_pack_rms = I_pack_rms_raw * current_scale;
    I_pack_max = I_pack_max_raw * current_scale;
    I_pack_min = I_pack_min_raw * current_scale;
    I_pack_peak = I_pack_peak_raw * current_scale;

    % 这里把P_bat定义为电池公共内阻上的焦耳热; 双电机同相时该功率由整车电池组总电流决定。
    P_bat = I_pack_rms^2 * R_bat_eff;
    % 外部电器损耗只用于总电耗和热损耗分解, 不并入电池0D热容。
    % 主结果使用显式铜耗/逆变器损耗; 固定效率只保留为量级参考。
    [P_motor, P_inv] = calc_explicit_external_losses( ...
        p, motor_count, I_branch_rms, R_s_eff);
    if p.use_average_loss_model
        [P_motor_diag, P_inv_diag] = calc_average_external_losses(p, P_bat);
    else
        P_motor_diag = P_motor;
        P_inv_diag = P_inv;
    end
    P_loss = calc_pack_heat_loss(p, T_celsius);
    P_net = P_bat - P_loss;
    P_elec = P_bat + P_motor + P_inv;
    P_elec_diag = P_bat + P_motor_diag + P_inv_diag;
    dTdt = P_net / p.Cth_bat * 60;

    op = struct();
    op.motor_count = motor_count;
    op.R_bat_eff = R_bat_eff;
    op.R_s_eff = R_s_eff;
    op.L_d_eff = L_d_eff;
    op.R_branch_equiv = R_branch_equiv;
    op.I_branch_rms = I_branch_rms;
    op.I_branch_peak = I_branch_peak;
    op.I_branch_max = I_branch_max;
    op.I_branch_min = I_branch_min;
    op.I_pack_rms = I_pack_rms;
    op.I_pack_max = I_pack_max;
    op.I_pack_min = I_pack_min;
    op.I_pack_peak = I_pack_peak;
    op.I_branch_rms_raw = I_branch_rms_raw;
    op.I_branch_peak_raw = I_branch_peak_raw;
    op.I_branch_max_raw = I_branch_max_raw;
    op.I_branch_min_raw = I_branch_min_raw;
    op.I_pack_rms_raw = I_pack_rms_raw;
    op.I_pack_max_raw = I_pack_max_raw;
    op.I_pack_min_raw = I_pack_min_raw;
    op.I_pack_peak_raw = I_pack_peak_raw;
    op.current_scale = current_scale;
    op.I_charge_limit = current_window.charge_peak;
    op.I_discharge_limit = current_window.discharge_peak;
    op.current_window_is_limit = current_window.enabled_as_limit;
    op.P_bat = P_bat;
    op.P_motor = P_motor;
    op.P_inv = P_inv;
    op.P_motor_diag = P_motor_diag;
    op.P_inv_diag = P_inv_diag;
    op.P_loss = P_loss;
    op.P_net = P_net;
    op.P_elec = P_elec;
    op.P_elec_diag = P_elec_diag;
    op.dTdt = dTdt;
end

function [L_d_eff, R_s_eff] = resolve_motor_branch_params(p, motor_count, R_bat_eff)
% 根据支路电流水平迭代确定等效Ld, 同时按铜阻温度系数修正Rs。

    R_s_eff = p.R_s;
    if isfield(p, 'use_ld_lookup') && ~p.use_ld_lookup
        L_d_eff = p.L_d;
        return;
    end
    if ~isfield(p, 'Ld_current_bp_A') || isempty(p.Ld_current_bp_A)
        L_d_eff = p.L_d;
        return;
    end

    L_d_eff = p.L_d;
    for k = 1:4
        R_branch = R_s_eff + motor_count * R_bat_eff;
        [I_branch_rms_est, ~, ~, ~] = calc_pwm_current_v2( ...
            p.V_pack_nom, R_branch, L_d_eff, p.f_sw, p.D);
        current_query = max(I_branch_rms_est, p.Ld_current_bp_A(1));
        L_d_next = interp1( ...
            p.Ld_current_bp_A, p.Ld_map_H, current_query, 'linear', 'extrap');
        L_d_next = min(max(L_d_next, min(p.Ld_map_H)), max(p.Ld_map_H));
        if abs(L_d_next - L_d_eff) < 1e-9
            break;
        end
        L_d_eff = L_d_next;
    end
end

function R_hot = apply_copper_temp_correction(R_ref, T_ref_C, T_hot_C, alpha_per_C)
% 铜阻线性温度修正。
    R_hot = R_ref * (1 + alpha_per_C * (T_hot_C - T_ref_C));
end

function sim = simulate_case(p, motor_count)
% 动态温升仿真。

    n_steps = floor(p.t_end_min * 60 / p.dt) + 1;
    t = (0:n_steps-1)' * p.dt;

    T = zeros(n_steps, 1);
    SOC = zeros(n_steps, 1);
    I_branch_rms = zeros(n_steps, 1);
    I_pack_rms = zeros(n_steps, 1);
    I_branch_peak = zeros(n_steps, 1);
    I_pack_peak = zeros(n_steps, 1);
    I_branch_max = zeros(n_steps, 1);
    I_branch_min = zeros(n_steps, 1);
    I_pack_max = zeros(n_steps, 1);
    I_pack_min = zeros(n_steps, 1);
    I_charge_limit = inf(n_steps, 1);
    I_discharge_limit = inf(n_steps, 1);
    P_bat = zeros(n_steps, 1);
    P_motor = zeros(n_steps, 1);
    P_inv = zeros(n_steps, 1);
    P_motor_diag = zeros(n_steps, 1);
    P_inv_diag = zeros(n_steps, 1);
    P_loss = zeros(n_steps, 1);
    P_net = zeros(n_steps, 1);
    P_elec = zeros(n_steps, 1);
    P_elec_diag = zeros(n_steps, 1);
    dTdt = zeros(n_steps, 1);
    E_cum_MJ = zeros(n_steps, 1);
    E_cum_diag_MJ = zeros(n_steps, 1);
    SOC_diag_equiv = zeros(n_steps, 1);

    T(1) = p.T_init;
    SOC(1) = p.SOC_init;
    SOC_diag_equiv(1) = p.SOC_init;

    for k = 1:n_steps
        op = calc_operating_point(p, motor_count, T(k), SOC(k));

        I_branch_rms(k) = op.I_branch_rms;
        I_pack_rms(k) = op.I_pack_rms;
        I_branch_peak(k) = op.I_branch_peak;
        I_pack_peak(k) = op.I_pack_peak;
        I_branch_max(k) = op.I_branch_max;
        I_branch_min(k) = op.I_branch_min;
        I_pack_max(k) = op.I_pack_max;
        I_pack_min(k) = op.I_pack_min;
        I_charge_limit(k) = op.I_charge_limit;
        I_discharge_limit(k) = op.I_discharge_limit;
        P_bat(k) = op.P_bat;
        P_motor(k) = op.P_motor;
        P_inv(k) = op.P_inv;
        P_motor_diag(k) = op.P_motor_diag;
        P_inv_diag(k) = op.P_inv_diag;
        P_loss(k) = op.P_loss;
        P_net(k) = op.P_net;
        P_elec(k) = op.P_elec;
        P_elec_diag(k) = op.P_elec_diag;
        dTdt(k) = op.dTdt;

        if k < n_steps
            % 显式Euler更新: 0D平均功率模型已经把一个PWM周期折算掉了, 因此这里按1 s宏观步长积分。
            T(k+1) = T(k) + op.P_net / p.Cth_bat * p.dt;
            % SOC只扣减正向电耗; 本模型不把再生回灌当作脉冲加热过程的一部分。
            E_step_J = max(op.P_elec, 0) * p.dt;
            E_step_diag_J = max(op.P_elec_diag, 0) * p.dt;
            SOC(k+1) = max(0, SOC(k) - E_step_J / (p.E_pack_kWh * 3.6e6));
            E_cum_MJ(k+1) = E_cum_MJ(k) + E_step_J / 1e6;
            SOC_diag_equiv(k+1) = max(0, SOC_diag_equiv(k) - E_step_diag_J / (p.E_pack_kWh * 3.6e6));
            E_cum_diag_MJ(k+1) = E_cum_diag_MJ(k) + E_step_diag_J / 1e6;
        end
    end

    sim = struct();
    sim.t = t;
    sim.T = T;
    sim.SOC = SOC;
    sim.I_branch_rms = I_branch_rms;
    sim.I_pack_rms = I_pack_rms;
    sim.I_branch_peak = I_branch_peak;
    sim.I_pack_peak = I_pack_peak;
    sim.I_branch_max = I_branch_max;
    sim.I_branch_min = I_branch_min;
    sim.I_pack_max = I_pack_max;
    sim.I_pack_min = I_pack_min;
    sim.I_charge_limit = I_charge_limit;
    sim.I_discharge_limit = I_discharge_limit;
    sim.P_bat = P_bat;
    sim.P_motor = P_motor;
    sim.P_inv = P_inv;
    sim.P_motor_diag = P_motor_diag;
    sim.P_inv_diag = P_inv_diag;
    sim.P_loss = P_loss;
    sim.P_net = P_net;
    sim.P_elec = P_elec;
    sim.P_elec_diag = P_elec_diag;
    sim.dTdt = dTdt;
    sim.E_cum_MJ = E_cum_MJ;
    sim.E_cum_diag_MJ = E_cum_diag_MJ;
    sim.SOC_diag_equiv = SOC_diag_equiv;
end

function energy = summarize_energy(sim, p)
% 汇总双电机同相时域仿真的能量分配, 用于图5。

    E_stored = max(p.Cth_bat * (sim.T(end) - sim.T(1)), 0);
    E_loss = trapz(sim.t, max(sim.P_loss, 0));
    E_motor = trapz(sim.t, max(sim.P_motor, 0));
    E_inv = trapz(sim.t, max(sim.P_inv, 0));
    E_total = trapz(sim.t, max(sim.P_elec, 0));

    E_motor_diag = trapz(sim.t, max(sim.P_motor_diag, 0));
    E_inv_diag = trapz(sim.t, max(sim.P_inv_diag, 0));
    E_total_diag = trapz(sim.t, max(sim.P_elec_diag, 0));

    energy.report.values = [E_stored, E_loss, E_motor, E_inv] / 1e6;
    energy.report.percent = energy.report.values / max(sum(energy.report.values), eps) * 100;
    energy.report.labels = { ...
        sprintf('有效储能 %.2fMJ (%.1f%%)', energy.report.values(1), energy.report.percent(1)), ...
        sprintf('散热 %.2fMJ (%.1f%%)', energy.report.values(2), energy.report.percent(2)), ...
        sprintf('电机铜耗 %.2fMJ (%.1f%%)', energy.report.values(3), energy.report.percent(3)), ...
        sprintf('控制器损耗 %.2fMJ (%.1f%%)', energy.report.values(4), energy.report.percent(4))};
    energy.report.total_MJ = E_total / 1e6;
    energy.report.eta_sys = E_stored / max(E_total, eps) * 100;

    energy.diag.values = [E_stored, E_loss, E_motor_diag, E_inv_diag] / 1e6;
    energy.diag.percent = energy.diag.values / max(sum(energy.diag.values), eps) * 100;
    energy.diag.labels = { ...
        sprintf('有效储能 %.2fMJ (%.1f%%)', energy.diag.values(1), energy.diag.percent(1)), ...
        sprintf('散热 %.2fMJ (%.1f%%)', energy.diag.values(2), energy.diag.percent(2)), ...
        sprintf('电机经验损耗 %.2fMJ (%.1f%%)', energy.diag.values(3), energy.diag.percent(3)), ...
        sprintf('控制器经验损耗 %.2fMJ (%.1f%%)', energy.diag.values(4), energy.diag.percent(4))};
    energy.diag.total_MJ = E_total_diag / 1e6;
    energy.diag.eta_sys = E_stored / max(E_total_diag, eps) * 100;

    energy.values = energy.report.values;
    energy.percent = energy.report.percent;
    energy.labels = energy.report.labels;
    energy.total_MJ = energy.report.total_MJ;
    energy.eta_sys = energy.report.eta_sys;
end

function R_eff = calc_battery_resistance_eff(p, f, T_kelvin)
% 整车电池组等效内阻。默认使用AD02/参数汇总表给出的T-SOC数据插值。

    T_celsius = T_kelvin - 273.15;
    SOC_query = clamp_value(p.current_SOC_for_resistance, ...
        min(p.R_data_SOC), max(p.R_data_SOC));
    T_query = clamp_value(T_celsius, min(p.R_data_T), max(p.R_data_T));

    R_dc = interp_resistance_table(p, T_query, SOC_query);

    if p.use_frequency_resistance_correction
        R_eff = apply_frequency_resistance_correction(p, R_dc, f);
    else
        R_eff = R_dc;
    end
end

function R_dc = interp_resistance_table(p, T_celsius, SOC)
% 根据实测/窗口表T-SOC数据插值得到整车电池组1s等效内阻。

    [Tq, SOCq] = compatible_arrays(T_celsius, SOC);
    R_dc = zeros(size(Tq));
    for idx = 1:numel(Tq)
        R_dc(idx) = interp2(p.R_data_SOC, p.R_data_T, p.R_pack_1s_table, ...
            SOCq(idx), Tq(idx), 'linear');
    end
end

function R_eff = apply_frequency_resistance_correction(p, R_dc, f)
% 预留的频率修正接口。默认关闭, 避免用经验RC模型替代实验数据。

    if ~isfield(p, 'R_ohm_frac') || ~isfield(p, 'R1_frac') || ...
            ~isfield(p, 'C1_pack')
        R_eff = R_dc;
        return;
    end

    tau1 = p.R1_frac .* R_dc .* p.C1_pack;
    R_eff = R_dc .* (p.R_ohm_frac + p.R1_frac ./ (1 + (2*pi*f.*tau1).^2));
end

function [t_wave, i_wave, v_pwm] = calc_pwm_waveform(Vdc, R, L, f, D, n_pts)
% 生成双极性PWM稳态单周期电流波形。

    [~, i_max, i_min, ~] = calc_pwm_current_v2(Vdc, R, L, f, D);
    T_period = 1 / f;
    t_on = D * T_period;
    tau = L / R;
    Vs = Vdc / R;

    t_wave = linspace(0, T_period, n_pts);
    i_wave = zeros(size(t_wave));
    v_pwm = Vdc * ones(size(t_wave));
    v_pwm(t_wave > t_on) = -Vdc;

    for k = 1:n_pts
        t = t_wave(k);
        if t <= t_on
            i_wave(k) = Vs + (i_min - Vs) * exp(-t / tau);
        else
            i_wave(k) = -Vs + (i_max + Vs) * exp(-(t - t_on) / tau);
        end
    end
end

function current_window = get_current_window_limit(p, T_celsius, SOC)
% 低温回充/放电整车电池组峰值窗口。表格来自3806参数汇总, 50%SOC。

    T_query = clamp_value(T_celsius, min(p.current_window_T), max(p.current_window_T));
    if p.current_window_duration_s <= 30
        charge_table = p.current_window_charge_30s;
        discharge_table = p.current_window_discharge_30s;
    else
        charge_table = p.current_window_charge_60s;
        discharge_table = p.current_window_discharge_60s;
    end

    charge_peak = interp1(p.current_window_T, charge_table, T_query, 'linear');
    discharge_peak = interp1(p.current_window_T, discharge_table, T_query, 'linear');

    % 已有窗口表为50%SOC。SOC偏离时先不外推更宽窗口, 只保守收紧高SOC回充能力。
    if SOC > p.current_window_SOC_ref
        charge_peak = charge_peak * max(0.25, 1 - 1.2*(SOC - p.current_window_SOC_ref));
    end

    current_window = struct( ...
        'charge_peak', max(charge_peak, 0), ...
        'discharge_peak', max(discharge_peak, 0), ...
        'enabled_as_limit', p.use_current_window_limits);
end

function [P_motor_loss, P_ctrl_loss] = calc_average_external_losses(p, P_bat)
% 用平均效率口径把电池外电器损耗拆成电机侧和控制器侧。
% P_bat是电池内阻发热, 在此作为脉冲加热的有效电功率; 总输入按90%系统效率闭合。

    eta_sys = max(min(p.eta_motor_ctrl_avg, 1), eps);
    eta_ctrl = max(min(p.eta_ctrl_avg, 1), eps);
    eta_motor = max(min(p.eta_motor_only_avg, 1), eps);

    P_in = P_bat / eta_sys;
    P_ctrl_loss = P_in * (1 - eta_ctrl);
    P_motor_loss = P_in * eta_ctrl * (1 - eta_motor);

    P_motor_loss = max(P_motor_loss, 0);
    P_ctrl_loss = max(P_ctrl_loss, 0);
end

function [P_motor_diag, P_inv_diag] = calc_explicit_external_losses(p, motor_count, I_branch_rms, R_s_eff)
% 显式损耗主结果口径, 用于替代固定效率的主结果计算。

    P_motor_diag = motor_count * I_branch_rms.^2 * R_s_eff;
    P_inv_diag = motor_count * calc_inverter_loss(p, I_branch_rms, p.f_sw, p.V_pack_nom);
end

function P_loss = calc_pack_heat_loss(p, T_celsius)
% 等效整车电池组对环境散热: 对流 + 辐射。
% P_loss为电池向环境流出的热量; 当电池不高于环境温度时不计环境反向加热收益。

    switch lower(string(p.thermal_boundary))
        case "adiabatic_upper_bound"
            P_loss = 0;
        case "thermal_resistance"
            if ~isfinite(p.R_th_pack) || p.R_th_pack <= 0
                error('thermal_resistance模式下R_th_pack必须为正的有限值。');
            end
            P_loss = max(0, (T_celsius - p.T_amb) / p.R_th_pack);
        case "convection_radiation"
            T_bat_K = T_celsius + 273.15;
            T_amb_K = p.T_amb + 273.15;
            Q_conv = p.h_pack_conv * p.A_pack_ext * max(0, T_celsius - p.T_amb);
            Q_rad = p.epsilon_pack * p.sigma_sb * p.A_pack_ext * ...
                max(0, T_bat_K^4 - T_amb_K^4);
            P_loss = Q_conv + Q_rad;
        otherwise
            error('未知热边界类型: %s。', p.thermal_boundary);
    end
end

function P_inv = calc_inverter_loss(p, I_rms, f, V_dc)
% 单台逆变器损耗备用简化模型。默认不调用; 仅在use_average_loss_model=false时用于敏感性比较。

    I_avg = I_rms * 2 / pi;
    P_cond = 2 * (p.V_ce0 * I_avg + p.r_ce * I_rms^2) + ...
             2 * (p.V_f0 * I_avg + p.r_f * I_rms^2);
    E_sw_total = p.E_on + p.E_off + p.E_rr;
    P_sw = 2 * f * E_sw_total * (I_rms / p.I_ref_sw) * (V_dc / p.V_ref_sw);
    P_inv = max(P_cond + P_sw, 0);
end

function [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D)
% 双极性PWM激励下RL负载的稳态电流解析解。

    T_period = 1 / f;
    tau = L / R;
    alpha = R * T_period / L;
    beta = D * alpha;

    if alpha > 50
        i_max = Vdc / R;
        i_min = -Vdc / R;
        i_rms = Vdc / R;
        i_pp = 2 * Vdc / R;
        return;
    end

    Vs = Vdc / R;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(alpha - beta);
    denom = exp_a - 1;

    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;
    i_pp = i_max - i_min;

    A1 = i_min - Vs;
    int_sq1 = Vs^2 * D * T_period ...
        + 2 * Vs * A1 * tau * (1 - exp(-beta)) ...
        + A1^2 * (tau/2) * (1 - exp(-2*beta));

    A2 = i_max + Vs;
    gamma = alpha - beta;
    int_sq2 = Vs^2 * (1-D) * T_period ...
        + 2 * (-Vs) * A2 * tau * (1 - exp(-gamma)) ...
        + A2^2 * (tau/2) * (1 - exp(-2*gamma));

    i_rms = sqrt(max((int_sq1 + int_sq2) / T_period, 0));

    if ~isfinite(i_rms)
        i_rms = 0;
    end
end

function y = clamp_value(x, xmin, xmax)
% 将查询点限制在实验数据覆盖范围内, 不对低温窗口外做危险外推。

    y = min(max(x, xmin), xmax);
end

function [A, B] = compatible_arrays(A, B)
% 支持标量和同尺寸数组组合。

    if isscalar(A) && ~isscalar(B)
        A = A + zeros(size(B));
    elseif ~isscalar(A) && isscalar(B)
        B = B + zeros(size(A));
    elseif ~isequal(size(A), size(B))
        error('查询数组尺寸不一致。');
    end
end

function print_operating_point(label, op)
% 打印工作点。

    if isfield(op, 'current_window_is_limit') && op.current_window_is_limit
        window_text = '限流';
    else
        window_text = '参考';
    end
    fprintf('%s: I支路=%.0f/%.0fA, I整车电池组=%.0f/%.0fA (rms/peak)\n', ...
        label, op.I_branch_rms, op.I_branch_peak, op.I_pack_rms, op.I_pack_peak);
    fprintf('发热: Pbat=%.1fkW, 外损=%.1fkW, dT/dt=%.3f°C/min, scale=%.2f\n', ...
        op.P_bat/1000, (op.P_motor + op.P_inv)/1000, op.dTdt, op.current_scale);
    fprintf('电流窗口: 回充/放电 %.0f/%.0fA (%s)\n', ...
        op.I_charge_limit, op.I_discharge_limit, window_text);
end

function txt = ternary_text(condition, true_text, false_text)
% MATLAB脚本内简单文本选择。

    if condition
        txt = true_text;
    else
        txt = false_text;
    end
end

function target_time = format_target_time(t, T, T_target)
% 目标温度达到时间格式化。

    idx = find(T >= T_target, 1, 'first');
    if isempty(idx)
        target_time = '未在仿真时间内达到';
    else
        target_time = sprintf('%.1f min', t(idx)/60);
    end
end

function lim = padded_limits(values, pad_ratio, symmetric_if_cross_zero)
% 统一给坐标轴留边, 避免结果贴边或由于量级差异而看不清。

    if nargin < 2
        pad_ratio = 0.08;
    end
    if nargin < 3
        symmetric_if_cross_zero = false;
    end

    values = values(isfinite(values));
    if isempty(values)
        lim = [-1 1];
        return;
    end

    vmin = min(values);
    vmax = max(values);
    if symmetric_if_cross_zero && vmin < 0 && vmax > 0
        vmax_abs = max(abs([vmin vmax]));
        pad = max(vmax_abs * pad_ratio, eps);
        lim = [-vmax_abs-pad, vmax_abs+pad];
        return;
    end

    if vmax == vmin
        base = max(abs(vmax), 1);
        pad = base * max(pad_ratio, 0.05);
        lim = [vmin-pad, vmax+pad];
        return;
    end

    span = vmax - vmin;
    pad = span * pad_ratio;
    lim = [vmin-pad, vmax+pad];
end

function assert_required_params(p, use_demo_values)
% 参数完整性检查。

    required_fields = {'V_pack_nom', 'E_pack_kWh', 'N_series', 'N_parallel', ...
        'C_cell', 'M_bat', 'Cp_bat', 'L_d', 'R_s', 'f_sw', 'D', ...
        'f_normal_run_min', 'f_normal_run_max', 'f_stall_carrier_max'};

    for k = 1:numel(required_fields)
        value = p.(required_fields{k});
        if ~isfinite(value) || value <= 0
            error('参数 %s 未填写有效值。请先补充实测/确认参数。', required_fields{k});
        end
    end

    if p.f_control_min <= 0 || p.f_control_max <= p.f_control_min
        error('控制频率扫描范围无效: f_control_min/f_control_max需要为正且上限大于下限。');
    end
    if p.f_normal_run_max <= p.f_normal_run_min
        error('正常运行载频范围无效。');
    end
    if p.f_control_max > p.f_stall_carrier_max * (1 + 1e-9)
        error('脉冲加热控制频率上限不应超过堵转载频上限 %.0fHz。', p.f_stall_carrier_max);
    end
    if p.f_sw < p.f_control_min || p.f_sw > p.f_control_max
        error('当前f_sw=%.0fHz超出脉冲加热控制范围 %.0f-%.0fHz。', ...
            p.f_sw, p.f_control_min, p.f_control_max);
    end

    if p.A_pack_ext <= 0 || p.h_pack_conv < 0 || p.epsilon_pack < 0 || p.epsilon_pack > 1
        error('热边界参数无效: A_pack_ext需为正, h_pack_conv需非负, epsilon_pack需在[0,1]。');
    end

    if isfinite(p.I_motor_rms_limit) && isfinite(p.I_motor_peak_limit)
        expected_peak = p.I_motor_rms_limit * sqrt(2);
        if abs(p.I_motor_peak_limit - expected_peak) > max(1e-6, 0.01 * expected_peak)
            error('电机峰值电流限制应与RMS口径一致: I_peak = I_rms*sqrt(2)。');
        end
    end

    if p.use_average_loss_model
        if p.eta_motor_ctrl_avg <= 0 || p.eta_motor_ctrl_avg > 1 || ...
                p.eta_ctrl_avg <= 0 || p.eta_ctrl_avg > 1
            error('平均效率必须在(0, 1]范围内。');
        end
        if p.eta_motor_ctrl_avg > p.eta_ctrl_avg
            error('电机+控制器系统效率不应高于控制器效率, 否则推得的电机效率会超过100%%。');
        end
        if abs(p.eta_motor_only_avg - p.eta_motor_ctrl_avg / p.eta_ctrl_avg) > 1e-9
            error('eta_motor_only_avg需要等于 eta_motor_ctrl_avg/eta_ctrl_avg。');
        end
    end

    if ~isfield(p, 'R_pack_1s_table') || isempty(p.R_pack_1s_table)
        error('缺少实验/窗口表支撑的 R_pack_1s_table。');
    end
    if size(p.R_pack_1s_table, 1) ~= numel(p.R_data_T) || ...
            size(p.R_pack_1s_table, 2) ~= numel(p.R_data_SOC)
        error('R_pack_1s_table尺寸必须匹配 R_data_T 和 R_data_SOC。');
    end

    if p.use_current_window_limits
        current_fields = {'current_window_T', 'current_window_charge_30s', ...
            'current_window_discharge_30s', 'current_window_charge_60s', ...
            'current_window_discharge_60s'};
        for k = 1:numel(current_fields)
            if ~isfield(p, current_fields{k}) || isempty(p.(current_fields{k}))
                error('缺少低温电流窗口字段 %s。', current_fields{k});
            end
        end
    end

    if use_demo_values
        return;
    end
end
