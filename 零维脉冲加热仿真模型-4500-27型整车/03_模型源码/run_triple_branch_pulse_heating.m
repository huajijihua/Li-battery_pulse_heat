%% Triple-branch zero-dimensional pulse-heating display model
% Runs only the three-battery-branch architecture group.

clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);
addpath(fullfile(script_dir, 'core'));
addpath(fullfile(script_dir, 'limits'));
addpath(fullfile(script_dir, 'plot'));
addpath(fullfile(fileparts(script_dir), '02_参数库'));

p = build_0528_pulse_heating_params();
study = build_0528_study_cases(p);
topology = define_pulse_topology('triple_branch');

fprintf('=== %s: %s ===\n', p.study_name, topology.name);
fprintf('模式: MATLAB图窗展示, 不生成结果文件。\n');
fprintf('参数状态: %s\n', p.parameter_status_cn);

result = solve_pulse_heating_case(p, study, topology);
print_pulse_heating_summary(result.summary, topology);
plot_pulse_heating_results(result, p, study, topology);

fprintf('\n%s图窗已生成。脚本未写出CSV/MAT/PNG/HTML/Markdown结果文件。\n', topology.short_name);
fprintf('=== %s完成 ===\n', topology.name);
