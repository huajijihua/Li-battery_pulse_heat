function parameterSensitivity(d02B, cfg)
%% PARAMETERSENSITIVITY  Fig 6: 参数敏感性龙卷风图
%  从 M4-02B B-series 数据计算 9 个参数对 P_batt_terminal 的影响百分比。
%  Low/High 值分别显示为蓝色/橙色条。

fprintf('  [6/8] 参数敏感性龙卷风图...\n');

bSeries = d02B(~contains(d02B.Scenario_ID, 'T'), :);
baseline = bSeries(strcmp(bSeries.Scenario_ID, 'B00_Base'), :);
bPct = baseline.P_batt_terminal_Model_W;

% 参数组: {标签, Low工况ID, High工况ID}
paramPairs = {
    'HVPath_R',     'B01_HVPathR_Low',     'B02_HVPathR_High';
    'DCLink_C',     'B03_DCLinkC_Low',     'B04_DCLinkC_High';
    'R_s',          'B05_Rs_Low',          'B06_Rs_High';
    'R_{batt,heat}', 'B07_BattHeatR_Low',  'B08_BattHeatR_High';
    'C_{batt}',     'B09_BattThermalC_Low', 'B10_BattThermalC_High';
    'IGBT Loss',    'B11_InvLoss_Low',     'B12_InvLoss_High';
    'C_{inv}',      'B13_InvThermalC_Low', 'B14_InvThermalC_High';
    'Rth_{inv}',    'B15_InvThermalR_Low', 'B16_InvThermalR_High';
    'Cooling',      'B17_CoolingBoundary_Low', 'B18_CoolingBoundary_High'};
nParams = size(paramPairs, 1);

lowVals  = zeros(nParams, 1);
highVals = zeros(nParams, 1);
paramNames = cell(nParams, 1);
for i = 1:nParams
    paramNames{i} = paramPairs{i, 1};
    idxLow  = strcmp(bSeries.Scenario_ID, paramPairs{i, 2});
    idxHigh = strcmp(bSeries.Scenario_ID, paramPairs{i, 3});
    if any(idxLow)
        lowVals(i) = (bSeries.P_batt_terminal_Model_W(idxLow) - bPct) / bPct * 100;
    end
    if any(idxHigh)
        highVals(i) = (bSeries.P_batt_terminal_Model_W(idxHigh) - bPct) / bPct * 100;
    end
end

% 按影响幅度排序
impact = max(abs([lowVals, highVals]), [], 2);
[~, sortIdx] = sort(impact, 'descend');
lowVals  = lowVals(sortIdx);
highVals = highVals(sortIdx);
paramNames = paramNames(sortIdx);
yPos = 1:nParams;

fig = figure('Position', [100 100 900 550]);
clf;

% 龙卷风图：左条(Low) 右条(High)
barh(yPos, lowVals, 'FaceColor', cfg.color.lowVal, 'EdgeColor', 'none');
hold on;
barh(yPos, highVals, 'FaceColor', cfg.color.highVal, 'EdgeColor', 'none');
hold off;

set(gca, 'YTick', yPos, 'YTickLabel', paramNames, 'FontSize', cfg.fontSize);
xlabel('Deviation from Baseline P_{batt} (%)', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
ylabel('Parameter', 'FontSize', cfg.labelSize, 'FontWeight', 'bold');
hold on;
plot([0 0], [0 nParams+1], 'k-', 'LineWidth', 1);
hold off;
xLim = max(abs([lowVals; highVals])) * 1.15;
xlim([-xLim, xLim]);

% 标注数值
for i = 1:nParams
    if lowVals(i) ~= 0
        text(lowVals(i) - xLim*0.02, i, sprintf('%.2f%%', lowVals(i)), ...
            'HorizontalAlignment', 'right', 'FontSize', 9, 'Color', cfg.color.lowVal);
    end
    if highVals(i) ~= 0
        text(highVals(i) + xLim*0.02, i, sprintf('%.2f%%', highVals(i)), ...
            'HorizontalAlignment', 'left', 'FontSize', 9, 'Color', cfg.color.highVal);
    end
end

legend({'Low Value', 'High Value'}, 'Location', 'southeast', 'FontSize', 10);
title(sprintf('Parameter Sensitivity on P_{batt,terminal} (Baseline: %.1f W)', bPct), ...
    'FontSize', cfg.titleSize, 'FontWeight', 'bold');
grid(cfg.gridOn);
set(gca, 'FontName', cfg.fontName);
fprintf('  ✓ Fig6_Parameter_Sensitivity\n');
end