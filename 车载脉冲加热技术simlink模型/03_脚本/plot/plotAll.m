function plotAll(targets)
%% PLOTALL  M4 结果图表主运行器
%  读取三份受控 CSV 数据，调用 +plot 包内的各绘图函数。
%  图表以 MATLAB 在线图形窗口显示，不保存图片文件。
%
%  plotAll('all')            显示全部 8 张图表
%  plotAll('control')        仅控制策略比较图 (Fig1-3)
%  plotAll('energy')         仅能量流与热源图 (Fig4-5)
%  plotAll('sensitivity')    仅参数敏感性图 (Fig6-8)
%  plotAll('list')           仅列出可用图表，不生成

arguments
    targets {mustBeText} = "all"
end

targets = string(targets);
cfg = plotConfig();

% 解析 CSV 路径
scriptDir = fileparts(mfilename('fullpath'));
modelRoot = fileparts(fileparts(scriptDir));  % 03_脚本/plot → 03_脚本 → 模型根
resultsDir = fullfile(modelRoot, '04_仿真结果');

csvFiles = containers.Map();
csvFiles('M4-03B') = fullfile(resultsDir, 'M4-03B_control_comparison_v01.csv');
csvFiles('M4-02B') = fullfile(resultsDir, 'M4-02B_complete_ledger_sensitivity_v01.csv');
csvFiles('M4-01C') = fullfile(resultsDir, 'M4-01C_thermal_ledger_v01.csv');

for k = keys(csvFiles)
    key = k{1};
    if ~isfile(csvFiles(key))
        error('Required CSV file not found: %s', csvFiles(key));
    end
end

% 读取数据
fprintf('读取 M4-03B 控制策略比较数据...\n');
d03B = readtable(csvFiles('M4-03B'));
fprintf('读取 M4-02B 参数敏感性数据...\n');
d02B = readtable(csvFiles('M4-02B'));
fprintf('读取 M4-01C 热账本数据...\n');
d01C = readtable(csvFiles('M4-01C'));
fprintf('数据加载完成 (%d+%d+%d 工况)。\n\n', ...
    height(d03B), height(d02B), height(d01C));

% 绘制图表
switch targets
    case "all"
        fprintf('=== 显示全部 8 张图表 ===\n');
        plot.frequencyTradeoff(d03B, cfg);
        plot.amplitudeSweep(d03B, cfg);
        plot.dutyBias(d03B, cfg);
        plot.energyWaterfall(d03B, cfg);
        plot.heatSourceAllocation(d03B, cfg);
        plot.parameterSensitivity(d02B, cfg);
        plot.thermalTimeConstant(d02B, cfg);
        plot.dcLinkSensitivity(d02B, cfg);

    case "control"
        fprintf('=== 控制策略比较图 (Fig1-3) ===\n');
        plot.frequencyTradeoff(d03B, cfg);
        plot.amplitudeSweep(d03B, cfg);
        plot.dutyBias(d03B, cfg);

    case "energy"
        fprintf('=== 能量流与热源图 (Fig4-5) ===\n');
        plot.energyWaterfall(d03B, cfg);
        plot.heatSourceAllocation(d03B, cfg);

    case "sensitivity"
        fprintf('=== 参数敏感性图 (Fig6-8) ===\n');
        plot.parameterSensitivity(d02B, cfg);
        plot.thermalTimeConstant(d02B, cfg);
        plot.dcLinkSensitivity(d02B, cfg);

    case "list"
        fprintf('可用图表:\n');
        fprintf('  [1] Fig1_Frequency_Tradeoff        - 频率-功率权衡 (control)\n');
        fprintf('  [2] Fig2_Amplitude_Sweep            - 幅值扫描 (control)\n');
        fprintf('  [3] Fig3_Duty_Bias                  - 占空比偏置 (control)\n');
        fprintf('  [4] Fig4_Energy_Waterfall           - 能量流分配 (energy)\n');
        fprintf('  [5] Fig5_HeatSource_Allocation      - 热源分配 (energy)\n');
        fprintf('  [6] Fig6_Parameter_Sensitivity      - 参数敏感性 (sensitivity)\n');
        fprintf('  [7] Fig7_Thermal_TimeConstant       - 热时间常数 (sensitivity)\n');
        fprintf('  [8] Fig8_DCLink_Sensitivity         - DC-link电容敏感性 (sensitivity)\n');
        return;

    otherwise
        error('Unsupported target: "%s". Use "all", "control", "energy", "sensitivity", or "list".', targets);
end

fprintf('\n=== 全部图表已在 MATLAB 图形窗口中显示 ===\n');
end