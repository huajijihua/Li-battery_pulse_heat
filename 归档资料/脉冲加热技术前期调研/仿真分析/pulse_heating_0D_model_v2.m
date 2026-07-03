%% ==========================================================================
% 零维脉冲加热系统模型 V2.1 — 方案1（软件策略）可行性分析
% ===========================================================================
%
% ┌─────────────────────────────────────────────────────────────────────┐
% │                    建 模 原 理 说 明                                 │
% └─────────────────────────────────────────────────────────────────────┘
%
% 【物理拓扑】
%   电池组(V_oc, R_bat) ─→ 逆变器(IGBT全桥) ─→ 电机绕组(L_d, R_s, 堵转)
%
%   堵转条件下(ω=0)，电机无反电动势，三相绕组等效为单相RL串联负载。
%   逆变器输出双极性PWM方波：+V_dc (占空比D) / -V_dc (占空比1-D)。
%
% 【电路方程 — 稳态解析解】
%   RL串联电路在双极性PWM激励下的微分方程：
%
%   状态1 (0 ≤ t < DT):   V_dc = L·di/dt + R·i
%     解: i₁(t) = Vs + (I_min - Vs)·exp(-t/τ)
%     其中 Vs = V_dc/R (饱和电流), τ = L/R (时间常数)
%
%   状态2 (DT ≤ t < T):  -V_dc = L·di/dt + R·i
%     解: i₂(t') = -Vs + (I_max + Vs)·exp(-t'/τ),  t' = t - DT
%
%   周期性边界条件: i₁(DT) = I_max,  i₂((1-D)T) = I_min
%
%   联立求解得稳态极值电流:
%     I_max = Vs·(e^α - 2·e^(α-β) + 1) / (e^α - 1)
%     I_min = Vs·(2·e^β - e^α - 1) / (e^α - 1)
%
%   其中: α = R·T_period/L (周期/时间常数比)
%         β = D·α (导通时间对应的无量纲参数)
%
%   特殊情况 D=0.5:
%     I_max = Vs·tanh(α/4),  I_min = -I_max (对称)
%
% 【RMS电流 — 解析积分】
%   I_rms² = (1/T)·[∫₀^{DT} i₁(t)² dt + ∫_{DT}^{T} i₂(t')² dt]
%
%   对指数函数平方积分:
%   ∫[A + B·e^{-t/τ}]² dt = A²·t + 2ABτ(1-e^{-t/τ}) + B²·(τ/2)(1-e^{-2t/τ})
%
% 【产热模型 — 1-RC Thevenin等效电路 (V2.1升级)】
%   电池等效电路: R_ohm + R1//C1
%   有效电阻: R_bat_eff(f,T) = R_ohm(T) + R1(T)/(1+(2πf·R1(T)·C1)²)
%
%   电池产热: P_bat = I_rms² · R_bat_eff(f,T)  [欧姆热 + 极化热]
%   电机铜耗: P_motor = I_rms² · R_s            [损失, 不加热电池]
%   总电耗:   P_elec = I_rms² · (R_bat_eff + R_s)
%
%   物理含义:
%   - 高频(f>>f_p): C1短路R1, R_bat_eff→R_ohm, 阻抗低→电流大→产热增加
%   - 低频(f<<f_p): C1开路, R_bat_eff→R_ohm+R1=DCIR, 与纯欧姆模型一致
%   - 特征频率: f_p(T) = 1/(2π·R1(T)·C1), 低温时f_p降低
%
%   相比V2.0纯欧姆模型的改进:
%   - 高频段(>200Hz)预测产热功率提升20-50% (更准确, 不再过度保守)
%   - 低频段(<50Hz)结果基本不变
%   - 自然解释了"高频AC加热效率更高"的物理机制
%
% 【热模型 — 集总参数法】
%   C_th · dT/dt = P_bat - (T - T_amb)/R_th
%
%   其中: C_th = M_bat · Cp_bat  [J/K] 电池Pack总热容
%         R_th [K/W] Pack对环境等效热阻(液冷关闭)
%
% 【内阻温度依赖 — Arrhenius模型】
%   R_cell(T) = R_cell_25 · exp[Ea·(1/T - 1/T_ref)]
%   R_pack(T) = (N_s/N_p) · R_cell(T) · (1 + k_parasitic)
%
%   Ea: 活化能参数 [K], 由EIS或HPPC数据拟合
%   k_parasitic: 母排/连接件/继电器附加电阻比例
%
% 【SOC消耗 — 库仑计数】
%   dSOC/dt = -P_elec / (V_nom · Q_nom · 3600)
%
% 【效率定义】
%   电气转换效率: η_elec = R_bat / (R_bat + R_s)
%   (表征电能中有多少比例转化为电池内部热量)
%
%   系统加热效率: η_sys = ΔT·C_th / E_total_consumed
%   (表征消耗的总电能中有多少转化为电池温升)
%
% 【模型假设与适用范围】
%   1. 电池组集总参数(0D), 单一温度节点, 忽略内部温差
%   2. 电机堵转(ω=0), 无反电动势, 绕组等效为RL串联
%   3. 逆变器理想化: 无死区、无开关损耗、无母线电压波动
%   4. 单相等效(三相中取d轴等效或两相导通等效)
%   5. 准稳态假设: 每个热步长内电流达到周期稳态
%   6. 1-RC等效电路: 含极化阻抗R1//C1, 基波频率近似
%   7. OCV恒定(LFP平台区内误差<3%)
%   8. 析锂安全约束: 基于负极阻抗模型 (V2.0新增)
%
% 【输出】
%   Fig 1: 单周期稳态电流波形
%   Fig 2: I_rms 参数扫描 (f × L × T), 含精确dT/dt等高线
%   Fig 3: 净加热功率与温升速率 (多配置对比)
%   Fig 4: 全动态温升仿真 (30分钟)
%   Fig 5: 能量分配饼图 (有效储能/散热/铜耗/逆变器)
%   Fig 6: 可行性边界图 (L-f 参数空间)
%
% 作者: 动力总成前瞻部
% 日期: 2026-05-09
% 版本: V2.2 (修正能量饼图、dT/dt等高线、析锂波形修正因子)
% ===========================================================================
clear; close all; clc;

fprintf('=== 脉冲加热零维系统模型 V2.2 ===\n');
fprintf('方案: 软件策略 — 复用电机逆变器\n');
fprintf('升级: 1-RC Thevenin等效电路 + 析锂安全约束(含波形修正)\n\n');

%% =========================================================================
% 第1部分: 参数定义
% ==========================================================================
fprintf('--- 第1部分: 参数定义 ---\n');

% -------------------------------------------------------------------
% 1.1 电池组参数 (商用车 LFP, 参考一汽解放纯电重卡)
% -------------------------------------------------------------------
% 电芯: LFP方形电芯, 3.2V/280Ah, 能量型
%   供应商: 宁德时代/福鼎时代
% 成组: 122串 × 3并 = 366颗电芯, 总电量约328kWh
%   匹配当前390V平台整包配置
% 注: 实测数据到货后请替换以下参数

N_series = 122;              % 串联电芯数 (122×3.2V≈390V)
N_parallel = 3;              % 并联数
V_cell_nom = 3.2;            % 单芯额定电压 [V]
C_cell = 280;                % 单芯容量 [Ah]
V_pack_nom = N_series * V_cell_nom;  % Pack额定电压 [V] 
E_pack_kWh = V_pack_nom * C_cell * N_parallel / 1000;  % Pack总电量 [kWh]

fprintf('  电池组: %dS%dP, 额定电压 %.0f V, 总容量 %.0f Ah, 总电量 %.0f kWh\n', ...
    N_series, N_parallel, V_pack_nom, C_cell * N_parallel, E_pack_kWh);

% --- 电池内阻 R_bat(T) ---
% Arrhenius模型: R(T) = R_25 * exp(Ea*(1/T - 1/T_ref))
% 参考: 大容量LFP方形电芯典型DCIR ~0.6mΩ @25°C, ~5mΩ @-20°C
R_cell_25 = 0.6e-3;          % 单芯内阻 @25°C [Ω]
Ea_R = 3500;                 % Arrhenius活化能参数 [K] (需EIS数据校核)
T_ref = 298.15;              % 参考温度 [K]

% Pack寄生电阻 (母排、连接件、继电器、熔断器)
k_parasitic = 0.10;          % 寄生电阻占比 (典型10%)

% Pack总内阻函数 (含寄生) — DCIR (直流极限)
R_pack_func = @(T_kelvin) (N_series / N_parallel) * R_cell_25 * ...
    exp(Ea_R * (1./T_kelvin - 1/T_ref)) * (1 + k_parasitic);

% -------------------------------------------------------------------
% 1-RC Thevenin 等效电路参数 (V2.1 新增)
% -------------------------------------------------------------------
% 将DCIR拆分为: R_ohm (欧姆) + R1//C1 (极化)
%
%   ┌─── R_ohm ───┬─── R1 ───┐
%   │              │          │
%   +  V_oc       C1         + V_terminal
%   │              │          │
%   └──────────────┴──────────┘
%
% 物理含义:
%   R_ohm: 电解液离子电导 + 接触电阻 + SEI膜电阻 (瞬态响应)
%   R1:    电荷转移电阻 (法拉第过程, 频率相关)
%   C1:    双电层电容 (决定极化时间常数 τ1 = R1×C1)
%
% 频率效应:
%   f >> f_p: C1短路R1 → Z_bat ≈ R_ohm (高频加热更高效)
%   f << f_p: C1开路   → Z_bat ≈ R_ohm + R1 = DCIR
%   f_p = 1/(2π·τ1) 为极化特征频率
%
% 参考文献:
%   Ruan H et al. Applied Energy, 2016, 177: 771-782 (阻抗模型)
%   Zhu J et al. J Power Sources, 2019, 427: 220-228 (EIS参数辨识)
%   Xie Y et al. Applied Energy, 2025, 391 (AC加热阻抗热模型)

R_ohm_frac = 0.65;          % 欧姆电阻占DCIR比例 (典型60-70%)
R1_frac = 0.35;             % 极化电阻占DCIR比例 (典型30-40%)
C1_cell = 1.0;              % 单芯极化电容 [F] (双电层, 大面积电芯)
                             % 参考: 比电容~20μF/cm², 面积~50000cm² → ~1F

% Pack等效极化电容 (串并联变换: C_pack = C_cell × N_p / N_s)
C1_pack = C1_cell * N_parallel / N_series;  % [F]

% 有效电池电阻函数 (频率相关, 核心升级!)
% R_bat_eff(f,T) = R_pack(T) × [R_ohm_frac + R1_frac / (1 + (2πf·τ1)²)]
% 其中 τ1(T) = R1_frac × R_pack(T) × C1_pack (Pack级时间常数)
% 注: τ1 = R1_cell × C1_cell (与成组方式无关)
R_bat_eff_func = @(f, T_kelvin) R_pack_func(T_kelvin) .* (...
    R_ohm_frac + R1_frac ./ ...
    (1 + (2*pi*f .* R1_frac .* R_pack_func(T_kelvin) .* C1_pack).^2));

% 验证几个温度点
fprintf('  电池Pack内阻估算 (1-RC Thevenin模型):\n');
fprintf('  %-6s %-12s %-12s %-12s %-10s %-10s\n', ...
    'T(°C)', 'DCIR(mΩ)', 'R_ohm(mΩ)', 'R1(mΩ)', 'τ1(ms)', 'f_p(Hz)');
for T_check = [-30, -20, -10, 0, 25]
    T_K = T_check + 273.15;
    R_dc = R_pack_func(T_K);
    R_ohm_k = R_ohm_frac * R_dc;
    R1_k = R1_frac * R_dc;
    tau1_k = R1_k * C1_pack;
    f_p_k = 1 / (2*pi*tau1_k);
    fprintf('  %4d°C  %8.1f     %8.1f     %8.1f    %7.3f   %7.1f\n', ...
        T_check, R_dc*1000, R_ohm_k*1000, R1_k*1000, tau1_k*1000, f_p_k);
end
fprintf('  频率效应示例 (@-20°C):\n');
T_K_demo = -20 + 273.15;
for f_demo = [50, 100, 500, 1000]
    R_eff_demo = R_bat_eff_func(f_demo, T_K_demo);
    ratio_demo = R_eff_demo / R_pack_func(T_K_demo) * 100;
    fprintf('    f=%4dHz: R_bat_eff=%.1fmΩ (DCIR的%.0f%%)\n', ...
        f_demo, R_eff_demo*1000, ratio_demo);
end

% --- 电池组热参数 ---
% 比热容: 典型LFP电芯~1000 J/(kg·K), Pack含结构件取~950
% Pack质量: 328kWh / 82Wh/kg(Pack级) ≈ 4000 kg
Cp_bat = 950;                % 电池Pack等效比热容 [J/(kg·K)]
M_bat = 4000;                % 电池Pack总质量 [kg]
Cth_bat = Cp_bat * M_bat;    % 总热容 [J/K] = 3.8e6 J/K

% 等效热阻 (液冷关闭, 自然对流+辐射+传导散热)
% 典型Pack在-20°C静置时自然冷却速率 ~0.02°C/min
% R_th ≈ ΔT / (C_th * dT/dt) ≈ 20 / (3.8e6 * 0.02/60) ≈ 0.016 K/W
R_th_pack = 0.015;           % Pack对外等效热阻 [K/W]

fprintf('  热参数: C_th = %.2e J/K (%.1f kJ/°C), R_th = %.4f K/W\n', ...
    Cth_bat, Cth_bat/1000, R_th_pack);
fprintf('  热时间常数 τ_th = C_th × R_th = %.1f h\n', Cth_bat*R_th_pack/3600);

% -------------------------------------------------------------------
% 1.2 电机参数 (盘毂520s, TZ430XS200, 堵转工况)
% -------------------------------------------------------------------
% 盘毂电机实测参数 (来源: 供应商数据手册)
% 额定功率300kW, 峰值功率438kW, 12极对数, 内嵌式永磁
% 额定母线电压390VDC, 峰值电流885Arms(60s)

L_d_default = 116.17e-6;    % d轴电感 [H] = 116.17μH (数据手册)
R_s_default = 11e-3;         % 定子绕组电阻 [Ω] = 11mΩ (@20°C)
                              % 注: @-20°C约9.3mΩ (铜α=0.00393/°C)
F_sw_default = 1000;         % 默认开关频率 [Hz] (低电感需高频限流)
D_default = 0.50;            % 默认占空比 (对称方波)
I_limit = 885;               % 电流安全上限 [A] (峰值电流, 60s持续)

fprintf('  电机(默认): L_d=%.1f mH, R_s=%.0f mΩ\n', ...
    L_d_default*1000, R_s_default*1000);
fprintf('  控制(默认): f=%.0f Hz, D=%.2f, I_limit=%d A\n', ...
    F_sw_default, D_default, I_limit);

% -------------------------------------------------------------------
% 1.3 逆变器与环境参数
% -------------------------------------------------------------------
V_dc = V_pack_nom;           % 直流母线电压 [V]
T_amb = -20;                 % 环境温度 [°C]
T_init = -20;                % 电池初始温度 [°C] (冷浸透)
SOC_init = 0.80;             % 初始SOC

% --- 逆变器损耗参数 (V2.1新增) ---
% 商用车IGBT模块典型参数 (600A/1200V级, 如Infineon FF600R12ME4)
% 参考: 供应商datasheet, 需获取实际模块型号后替换
%
% 损耗模型:
%   P_inv = P_cond + P_sw
%   P_cond = 2 × (V_ce0 × I_avg + r_ce × I_rms²)  [导通损耗, 2管串联]
%   P_sw = 4 × f × E_sw(I) × V_dc/V_ref           [开关损耗, 每周期4次]
%   E_sw(I) = (E_on + E_off + E_rr) × I_rms/I_ref  [线性近似]

V_ce0 = 0.8;                % IGBT阈值电压 [V] (典型0.7-1.0V @125°C)
r_ce = 2.5e-3;              % IGBT导通微分电阻 [Ω] (典型2-4mΩ @125°C)
V_f0 = 0.7;                 % 续流二极管正向压降 [V] (典型0.6-0.9V)
r_f = 2.0e-3;               % 续流二极管微分电阻 [Ω] (典型1.5-3mΩ)
E_on = 25e-3;               % IGBT开通能量 [J] @I_ref, V_ref (典型20-40mJ)
E_off = 20e-3;              % IGBT关断能量 [J] @I_ref, V_ref (典型15-30mJ)
E_rr = 15e-3;               % 二极管反向恢复能量 [J] @I_ref, V_ref (典型10-20mJ)
I_ref_sw = 400;             % 开关能量参考电流 [A]
V_ref_sw = 600;             % 开关能量参考电压 [V]

% 逆变器损耗计算说明 (在Section 5动态仿真中内联计算)
% 输入: I_rms [A], f [Hz], V_dc [V]
% 输出: P_cond [W], P_sw [W], P_inv_total [W]
%
% 物理说明:
%   双极性PWM全桥, D=0.5时:
%   - 任意时刻2个器件导通 (1个IGBT + 1个二极管, 或2个IGBT)
%   - 对称方波: IGBT和二极管各承担约50%电流时间
%   - 每个开关周期: 2组完整换流事件
%   P_cond = 2×(V_ce0×I_avg + r_ce×I_rms²) + 2×(V_f0×I_avg + r_f×I_rms²)
%   P_sw = 2×f×(E_on+E_off+E_rr)×(I_rms/I_ref)×(V_dc/V_ref)
%   I_avg ≈ I_rms×2/π (正弦近似, 对三角波误差<5%)

fprintf('  环境温度: %.0f°C, 初始SOC: %.0f%%\n', T_amb, SOC_init*100);
fprintf('  逆变器: V_ce0=%.1fV, r_ce=%.1fmΩ, E_sw=%.0fmJ @%dA/%dV\n', ...
    V_ce0, r_ce*1000, (E_on+E_off+E_rr)*1000, I_ref_sw, V_ref_sw);
fprintf('\n');

%% =========================================================================
% 第2部分: 单周期稳态电流解析解
% ==========================================================================
fprintf('--- 第2部分: 稳态电流波形计算 ---\n');

% 计算默认参数下的稳态电流 (使用频率相关有效电阻)f
R_bat_eff_def = R_bat_eff_func(F_sw_default, T_init + 273.15);
R_total_def = R_bat_eff_def + R_s_default;
[i_rms_def, i_max_def, i_min_def, i_pp_def] = ...
    calc_pwm_current_v2(V_dc, R_total_def, L_d_default, F_sw_default, D_default);

tau_def = L_d_default / R_total_def;  % 电气时间常数 [s]
fprintf('  R_bat_eff(@%d°C, %dHz) = %.1f mΩ (DCIR=%.1f mΩ)\n', ...
    T_init, F_sw_default, R_bat_eff_def*1000, R_pack_func(T_init+273.15)*1000);
fprintf('  R_total(@%d°C) = %.1f mΩ\n', T_init, R_total_def*1000);
fprintf('  τ_elec = L/R = %.3f ms (周期T = %.3f ms → α = T/τ = %.3f)\n', ...
    tau_def*1000, 1000/F_sw_default, 1/(F_sw_default*tau_def));
fprintf('  I_rms = %.1f A (%.2fC), I_max = %.1f A, I_pp = %.1f A\n', ...
    i_rms_def, i_rms_def/(C_cell*N_parallel), i_max_def, i_pp_def);

% 生成单周期详细波形
T_period = 1 / F_sw_default;
t_on = D_default * T_period;
N_pts = 500;
t_wave = linspace(0, T_period, N_pts);
i_wave = zeros(1, N_pts);

Vs_def = V_dc / R_total_def;
for k = 1:N_pts
    t = t_wave(k);
    if t <= t_on
        i_wave(k) = Vs_def + (i_min_def - Vs_def) * exp(-t / tau_def);
    else
        i_wave(k) = -Vs_def + (i_max_def + Vs_def) * exp(-(t - t_on) / tau_def);
    end
end

% --- 绘图: 单周期波形 ---
figure(1); clf;
set(gcf, 'Position', [100 500 900 400], 'Color', 'w');

subplot(1,2,1);
hold on;
plot(t_wave*1000, i_wave, 'b-', 'LineWidth', 1.8);
plot(t_on*1000, i_max_def, 'rv', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
plot(0, i_min_def, 'g^', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
yline(i_rms_def, 'r--', sprintf('I_{rms}=%.0fA', i_rms_def), 'LineWidth', 1);
yline(-i_rms_def, 'r--', '', 'LineWidth', 1);
yline(0, 'k-', 'LineWidth', 0.5);
xlabel('时间 t (ms)'); ylabel('电流 i (A)');
title(sprintf('稳态电流波形\n(f=%dHz, L=%.1fmH, R=%.0fmΩ, D=%.2f)', ...
    F_sw_default, L_d_default*1000, R_total_def*1000, D_default));
legend('i(t)', 'I_{max}', 'I_{min}', 'Location', 'best');
grid on; hold off;

subplot(1,2,2);
yyaxis left;
v_pwm = V_dc * ones(size(t_wave));
v_pwm(t_wave > t_on) = -V_dc;
stairs(t_wave*1000, v_pwm, 'b-', 'LineWidth', 1.5);
ylabel('逆变器输出电压 V_{inv} (V)');
ylim([-V_dc*1.3, V_dc*1.3]);

yyaxis right;
plot(t_wave*1000, i_wave, 'r-', 'LineWidth', 1.5);
ylabel('绕组电流 i (A)');
xlabel('时间 t (ms)');
title('PWM电压与电流响应');
grid on;

sgtitle(sprintf('图1: 稳态单周期电流波形 @ T_{init}=%d°C (RL负载, 双极性PWM)', T_init), 'FontWeight', 'bold');
fprintf('  → 图1已生成\n');

%% =========================================================================
% 第3部分: 参数扫描 — I_rms 多维敏感性分析
% ==========================================================================
fprintf('\n--- 第3部分: I_rms 参数扫描 ---\n');

% 扫描范围 (匹配盘毂520s低电感特性, 线性轴)
f_scan = linspace(500, 4000, 30);           % 频率 500~4000 Hz
L_scan = linspace(0.05e-3, 0.5e-3, 30);    % 电感 0.05~0.5 mH
T_scan = [-30, -20, -10, 0];                          % 温度点

[F_grid, L_grid] = meshgrid(f_scan, L_scan);

figure(2); clf;
set(gcf, 'Position', [100 50 1200 800], 'Color', 'w');

for idx_T = 1:length(T_scan)
    T_cur = T_scan(idx_T);
    T_cur_K = T_cur + 273.15;

    I_rms_grid = zeros(size(F_grid));
    I_max_grid = zeros(size(F_grid));
    for i = 1:size(F_grid, 1)
        for j = 1:size(F_grid, 2)
            % 1-RC: 有效电阻随频率变化
            R_bat_eff_ij = R_bat_eff_func(F_grid(i,j), T_cur_K);
            R_cur = R_bat_eff_ij + R_s_default;
            [I_rms_grid(i,j), imax_ij, ~, ~] = ...
                calc_pwm_current_v2(V_dc, R_cur, L_grid(i,j), F_grid(i,j), D_default);
            I_max_grid(i,j) = abs(imax_ij);
        end
    end

    % 计算每个网格点的实际温升速率 dT/dt (考虑R_bat_eff随频率变化)
    dTdt_grid = zeros(size(F_grid));
    for i = 1:size(F_grid, 1)
        for j = 1:size(F_grid, 2)
            R_bat_eff_ij = R_bat_eff_func(F_grid(i,j), T_cur_K);
            dTdt_grid(i,j) = I_rms_grid(i,j)^2 * R_bat_eff_ij / Cth_bat * 60;  % °C/min
        end
    end

    % 子图: I_rms等高线
    subplot(2, 2, idx_T);
    contourf(F_grid, L_grid*1000, I_rms_grid, ...
        [0 100 200 300 500 700 1000 1500], 'LineColor', [0.4 0.4 0.4], 'LineWidth', 0.5);
    cb = colorbar; ylabel(cb, 'I_{rms} (A)');
    clim([0 1500]);
    xlabel('频率 f (Hz)'); ylabel('电感 L (mH)');
    % 线性轴, 清晰刻度
    set(gca, 'XTick', [500 1000 1500 2000 2500 3000 3500 4000]);
    set(gca, 'YTick', [0.05 0.1 0.15 0.2 0.3 0.4 0.5]);
    title(sprintf('I_{rms} @ %d°C (DCIR=%.0fmΩ)', T_cur, R_pack_func(T_cur_K)*1000));
    colormap(parula); hold on;
    % 标注默认参数点
    plot(F_sw_default, L_d_default*1000, 'wp', 'MarkerSize', 12, ...
        'MarkerFaceColor', 'w', 'LineWidth', 1.5);
    % 绿虚线: dT/dt = 1°C/min 等高线 (精确, 考虑R_bat_eff频率依赖)
    contour(F_grid, L_grid*1000, dTdt_grid, [1.0 1.0], ...
        'g--', 'LineWidth', 2);
    % 青虚线: dT/dt = 0.5°C/min 等高线
    contour(F_grid, L_grid*1000, dTdt_grid, [0.5 0.5], ...
        'c--', 'LineWidth', 2);
    % 红线: I_peak = I_limit (峰值电流安全边界, 左下=超限, 右上=安全)
    contour(F_grid, L_grid*1000, I_max_grid, [I_limit I_limit], ...
        'r-', 'LineWidth', 2);
    hold off;
end

sgtitle(sprintf('图2: I_{rms}参数扫描\n(绿虚线=dT/dt=1°C/min, 青虚线=0.5°C/min, 红线=I_{peak}=%dA器件限)', I_limit), ...
    'FontWeight', 'bold');
fprintf('  → 图2已生成\n');

%% =========================================================================
% 第4部分: 净加热判据 — 产热 vs 散热, 温升速率
% ==========================================================================
fprintf('\n--- 第4部分: 净加热判据 ---\n');

% 核心判据:
%   净加热条件: I_rms² × R_bat(T) > (T_bat - T_amb) / R_th
%   初始时刻(T_bat=T_amb): P_loss=0, 只要有电流就能净加热
%   随温升增大, 散热增大, 最终达到热平衡

T_range = linspace(-30, 20, 120);
T_range_K = T_range + 273.15;

% 使用默认模型参数
configs = {
    struct('label', sprintf('f=%dHz, L=%.1fmH', F_sw_default, L_d_default*1000), ...
           'f', F_sw_default, 'L', L_d_default);
};

colors = lines(length(configs));

figure(3); clf;
set(gcf, 'Position', [950 50 900 800], 'Color', 'w');

% --- 上子图: 产热功率 vs 散热功率 ---
subplot(2,1,1);
hold on;

% 散热功率曲线 (以T_amb=-20°C为基准)
P_loss_curve = max(0, (T_range - T_amb)) / R_th_pack;
plot(T_range, P_loss_curve/1000, 'k-', 'LineWidth', 2.5, ...
    'DisplayName', sprintf('散热 P_{loss} (T_{amb}=%d°C)', T_amb));

for idx_c = 1:length(configs)
    cfg = configs{idx_c};
    P_heat_curve = zeros(size(T_range));
    for k = 1:length(T_range)
        % 1-RC: 有效电阻取决于频率和温度
        R_bat_eff_k = R_bat_eff_func(cfg.f, T_range_K(k));
        R_tot = R_bat_eff_k + R_s_default;
        [i_rms_k, ~, ~, ~] = calc_pwm_current_v2(V_dc, R_tot, cfg.L, cfg.f, D_default);
        P_heat_curve(k) = i_rms_k^2 * R_bat_eff_k;  % 有效电阻产热
    end
    plot(T_range, P_heat_curve/1000, '-', 'LineWidth', 2, ...
        'Color', colors(idx_c,:), 'DisplayName', cfg.label);
end

xlabel('电池温度 (°C)'); ylabel('功率 (kW)');
title('电池产热功率 vs 环境散热功率');
legend('Location', 'northeast', 'FontSize', 9);
grid on; xlim([-30 20]);
hold off;

% --- 下子图: 温升速率 ---
subplot(2,1,2);
hold on;

for idx_c = 1:length(configs)
    cfg = configs{idx_c};
    dTdt_curve = zeros(size(T_range));
    for k = 1:length(T_range)
        R_bat_eff_k = R_bat_eff_func(cfg.f, T_range_K(k));
        R_tot = R_bat_eff_k + R_s_default;
        [i_rms_k, ~, ~, ~] = calc_pwm_current_v2(V_dc, R_tot, cfg.L, cfg.f, D_default);
        P_heat = i_rms_k^2 * R_bat_eff_k;
        P_loss = max(0, (T_range(k) - T_amb)) / R_th_pack;
        dTdt_curve(k) = (P_heat - P_loss) / Cth_bat * 60;  % °C/min
    end
    plot(T_range, dTdt_curve, '-', 'LineWidth', 2, ...
        'Color', colors(idx_c,:), 'DisplayName', cfg.label);
end

% 目标线
yline(1.0, 'r--', ' 1°C/min', 'LineWidth', 1.5, 'FontSize', 9);
yline(0.5, 'b--', ' 0.5°C/min', 'LineWidth', 1.5, 'FontSize', 9);
yline(0.15, 'k--', ' 0.15°C/min', 'LineWidth', 1.5, 'FontSize', 9);

xlabel('电池温度 (°C)'); ylabel('温升速率 dT/dt (°C/min)');
title('净温升速率 vs 电池温度 (含散热损失)');
legend('Location', 'northeast', 'FontSize', 9);
grid on; xlim([-30 20]); ylim([0 2.5]);
hold off;

sgtitle(sprintf('图3: 净加热判据与温升速率 (T_{amb}=%d°C)', T_amb), 'FontWeight', 'bold');
fprintf('  → 图3已生成\n');

%% =========================================================================
% 第5部分: 全动态时域仿真 (电-热耦合)
% ==========================================================================
fprintf('\n--- 第5部分: 全动态时域仿真 ---\n');

% 仿真参数
t_sim = 30 * 60;             % 仿真时长 30分钟 [s]
dt_sim = 1.0;                % 时间步长 [s] (热时间常数~16h, 1s步长足够)

% 对默认配置进行动态仿真
sim_configs = {
    struct('label', sprintf('f=%dHz, L=%.1fmH', F_sw_default, L_d_default*1000), ...
           'f', F_sw_default, 'L', L_d_default);
};

N_steps = ceil(t_sim / dt_sim) + 1;
t_array = (0:N_steps-1) * dt_sim;

% 存储所有配置的结果
all_T = zeros(length(sim_configs), N_steps);
all_SOC = zeros(length(sim_configs), N_steps);
all_Irms = zeros(length(sim_configs), N_steps);
all_Imax = zeros(length(sim_configs), N_steps);
all_Iplat = zeros(length(sim_configs), N_steps);
all_Isafe = zeros(length(sim_configs), N_steps);
all_Pheat = zeros(length(sim_configs), N_steps);
all_Ploss = zeros(length(sim_configs), N_steps);
all_Pmotor = zeros(length(sim_configs), N_steps);
all_Pinv = zeros(length(sim_configs), N_steps);   % 逆变器损耗 [W]
all_Pnet = zeros(length(sim_configs), N_steps);
all_Pelec = zeros(length(sim_configs), N_steps);

for idx_cfg = 1:length(sim_configs)
    cfg = sim_configs{idx_cfg};

    T_bat = T_init;
    SOC_now = SOC_init;

    for idx = 1:N_steps
        % 记录当前状态
        all_T(idx_cfg, idx) = T_bat;
        all_SOC(idx_cfg, idx) = SOC_now;

        % 计算当前条件下的电流和功率 (1-RC: 频率相关有效电阻)
        R_bat_eff_now = R_bat_eff_func(cfg.f, T_bat + 273.15);
        R_tot_now = R_bat_eff_now + R_s_default;
        [I_rms_now, I_max_now, ~, ~] = ...
            calc_pwm_current_v2(V_dc, R_tot_now, cfg.L, cfg.f, D_default);

        % 安全限制: 取器件限流和析锂限流中更严格者
        %   条件1: I_max < I_limit (IGBT/电机热限制)
        %   条件2: I_max < I_plating_limit (析锂安全, 基于负极阻抗模型)
        I_plating_now = lithium_plating_criterion(cfg.f, T_bat, SOC_now, ...
            N_parallel, C_cell);
        I_safe = min(I_limit, I_plating_now);

        if abs(I_max_now) > I_safe
            % 简化处理: 按比例缩减电流
            scale = I_safe / abs(I_max_now);
            I_rms_now = I_rms_now * scale;
        end

        P_heat_now = I_rms_now^2 * R_bat_eff_now;  % 有效电阻产热
        P_loss_now = max(0, (T_bat - T_amb)) / R_th_pack;
        P_motor_now = I_rms_now^2 * R_s_default;  % 电机铜耗

        % 逆变器损耗 (导通 + 开关)
        P_cond_now = 2 * (V_ce0 * I_rms_now * 2/pi + r_ce * I_rms_now^2) + ...
                     2 * (V_f0 * I_rms_now * 2/pi + r_f * I_rms_now^2);
        P_sw_now = 2 * cfg.f * (E_on + E_off + E_rr) * ...
                   (I_rms_now / I_ref_sw) * (V_dc / V_ref_sw);
        P_inv_now = P_cond_now + P_sw_now;

        % 总电耗 = 电池产热 + 电机铜耗 + 逆变器损耗
        P_elec_now = P_heat_now + P_motor_now + P_inv_now;

        all_Irms(idx_cfg, idx) = I_rms_now;
        all_Imax(idx_cfg, idx) = abs(I_max_now);
        all_Iplat(idx_cfg, idx) = I_plating_now;
        all_Isafe(idx_cfg, idx) = I_safe;
        all_Pheat(idx_cfg, idx) = P_heat_now;
        all_Ploss(idx_cfg, idx) = P_loss_now;
        all_Pmotor(idx_cfg, idx) = P_motor_now;
        all_Pinv(idx_cfg, idx) = P_inv_now;
        all_Pnet(idx_cfg, idx) = P_heat_now - P_loss_now;
        all_Pelec(idx_cfg, idx) = P_elec_now;

        % 更新状态 (显式Euler)
        if idx < N_steps
            P_net = P_heat_now - P_loss_now;
            T_bat = T_bat + P_net / Cth_bat * dt_sim;
            SOC_now = SOC_now - P_elec_now * dt_sim / ...
                (V_pack_nom * C_cell * N_parallel * 3600);
            SOC_now = max(0.10, SOC_now);
        end
    end
end

% --- 输出关键结果 ---
fprintf('\n  ┌───────────────────────────────────────────────────────────────────────────────┐\n');
fprintf('  │              30分钟动态仿真结果汇总 (含逆变器损耗)                             │\n');
fprintf('  ├──────────────────┬───────┬────────┬──────────┬────────┬────────┬──────────────┤\n');
fprintf('  │ 配置             │ΔT(°C) │dT/dt   │ΔSOC(%%)  │η_sys   │P_inv   │η_inv         │\n');
fprintf('  │                  │       │(°C/min)│          │(%%)     │(kW)    │(%%)           │\n');
fprintf('  ├──────────────────┼───────┼────────┼──────────┼────────┼────────┼──────────────┤\n');

for idx_cfg = 1:length(sim_configs)
    cfg = sim_configs{idx_cfg};
    delta_T = all_T(idx_cfg, end) - T_init;
    avg_rate = delta_T / (t_sim/60);
    delta_SOC = (SOC_init - all_SOC(idx_cfg, end)) * 100;

    % 系统效率: η_sys = P_bat_heat / P_total_elec (电池产热/总电耗)
    P_heat_avg = mean(all_Pheat(idx_cfg, :));
    P_inv_avg = mean(all_Pinv(idx_cfg, :));
    P_motor_avg = mean(all_Irms(idx_cfg, :).^2) * R_s_default;
    P_total_avg = P_heat_avg + P_motor_avg + P_inv_avg;
    eta_sys = P_heat_avg / max(P_total_avg, 1) * 100;

    % 逆变器效率: η_inv = 1 - P_inv/P_total
    eta_inv = (1 - P_inv_avg / max(P_total_avg, 1)) * 100;

    % 初始I_max
    R_bat_eff_i = R_bat_eff_func(cfg.f, T_init + 273.15);
    [~, Imax_i, ~, ~] = calc_pwm_current_v2(V_dc, R_bat_eff_i+R_s_default, cfg.L, cfg.f, D_default);

    fprintf('  │ %-16s │%6.1f │%7.3f │%9.2f │%7.1f │%7.2f │%10.1f    │\n', ...
        cfg.label, delta_T, avg_rate, delta_SOC, eta_sys, P_inv_avg/1000, eta_inv);
end
fprintf('  └──────────────────┴───────┴────────┴──────────┴────────┴────────┴──────────────┘\n');
fprintf('  η_sys = P_bat_heat / (P_bat + P_motor + P_inv), P_inv = 导通损耗 + 开关损耗\n');

% --- 绘图: 动态仿真结果 ---
figure(4); clf;
set(gcf, 'Position', [50 50 1200 850], 'Color', 'w');
sim_colors = [0 0.45 0.74];  % 单配置蓝色

% 子图1: 温度曲线
subplot(3,2,1);
plot(t_array/60, all_T(1,:), '-', 'LineWidth', 2, 'Color', sim_colors);
hold on;
yline(0, 'r--', '0°C', 'LineWidth', 1);
yline(-10, 'k:', '-10°C', 'LineWidth', 0.8);
xlabel('时间 (min)'); ylabel('温度 (°C)');
title(sprintf('电池温度 (%s)', sim_configs{1}.label));
grid on; hold off;

% 子图2: 温升速率 (由功率平衡直接得到)
subplot(3,2,2);
dTdt = all_Pnet(1,:) / Cth_bat * 60;  % °C/min
plot(t_array/60, dTdt, '-', 'LineWidth', 1.5, 'Color', sim_colors);
hold on;
yline(1.0, 'r--', '1°C/min', 'LineWidth', 1);
yline(0.5, 'b--', '0.5°C/min', 'LineWidth', 1);
xlabel('时间 (min)'); ylabel('dT/dt (°C/min)');
title('瞬时温升速率 (由P_{net}/C_{th}计算)'); grid on; hold off;

% 子图3: 电流与安全约束
subplot(3,2,3);
plot(t_array/60, all_Irms(1,:), 'b-', 'LineWidth', 1.6, ...
    'DisplayName', 'I_{rms}');
hold on;
plot(t_array/60, all_Imax(1,:), '-', 'LineWidth', 1.8, 'Color', [0 0.45 0.74], ...
    'DisplayName', 'I_{peak}');
yline(I_limit, 'r--', sprintf('I_{device}=%dA', I_limit), ...
    'LineWidth', 1, 'DisplayName', 'I_{device}');
plot(t_array/60, all_Iplat(1,:), 'm--', 'LineWidth', 1.5, ...
    'DisplayName', 'I_{plating,limit}(T,SOC)');
plot(t_array/60, all_Isafe(1,:), 'k-.', 'LineWidth', 1.3, ...
    'DisplayName', 'I_{safe}=min(I_{device},I_{plating})');
xlabel('时间 (min)'); ylabel('电流 (A)');
title('RMS/峰值电流与参考限');
legend('Location', 'best', 'FontSize', 8);
grid on; hold off;

% 子图4: 功率分解
subplot(3,2,4);
hold on;
plot(t_array/60, all_Pheat(1,:)/1000, '-', 'LineWidth', 1.5, ...
    'Color', sim_colors, 'DisplayName', 'P_{bat}(产热)');
plot(t_array/60, all_Pmotor(1,:)/1000, 'c-', 'LineWidth', 1.2, ...
    'DisplayName', 'P_{motor}(铜耗)');
plot(t_array/60, all_Pinv(1,:)/1000, 'm-', 'LineWidth', 1.2, ...
    'DisplayName', 'P_{inv}(逆变器)');
plot(t_array/60, all_Ploss(1,:)/1000, 'k--', 'LineWidth', 1.2, ...
    'DisplayName', 'P_{loss}(散热)');
xlabel('时间 (min)'); ylabel('功率 (kW)');
title('功率分解'); legend('Location', 'east', 'FontSize', 8);
grid on; hold off;

% 子图5: 净加热功率与总电耗
subplot(3,2,5);
yyaxis left;
plot(t_array/60, all_Pnet(1,:)/1000, 'g-', 'LineWidth', 1.8);
ylabel('P_{net} (kW)');
yyaxis right;
plot(t_array/60, all_Pelec(1,:)/1000, 'Color', [0.85 0.33 0.10], 'LineWidth', 1.5);
ylabel('P_{elec} (kW)');
xlabel('时间 (min)');
title('净加热功率与总电耗');
grid on;

% 子图6: SOC与累计电耗
subplot(3,2,6);
Eelec_cum_kWh = cumsum(all_Pelec(1,1:end-1)) * dt_sim / 3.6e6;
yyaxis left;
plot(t_array/60, all_SOC(1,:)*100, '-', 'LineWidth', 1.5, 'Color', sim_colors);
ylabel('SOC (%)');
yyaxis right;
plot(t_array(1:end-1)/60, Eelec_cum_kWh, '-', 'LineWidth', 1.5, 'Color', [0.85 0.33 0.10]);
ylabel('累计电耗 (kWh)');
xlabel('时间 (min)');
title('SOC与累计电耗');
grid on;

sgtitle(sprintf('图4: 全动态时域仿真 @ T_{init}=%d°C (30min, 电-热耦合)', T_init), 'FontWeight', 'bold');
fprintf('  → 图4已生成\n');

% --- 图5: 能量分配饼图 (独立成图) ---
figure(5); clf;
set(gcf, 'Position', [400 200 600 550], 'Color', 'w');
cfg1 = sim_configs{1};
% 正确的能量分配: 从电池SOC消耗角度, 各项互不重叠
%   总电耗 = 有效温升储能 + 环境散热 + 电机铜耗 + 逆变器损耗
E_retained = (all_T(1,end) - T_init) * Cth_bat / 1e6;  % 有效温升储能 [MJ]
E_env_loss = sum(all_Ploss(1, 1:end-1)) * dt_sim / 1e6;   % 散失到环境 [MJ]
E_motor = sum(all_Irms(1, 1:end-1).^2 * R_s_default) * dt_sim / 1e6;  % 电机铜耗 [MJ]
E_inv = sum(all_Pinv(1, 1:end-1)) * dt_sim / 1e6;  % 逆变器损耗 [MJ]
pie_data = [E_retained, E_env_loss, E_motor, E_inv];
pie_labels = {sprintf('有效温升储能\n%.2fMJ (%.0f%%)', E_retained, E_retained/sum(pie_data)*100), ...
              sprintf('环境散热\n%.3fMJ (%.0f%%)', E_env_loss, E_env_loss/sum(pie_data)*100), ...
              sprintf('电机铜耗\n%.2fMJ (%.0f%%)', E_motor, E_motor/sum(pie_data)*100), ...
              sprintf('逆变器损耗\n%.3fMJ (%.0f%%)', E_inv, E_inv/sum(pie_data)*100)};
% 缩小饼图区域, 给标题留空间
ax5 = gca;
ax5.Position = [0.1 0.05 0.8 0.75];  % [left bottom width height]
p = pie(pie_data);
for k = 2:2:length(p)
    p(k).String = pie_labels{k/2};
    p(k).FontSize = 9;
end
title(sprintf('图5: 30min能量分配 @ T_{init}=%d°C (%s)\n总电耗=%.2fMJ, η_{sys}=有效储能/总电耗=%.1f%%', ...
    T_init, cfg1.label, sum(pie_data), E_retained/sum(pie_data)*100), ...
    'FontWeight', 'bold', 'Units', 'normalized', 'Position', [0.5 1.15 0]);
fprintf('  → 图5已生成\n');

%% =========================================================================
% 第5b部分: 加热效率与SOC电耗 vs 温度
% ==========================================================================
fprintf('\n--- 第5b部分: 加热效率与SOC电耗分析 ---\n');

% 固定当前电感L_d和频率f, 扫描电池温度, 计算:
%   (1) 系统加热效率 η_sys = P_bat_heat / P_total
%   (2) 单位温升SOC消耗 ΔSOC/ΔT [%SOC/°C]

T_eff_scan = linspace(-35, 10, 80);  % 温度扫描范围
T_eff_scan_K = T_eff_scan + 273.15;

% 预分配
eta_sys_vec = zeros(size(T_eff_scan));      % 系统加热效率 [%]
soc_per_deg_vec = zeros(size(T_eff_scan));  % 单位温升SOC消耗 [%SOC/°C]
P_bat_vec = zeros(size(T_eff_scan));        % 电池产热功率 [kW]
P_total_vec = zeros(size(T_eff_scan));      % 总电耗功率 [kW]
P_motor_vec = zeros(size(T_eff_scan));      % 电机铜耗 [kW]
P_inv_vec = zeros(size(T_eff_scan));        % 逆变器损耗 [kW]

for k = 1:length(T_eff_scan)
    T_K = T_eff_scan_K(k);
    R_bat_eff_k = R_bat_eff_func(F_sw_default, T_K);
    R_tot_k = R_bat_eff_k + R_s_default;
    [irms_k, imax_k, ~, ~] = calc_pwm_current_v2(V_dc, R_tot_k, L_d_default, F_sw_default, D_default);

    % 安全限流
    I_plat_k = lithium_plating_criterion(F_sw_default, T_eff_scan(k), SOC_init, N_parallel, C_cell);
    I_safe_k = min(I_limit, I_plat_k);
    if abs(imax_k) > I_safe_k
        irms_k = irms_k * I_safe_k / abs(imax_k);
    end

    P_bat_k = irms_k^2 * R_bat_eff_k;
    P_motor_k = irms_k^2 * R_s_default;
    P_cond_k = 2*(V_ce0*irms_k*2/pi + r_ce*irms_k^2) + ...
               2*(V_f0*irms_k*2/pi + r_f*irms_k^2);
    P_sw_k = 2*F_sw_default*(E_on+E_off+E_rr)*(irms_k/I_ref_sw)*(V_dc/V_ref_sw);
    P_inv_k = P_cond_k + P_sw_k;
    P_total_k = P_bat_k + P_motor_k + P_inv_k;

    eta_sys_vec(k) = P_bat_k / max(P_total_k, 1) * 100;
    P_bat_vec(k) = P_bat_k / 1000;
    P_total_vec(k) = P_total_k / 1000;
    P_motor_vec(k) = P_motor_k / 1000;
    P_inv_vec(k) = P_inv_k / 1000;

    % 单位温升SOC消耗: ΔSOC/ΔT = P_total / (V*Q*3600) / (P_bat/C_th)
    dTdt_k = P_bat_k / Cth_bat;  % °C/s
    dSOCdt_k = P_total_k / (V_pack_nom * C_cell * N_parallel * 3600);  % 1/s
    if dTdt_k > 0
        soc_per_deg_vec(k) = dSOCdt_k / dTdt_k * 100;  % %SOC/°C
    end
end

figure(55); clf;
set(gcf, 'Position', [100 100 600 700], 'Color', 'w');

% --- 上子图: 系统加热效率 vs 温度 ---
subplot(2,1,1);
hold on;
% 效率曲线
plot(T_eff_scan, eta_sys_vec, 'b-', 'LineWidth', 2.5);
% 标注关键温度点
for T_mark = [-30 -20 -10 0]
    eta_mark = interp1(T_eff_scan, eta_sys_vec, T_mark, 'linear');
    plot(T_mark, eta_mark, 'ko', 'MarkerSize', 8, 'MarkerFaceColor', 'b');
    text(T_mark, eta_mark-1.5, sprintf('%.1f%%', eta_mark), ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
end
xlabel('电池温度 (°C)'); ylabel('\eta_{sys} (%)');
title('系统加热效率 \eta_{sys} = P_{bat} / P_{total}');
grid on; set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.3);
ylim([floor(min(eta_sys_vec)-2) 100]);
xlim([-35 10]);
hold off;

% --- 下子图: 单位温升SOC消耗 vs 温度 ---
subplot(2,1,2);
hold on;
plot(T_eff_scan, soc_per_deg_vec, 'r-', 'LineWidth', 2.5);
% 标注关键温度点
for T_mark = [-30 -20 -10 0]
    soc_mark = interp1(T_eff_scan, soc_per_deg_vec, T_mark, 'linear');
    plot(T_mark, soc_mark, 'ko', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    text(T_mark, soc_mark+0.01, ...
        sprintf('%.3f%%/°C', soc_mark), ...
        'FontSize', 9, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
end
xlabel('电池温度 (°C)'); ylabel('\DeltaSOC / \DeltaT (%SOC/°C)');
title('单位温升SOC消耗');
grid on; set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.3);
xlim([-35 10]);
hold off;

sgtitle(sprintf('图5b: 加热效率与SOC电耗 (f=%dHz, L_d=%.2fmH, SOC_0=%.0f%%)', ...
    F_sw_default, L_d_default*1000, SOC_init*100), 'FontWeight', 'bold');
fprintf('  → 图5b已生成\n');
fprintf('  关键数值: @-20°C η_sys=%.1f%%, ΔSOC/ΔT=%.3f%%/°C, 加热10°C消耗%.2f%%SOC\n', ...
    eta_sys_vec(find(T_eff_scan>=-20,1)), ...
    soc_per_deg_vec(find(T_eff_scan>=-20,1)), ...
    soc_per_deg_vec(find(T_eff_scan>=-20,1))*10);

%% =========================================================================
% 第6部分: 可行性边界图 — (L, f) 参数空间
% ==========================================================================
fprintf('\n--- 第6部分: 可行性边界分析 ---\n');

% 在(L, f)空间扫描, 判断:
%   条件A: 净加热 (P_heat > 0, 初始时T=T_amb故P_loss=0, 恒满足)
%   条件B: I_max < I_limit (电流安全)
%   条件C: dT/dt > 0.5°C/min (有意义加热)
%   条件D: dT/dt > 1.0°C/min (达标)

f_bnd = linspace(1, 3000, 60);              % 频率 1~3000 Hz (线性分布)
L_bnd = linspace(0.05e-3, 0.25e-3, 50);    % 电感 0.05~0.25 mH (聚焦实际选型区间)
[F_B, L_B] = meshgrid(f_bnd, L_bnd);

R_bat_init = R_pack_func(T_init + 273.15);  % DCIR (用于参考)

% 计算各点的温升速率和峰值电流 (1-RC: 频率相关)
dTdt_map = zeros(size(F_B));
Imax_map = zeros(size(F_B));
I_plating_map = zeros(size(F_B));  % 析锂限制电流

for i = 1:size(F_B, 1)
    for j = 1:size(F_B, 2)
        R_bat_eff_ij = R_bat_eff_func(F_B(i,j), T_init + 273.15);
        R_tot_ij = R_bat_eff_ij + R_s_default;
        [irms, imax, ~, ~] = calc_pwm_current_v2(V_dc, R_tot_ij, L_B(i,j), F_B(i,j), D_default);
        P_heat = irms^2 * R_bat_eff_ij;
        dTdt_map(i,j) = P_heat / Cth_bat * 60;  % °C/min (初始时P_loss=0)
        Imax_map(i,j) = abs(imax);
        % 析锂限制 (在初始温度和SOC下)
        I_plating_map(i,j) = lithium_plating_criterion(F_B(i,j), T_init, SOC_init, ...
            N_parallel, C_cell);
    end
end

% 考虑析锂约束后的有效温升速率
dTdt_map_safe = dTdt_map;
plating_limited = Imax_map > I_plating_map;
for i = 1:size(F_B, 1)
    for j = 1:size(F_B, 2)
        if plating_limited(i,j)
            % 按析锂限制缩减电流后重新计算温升
            scale = I_plating_map(i,j) / Imax_map(i,j);
            R_bat_eff_ij = R_bat_eff_func(F_B(i,j), T_init + 273.15);
            R_tot_ij = R_bat_eff_ij + R_s_default;
            [irms, ~, ~, ~] = calc_pwm_current_v2(V_dc, R_tot_ij, L_B(i,j), F_B(i,j), D_default);
            irms_safe = irms * scale;
            P_heat_safe = irms_safe^2 * R_bat_eff_ij;
            dTdt_map_safe(i,j) = P_heat_safe / Cth_bat * 60;
        end
    end
end

figure(6); clf;
set(gcf, 'Position', [300 50 900 650], 'Color', 'w');
hold on;

% 温升速率填充:
% 保持图6的原始语义: 在固定电池包与固定温度下, 仅考察(L,f)变化对升温速率的影响。
% 析锂边界单独叠加显示, 但不改写底图和升温参考线。
contourf(F_B, L_B*1000, dTdt_map, [0 0.15 0.3 0.5 0.7 1.0 1.5 2.0], ...
    'LineColor', [0.5 0.5 0.5], 'LineWidth', 0.5);
colormap(parula);
cb = colorbar; ylabel(cb, '初始温升速率 dT/dt (°C/min)');
clim([0 2]);

% 用句柄管理legend
h_lines = [];

% 电流安全边界 (红色粗线)
[~, h1] = contour(F_B, L_B*1000, Imax_map, [I_limit I_limit], 'r-', 'LineWidth', 2.5);
h_lines(end+1) = h1;

% 析锂安全边界 (洋红色粗线)
[~, h2] = contour(F_B, L_B*1000, Imax_map - I_plating_map, [0 0], 'm-', 'LineWidth', 2.5);
h_lines(end+1) = h2;

% 目标线 (均为虚线)
[~, h3] = contour(F_B, L_B*1000, dTdt_map, [1.0 1.0], 'g--', 'LineWidth', 2.5);
h_lines(end+1) = h3;
[~, h4] = contour(F_B, L_B*1000, dTdt_map, [0.5 0.5], 'c--', 'LineWidth', 2);
h_lines(end+1) = h4;

% 标注默认参数
h5 = plot(F_sw_default, L_d_default*1000, 'w*', 'MarkerSize', 14, 'LineWidth', 2);
h_lines(end+1) = h5;

% 当前电机电感水平线 (选型已定, 仅频率可调)
h6 = yline(L_d_default*1000, 'w-', ...
    sprintf('  L_d=%.2fmH (盘毂520s)', L_d_default*1000), ...
    'LineWidth', 2, 'FontSize', 9, 'FontWeight', 'bold', ...
    'LabelHorizontalAlignment', 'right', 'Color', 'w');
h_lines(end+1) = h6;

set(gca, 'XTick', [1 200 500 1000 1500 2000 2500 3000]);
set(gca, 'YTick', [0.05 0.08 0.10 0.12 0.15 0.20 0.25]);
xlabel('开关频率 f (Hz)'); ylabel('电机电感 L (mH)');
title(sprintf('图6: 可行性边界图 (T_{init}=%d°C, T_{amb}=%d°C, SOC_0=%.0f%%)', ...
    T_init, T_amb, SOC_init*100), 'FontWeight', 'bold');
legend(h_lines, {'器件电流限', '析锂限', '1°C/min', '0.5°C/min', '默认参数', ...
    sprintf('当前电感 L_d=%.2fmH', L_d_default*1000)}, ...
    'Location', 'southwest', 'FontSize', 8, 'TextColor', 'w', 'Color', [0.3 0.3 0.3]);

% 网格线: 淡灰色虚线, 跟随XTick/YTick垂直和水平方向
grid on;
set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.4, 'GridColor', [0.6 0.6 0.6]);
set(gca, 'Layer', 'top');  % 确保边界线绘制在网格线上方

hold off;
fprintf('  → 图6已生成\n');

%% =========================================================================
% 第6b部分: 电池组配置对温升速率的影响 (图7)
% ==========================================================================
fprintf('\n--- 第6b部分: 电池组配置敏感性分析 ---\n');

% 图7: 固定电机参数(L_d, R_s, f), 遍历电池组成组参数
% 横轴: Pack额定电压 V_pack [V] (= N_series × V_cell_nom)
% 纵轴: Pack总能量 E_pack [kWh] (= V_pack × Q_total / 1000)
%
% 物理逻辑:
%   - 电压↑(串联数↑) → 驱动电流↑ → 产热↑, 但Pack内阻也↑
%   - 能量↑(电芯总数↑) → 热容↑ → 温升速率↓
%   - 温升速率 dT/dt ∝ P_heat / C_th = I_rms²·R_bat_eff / (M·Cp)
%
% 注意:
%   图6使用主模型标定的Pack总热容 Cth_bat。
%   因此图7也必须以当前配置(N_series, N_parallel)为基准做同比例缩放，
%   这样“当前配置点”在图6和图7中的温升速率才能一致。
%
% 扫描范围 (覆盖LFP商用车典型配置):
%   电压: 350~750 V (轻卡400V平台 ~ 重卡600V平台)
%   能量: 80~500 kWh (轻卡~80kWh, 重卡~450kWh)

V_pack_scan = linspace(350, 750, 50);     % Pack额定电压 [V]
E_pack_scan = linspace(80, 500, 50);      % Pack总能量 [kWh]
[V_grid7, E_grid7] = meshgrid(V_pack_scan, E_pack_scan);

% 计算每个配置点的温升速率
dTdt_pack_map = zeros(size(V_grid7));
dTdt_pack_map_safe = zeros(size(V_grid7));
Imax_pack_map = zeros(size(V_grid7));
Iplat_pack_map = zeros(size(V_grid7));  % 析锂限制电流

for i = 1:size(V_grid7, 1)
    for j = 1:size(V_grid7, 2)
        V_pk = V_grid7(i,j);          % Pack电压 [V]
        E_pk = E_grid7(i,j);          % Pack能量 [kWh]

        % 由电压和能量反推成组参数
        N_s_ij = round(V_pk / V_cell_nom);           % 串联数
        Q_total_ij = E_pk * 1000 / V_pk;             % Pack总容量 [Ah]
        N_p_ij = max(1, round(Q_total_ij / C_cell)); % 并联数

        % Pack内阻 (Arrhenius, 含寄生)
        R_pack_ij = (N_s_ij / N_p_ij) * R_cell_25 * ...
            exp(Ea_R * (1/(T_init+273.15) - 1/T_ref)) * (1 + k_parasitic);

        % 1-RC有效电阻 (频率相关)
        C1_pack_ij = C1_cell * N_p_ij / N_s_ij;
        R_bat_eff_ij = R_pack_ij * (R_ohm_frac + R1_frac / ...
            (1 + (2*pi*F_sw_default * R1_frac * R_pack_ij * C1_pack_ij)^2));

        % 总回路电阻
        R_tot_ij = R_bat_eff_ij + R_s_default;

        % 电流计算 (使用Pack电压作为母线电压)
        [irms_ij, imax_ij, ~, ~] = calc_pwm_current_v2(V_pk, R_tot_ij, ...
            L_d_default, F_sw_default, D_default);

        % Pack热容量:
        % 以主模型当前配置的总热容 Cth_bat 为基准，按总电芯数线性缩放。
        % 这样图7中当前配置点会与图6/主模型保持同一热容口径。
        cell_count_scale = (N_s_ij * N_p_ij) / (N_series * N_parallel);
        Cth_ij = Cth_bat * cell_count_scale;    % 热容 [J/K]

        % 产热功率与温升速率
        P_heat_ij = irms_ij^2 * R_bat_eff_ij;
        dTdt_pack_map(i,j) = P_heat_ij / Cth_ij * 60;  % °C/min
        Imax_pack_map(i,j) = abs(imax_ij);

        % 析锂限制电流 (并联数影响Pack级限值)
        Iplat_pack_map(i,j) = lithium_plating_criterion(F_sw_default, T_init, ...
            SOC_init, N_p_ij, C_cell);

        % 析锂约束后的有效温升速率
        if Imax_pack_map(i,j) > Iplat_pack_map(i,j)
            scale = Iplat_pack_map(i,j) / Imax_pack_map(i,j);
            irms_safe_ij = irms_ij * scale;
            P_heat_safe_ij = irms_safe_ij^2 * R_bat_eff_ij;
            dTdt_pack_map_safe(i,j) = P_heat_safe_ij / Cth_ij * 60;
        else
            dTdt_pack_map_safe(i,j) = dTdt_pack_map(i,j);
        end
    end
end

figure(7); clf;
set(gcf, 'Position', [350 50 900 650], 'Color', 'w');
hold on;

% 温升速率填充:
% 保持图7的原始语义: 在固定电机参数与固定温度下, 仅考察电池包配置变化对升温速率的影响。
% 析锂边界单独叠加显示, 但不改写底图和升温参考线。
contourf(V_grid7, E_grid7, dTdt_pack_map, [0 0.15 0.3 0.5 0.7 1.0 1.5 2.0 3.0], ...
    'LineColor', [0.5 0.5 0.5], 'LineWidth', 0.5);
colormap(parula);
cb = colorbar; ylabel(cb, '初始温升速率 dT/dt (°C/min)');
clim([0 2]);

% 句柄管理
h7_lines = [];

% 器件电流限制
[~, h7_1] = contour(V_grid7, E_grid7, Imax_pack_map, [I_limit I_limit], ...
    'r-', 'LineWidth', 2.5);
h7_lines(end+1) = h7_1;

% 析锂限制边界 (峰值电流 = 析锂限值)
[~, h7_plat] = contour(V_grid7, E_grid7, Imax_pack_map - Iplat_pack_map, [0 0], ...
    'm-', 'LineWidth', 2.5);
h7_lines(end+1) = h7_plat;

% 温升目标线
[~, h7_2] = contour(V_grid7, E_grid7, dTdt_pack_map, [1.0 1.0], 'g--', 'LineWidth', 2.5);
h7_lines(end+1) = h7_2;
[~, h7_3] = contour(V_grid7, E_grid7, dTdt_pack_map, [0.5 0.5], 'c--', 'LineWidth', 2);
h7_lines(end+1) = h7_3;

% 标注当前配置点
E_pack_current = V_pack_nom * C_cell * N_parallel / 1000;  % 当前Pack能量 [kWh]
h7_4 = plot(V_pack_nom, E_pack_current, 'w*', 'MarkerSize', 14, 'LineWidth', 2);
h7_lines(end+1) = h7_4;

% 当前配置参考线
h7_5 = xline(V_pack_nom, 'w-', sprintf('%.0fV ', V_pack_nom), ...
    'LineWidth', 1.5, 'FontSize', 9, 'FontWeight', 'bold', ...
    'LabelHorizontalAlignment', 'left', 'Color', 'w');
h7_lines(end+1) = h7_5;
h7_6 = yline(E_pack_current, 'w--', sprintf('  %.0fkWh', E_pack_current), ...
    'LineWidth', 1.5, 'FontSize', 9, 'FontWeight', 'bold', ...
    'LabelHorizontalAlignment', 'right', 'Color', 'w');
h7_lines(end+1) = h7_6;

set(gca, 'XTick', [350 400 450 500 550 600 650 700 750]);
set(gca, 'YTick', [100 150 200 250 300 350 400 450 500]);
xlabel('Pack额定电压 (V)'); ylabel('Pack总能量 (kWh)');
title(sprintf('图7: 电池组配置对温升速率的影响 (f=%dHz, L_d=%.2fmH, T_{init}=%d°C)', ...
    F_sw_default, L_d_default*1000, T_init), 'FontWeight', 'bold');
legend(h7_lines, {sprintf('器件电流限 %dA', I_limit), '析锂限制边界', ...
    '1°C/min', '0.5°C/min', ...
    sprintf('当前配置 (%dS%dP, %.0fV/%.0fkWh)', N_series, N_parallel, V_pack_nom, E_pack_current), ...
    sprintf('当前电压 %.0fV', V_pack_nom), sprintf('当前能量 %.0fkWh', E_pack_current)}, ...
    'Location', 'southeast', 'FontSize', 8, 'TextColor', 'k');

% 网格线
grid on;
set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.4, 'GridColor', [0.6 0.6 0.6]);
set(gca, 'Layer', 'top');

hold off;
fprintf('  → 图7已生成\n');
fprintf('  读图: 横轴=电压平台(串联数), 纵轴=Pack总能量(kWh)\n');
fprintf('        同电压下能量↑意味着并联数↑, 热容增大温升变慢\n');

%% =========================================================================
% 第7部分: 可行性总结与建议
% ==========================================================================
fprintf('\n');
fprintf('╔══════════════════════════════════════════════════════════════════╗\n');
fprintf('║              可 行 性 分 析 总 结                               ║\n');
fprintf('╚══════════════════════════════════════════════════════════════════╝\n\n');

fprintf('【系统参数】\n');
fprintf('  电池: %dS%dP LFP, %.0fV, %.0fkWh, %.0fkg\n', ...
    N_series, N_parallel, V_pack_nom, E_pack_kWh, M_bat);
fprintf('  电机: 盘毂520s (TZ430XS200), L_d=%.3fmH, R_s=%.0fmΩ\n', ...
    L_d_default*1000, R_s_default*1000);
fprintf('  热参数: C_th=%.2fMJ/K, R_th=%.4fK/W, τ_th=%.1fh\n', ...
    Cth_bat/1e6, R_th_pack, Cth_bat*R_th_pack/3600);
fprintf('  环境: T_amb=%d°C, T_init=%d°C\n\n', T_amb, T_init);

fprintf('【核心物理约束】\n');
P_target = 1.0/60 * Cth_bat;  % 达到1°C/min所需功率 [W]
R_bat_eff_init = R_bat_eff_func(F_sw_default, T_init + 273.15);
I_target = sqrt(P_target / R_bat_eff_init);
fprintf('  达到1°C/min目标所需 (1-RC模型, f=%dHz):\n', F_sw_default);
fprintf('    净加热功率 P_heat ≥ %.1f kW\n', P_target/1000);
fprintf('    所需I_rms ≥ %.0f A (%.2fC)\n', I_target, I_target/(C_cell*N_parallel));
fprintf('    R_bat_eff(@%d°C,%dHz) = %.1f mΩ (DCIR的%.0f%%)\n', ...
    T_init, F_sw_default, R_bat_eff_init*1000, R_bat_eff_init/R_bat_init*100);
fprintf('    约束: f·L ≤ V_dc/(4√3·I_rms) = %.1f mH·kHz (三角波近似)\n\n', ...
    V_dc/(4*sqrt(3)*I_target)*1000*1000/1000);

fprintf('【默认参数评估 (f=%dHz, L=%.1fmH)】\n', F_sw_default, L_d_default*1000);
fprintf('  I_rms = %.1f A → P_heat = %.2f kW → dT/dt = %.3f °C/min\n', ...
    i_rms_def, i_rms_def^2*R_bat_eff_init/1000, i_rms_def^2*R_bat_eff_init/Cth_bat*60);
fprintf('  结论: ❌ 温升速率仅为目标的 %.1f%%, 完全不可行\n\n', ...
    i_rms_def^2*R_bat_eff_init/Cth_bat*60/1.0*100);

fprintf('【可行参数窗口 (dT/dt≥1°C/min 且 I_max≤%dA)】\n', I_limit);
% 动态计算可行窗口示例点
f_examples = [1000, 2000, 5000];
for f_ex = f_examples
    R_bat_eff_ex = R_bat_eff_func(f_ex, T_init + 273.15);
    R_tot_ex = R_bat_eff_ex + R_s_default;
    [irms_ex, imax_ex, ~, ~] = calc_pwm_current_v2(V_dc, R_tot_ex, L_d_default, f_ex, D_default);
    P_heat_ex = irms_ex^2 * R_bat_eff_ex;
    dTdt_ex = P_heat_ex / Cth_bat * 60;
    fprintf('  f=%dHz, L=%.2fmH: dT/dt=%.2f°C/min, I_max=%.0fA', ...
        f_ex, L_d_default*1000, dTdt_ex, abs(imax_ex));
    if abs(imax_ex) > I_limit
        fprintf(' ❌ 超限\n');
    elseif dTdt_ex >= 1.0
        fprintf(' ✓ 达标\n');
    else
        fprintf(' ⚠ 不足\n');
    end
end
fprintf('\n');

fprintf('【析锂安全约束 (V2.0新增)】\n');
fprintf('  基于负极阻抗模型 (Ge et al. 2016; Liu et al. 2023):\n');
fprintf('  判据: I_peak × |Z_neg(f,T)| < U_e (石墨平衡电位)\n');
I_plat_500 = lithium_plating_criterion(500, T_init, SOC_init, N_parallel, C_cell);
I_plat_1k = lithium_plating_criterion(1000, T_init, SOC_init, N_parallel, C_cell);
I_plat_2k = lithium_plating_criterion(2000, T_init, SOC_init, N_parallel, C_cell);
I_plat_5k = lithium_plating_criterion(5000, T_init, SOC_init, N_parallel, C_cell);
fprintf('  @%d°C, SOC=%.0f%%:\n', T_init, SOC_init*100);
fprintf('    f= 500Hz: I_plating_limit = %.0f A (%.2fC)\n', I_plat_500, I_plat_500/(C_cell*N_parallel));
fprintf('    f=1000Hz: I_plating_limit = %.0f A (%.2fC)\n', I_plat_1k, I_plat_1k/(C_cell*N_parallel));
fprintf('    f=2000Hz: I_plating_limit = %.0f A (%.2fC)\n', I_plat_2k, I_plat_2k/(C_cell*N_parallel));
fprintf('    f=5000Hz: I_plating_limit = %.0f A (%.2fC)\n', I_plat_5k, I_plat_5k/(C_cell*N_parallel));
fprintf('  结论: 盘毂520s电感极低(116μH), 需高频(>2kHz)工作。\n');
fprintf('         高频段(>1kHz)析锂约束宽松, 有利于安全。\n');
fprintf('  ⚠ 注意: 以上为基于文献经验参数的估算, 需EIS实测数据校核。\n\n');

fprintf('【电气效率】\n');
fprintf('  η_elec = R_bat_eff/(R_bat_eff+R_s) = %.1f%% (@%d°C, %dHz)\n', ...
    R_bat_eff_init/(R_bat_eff_init+R_s_default)*100, T_init, F_sw_default);
fprintf('  低温下R_bat_eff(%.0fmΩ) >> R_s(%.0fmΩ), 效率天然很高\n', ...
    R_bat_eff_init*1000, R_s_default*1000);
fprintf('  注: 高频时R_bat_eff < DCIR, 但效率仍高(R_bat_eff仍>>R_s)\n\n');

fprintf('【折算电耗】\n');
fprintf('  理论最小值: %.2f%%SOC/10°C (η=100%%时)\n', ...
    Cth_bat*10/(V_pack_nom*C_cell*N_parallel*3600)*100);
fprintf('  实际估算:   %.2f%%SOC/10°C (含电机铜耗+散热)\n\n', ...
    Cth_bat*10/(V_pack_nom*C_cell*N_parallel*3600)/...
    (R_bat_eff_init/(R_bat_eff_init+R_s_default))*100 * 1.05);

fprintf('【结论与建议】\n');
fprintf('  盘毂520s电感极低(116μH), 需高频才能将电流控制在安全范围。\n');
fprintf('  高频工作的优势: 析锂风险大幅降低, 电池阻抗中欧姆分量占主导。\n');
fprintf('  图6的可行性边界图可直观判断实际工作点是否落入可行域。\n');

fprintf('\n=== 脚本运行完毕, 共生成6张图 ===\n');
fprintf('所有参数定义在"第1部分", 收到实测值后直接替换即可。\n');

%% =========================================================================
% 局部函数定义 (MATLAB要求放在脚本末尾)
% ==========================================================================

function [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D)
% CALC_PWM_CURRENT_V2  计算双极性PWM下RL负载的稳态电流特征值
%
% 输入:
%   Vdc - 直流母线电压 [V]
%   R   - 总回路电阻 (R_bat + R_s) [Ω]
%   L   - 等效电感 [H]
%   f   - 开关频率 [Hz]
%   D   - 占空比 (0~1), 正电压施加时间占比
%
% 输出:
%   i_rms - 一个周期内的RMS电流 [A]
%   i_max - 稳态最大电流 (正半周期末) [A]
%   i_min - 稳态最小电流 (负半周期末) [A]
%   i_pp  - 峰峰值电流 [A]
%
% 推导:
%   状态1: i₁(t) = Vs + (I_min - Vs)·exp(-t/τ),  Vs=Vdc/R, τ=L/R
%   状态2: i₂(t') = -Vs + (I_max + Vs)·exp(-t'/τ)
%   周期性边界条件联立求解:
%     I_max = Vs·(e^α - 2·e^{α-β} + 1) / (e^α - 1)
%     I_min = Vs·(2·e^β - e^α - 1) / (e^α - 1)
%   其中 α = R·T/L, β = D·α

    T_period = 1/f;
    tau = L/R;
    alpha = R * T_period / L;   % = T_period / tau
    beta = D * alpha;

    % 防止数值溢出 (alpha极大时电流趋近Vs)
    if alpha > 50
        i_max = Vdc/R;
        i_min = -Vdc/R;
        i_rms = Vdc/R;
        i_pp = 2*Vdc/R;
        return;
    end

    Vs = Vdc / R;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(alpha - beta);
    denom = exp_a - 1;

    % 稳态极值电流 (正确公式)
    i_max = Vs * (exp_a - 2*exp_ab + 1) / denom;
    i_min = Vs * (2*exp_b - exp_a - 1) / denom;

    % 峰峰值
    i_pp = i_max - i_min;

    % RMS电流 — 解析积分
    % 区间1: i₁(t) = Vs + A1·exp(-t/τ), A1 = I_min - Vs, t∈[0, D·T]
    % ∫i₁²dt = Vs²·DT + 2·Vs·A1·τ·(1-e^{-β}) + A1²·(τ/2)·(1-e^{-2β})
    A1 = i_min - Vs;
    int_sq1 = Vs^2 * D * T_period ...
            + 2 * Vs * A1 * tau * (1 - exp(-beta)) ...
            + A1^2 * (tau/2) * (1 - exp(-2*beta));

    % 区间2: i₂(t') = -Vs + A2·exp(-t'/τ), A2 = I_max + Vs, t'∈[0, (1-D)·T]
    % ∫i₂²dt' = Vs²·(1-D)T + 2·(-Vs)·A2·τ·(1-e^{-(α-β)}) + A2²·(τ/2)·(1-e^{-2(α-β)})
    A2 = i_max + Vs;
    gamma = alpha - beta;  % (1-D)·T/τ
    int_sq2 = Vs^2 * (1-D) * T_period ...
            + 2 * (-Vs) * A2 * tau * (1 - exp(-gamma)) ...
            + A2^2 * (tau/2) * (1 - exp(-2*gamma));

    i_rms = sqrt((int_sq1 + int_sq2) / T_period);

    % 数值保护
    if ~isfinite(i_rms) || i_rms < 0
        i_rms = 0;
    end
end
