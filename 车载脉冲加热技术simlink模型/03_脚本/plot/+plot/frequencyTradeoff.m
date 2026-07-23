function frequencyTradeoff(d03B, cfg)
%% FREQUENCYTRADEOFF  Fig 1: 频率-功率权衡分析
%  从 M4-03B 数据提取 C01_Freq_Low(25Hz), C00_Base(50Hz), C02_Freq_High(100Hz)
%  比较 Id 跟踪误差、电池端功率、铜耗和逆变器损耗随频率的变化。

fprintf('  [1/8] 频率-功率权衡分析...\n');

rows = d03B(ismember(d03B.Scenario_ID, ...
    ["C01_Freq_Low", "C00_Base", "C02_Freq_High"]), :);
[~, ord] = sort(rows.Pulse_Frequency_Hz);
rows = rows(ord, :);
freqs = rows.Pulse_Frequency_Hz;
x = 1:3;

fig = figure('Position', cfg.figurePos);
clf;

% 左轴：柱状图（Id 跟踪误差）
yyaxis left;
b = bar(x, rows.Id_Tracking_RMS_Error_A, 0.5, 'FaceColor', cfg.color.cuLoss);
xlabel('Pulse Frequency', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Id Tracking RMS Error (A)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'XTick', x, 'XTickLabel', compose("%d Hz", freqs), 'FontSize', cfg.fontSize);
hold on;
for i = x
    text(i, rows.Id_Tracking_RMS_Error_A(i) + 0.3, ...
        sprintf('%.1f A', rows.Id_Tracking_RMS_Error_A(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', cfg.color.cuLoss);
end

% 右轴：折线图（电池端功率）
yyaxis right;
p = plot(x, rows.P_batt_terminal_Model_W, 'o-', ...
    'LineWidth', 2.5, 'MarkerSize', 10, 'Color', cfg.color.physical);
ylabel('P_{batt,terminal} (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'YColor', cfg.color.physical);
for i = x
    text(i, rows.P_batt_terminal_Model_W(i) + 1.5, ...
        sprintf('%.1f W', rows.P_batt_terminal_Model_W(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', cfg.color.physical);
end

% 底栏：辅助损耗信息
annotation('textbox', [0.12 0.01 0.76 0.07], 'String', ...
    sprintf('P_{cu}: %.1f / %.1f / %.1f W  |  P_{inv}: %.1f / %.1f / %.1f W  |  P_{heat,rej}: %.1f / %.1f / %.1f W', ...
        rows.P_cu_Mean_W(1), rows.P_cu_Mean_W(2), rows.P_cu_Mean_W(3), ...
        rows.P_inv_Mean_W(1), rows.P_inv_Mean_W(2), rows.P_inv_Mean_W(3), ...
        rows.P_heat_rejection_Model_W(1), rows.P_heat_rejection_Model_W(2), rows.P_heat_rejection_Model_W(3)), ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'EdgeColor', 'none', ...
    'BackgroundColor', [0.95 0.95 0.95]);

title('Frequency Trade-off: Tracking Error vs Battery Power', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig1_Frequency_Tradeoff\n');
end