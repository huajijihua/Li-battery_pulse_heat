function amplitudeSweep(d03B, cfg)
%% AMPLITUDESWEEP  Fig 2: 幅值扫描分析
%  从 M4-03B 提取 C05_Amplitude_Low(20A), C00_Base(40A), C06_Amplitude_High(60A)
%  堆叠柱状图显示 P_cu + P_inv，折线叠加载波和跟踪误差。

fprintf('  [2/8] 幅值扫描分析...\n');

rows = d03B(ismember(d03B.Scenario_ID, ...
    ["C05_Amplitude_Low", "C00_Base", "C06_Amplitude_High"]), :);
[~, ord] = sort(rows.Id_Amplitude_A);
rows = rows(ord, :);
x = 1:3;

fig = figure('Position', cfg.figurePos);
clf;

% 左轴：堆叠柱状图（P_cu + P_inv）
yyaxis left;
b = bar(x, [rows.P_cu_Mean_W, rows.P_inv_Mean_W], 0.6, 'stacked');
b(1).FaceColor = cfg.color.cuLoss;
b(2).FaceColor = cfg.color.invLoss;
xlabel('Id Amplitude', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Loss Power (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'XTick', x, 'XTickLabel', compose("%d A", rows.Id_Amplitude_A), ...
    'FontSize', cfg.fontSize);
totalLoss = rows.P_cu_Mean_W + rows.P_inv_Mean_W;
for i = x
    text(i, totalLoss(i) + 1, sprintf('%.1f W', totalLoss(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
end

% 右轴：折线（纹波 + 跟踪误差）
yyaxis right;
hold on;
plot(x, rows.Vdc_Ripple_V, 's--', 'LineWidth', 2, 'MarkerSize', 9, ...
    'Color', cfg.color.physical);
plot(x, rows.Id_Tracking_RMS_Error_A, '^--', 'LineWidth', 2, 'MarkerSize', 9, ...
    'Color', cfg.color.control);
ylabel('Vdc Ripple (V) / Tracking Error (A)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'YColor', cfg.color.physical);
legend({'Vdc Ripple', 'Id Tracking Error'}, 'Location', 'northwest', 'FontSize', 10);
for i = x
    text(i+0.05, rows.Vdc_Ripple_V(i), sprintf('%.1f V', rows.Vdc_Ripple_V(i)), ...
        'FontSize', 9, 'Color', cfg.color.physical);
end

title('Amplitude Sweep: Losses, Ripple, and Tracking Error', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig2_Amplitude_Sweep\n');
end