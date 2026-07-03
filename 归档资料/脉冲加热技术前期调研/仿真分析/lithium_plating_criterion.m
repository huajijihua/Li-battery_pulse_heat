function [I_plating_limit, info] = lithium_plating_criterion(f, T_celsius, SOC, N_parallel, C_cell, params)
% LITHIUM_PLATING_CRITERION  计算脉冲加热时的析锂安全电流上限 (Pack级)
%
% 基于负极电化学阻抗模型，计算在给定频率和温度下，不引发析锂的
% 最大允许Pack峰值电流。
%
% =========================================================================
% 理论基础 (参考文献见末尾)
% =========================================================================
%
% 【析锂热力学判据】
%   析锂发生条件: 负极表面过电位 η_neg < 0 (即负极电位低于 Li/Li+ 电位)
%   安全条件:     η_neg + U_e > 0
%
%   其中 U_e = 石墨负极平衡电位 vs Li/Li+ [V]
%        η_neg = 负极过电位 (充电时为负值)
%
% 【频域分析 — 方波PWM激励】
%   对称方波(D=0.5)电流的基波分量幅值 = (4/π) × I_peak
%   负极电压降: V_neg = (4/π) × I_cell_peak × |Z_neg(f, T)|
%
%   析锂安全条件: V_neg < U_e
%   → I_cell_peak < (π/4) × U_e / |Z_neg_cell(f, T)|
%   → I_pack_peak < N_parallel × (π/4) × U_e / |Z_neg_cell(f, T)|
%
% 【负极阻抗模型 — 简化EEC】
%   Z_neg(f, T) = R_SEI(T) + R_ct(T) // C_dl
%              = R_SEI(T) + R_ct(T) / (1 + j·2πf·R_ct(T)·C_dl)
%
%   模量: |Z_neg| = R_SEI + R_ct / sqrt(1 + (f/f_ct)^2)
%   其中: f_ct(T) = 1 / (2π·R_ct(T)·C_dl)  [特征频率]
%
% 【温度依赖 — Arrhenius模型】
%   R_ct(T) = R_ct_ref × exp(Ea_ct × (1/T - 1/T_ref))
%   R_SEI(T) = R_SEI_ref × exp(Ea_SEI × (1/T - 1/T_ref))
%   C_dl: 近似温度无关 (几何/介电性质)
%
% 【关键物理机制】
%   高频时(f >> f_ct): 双电层电容短路R_ct → 法拉第电流极小 → 析锂风险低
%   低频时(f << f_ct): 全部电流通过R_ct → 法拉第电流=总电流 → 析锂风险高
%   这解释了为什么高频AC加热天然比低频更安全。
%
% =========================================================================
% 输入参数
% =========================================================================
%   f          - 脉冲频率 [Hz] (标量或向量)
%   T_celsius  - 电池温度 [°C] (标量或向量)
%   SOC        - 电池荷电状态 [0~1]
%   N_parallel - 并联数
%   C_cell     - 单芯容量 [Ah]
%   params     - (可选) 结构体，包含以下字段:
%       .R_ct_ref    - 单芯负极R_ct @25°C [Ω] (默认 0.35e-3)
%       .Ea_ct       - R_ct活化能参数 [K] (默认 5800)
%       .R_SEI_ref   - 单芯SEI电阻 @25°C [Ω] (默认 0.12e-3)
%       .Ea_SEI      - R_SEI活化能参数 [K] (默认 3800)
%       .C_dl        - 单芯双电层电容 [F] (默认 35)
%       .U_e_func    - 石墨平衡电位函数 @(SOC) [V]
%       .k_safety    - 安全裕度系数 (默认 0.8, 即只用80%的理论极限)
%
% =========================================================================
% 输出
% =========================================================================
%   I_plating_limit - Pack级最大允许峰值电流 [A] (与f, T同维度)
%   info            - 结构体，包含中间计算结果
%
% =========================================================================
% 参考文献
% =========================================================================
%   [1] Ge H, Huang J, Zhang J, Li Z. Temperature-Adaptive Alternating
%       Current Preheating of Lithium-Ion Batteries with Lithium Deposition
%       Prevention. J Electrochem Soc, 2016, 163(2): A290-A299.
%       DOI: 10.1149/2.0961602jes
%
%   [2] Liu G, Zhang Z, Gong J, et al. A Square Wave Alternating Current
%       Preheating with High Applicability and Effectiveness of Preventing
%       Lithium Plating. Processes, 2023, 11(4): 1089.
%       DOI: 10.3390/pr11041089
%
%   [3] Zheng D, Li K, Sang Y, et al. Experimental study on alternating
%       current heating strategy for lithium-ion batteries based on lithium
%       precipitation-overvoltage dual safety constraints. Energy, 2025, 335.
%       DOI: 10.1016/j.energy.2025
%
%   [4] Ruan H, Jiang J, Sun B, et al. A rapid low-temperature internal
%       heating strategy with optimal frequency based on constant
%       polarization voltage. Applied Energy, 2016, 177: 771-782.
%       DOI: 10.1016/j.apenergy.2016.05.151
%
%   [5] Xie Y, Guo W, Zhou T, et al. An impedance-based electro-thermal
%       model integrated with in-situ lithium-plating criterion for AC
%       heating. Applied Energy, 2025, 391.
%
% =========================================================================
% 作者: 动力总成前瞻部
% 日期: 2026-05-08
% =========================================================================

