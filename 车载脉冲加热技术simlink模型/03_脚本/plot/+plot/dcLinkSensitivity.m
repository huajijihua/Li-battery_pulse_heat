function dcLinkSensitivity(d02B, cfg)
%% DCLINKSENSITIVITY  Fig 8: DC-link 电容敏感性分析
%  从 M4-02B 提取 B00_Base(470μF), B03_DCLinkC_Low(235μF), B04_DCLinkC_High(940μF)
%  展示电容变化对母线纹波、电池 RMS 电流和 DC-link 储能功率的影响。

fprintf('  [8/8] DC-link 电容敏感性分析...\n');

rows = d02B(ismember(d02B.Scenario_ID, ...
    ["B03_DCLinkC_Low", "B00_Base", "B04_DCLinkC_High"]), :);
[~, ord] = sort(rows.DCLink_C_F);
rows = rows(ord, :);
x = 1:3;
capLabels = compose("%d μF", round(rows.DCLink_C_F * 1e6));

fig = figure('Position', cfg.figurePos);
clf;

% 左轴：柱状图（Vdc 纹波 + Ibatt RMS）
yyaxis left;
b = bar(x, [rows.Vdc_Ripple_V, rows.Ibatt_RMS_A], 0.6);
b(1).FaceColor = cfg.color.physical;
b(2).FaceColor = cfg.color.control;
xlabel('DC-Link Capacitance', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Vdc Ripple (V) / Ibatt RMS (A)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'XTick', x, 'XTickLabel', capLabels, 'FontSize', cfg.fontSize);
% 标注纹波
for i = x
    text(i - 0.15, rows.Vdc_Ripple_V(i) + 0.3, ...
        sprintf('%.1f V', rows.Vdc_Ripple_V(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', cfg.color.physical);
    text(i + 0.15, rows.Ibatt_RMS_A(i) + 0.3, ...
        sprintf('%.1f A', rows.Ibatt_RMS_A(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 9, 'Color', cfg.color.control);
end

% 右轴：折线（P_dc_link_storage, P_batt_terminal）
yyaxis right;
hold on;
plot(x, rows.P_dc_link_storage_Model_W, 's--', 'LineWidth', 2, 'MarkerSize', 9, ...
    'Color', cfg.color.dcStorage);
plot(x, rows.P_batt_terminal_Model_W, 'o-', 'LineWidth', 2, 'MarkerSize', 9, ...
    'Color', cfg.color.battHeat);
ylabel('Power (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
set(gca, 'YColor', cfg.color.dcStorage);
legend({'P_{dc,storage}', 'P_{batt,terminal}'}, 'Location', 'northwest', 'FontSize', 10);
for i = x
    text(i+0.05, rows.P_dc_link_storage_Model_W(i), ...
        sprintf('%.1f W', rows.P_dc_link_storage_Model_W(i)), ...
        'FontSize', 9, 'Color', cfg.color.dcStorage);
end

title('DC-Link Capacitance Sensitivity: Ripple, Battery RMS, and Storage Power', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig8_DCLink_Sensitivity\n');
end