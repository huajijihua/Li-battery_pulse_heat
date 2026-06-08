%% Compatibility entry for the 0528 pulse-heating model
% The model has been split into separate dual-branch and triple-branch
% architecture entries. This file keeps the old entry name available and
% intentionally does not calculate both architectures together.

clear; clc;

script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

fprintf('0528零维脉冲加热模型已拆分为两个独立入口。\n\n');
fprintf('双支路电池架构:\n');
fprintf('  run_dual_branch_pulse_heating\n\n');
fprintf('三支路电池架构:\n');
fprintf('  run_triple_branch_pulse_heating\n\n');
fprintf('请按需要运行其中一个入口。旧入口不再一次性混合计算双支路和三支路结果。\n');
