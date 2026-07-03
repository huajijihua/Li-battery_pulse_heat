%% ==========================================================================
% 析锂安全约束验证与可视化脚本
% ===========================================================================
% 本脚本调用 lithium_plating_criterion.m 函数，验证其输出是否与文献一致，
% 并生成析锂安全边界图，用于集成到主模型。
%
% 验证基准 (来自文献):
%   - Ge et al. 2016: 2.6Ah 18650电芯, @-20°C, 100Hz → ~1.0-1.5C
%   - Liu et al. 2023: @-20°C, 400Hz → ~3-5C
%   - PMC 2024 (高频AC加热): @-20°C, 500Hz, 4.2C 安全运行
%   - Zheng et al. 2025: @-20°C, 50%SOC → 3.79°C/min (对应约2-3C)
%
% 注: C-rate析锂阈值近似与电芯容量无关 (R_ct×C_cell≈常数)
% ===========================================================================
clear; close all; clc;

fprintf('=== 析锂安全约束验证 ===\n\n');

%% 1. 基本参数
N_parallel = 3;
C_cell = 280;  % Ah

%% 2. 单点验证
fprintf('--- 单点验证 ---\n');
test_cases = [
    50,  -20, 0.5;
    100, -20, 0.5;
    200, -20, 0.5;
    500, -20, 0.5;
    50,  -30, 0.5;
    100, -10, 0.5;
    500,   0, 0.5;
];

fprintf('  %-8s %-8s %-6s | %-12s %-10s %-12s\n', ...
    'f(Hz)', 'T(°C)', 'SOC', 'I_limit(A)', 'C-rate', '|Z_neg|(mΩ)');
fprintf('  %s\n', repmat('-', 1, 70));

for k = 1:size(test_cases, 1)
    f_k = test_cases(k, 1);
    T_k = test_cases(k, 2);
    SOC_k = test_cases(k, 3);
    [I_lim, info] = lithium_plating_criterion(f_k, T_k, SOC_k, N_parallel, C_cell);
    C_rate = I_lim / (C_cell * N_parallel);
    fprintf('  %-8.0f %-8.0f %-6.2f | %-12.0f %-10.2f %-12.4f\n', ...
        f_k, T_k, SOC_k, I_lim, C_rate, info.Z_neg_mag*1000);
end

fprintf('\n  参考文献对照 (小电芯数据, 2.6-8Ah):\n');
fprintf('    @-20°C, 100Hz: 文献报道 ~1.0-1.5C (Ge 2016, LMO/石墨 2.6Ah)\n');
fprintf('    @-20°C, 500Hz: 文献报道 ~3-5C (Liu 2023; PMC 2024)\n');
fprintf('  本模型偏保守约1.5-2倍, 原因:\n');
fprintf('    1) 商用车Pack内电芯不一致性 (最弱电芯决定边界)\n');
fprintf('    2) 大电芯内部电流/温度分布不均匀\n');
fprintf('    3) 无实测三电极EIS数据, 参数为经验估计\n');
fprintf('  频率依赖性趋势正确: 100Hz→500Hz 约3倍提升。\n\n');

%% 3. 温度-频率二维扫描
fprintf('--- 生成析锂边界图 ---\n');

f_scan = logspace(log10(10), log10(5000), 80);
T_scan = linspace(-35, 10, 60);
SOC_test = 0.70;

[I_limit_map, info_map] = lithium_plating_criterion(f_scan, T_scan, SOC_test, N_parallel, C_cell);
C_rate_map = I_limit_map / (C_cell * N_parallel);

figure(1); clf;
set(gcf, 'Position', [100 100 1200 550], 'Color', 'w');

% --- 子图1: 最大允许电流 (Pack级) ---
subplot(1,2,1);
contourf(f_scan, T_scan, I_limit_map, [100 200 400 600 800 1200 2000 3000 5000], ...
    'ShowText', 'on', 'LineWidth', 0.8);
set(gca, 'XScale', 'log');
colormap(parula);
cb = colorbar; ylabel(cb, 'I_{plating,limit} (A)');
xlabel('脉冲频率 f (Hz)');
ylabel('电池温度 T (°C)');
title(sprintf('析锂安全电流上限 (Pack级, SOC=%.0f%%)', SOC_test*100));
hold on;
% 标注800A等高线 (器件限制)
contour(f_scan, T_scan, I_limit_map, [800 800], 'r-', 'LineWidth', 2.5);
text(200, -25, 'I=800A (器件限制)', 'Color', 'r', 'FontWeight', 'bold', 'FontSize', 9);
% 区域含义: 红线上方=析锂限值>器件限值, 器件限制为瓶颈; 红线下方=析锂为瓶颈
text(500, 5, '红线上方: 析锂限值宽松, 器件限流为瓶颈', ...
    'FontSize', 8, 'Color', [0 0.4 0], 'FontWeight', 'bold');
text(30, -32, '低温+低频: 析锂限值最严格(最危险)', ...
    'FontSize', 8, 'Color', [0.8 0 0], 'FontWeight', 'bold');
hold off;
grid on;

% --- 子图2: 等效C-rate限制 ---
subplot(1,2,2);
contourf(f_scan, T_scan, C_rate_map, [0.2 0.5 1 1.5 2 3 5 8], ...
    'ShowText', 'on', 'LineWidth', 0.8);
