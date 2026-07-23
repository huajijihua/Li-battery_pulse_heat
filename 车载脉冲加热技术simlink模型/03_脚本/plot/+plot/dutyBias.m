function dutyBias(d03B, cfg)
%% DUTYBIAS  Fig 3: 占空比偏置对比
%  C03_Duty_Low(25%), C00_Base(50%), C04_Duty_High(75%)
%  分组柱状图显示 5 个关键指标。

fprintf('  [3/8] 占空比偏置对比...\n');

rows = d03B(ismember(d03B.Scenario_ID, ...
    ["C03_Duty_Low", "C00_Base", "C04_Duty_High"]), :);
[~, ord] = sort(rows.Positive_Duty_Percent);
rows = rows(ord, :);

metrics = [rows.Id_Tracking_RMS_Error_A, ...
           rows.P_batt_terminal_Model_W, ...
           rows.P_cu_Mean_W, ...
           rows.P_inv_Mean_W, ...
           rows.P_heat_rejection_Model_W];
metricNames = {'Id Tracking Error (A)', 'P_{batt} (W)', 'P_{cu} (W)', ...
    'P_{inv} (W)', 'P_{heat,rej} (W)'};
nMetrics = size(metrics, 2);

fig = figure('Position', cfg.figurePosWide);
clf;

x = 1:nMetrics;
width = 0.25;
dutyColors = [cfg.color.physical; cfg.color.cuLoss; cfg.color.invLoss];

for i = 1:3
    bar(x + (i-2)*width, metrics(i, :), width, 'FaceColor', dutyColors(i,:), ...
        'EdgeColor', 'none');
    hold on;
end
hold off;

set(gca, 'XTick', x, 'XTickLabel', metricNames, 'FontSize', cfg.fontSize);
xtickangle(15);
ylabel('Value', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
legend({'25% (negative bias)', '50% (symmetric)', '75% (positive bias)'}, ...
    'Location', 'northeast', 'FontSize', 10);

% 底栏：Id 均值注释
annotation('textbox', [0.12 0.01 0.76 0.05], 'String', ...
    sprintf('Id mean: %.1f A (25%%) / %.1f A (50%%) / %.1f A (75%%)', ...
        rows.IdRef_Mean_A(1), rows.IdRef_Mean_A(2), rows.IdRef_Mean_A(3)), ...
    'FontSize', 9, 'HorizontalAlignment', 'center', 'EdgeColor', 'none', ...
    'BackgroundColor', [0.95 0.95 0.95]);

title('Duty Cycle Bias: Asymmetric Pulse Comparison', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig3_Duty_Bias\n');
end