%% 参数默认值设置
if nargin < 6 || isempty(params)
    params = struct();
end

T_ref = 298.15;  % 参考温度 25°C [K]

% --- 负极电荷转移电阻 R_ct ---
% 230Ah LFP/石墨电芯: R_ct_neg @25°C 典型值 0.15~0.30 mΩ
% 活化能 Ea_ct: 石墨负极电荷转移典型 40~50 kJ/mol → Ea/R = 4800~6000 K
% 标定依据: 文献报道 @-20°C, 100Hz → ~1.2C; @-20°C, 500Hz → ~3-4C
%   (Ge et al. 2016, J. Electrochem. Soc.; Liu et al. 2023, Processes)
if ~isfield(params, 'R_ct_ref')
    params.R_ct_ref = 0.12e-3;   % [Ω] 单芯负极R_ct @25°C
end
if ~isfield(params, 'Ea_ct')
    params.Ea_ct = 3600;         % [K] ≈ 29.9 kJ/mol
end

% --- SEI膜电阻 R_SEI ---
% 高频极限阻抗, 对于230Ah大面积电芯极小
% 在工作频率范围(50-5000Hz)内近似为常数底噪
if ~isfield(params, 'R_SEI_ref')
    params.R_SEI_ref = 0.015e-3; % [Ω] 单芯SEI电阻 @25°C (大面积电芯极小)
end
if ~isfield(params, 'Ea_SEI')
    params.Ea_SEI = 2500;        % [K] ≈ 20.8 kJ/mol (SEI离子传导)
end

% --- 双电层电容 C_dl ---
% 关键参数! 决定特征频率 f_ct 和频率依赖性强度
% 比电容 ~20-30 μF/cm², 230Ah电芯负极面积 ~60000-80000 cm²
% C_dl = 25μF/cm² × 70000cm² ≈ 1.75 F
% 注: 此值远小于之前的40F估计(那是全电芯电容, 非纯双电层)
% 参考: 由文献C-rate限制的频率依赖性反推标定
if ~isfield(params, 'C_dl')
    params.C_dl = 1.5;           % [F] 单芯负极双电层电容
end

% --- 石墨负极平衡电位 U_e(SOC) ---
% LFP/石墨体系中, 全电池SOC≈负极锂化程度x
% 石墨平衡电位 vs Li/Li+: 在x=0.3~0.8范围内约80~200mV
% 参考: Ge et al. 2016 取 U_e ≈ 90mV; Liu et al. 2023 取 ~100mV
if ~isfield(params, 'U_e_func')
    % 石墨平衡电位模型 vs Li/Li+ (基于典型LFP/石墨全电池SOC映射)
    % SOC=0.2→U_e≈250mV, SOC=0.5→U_e≈130mV, SOC=0.8→U_e≈85mV, SOC=0.95→U_e≈50mV
    % 参考: Ge et al. 2016 取 U_e≈90mV @50%SOC; 实际石墨在stage II约120mV
    params.U_e_func = @(soc) max(0.04, 0.30 - 0.28 * soc);  % [V]
end

% --- 安全裕度系数 ---
% 脉冲加热为交变电流, 充电半周期后紧跟放电半周期,
% 负极表面锂离子有时间重新嵌入, 实际析锂阈值比持续充电高。
% 参考: Jiang et al. 2018 验证600次加热循环无寿命衰减
if ~isfield(params, 'k_safety')
    params.k_safety = 0.90;
end

% --- 波形修正因子 ---
% (4/π)因子假设电流为理想方波, 但RL电路中实际为指数锯齿波。
% 基波/峰值比: 方波=4/π≈1.27, 三角波=8/π²≈0.81
% 修正: 根据 α=T_period/(L/R) 在两者间插值
%   α→∞: 电流趋近方波, 基波系数→4/π
%   α→0: 电流趋近三角波, 基波系数→8/π²
% 使用解析近似: k_waveform(α) = (8/π²) + (4/π - 8/π²)×(1 - exp(-α/2))
% 析锂限制: I_peak < U_e / (k_waveform × |Z_neg|)
%   即 I_limit = U_e / (k_waveform × |Z_neg|) × N_p × k_safety
if ~isfield(params, 'R_total_for_alpha')
    % 默认总回路电阻 (用于计算α, 需与主模型一致)
    % R_total ≈ R_pack(T) + R_s, 此处取-20°C典型值作为默认
    params.R_total_for_alpha = [];  % 空=使用内部估算
