fu
ctio
 visualizeM4Results()
%% visualizeM4Results - M4 Refere
ce / Platform 研究结果可视化
%
% 生成 6 张研究级图表，涵盖控制策略比较、能量流分配、参数敏感性分析。
% 所有数据从受控 CSV 读取，支持重新运行更新。
%
% 输出目录（预留，仅当用户允许保存时使用）
% outDir = fullfile(resultsDir, 'visualizatio
s');

%% 0. 路径与文件检查
scriptDir = fileparts(mfile
ame('fullpath'));
resultsDir = fullfile(fileparts(scriptDir), '04_仿真结果');

% 检查必需 CSV 文件
csvFiles = {'M4-03B_co
trol_compariso
_v01.csv', ...
            'M4-02B_complete_ledger_se
sitivity_v01.csv', ...
            'M4-01C_thermal_ledger_v01.csv'};
for i = 1:
umel(csvFiles)
    fpath = fullfile(resultsDir, csvFiles{i});
    if ~isfile(fpath)
        error('必需 CSV 文件不存在: %s', fpath);
    e
d
e
d

%% 1. 读取数据
fpri
tf('读取 M4-03B 控制策略比较数据...\
');
d03B = readtable(fullfile(resultsDir, 'M4-03B_co
trol_compariso
_v01.csv'));
fpri
tf('读取 M4-02B 参数敏感性数据...\
');
d02B = readtable(fullfile(resultsDir, 'M4-02B_complete_ledger_se
sitivity_v01.csv'));
fpri
tf('读取 M4-01C 热账本数据...\
');
d01C = readtable(fullfile(resultsDir, 'M4-01C_thermal_ledger_v01.csv'));

fpri
tf('数据加载完成: M4-03B %d 工况, M4-02B %d 工况, M4-01C %d 工况\
', ...
    height(d03B), height(d02B), height(d01C));

%% 2. 生成图表
fig1_freque
cyTradeoff(d03B);
fig2_amplitudeSweep(d03B);
fig3_e
ergyWaterfall(d03B);
fig4_heatSourceAllocatio
(d03B);
fig5_parameterSe
sitivity(d02B);
fig6_dutyBias(d03B);

fpri
tf('\
=== 全部 6 张图表已在 MATLAB 图形窗口中显示 ===\
');
e
d

%% ======================================================================
fu
ctio
 fig1_freque
cyTradeoff(d)
% Fig 1: 频率-功率权衡分析 (25/50/100 Hz)
fpri
tf('  [1/6] 频率-功率权衡分析...\
');

rows = d(ismember(d.Sce
ario_ID, ["C01_Freq_Low","C00_Base","C02_Freq_High"]), :);
[~, order] = sort(rows.Pulse_Freque
cy_Hz);
rows = rows(order, :);
freqs = rows.Pulse_Freque
cy_Hz;
labels = compose("%d Hz", freqs);

fig = figure('Positio
', [100 100 1000 650], 'Visible', 'o
');
clf;

% 左轴: 柱状图 (跟踪误差)
yyaxis left;
b = bar(1:3, rows.Id_Tracki
g_RMS_Error_A, 0.5, 'FaceColor', [0.85 0.33 0.10]);
xlabel('Pulse Freque
cy', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
ylabel('Id Tracki
g RMS Error (A)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
set(gca, 'XTickLabel', labels, 'Fo
tSize', 11);
hold o
;
% 在柱上标注数值
for i = 1:3
    text(i, rows.Id_Tracki
g_RMS_Error_A(i) + 0.3, ...
        spri
tf('%.1f A', rows.Id_Tracki
g_RMS_Error_A(i)), ...
        'Horizo
talAlig
me
t', 'ce
ter', 'Fo
tSize', 10, 'Color', [0.85 0.33 0.10]);
e
d

% 右轴: 折线图 (电池功率)
yyaxis right;
p = plot(1:3, rows.P_batt_termi
al_Model_W, 'o-', ...
    'Li
eWidth', 2.5, 'MarkerSize', 10, 'Color', [0.00 0.45 0.74]);
ylabel('P_{batt,termi
al} (W)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold', 'Color', [0.00 0.45 0.74]);
set(gca, 'YColor', [0.00 0.45 0.74]);
for i = 1:3
    text(i, rows.P_batt_termi
al_Model_W(i) + 1.5, ...
        spri
tf('%.1f W', rows.P_batt_termi
al_Model_W(i)), ...
        'Horizo
talAlig
me
t', 'ce
ter', 'Fo
tSize', 10, 'Color', [0.00 0.45 0.74]);
e
d

% 辅助信息表格
a

otatio
('textbox', [0.15 0.01 0.7 0.08], 'Stri
g', ...
    spri
tf('P_{cu}: %.1f / %.1f / %.1f W  |  P_{i
v}: %.1f / %.1f / %.1f W  |  P_{heat,rej}: %.1f / %.1f / %.1f W', ...
        rows.P_cu_Mea
_W(1), rows.P_cu_Mea
_W(2), rows.P_cu_Mea
_W(3), ...
        rows.P_i
v_Mea
_W(1), rows.P_i
v_Mea
_W(2), rows.P_i
v_Mea
_W(3), ...
        rows.P_heat_rejectio
_Model_W(1), rows.P_heat_rejectio
_Model_W(2), rows.P_heat_rejectio
_Model_W(3)), ...
    'Fo
tSize', 9, 'Horizo
talAlig
me
t', 'ce
ter', 'EdgeColor', '
o
e', 'Backgrou
dColor', [0.95 0.95 0.95]);

title('Freque
cy Trade-off: Tracki
g Error vs Battery Power', ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

cy_Tradeoff.p
g'));
cy_Tradeoff.fig'));
e
d

%% ======================================================================
fu
ctio
 fig2_amplitudeSweep(d)
% Fig 2: 幅值扫描分析 (20/40/60 A)
fpri
tf('  [2/6] 幅值扫描分析...\
');

rows = d(ismember(d.Sce
ario_ID, ["C05_Amplitude_Low","C00_Base","C06_Amplitude_High"]), :);
[~, order] = sort(rows.Id_Amplitude_A);
rows = rows(order, :);
amps = rows.Id_Amplitude_A;
labels = compose("%d A", amps);

fig = figure('Positio
', [100 100 1000 650], 'Visible', 'o
');
clf;

% 左轴: 堆叠柱状图 (P_cu + P_i
v)
yyaxis left;
b = bar(1:3, [rows.P_cu_Mea
_W, rows.P_i
v_Mea
_W], 0.6, 'stacked');
b(1).FaceColor = [0.85 0.33 0.10];
b(2).FaceColor = [0.93 0.69 0.13];
xlabel('Id Amplitude', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
ylabel('Loss Power (W)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
set(gca, 'XTickLabel', labels, 'Fo
tSize', 11);
% 标注总损耗
totalLoss = rows.P_cu_Mea
_W + rows.P_i
v_Mea
_W;
for i = 1:3
    text(i, totalLoss(i) + 1, spri
tf('%.1f W', totalLoss(i)), ...
        'Horizo
talAlig
me
t', 'ce
ter', 'Fo
tSize', 10, 'Fo
tWeight', 'bold');
e
d

% 右轴: 折线 (纹波 + 跟踪误差)
yyaxis right;
plot(1:3, rows.Vdc_Ripple_V, 's--', 'Li
eWidth', 2, 'MarkerSize', 9, ...
    'Color', [0.00 0.45 0.74]);
hold o
;
plot(1:3, rows.Id_Tracki
g_RMS_Error_A, '^--', 'Li
eWidth', 2, 'MarkerSize', 9, ...
    'Color', [0.49 0.18 0.56]);
ylabel('Vdc Ripple (V) / Tracki
g Error (A)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
set(gca, 'YColor', [0.00 0.45 0.74]);
lege
d({'Vdc Ripple', 'Id Tracki
g Error'}, 'Locatio
', '
orthwest', 'Fo
tSize', 10);

% 标注数据
for i = 1:3
    text(i+0.05, rows.Vdc_Ripple_V(i), spri
tf('%.1f V', rows.Vdc_Ripple_V(i)), ...
        'Fo
tSize', 9, 'Color', [0.00 0.45 0.74]);
e
d

title('Amplitude Sweep: Losses, Ripple, a
d Tracki
g Error', ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

g'));
e
d

%% ======================================================================
fu
ctio
 fig3_e
ergyWaterfall(d)
% Fig 3: 基线工况能量流瀑布图
fpri
tf('  [3/6] 基线工况能量流分配...\
');

row = d(strcmp(d.Sce
ario_ID, 'C00_Base'), :);
if isempty(row)
    war
i
g('C00_Base 未找到，使用第一行数据。');
    row = d(1, :);
e
d

% 能量流分量
pBatt = row.P_batt_termi
al_Model_W;          % 电池端功率
pHvLoss = row.P_hv_loss_Model_W;               % HV 路径损耗
pDcI
put = row.P_dc_i
put_Model_W;             % DC 输入功率
pBattHeat = row.P_batt_heat_Mea
_W;            % 电池热源
pCu = row.P_cu_Mea
_W;                         % 铜耗
pI
v = row.P_i
v_Mea
_W;                       % 逆变器损耗
pIro
 = row.P_iro
_Mea
_W;                     % 铁耗 (≈0 for locked rotor)
pHeatRej = row.P_heat_rejectio
_Model_W;       % 热排散
pThermStore = row.P_thermal_storage_Model_W;   % 热储能
pU
modeled = row.P_u
modeled_Model_W;          % 未建模项
pMech = row.P_mech_Model_W;                    % 机械功率 (≈0)
pDcLi
kStore = row.P_dc_li
k_storage_Model_W;  % DC-li
k 储能

% 瀑布图: 从电池端到热排散的逐步分解
% 步骤: 流入能量 → 路径损耗 → 热源分配 → 热排散/储能/未建模
steps = {'P_{batt}', 'P_{dc,i
}', 'P_{batt,heat}', 'P_{cu}', ...
    'P_{i
v}', 'P_{hv,loss}', 'P_{iro
}', 'P_{heat,rej}', ...
    'P_{th,store}', 'P_{u
modeled}', 'P_{mech}', 'P_{dc,store}'};
% 瀑布值: 正值 = 流入能量, 负值 = 消耗/存储, 累计显示总能量平衡
% 显示为: 电池端 → 各消耗项 → 最终去向
values = [pBatt, pDcI
put, pBattHeat, pCu, pI
v, pHvLoss, pIro
, ...
    pHeatRej, pThermStore, pU
modeled, pMech, pDcLi
kStore];

fig = figure('Positio
', [100 100 1100 600], 'Visible', 'o
');
clf;

% 用自定义颜色区分能量类型

 = 
umel(steps);
colors = [0.20 0.63 0.17;   % P_batt - 绿色(输入)
          0.00 0.45 0.74;   % P_dc_i
 - 蓝色
          0.85 0.33 0.10;   % P_batt_heat - 红色
          0.93 0.69 0.13;   % P_cu - 金色
          0.49 0.18 0.56;   % P_i
v - 紫色
          0.47 0.67 0.19;   % P_hv_loss - 橄榄绿
          0.30 0.75 0.93;   % P_iro
 - 青色
          0.64 0.08 0.18;   % P_heat_rej - 深红
          0.00 0.45 0.74;   % P_th_store - 蓝色
          0.50 0.50 0.50;   % P_u
modeled - 灰色
          0.80 0.80 0.80;   % P_mech - 浅灰
          0.30 0.30 0.30];  % P_dc_store - 深灰

% 瀑布图: 用递减/递增的累积柱状图表示
% 初始点为电池端功率, 每步减去一个消耗项
cumulative = zeros(1, 
+1);
cumulative(1) = pBatt;  % 起始点: 电池端功率
for i = 1:

    if i == 2
        cumulative(i+1) = pDcI
put;  % DC 输入 (略小于 P_batt, 因为 HV 损耗在 DC 侧之后)
    elseif i == 1
        cumulative(i+1) = cumulative(i);  % 第一项
    else
        cumulative(i+1) = cumulative(i) - abs(values(i));
    e
d
e
d

% 简化: 直接显示各分量的绝对值柱状图, 用颜色区分正负贡献
x = 1:
;
bar(x, abs(values), 0.7, 'FaceColor', 'flat');
for i = 1:

    h = bar(i, abs(values(i)), 0.7);
    if i <= 2
        set(h, 'FaceColor', colors(i,:));  % 输入能量
    elseif i <= 7
        set(h, 'FaceColor', colors(i,:));  % 损耗/热源
    else
        set(h, 'FaceColor', colors(i,:));  % 去向
    e
d
    hold o
;
e
d
hold off;

set(gca, 'XTick', 1:
, 'XTickLabel', steps, 'Fo
tSize', 10);
xticka
gle(30);
ylabel('Power (W)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
% 标注数值
for i = 1:

    text(i, abs(values(i)) + 1, spri
tf('%.1f', abs(values(i))), ...
        'Horizo
talAlig
me
t', 'ce
ter', 'Fo
tSize', 9, 'Fo
tWeight', 'bold');
e
d

% 添加能量流注释
a

otatio
('textbox', [0.15 0.92 0.7 0.05], 'Stri
g', ...
    spri
tf('E
ergy Flow: P_{batt}=%.1f W → P_{dc,i
}=%.1f W → Heat Sources (%.1f+%.1f+%.1f+%.1f+%.1f=%.1f W) → P_{heat,rej}=%.1f W | P_{th,store}=%.1f W | P_{u
modeled}=%.1f W', ...
        pBatt, pDcI
put, pBattHeat, pCu, pI
v, pHvLoss, pIro
, ...
        pBattHeat+pCu+pI
v+pHvLoss+pIro
, pHeatRej, pThermStore, pU
modeled), ...
    'Fo
tSize', 8, 'Horizo
talAlig
me
t', 'ce
ter', 'EdgeColor', '
o
e', ...
    'Backgrou
dColor', [0.95 0.95 0.95]);

title(spri
tf('Baseli
e E
ergy Flow Allocatio
 (C00, 40A 50Hz 50%%, [%.2f,%.2f]s)', ...
    row.Wi
dow_Start_s, row.Wi
dow_Stop_s), ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

ergy_Waterfall.p
g'));
ergy_Waterfall.fig'));
e
d

%% ======================================================================
fu
ctio
 fig4_heatSourceAllocatio
(d)
% Fig 4: 热源分配堆叠图 (全部 11 工况)
fpri
tf('  [4/6] 热源分配堆叠图...\
');

% 筛选 C00-C06 (控制策略变化), 排除 C07-C10 (与 C00 相同)
mai
Sce
arios = d(~ismember(d.Sce
ario_ID, ["C07_LimitId_Low","C08_LimitDuty_Low", ...
    "C09_LimitMode_Active","C10_LimitStatus_Off"]), :);
% 按策略族排序
[~, order] = sort(mai
Sce
arios.Strategy_Family);
mai
Sce
arios = mai
Sce
arios(order, :);

% 堆叠数据: P_batt_heat, P_cu, P_i
v, P_hv_loss, P_u
modeled
stackData = [mai
Sce
arios.P_batt_heat_Mea
_W, ...
             mai
Sce
arios.P_cu_Mea
_W, ...
             mai
Sce
arios.P_i
v_Mea
_W, ...
             mai
Sce
arios.P_hv_loss_Model_W, ...
             mai
Sce
arios.P_u
modeled_Model_W];

fig = figure('Positio
', [100 100 1100 600], 'Visible', 'o
');
clf;

b = bar(1:height(mai
Sce
arios), stackData, 0.7, 'stacked');
b(1).FaceColor = [0.85 0.33 0.10];  % P_batt_heat
b(2).FaceColor = [0.93 0.69 0.13];  % P_cu
b(3).FaceColor = [0.49 0.18 0.56];  % P_i
v
b(4).FaceColor = [0.47 0.67 0.19];  % P_hv_loss
b(5).FaceColor = [0.50 0.50 0.50];  % P_u
modeled

xlabel('Sce
ario', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
ylabel('Heat Source Power (W)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
% 短标签
shortLabels = strrep(mai
Sce
arios.Sce
ario_ID, '_', ' ');
set(gca, 'XTick', 1:height(mai
Sce
arios), 'XTickLabel', shortLabels, 'Fo
tSize', 9);
xticka
gle(30);
lege
d({'P_{batt,heat}', 'P_{cu}', 'P_{i
v}', 'P_{hv,loss}', 'P_{u
modeled}'}, ...
    'Locatio
', '
ortheast', 'Fo
tSize', 9);

% 标注总热源
for i = 1:height(mai
Sce
arios)
    total = sum(stackData(i, :));
    text(i, total + 2, spri
tf('%.0f W', total), ...
        'Horizo
talAlig
me
t', 'ce
ter', 'Fo
tSize', 8, 'Fo
tWeight', 'bold');
e
d

title('Heat Source Allocatio
 Across Co
trol Strategies', ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

.p
g'));
.fig'));
e
d

%% ======================================================================
fu
ctio
 fig5_parameterSe
sitivity(d)
% Fig 5: 参数敏感性龙卷风图 (M4-02B B-series 40ms)
fpri
tf('  [5/6] 参数敏感性龙卷风图...\
');

% 筛选 B-series 工况 (排除 T-series 200ms)
bSeries = d(~co
tai
s(d.Sce
ario_ID, 'T'), :);
baseli
e = bSeries(strcmp(bSeries.Sce
ario_ID, 'B00_Base'), :);
bPct = baseli
e.P_batt_termi
al_Model_W;  % 基线电池功率

% 定义参数组: 每对 (Low, High) 对应一个参数
paramPairs = {
    'HVPath_R',    'B01_HVPathR_Low',    'B02_HVPathR_High';
    'DCLi
k_C',    'B03_DCLi
kC_Low',    'B04_DCLi
kC_High';
    'Rs',          'B05_Rs_Low',         'B06_Rs_High';
    'R_{batt,heat}','B07_BattHeatR_Low', 'B08_BattHeatR_High';
    'C_{batt}',    'B09_BattThermalC_Low','B10_BattThermalC_High';
    'IGBT Loss',   'B11_I
vLoss_Low',    'B12_I
vLoss_High';
    'C_{i
v}',     'B13_I
vThermalC_Low','B14_I
vThermalC_High';
    'Rth_{i
v}',   'B15_I
vThermalR_Low','B16_I
vThermalR_High';
    'Cooli
g',     'B17_Cooli
gBou
dary_Low','B18_Cooli
gBou
dary_High'};

Params = size(paramPairs, 1);

% 计算每个参数 Low/High 对 P_batt_termi
al 的影响百分比
lowVals = zeros(
Params, 1);
highVals = zeros(
Params, 1);
param
ames = cell(
Params, 1);
for i = 1:
Params
    param
ames{i} = paramPairs{i, 1};
    idxLow = strcmp(bSeries.Sce
ario_ID, paramPairs{i, 2});
    idxHigh = strcmp(bSeries.Sce
ario_ID, paramPairs{i, 3});
    if a
y(idxLow)
        lowVals(i) = (bSeries.P_batt_termi
al_Model_W(idxLow) - bPct) / bPct * 100;
    e
d
    if a
y(idxHigh)
        highVals(i) = (bSeries.P_batt_termi
al_Model_W(idxHigh) - bPct) / bPct * 100;
    e
d
e
d

% 按影响幅度排序 (max absolute deviatio
)
impact = max(abs([lowVals, highVals]), [], 2);
[~, sortIdx] = sort(impact, 'desce
d');
lowVals = lowVals(sortIdx);
highVals = highVals(sortIdx);
param
ames = param
ames(sortIdx);

fig = figure('Positio
', [100 100 900 550], 'Visible', 'o
');
clf;

% 龙卷风图: 左条 (Low → 负偏差) 右条 (High → 正偏差)
yPos = 1:
Params;
barh(yPos, lowVals, 'FaceColor', [0.00 0.45 0.74], 'EdgeColor', '
o
e');
hold o
;
barh(yPos, highVals, 'FaceColor', [0.85 0.33 0.10], 'EdgeColor', '
o
e');
hold off;

set(gca, 'YTick', yPos, 'YTickLabel', param
ames, 'Fo
tSize', 11);
xlabel('Deviatio
 from Baseli
e P_{batt} (%)', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
ylabel('Parameter', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
% 添加零线
hold o
;
plot([0 0], [0 
Params+1], 'k-', 'Li
eWidth', 1);
hold off;
xlim([mi
([lowVals; highVals])-2, max([lowVals; highVals])+2] * 1.1);

% 标注数值
for i = 1:
Params
    if lowVals(i) ~= 0
        text(lowVals(i) - 0.1, i, spri
tf('%.2f%%', lowVals(i)), ...
            'Horizo
talAlig
me
t', 'right', 'Fo
tSize', 9, 'Color', [0.00 0.45 0.74]);
    e
d
    if highVals(i) ~= 0
        text(highVals(i) + 0.1, i, spri
tf('%.2f%%', highVals(i)), ...
            'Horizo
talAlig
me
t', 'left', 'Fo
tSize', 9, 'Color', [0.85 0.33 0.10]);
    e
d
e
d

lege
d({'Low Value', 'High Value'}, 'Locatio
', 'southeast', 'Fo
tSize', 10);
title(spri
tf('Parameter Se
sitivity o
 P_{batt,termi
al} (Baseli
e: %.1f W)', bPct), ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

sitivity.p
g'));
sitivity.fig'));
e
d

%% ======================================================================
fu
ctio
 fig6_dutyBias(d)
% Fig 6: 占空比偏置对比 (25%/50%/75%)
fpri
tf('  [6/6] 占空比偏置对比...\
');

rows = d(ismember(d.Sce
ario_ID, ["C03_Duty_Low","C00_Base","C04_Duty_High"]), :);
[~, order] = sort(rows.Positive_Duty_Perce
t);
rows = rows(order, :);
duties = rows.Positive_Duty_Perce
t;
labels = compose("%d%% duty", duties);

% 指标: Id tracki
g error, P_batt, P_cu, P_i
v, P_heat_rejectio

metrics = [rows.Id_Tracki
g_RMS_Error_A, ...
           rows.P_batt_termi
al_Model_W, ...
           rows.P_cu_Mea
_W, ...
           rows.P_i
v_Mea
_W, ...
           rows.P_heat_rejectio
_Model_W];
metric
ames = {'Id Tracki
g Error (A)', 'P_{batt} (W)', 'P_{cu} (W)', ...
    'P_{i
v} (W)', 'P_{heat,rej} (W)'};

fig = figure('Positio
', [100 100 1100 500], 'Visible', 'o
');
clf;

% 分组柱状图: 每个指标一组, 3 个占空比

Metrics = 
umel(metric
ames);
x = 1:
Metrics;
width = 0.25;
colors = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13];

for i = 1:3
    bar(x + (i-2)*width, metrics(i, :), width, 'FaceColor', colors(i,:), ...
        'EdgeColor', '
o
e');
    hold o
;
e
d
hold off;

set(gca, 'XTick', x, 'XTickLabel', metric
ames, 'Fo
tSize', 10);
xticka
gle(15);
ylabel('Value', 'Fo
tSize', 12, 'Fo
tWeight', 'bold');
lege
d({'25% (
egative bias)', '50% (symmetric)', '75% (positive bias)'}, ...
    'Locatio
', '
ortheast', 'Fo
tSize', 10);

% 标注 Id mea
 值
a

otatio
('textbox', [0.15 0.01 0.7 0.05], 'Stri
g', ...
    spri
tf('Id mea
: %.1f A (25%%) / %.1f A (50%%) / %.1f A (75%%)  |  Expected: %.0f / %.0f / %.0f A', ...
        rows.IdRef_Mea
_A(1), rows.IdRef_Mea
_A(2), rows.IdRef_Mea
_A(3), ...
        rows.Expected_Id_Mea
_A(1), rows.Expected_Id_Mea
_A(2), rows.Expected_Id_Mea
_A(3)), ...
    'Fo
tSize', 9, 'Horizo
talAlig
me
t', 'ce
ter', 'EdgeColor', '
o
e', ...
    'Backgrou
dColor', [0.95 0.95 0.95]);

title('Duty Cycle Bias: Asymmetric Pulse Compariso
', ...
    'Fo
tSize', 13, 'Fo
tWeight', 'bold');
grid o
;
set(gca, 'Fo
t
ame', 'Arial');

g'));
e
d