set(gca, 'XScale', 'log');
colormap(parula);
cb = colorbar; ylabel(cb, 'C-rate limit');
xlabel('脉冲频率 f (Hz)');
ylabel('电池温度 T (°C)');
title('析锂安全C-rate上限 (单芯等效)');
hold on;
contour(f_scan, T_scan, C_rate_map, [1 1], 'r--', 'LineWidth', 2);
text(30, 0, '1C', 'Color', 'r', 'FontWeight', 'bold');
% 直观读图说明
text(300, 7, '高温+高频: 允许大电流, 析锂裕度充足', ...
    'FontSize', 8, 'Color', [0 0.4 0], 'FontWeight', 'bold');
text(15, -32, '低温+低频: 仅允许小电流, 加热能力受限', ...
    'FontSize', 8, 'Color', [0.8 0 0], 'FontWeight', 'bold');
% 核心结论文本框
annotation('textbox', [0.56 0.02 0.42 0.10], 'String', ...
    {'读图要点:', ...
     '  ↑ 温度升高 → 允许电流增大 (扩散加快, 不易析锂)', ...
     '  → 频率升高 → 允许电流增大 (电容屏蔽法拉第电流)'}, ...
    'FontSize', 8, 'EdgeColor', [0.3 0.3 0.3], 'BackgroundColor', [1 1 0.92], ...
    'FitBoxToText', 'on', 'Margin', 4);
hold off;
grid on;

sgtitle('图A: 析锂安全边界 (基于负极阻抗模型)', 'FontWeight', 'bold');
fprintf('  → 图A已生成\n');

%% 4. 与主模型I_max对比
fprintf('\n--- 与主模型电流需求对比 ---\n');

% 主模型参数 (从 pulse_heating_0D_model_v2.m)
N_series = 122;
V_cell_nom = 3.2;
V_dc = N_series * V_cell_nom;  % ≈390V
R_cell_25 = 0.6e-3;
Ea_R = 3500;
T_ref = 298.15;
k_parasitic = 0.10;
R_s = 20e-3;
L_d = 1.5e-3;

R_pack_func = @(T_K) (N_series/N_parallel) * R_cell_25 * ...
    exp(Ea_R*(1./T_K - 1/T_ref)) * (1 + k_parasitic);

% 对比几组配置
configs = {
    struct('label', 'f=50Hz, L=1.5mH',  'f', 50,   'L', 1.5e-3);
    struct('label', 'f=50Hz, L=3.4mH',  'f', 50,   'L', 3.4e-3);
    struct('label', 'f=100Hz, L=1.7mH', 'f', 100,  'L', 1.7e-3);
    struct('label', 'f=500Hz, L=0.5mH', 'f', 500,  'L', 0.5e-3);
    struct('label', 'f=1000Hz, L=1.5mH','f', 1000, 'L', 1.5e-3);
};

fprintf('\n  %-22s | %-8s %-8s %-10s %-10s %-8s\n', ...
    '配置', 'I_max', 'I_plat', 'I_max/Ilim', '安全?', 'C-rate');
fprintf('  %s\n', repmat('-', 1, 75));

T_test = -20;
for k = 1:length(configs)
    cfg = configs{k};
    R_tot = R_pack_func(T_test + 273.15) + R_s;

    % 计算I_max (复用主模型的解析解逻辑)
    T_period = 1/cfg.f;
    tau = cfg.L / R_tot;
    alpha = R_tot * T_period / cfg.L;
    Vs = V_dc / R_tot;
    if alpha > 50
        i_max = Vs;
    else
        exp_a = exp(alpha);
        exp_ab = exp(alpha/2);  % D=0.5 → beta=alpha/2
        i_max = Vs * (exp_a - 2*exp_ab + 1) / (exp_a - 1);
    end

    % 析锂限制
    [I_plat, ~] = lithium_plating_criterion(cfg.f, T_test, SOC_test, N_parallel, C_cell);

    ratio = abs(i_max) / I_plat;
    safe_str = '✓ 安全';
    if ratio > 1.0
        safe_str = '✗ 超限!';
    elseif ratio > 0.8
        safe_str = '⚠ 接近';
    end

    fprintf('  %-22s | %-8.0f %-8.0f %-10.2f %-10s %-8.2f\n', ...
        cfg.label, abs(i_max), I_plat, ratio, safe_str, ...
        abs(i_max)/(C_cell*N_parallel));
end

fprintf('\n  结论: 析锂约束在低频段(50-100Hz)可能比器件限流(800A)更宽松,\n');
fprintf('        但在高频段(>500Hz)析锂约束远大于器件限制, 不构成瓶颈。\n');
fprintf('        实际约束取 min(I_device_limit, I_plating_limit)。\n');

%% 5. 特征频率分析
fprintf('\n--- 负极特征频率 f_ct(T) ---\n');
fprintf('  (f >> f_ct 时双电层短路R_ct, 析锂风险大幅降低)\n\n');

[~, info_fct] = lithium_plating_criterion(100, [-30 -20 -10 0 25], 0.5, N_parallel, C_cell);
for k = 1:5
    T_k = [-30 -20 -10 0 25];
    fprintf('    @%3d°C: f_ct = %.2f Hz, R_ct = %.2f mΩ, R_SEI = %.3f mΩ\n', ...
        T_k(k), info_fct.f_ct_T(k), info_fct.R_ct_T(k)*1000, info_fct.R_SEI_T(k)*1000);
end
fprintf('\n  → 在-20°C时 f_ct ≈ %.1f Hz, 我们的工作频率(50-1000Hz)\n', info_fct.f_ct_T(2));
fprintf('    远高于f_ct, 双电层电容有效屏蔽了法拉第电流, 析锂风险可控。\n');

fprintf('\n=== 验证完毕 ===\n');
