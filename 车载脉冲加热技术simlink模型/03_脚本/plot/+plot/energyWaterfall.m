function energyWaterfall(d03B, cfg)
%% ENERGYWATERFALL  Fig 4: 基线工况能量流分配
%  从 M4-03B 读取 C00_Base 基线工况，展示从电池端到热排散的完整能量流。

fprintf('  [4/8] 基线工况能量流分配...\n');

row = d03B(strcmp(d03B.Scenario_ID, 'C00_Base'), :);
if isempty(row)
    warning('C00_Base not found, using first row.');
    row = d03B(1, :);
end

% 能量流分量
labels = {'P_{batt}', 'P_{dc,in}', 'P_{batt,heat}', 'P_{cu}', ...
    'P_{inv}', 'P_{hv,loss}', 'P_{iron}', 'P_{heat,rej}', ...
    'P_{th,store}', 'P_{unmodeled}', 'P_{mech}', 'P_{dc,store}'};
values = [row.P_batt_terminal_Model_W, row.P_dc_input_Model_W, ...
    row.P_batt_heat_Mean_W, row.P_cu_Mean_W, row.P_inv_Mean_W, ...
    row.P_hv_loss_Model_W, row.P_iron_Mean_W, ...
    row.P_heat_rejection_Model_W, row.P_thermal_storage_Model_W, ...
    row.P_unmodeled_Model_W, row.P_mech_Model_W, ...
    row.P_dc_link_storage_Model_W];
n = numel(labels);

% 颜色：输入(蓝) → 损耗源(暖色) → 去向(灰/紫)
colors = [cfg.color.physical;      % P_batt
          cfg.color.physicalLt;    % P_dc_in
          cfg.color.battHeat;      % P_batt_heat
          cfg.color.cuLoss;        % P_cu
          cfg.color.invLoss;       % P_inv
          cfg.color.hvLoss;        % P_hv_loss
          cfg.color.ironLoss;      % P_iron
          cfg.color.thermal;       % P_heat_rej
          cfg.color.thermalStore;  % P_th_store
          cfg.color.unmodeled;     % P_unmodeled
          cfg.color.mech;          % P_mech
          cfg.color.dcStorage];    % P_dc_store

fig = figure('Position', [100 100 1100 600]);
clf;

% 绝对值柱状图，按能量类型着色
x = 1:n;
for i = 1:n
    bar(i, abs(values(i)), 0.7, 'FaceColor', colors(i,:), 'EdgeColor', 'none');
    hold on;
end
hold off;

set(gca, 'XTick', x, 'XTickLabel', labels, 'FontSize', cfg.fontSize);
xtickangle(30);
ylabel('Power (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
% 标注数值
for i = 1:n
    text(i, abs(values(i)) + 1, sprintf('%.1f', abs(values(i))), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'FontWeight', 'bold');
end

% 能量流摘要
pBatt = row.P_batt_terminal_Model_W;
pBattH = row.P_batt_heat_Mean_W;
pCu = row.P_cu_Mean_W;
pInv = row.P_inv_Mean_W;
pHv = row.P_hv_loss_Model_W;
pIron = row.P_iron_Mean_W;
pHeatRej = row.P_heat_rejection_Model_W;
pThStore = row.P_thermal_storage_Model_W;
pUnmod = row.P_unmodeled_Model_W;
heatSum = pBattH + pCu + pInv + pHv + pIron;

annotation('textbox', [0.12 0.92 0.76 0.05], 'String', ...
    sprintf('Energy Flow: P_{batt}=%.1f W  →  Heat Sources (%.1f+%.1f+%.1f+%.1f+%.1f=%.1f W)  →  P_{heat,rej}=%.1f W | P_{th,store}=%.1f W | P_{unmodeled}=%.1f W', ...
        pBatt, pBattH, pCu, pInv, pHv, pIron, heatSum, pHeatRej, pThStore, pUnmod), ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'EdgeColor', 'none', ...
    'BackgroundColor', [0.95 0.95 0.95]);

title(sprintf('Baseline Energy Flow Allocation (C00, 40A 50Hz 50%%, [%.2f,%.2f]s)', ...
    row.Window_Start_s, row.Window_Stop_s), ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig4_Energy_Waterfall\n');
end