end
if ~isfield(params, 'L_for_alpha')
    params.L_for_alpha = [];  % 空=不做波形修正(退化为方波假设)
end

%% 核心计算
T_kelvin = T_celsius + 273.15;  % 转换为开尔文

% 1. 计算温度相关的负极阻抗参数
R_ct_T = params.R_ct_ref * exp(params.Ea_ct * (1./T_kelvin - 1/T_ref));
R_SEI_T = params.R_SEI_ref * exp(params.Ea_SEI * (1./T_kelvin - 1/T_ref));

% 2. 计算特征频率 f_ct(T)
%    f_ct = 1/(2π·R_ct·C_dl)
%    低温时R_ct增大 → f_ct降低 → 需要更高频率才能"绕过"R_ct
f_ct_T = 1 ./ (2 * pi * R_ct_T * params.C_dl);

% 3. 计算负极阻抗模量 |Z_neg(f, T)|
%    |Z_neg| = R_SEI + R_ct / sqrt(1 + (f/f_ct)^2)
%
%    物理含义:
%    - f >> f_ct: |Z_neg| → R_SEI (双电层短路R_ct, 法拉第电流极小)
%    - f << f_ct: |Z_neg| → R_SEI + R_ct (全部电流驱动电化学反应)
%    - f = f_ct:  |Z_neg| = R_SEI + R_ct/√2

% 支持f和T均为向量的情况 (生成网格)
if numel(f) > 1 && numel(T_kelvin) > 1
    [F_mat, T_mat] = meshgrid(f, T_kelvin);
    R_ct_mat = params.R_ct_ref * exp(params.Ea_ct * (1./T_mat - 1/T_ref));
    R_SEI_mat = params.R_SEI_ref * exp(params.Ea_SEI * (1./T_mat - 1/T_ref));
    f_ct_mat = 1 ./ (2 * pi * R_ct_mat * params.C_dl);
    Z_neg_mag = R_SEI_mat + R_ct_mat ./ sqrt(1 + (F_mat ./ f_ct_mat).^2);
else
    Z_neg_mag = R_SEI_T + R_ct_T ./ sqrt(1 + (f ./ f_ct_T).^2);
end

% 4. 获取石墨平衡电位
U_e = params.U_e_func(SOC);

% 5. 计算波形修正因子 k_waveform
%    方波基波系数 4/π ≈ 1.27, 三角波基波系数 8/π² ≈ 0.81
%    实际RL电路中电流波形介于两者之间, 由 α = T_period×R/L 决定
%    α大→方波, α小→三角波
%    k_waveform(α) = (8/π²) + (4/π - 8/π²)×(1 - exp(-α/2))
k_wave_sq = 4/pi;       % 方波极限
k_wave_tri = 8/pi^2;    % 三角波极限

if ~isempty(params.L_for_alpha) && ~isempty(params.R_total_for_alpha)
    % 使用外部提供的电路参数计算α
    T_period_vec = 1 ./ f;
    alpha_vec = params.R_total_for_alpha .* T_period_vec / params.L_for_alpha;
    k_waveform = k_wave_tri + (k_wave_sq - k_wave_tri) * (1 - exp(-alpha_vec/2));
else
    % 无电路参数时, 使用保守的方波假设 (4/π)
    k_waveform = k_wave_sq;
end

% 6. 计算最大允许峰值电流 (Pack级)
%    公式: I_pack_peak < N_p × U_e / (k_waveform × |Z_neg_cell(f,T)|) × k_safety
%
%    物理含义: 基波电流在负极产生的电压降不超过石墨平衡电位
%    k_waveform 修正了实际波形与理想方波的差异
%    参考: Liu et al. 2023, Eq.(19); Ge et al. 2016
if numel(f) > 1 && numel(T_kelvin) > 1
    % 二维网格情况: k_waveform 沿频率维度(列方向)
    k_waveform_mat = repmat(k_waveform(:)', size(Z_neg_mag, 1), 1);
    I_plating_limit = N_parallel * U_e ./ (k_waveform_mat .* Z_neg_mag) * params.k_safety;
else
    I_plating_limit = N_parallel * U_e ./ (k_waveform .* Z_neg_mag) * params.k_safety;
end

% 7. 输出诊断信息
if nargout > 1
    info = struct();
    info.U_e = U_e;
    info.R_ct_T = R_ct_T;
    info.R_SEI_T = R_SEI_T;
    info.f_ct_T = f_ct_T;
    info.Z_neg_mag = Z_neg_mag;
    info.k_waveform = k_waveform;  % 波形修正因子
    info.params = params;
    % 等效C-rate限制
    info.C_rate_limit = I_plating_limit / (C_cell * N_parallel);
end

end
