function thermalTimeConstant(d02B, cfg)
%% THERMALTIMECONSTANT  Fig 7: 热时间常数简并分析
%  从 M4-02B T-series 展示 C_inv 与 Rth_inv 的简并效应。
%  T01(T03) = tau减半, T02(T04) = tau加倍, T05/T06 = 冷却边界独立影响。

fprintf('  [7/8] 热时间常数简并分析...\n');

tSeries = d02B(contains(d02B.Scenario_ID, 'T'), :);
[~, tOrd] = sort(tSeries.C_inv_J_K .* tSeries.Rth_inv_K_W);
tSeries = tSeries(tOrd, :);

keyIds = ["T00_Base", "T01_InvThermalC_Low", "T02_InvThermalC_High", ...
    "T05_CoolingBoundary_Low", "T06_CoolingBoundary_High"];
keyRows = tSeries(ismember(tSeries.Scenario_ID, keyIds), :);
[~, kOrd] = sort(keyRows.C_inv_J_K .* keyRows.Rth_inv_K_W);
keyRows = keyRows(kOrd, :);
nKey = height(keyRows);

% 简并标记（使用简单 ASCII 标签避免特殊字符问题）
labels = {
    'tau_half (C_inv down)';  % T01
    'tau_half (Rth_inv down)'; % T03 will be merged
    'tau_double (C_inv up)';   % T02
    'tau_double (Rth_inv up)'; % T04 will be merged
    'Cooling down 258K';       % T05
    'Cooling up 268K'          % T06
    };
% Map the 5 key scenarios to labels
labelMap = containers.Map();
labelMap('T00_Base') = 'Base';
labelMap('T01_InvThermalC_Low') = 'tau_half (C_inv down)';
labelMap('T02_InvThermalC_High') = 'tau_double (C_inv up)';
labelMap('T05_CoolingBoundary_Low') = 'Cooling down 258K';
labelMap('T06_CoolingBoundary_High') = 'Cooling up 268K';

xtLabels = cell(nKey, 1);
for i = 1:nKey
    id = char(keyRows.Scenario_ID(i));
    if labelMap.isKey(id)
        xtLabels{i} = labelMap(id);
    else
        xtLabels{i} = id;
    end
end

fig = figure('Position', cfg.figurePosWide);
clf;

x = 1:nKey;
barWidth = 0.35;
bar(x - barWidth/2, keyRows.P_thermal_storage_Model_W, barWidth, ...
    'FaceColor', cfg.color.thermalStore, 'EdgeColor', 'none');
hold on;
bar(x + barWidth/2, keyRows.P_heat_rejection_Model_W, barWidth, ...
    'FaceColor', cfg.color.thermal, 'EdgeColor', 'none');
hold off;

set(gca, 'XTick', x, 'XTickLabel', xtLabels, 'FontSize', cfg.fontSize);
xlabel('Scenario (tau = C_{inv} x Rth_{inv})', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Thermal Power (W)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
legend({'P_{thermal,storage}', 'P_{heat,rejection}'}, 'Location', 'southeast', 'FontSize', 10);

for i = 1:nKey
    text(i - barWidth/2, keyRows.P_thermal_storage_Model_W(i) + 1, ...
        sprintf('%.0f', keyRows.P_thermal_storage_Model_W(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', cfg.color.thermalStore);
    text(i + barWidth/2, keyRows.P_heat_rejection_Model_W(i) + 1, ...
        sprintf('%.0f', keyRows.P_heat_rejection_Model_W(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', cfg.color.thermal);
end

annotation('textbox', [0.12 0.01 0.76 0.05], 'String', ...
    sprintf('T_batt = %.2f K (all)  |  T01 = T03 (degenerate: same tau)  |  T02 = T04 (degenerate: same tau)', ...
        keyRows.T_batt_End_K(1)), ...
    'FontSize', 8, 'HorizontalAlignment', 'center', 'EdgeColor', 'none', ...
    'BackgroundColor', [0.95 0.95 0.95]);

title('Thermal Time Constant Degeneracy: C_{inv} and Rth_{inv} in 200ms Window', ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig7_Thermal_TimeConstant\n');
end