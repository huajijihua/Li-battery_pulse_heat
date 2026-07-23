function heatSourceAllocation(d03B, cfg)
%% HEATSOURCEALLOCATION  Fig 5: 热源分配堆叠图
%  展示全部 11 个 M4-03B 工况的热源构成（P_batt_heat, P_cu, P_inv, P_hv_loss, P_unmodeled）
%  C07-C10 与 C00 结果相同（限幅为被动监控层），但在图中一并保留以展示完整性。

fprintf('  [5/8] 热源分配堆叠图...\n');

% 排除 C07-C10 因与 C00 完全相同，保留控制策略变化部分
mainIdx = ~ismember(d03B.Scenario_ID, ...
    ["C07_LimitId_Low", "C08_LimitDuty_Low", "C09_LimitMode_Active", "C10_LimitStatus_Off"]);
mainD = d03B(mainIdx, :);
[~, ord] = sort(mainD.Strategy_Family);
mainD = mainD(ord, :);

stackData = [mainD.P_batt_heat_Mean_W, ...
             mainD.P_cu_Mean_W, ...
             mainD.P_inv_Mean_W, ...
             mainD.P_hv_loss_Model_W, ...
             mainD.P_unmodeled_Model_W];
nScen = height(mainD);

fig = figure('Position', cfg.figurePosWide);
clf;

b = bar(1:nScen, stackData, 0.7, 'stacked');
b(1).FaceColor = cfg.color.battHeat;   % P_batt_heat
b(2).FaceColor = cfg.color.cuLoss;     % P_cu
b(3).FaceColor = cfg.color.invLoss;    % P_inv
b(4).FaceColor = cfg.color.hvLoss;     % P_hv_loss
b(5).FaceColor = cfg.color.unmodeled;  % P_unmodeled

xlabel('Scenario', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Heat Source Power (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
shortLabels = strrep(mainD.Scenario_ID, '_', ' ');
set(gca, 'XTick', 1:nScen, 'XTickLabel', shortLabels, 'FontSize', 9);
xtickangle(30);
legend({'P_{batt,heat}', 'P_{cu}', 'P_{inv}', 'P_{hv,loss}', 'P_{unmodeled}'}, ...
    'Location', 'northeast', 'FontSize', 9);

% 标注总热源
for i = 1:nScen
    total = sum(stackData(i, :));
    text(i, total + 2, sprintf('%.0f W', total), ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'FontWeight', 'bold');
end

title('Heat Source Allocation Across Control Strategies', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig5_HeatSource_Allocation\n');
end