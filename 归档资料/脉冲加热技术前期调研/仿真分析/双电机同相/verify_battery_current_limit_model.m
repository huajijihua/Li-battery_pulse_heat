%% =========================================================================
% 3806零维脉冲加热电池侧电流限制模型验证
% =========================================================================
% 目的:
%   1) 对比电芯规格书30s/60s低温窗口与高频析锂自适应限值;
%   2) 验证1250Hz、双电机同相工况下应使用Pack级电流比较;
%   3) 给主模型的 battery_current_limit_mode 提供数值检查。
% =========================================================================

clear; clc;

fprintf('=== 3806电池侧电流限制模型验证 ===\n\n');

[p, ~] = build_3806_platform_params('dual_inphase_lowtemp_window');

N_parallel = p.N_parallel;
C_cell = p.C_cell;
SOC = p.SOC_init;
f = p.f_sw;
T_list = [-20 -10 -5 0 10];

R_s = p.R_s;
L_d = p.L_d;
R_bat_eff_ref = interp2(p.R_data_SOC, p.R_data_T, p.R_pack_1s_table, SOC, -20, 'linear');
params = build_3806_battery_limit_params(p, R_s + p.motor_count * R_bat_eff_ref, L_d);

fprintf('  %-8s %-12s %-12s %-14s %-12s %-10s\n', ...
    'T(C)', 'Spec30_chg', 'Spec60_chg', 'Plating_chg', 'C-rate', 'Mode_chg');
fprintf('  %s\n', repmat('-', 1, 78));

for k = 1:numel(T_list)
    T = T_list(k);

    p30 = params;
    p30.current_window_duration_s = 30;
    [lim30, info30] = battery_current_limit_model(f, T, SOC, N_parallel, C_cell, p30);

    p60 = params;
    p60.limit_mode = 'spec_window';
    p60.current_window_duration_s = 60;
    [lim60, ~] = battery_current_limit_model(f, T, SOC, N_parallel, C_cell, p60);

    fprintf('  %-8.0f %-12.0f %-12.0f %-14.0f %-12.2f %-10.0f\n', ...
        T, lim30.spec_charge_peak, lim60.charge_peak, ...
        lim30.plating_charge_peak, info30.C_rate_plating, lim30.charge_peak);
end

fprintf('\n解释:\n');
fprintf('  Spec30/Spec60 是规格书低温脉冲回充窗口, 不直接代表kHz交流加热上限。\n');
fprintf('  Plating_chg 是高频负极极化析锂判据给出的Pack峰值回充限制。\n');
fprintf('  plating_adaptive模式下, 主模型用Plating_chg限制负半周回充峰值。\n\n');

% 简化复算当前主模型初始点的原始电流需求, 只用于口径检查。
V_pack_nom = 192 * 3.22;
R_bat_eff = R_bat_eff_ref;
motor_count = p.motor_count;
D = 0.50;
R_branch_equiv = R_s + motor_count * R_bat_eff;
[I_branch_rms, I_branch_max, I_branch_min] = calc_pwm_current_v2( ...
    V_pack_nom, R_branch_equiv, L_d, f, D);
I_pack_peak = motor_count * max(abs(I_branch_max), abs(I_branch_min));

[lim_init, ~] = battery_current_limit_model(f, -20, SOC, N_parallel, C_cell, params);
scale_by_plating = lim_init.charge_peak / I_pack_peak;

fprintf('当前双电机同相口径检查 @ -20C, %.0fHz:\n', f);
fprintf('  单支路原始RMS %.0fA, Pack原始峰值 %.0fA\n', I_branch_rms, I_pack_peak);
fprintf('  高频析锂回充峰值 %.0fA, 对应电池侧scale %.2f\n', ...
    lim_init.charge_peak, scale_by_plating);
fprintf('  注意: 析锂/BMS/规格书窗口看Pack总电流, 器件限流看单支路电流。\n');

fprintf('\n=== 验证完成 ===\n');

function [i_rms, i_max, i_min] = calc_pwm_current_v2(Vdc, R, L, f, D)
    T_period = 1 / f;
    t_on = D * T_period;
    t_off = (1 - D) * T_period;
    tau = L / R;
    Vs = Vdc / R;

    if L <= 0
        i_max = Vs;
        i_min = -Vs;
        i_rms = Vs;
        return;
    end

    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(t_off / tau);
    denom = exp_a - 1;

    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;

    A1 = i_min - Vs;
    int_sq1 = Vs^2 * t_on + 2 * Vs * A1 * tau * (1 - exp(-t_on/tau)) + ...
        A1^2 * tau/2 * (1 - exp(-2*t_on/tau));
    A2 = i_max + Vs;
    int_sq2 = Vs^2 * t_off - 2 * Vs * A2 * tau * (1 - exp(-t_off/tau)) + ...
        A2^2 * tau/2 * (1 - exp(-2*t_off/tau));
    i_rms = sqrt(max((int_sq1 + int_sq2) / T_period, 0));
end
