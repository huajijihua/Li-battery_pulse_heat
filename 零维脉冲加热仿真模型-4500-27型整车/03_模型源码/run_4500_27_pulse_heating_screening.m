%% 4500-27 zero-dimensional pulse-heating screening
% Uses the updated 811.44V target-vehicle workbook parameters.
% 中文说明:
% 本脚本是4500-27整车零维脉冲加热模型的主入口。它负责加载参数、
% 定义仿真工况和整车拓扑，调用核心求解器，然后输出摘要表、扫描表和报告图。
% 注意: 这是粗筛模型入口，不是实车安全放行脚本。

% 清理当前MATLAB会话，避免旧变量、旧图窗影响本次运行。
clear; close all; clc;

% 定位项目目录，并把参数库、核心计算、限制判断和绘图函数加入搜索路径。
% 这些addpath会影响当前MATLAB会话；若后续做成自动化工具，建议改成函数并在退出时恢复路径。
script_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(script_dir);
addpath(script_dir);
addpath(fullfile(script_dir, 'core'));
addpath(fullfile(script_dir, 'limits'));
addpath(fullfile(script_dir, 'plot'));
addpath(fullfile(project_dir, '02_参数库'));

% 构造三类输入:
% p        : 车型/部件参数，例如电池、电机、逆变器、热边界。
% study    : 本次要扫描的温度、频率、占空比、电流幅值和限流范围。
% topology : 当前4500-27实车约束下允许的电池包-电机接入方案。
p = build_4500_27_pulse_heating_params();
study = build_4500_27_study_cases(p);
topology = define_pulse_topology('vehicle_4500_27');

% 在命令行打印关键假设，提醒读者不要把占位参数误解为已验证实车数据。
fprintf('=== %s: %s ===\n', p.study_name, topology.name);
fprintf('参数状态: %s\n', p.parameter_status_cn);
fprintf('热边界: %s\n', p.thermal_assumption_cn);
fprintf('电机电流边界: %s\n', p.motor_current_limit_note_cn);

% 核心求解:
% result.summary     默认工况摘要。
% result.results     全量参数扫描结果。
% result.sensitivity 报告用敏感性汇总。
result = solve_pulse_heating_case(p, study, topology);
print_pulse_heating_summary(result.summary, topology);
plot_pulse_heating_results(result, p, study, topology);

% 输出目录。主脚本每次运行会删除旧的4500_27_fig*.png并重新导出图，
% 如果需要保留历史结果，应改用带时间戳的输出目录。
output_dir = fullfile(project_dir, '05_仿真结果', '4500_27_screening');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
delete(fullfile(output_dir, '4500_27_fig*.png'));

% 写出CSV表格，便于在Excel或报告中继续筛选、排序和复核。
writetable(result.summary, fullfile(output_dir, '4500_27_summary.csv'));
writetable(result.results, fullfile(output_dir, '4500_27_scan_results.csv'));
writetable(result.sensitivity, fullfile(output_dir, '4500_27_sensitivity_summary.csv'));

% 导出当前打开的MATLAB图窗。图的计算结果来自上面的result，不在这里重新求解。
figs = findall(0, 'Type', 'figure');
figs = flipud(figs);
for k = 1:numel(figs)
    fig = figs(k);
    fig_name = sprintf('4500_27_fig%02d', k);
    exportgraphics(fig, fullfile(output_dir, [fig_name, '.png']), ...
        'Resolution', 180);
end

fprintf('\n结果已写出到: %s\n', output_dir);
fprintf('=== 4500-27仿真完成 ===\n');
