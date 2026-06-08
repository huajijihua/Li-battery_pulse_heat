%% 4500-27 zero-dimensional pulse-heating screening
% Uses the updated 811.44V target-vehicle workbook parameters.

clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
project_dir = fileparts(script_dir);
addpath(script_dir);
addpath(fullfile(script_dir, 'core'));
addpath(fullfile(script_dir, 'limits'));
addpath(fullfile(script_dir, 'plot'));
addpath(fullfile(project_dir, '02_参数库'));

p = build_4500_27_pulse_heating_params();
study = build_4500_27_study_cases(p);
topology = define_pulse_topology('vehicle_4500_27');

fprintf('=== %s: %s ===\n', p.study_name, topology.name);
fprintf('参数状态: %s\n', p.parameter_status_cn);
fprintf('热边界: %s\n', p.thermal_assumption_cn);
fprintf('电机电流边界: %s\n', p.motor_current_limit_note_cn);

result = solve_pulse_heating_case(p, study, topology);
print_pulse_heating_summary(result.summary, topology);
plot_pulse_heating_results(result, p, study, topology);

output_dir = fullfile(project_dir, '05_仿真结果', '4500_27_screening');
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

writetable(result.summary, fullfile(output_dir, '4500_27_summary.csv'));
writetable(result.results, fullfile(output_dir, '4500_27_scan_results.csv'));

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
