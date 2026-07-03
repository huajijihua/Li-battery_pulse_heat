function result = run_4500_27_pulse_heating_screening_singlefile()
%RUN_4500_27_PULSE_HEATING_SCREENING_SINGLEFILE One-file 4500-27 pulse-heating model.
% 中文说明:
% 本文件是4500-27型整车零维脉冲加热模型的单文件发布版。
% 使用方式: 下载本m文件后，在MATLAB中打开并点击Run，或在命令行运行
% run_4500_27_pulse_heating_screening_singlefile。
%
% 建模内容 / 控制方程:
% 1) 车辆拓扑: 三包并联整体输出, 单电机/双电机两种可接入边界;
% 2) 电气主方程: OCV = f(SOC), R = f(T,SOC), R-L PWM等效回路响应;
% 3) 电流合成: I_pack,rms 由多电机RMS相关系数rho合成, 再按支路电导分流;
% 4) 产热方程: P_battery = sum(I_branch,rms^2 * R_branch);
% 5) 热平衡方程: dT/dt = (P_battery - P_loss - P_motor - P_inverter) / C_th;
% 6) 限流方程: current_scale = min(电机RMS裕度, 电机峰值裕度, 电池高频峰值裕度);
% 7) 安全参考: 30s/60s窗口与析锂参考仅作边界提示, 不作为最终放行结论。
%
% 主要变量口径:
% p     : 车型/部件参数;
% study : 扫描工况;
% topology : 当前4500-27实车约束下允许的接入方案;
% op    : 单点工作点结果;
% sim   : 30min瞬态结果;
%
% 使用边界:
% 该模型是L0.5零维集总粗筛模型，用于判断温升量级、能耗、电流压力和方案排序；
% 不能替代BMS、MCU、电机/逆变器热安全和整车安全放行验证。

    close all;
    clc;

    % 输出目录以本文件所在目录为根目录，便于单文件转发后在任意位置运行。
    model_dir = fileparts(mfilename('fullpath'));
    if isempty(model_dir)
        model_dir = pwd;
    end
    output_dir = fullfile(model_dir, '05_仿真结果', '4500_27_screening');
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    delete_old_output_figures(output_dir);

    % 构造三类输入:
    % p        : 车型/部件参数，例如电池、电机、逆变器、热边界。
    % study    : 本次要扫描的温度、频率、占空比、电流幅值和限流范围。
    % topology : 当前4500-27实车约束下允许的电池包-电机接入方案。
    p = build_4500_27_pulse_heating_params();
    study = build_4500_27_study_cases(p);
    topology = define_pulse_topology('vehicle_4500_27');

    fprintf('=== %s: %s ===\n', p.study_name, topology.name);
    fprintf('参数状态: %s\n', p.parameter_status_cn);
    fprintf('热边界: %s\n', p.thermal_assumption_cn);
    fprintf('电机电流边界: %s\n', p.motor_current_limit_note_cn);

    % 核心求解和结果展示。
    result = solve_pulse_heating_case(p, study, topology);
    print_pulse_heating_summary(result.summary, topology);
    plot_pulse_heating_results(result, p, study, topology);

    % 写出CSV表格，便于在Excel或报告中继续筛选、排序和复核。
    writetable(result.summary, fullfile(output_dir, '4500_27_summary.csv'));
    writetable(result.results, fullfile(output_dir, '4500_27_scan_results.csv'));
    writetable(result.sensitivity, fullfile(output_dir, '4500_27_sensitivity_summary.csv'));

    % 导出当前打开的MATLAB图窗。图的计算结果来自result，不在这里重新求解。
    figs = findall(0, 'Type', 'figure');
    figs = flipud(figs);
    for k = 1:numel(figs)
        fig_name = sprintf('4500_27_fig%02d', k);
        export_one_figure_png(figs(k), fullfile(output_dir, [fig_name, '.png']));
    end

    fprintf('\n结果已写出到: %s\n', output_dir);
    fprintf('=== 4500-27仿真完成 ===\n');
end

function delete_old_output_figures(output_dir)
%DELETE_OLD_OUTPUT_FIGURES Remove previous generated report figures only.
% 只清理本模型固定命名的PNG图，避免误删其他人工放入的文件。

    old_figs = dir(fullfile(output_dir, '4500_27_fig*.png'));
    for k = 1:numel(old_figs)
        delete(fullfile(old_figs(k).folder, old_figs(k).name));
    end
end

function export_one_figure_png(fig, file_path)
%EXPORT_ONE_FIGURE_PNG Export a figure with a fallback for older MATLAB releases.
% exportgraphics在较新的MATLAB中效果更好；若版本不支持，则退回print。

    if exist('exportgraphics', 'file') == 2 || exist('exportgraphics', 'builtin') == 5
        exportgraphics(fig, file_path, 'Resolution', 180);
    else
        print(fig, file_path, '-dpng', '-r180');
    end
end


%% ------------------------------------------------------------------------
% Local functions from build_4500_27_pulse_heating_params.m

function p = build_4500_27_pulse_heating_params()
%BUILD_4500_27_PULSE_HEATING_PARAMS Updated 4500-27 vehicle parameters.
% Values are taken from 零维脉冲加热_参数需求.xlsx updated on 2026-06-08.
% 中文说明:
% 本函数集中定义4500-27整车零维模型所需的所有参数。输出p是一个结构体，
% 后续电路、电热、限流和安全边界计算都从p读取参数。这里既包含已收到的
% 目标车型数据，也包含用于粗筛的占位假设；占位项均应在报告中保留边界说明。

    % 基本项: 研究名称和参数状态，用于命令行和输出表标识当前参数版本。
    p = struct();
    p.study_name = '4500-27型整车零维脉冲加热仿真';
    p.parameter_status = 'target_vehicle_updated_20260608';
    p.parameter_status_cn = ['4500-27更新参数: 811.44V高压平台, ', ...
        '3个252S/278Ah电池包并联输出, 双CAM255PT56电机'];

    % 电池包/支路基础参数:
    % 参数表给出3个电池包并联输出且非独立输出。零维模型把每个电池包视作
    % 一个并联支路；当前4500-27实车方案不假设单包可独立接入电驱。
    p.N_series = 252;
    p.V_cell_nom = 811.44 / 252;
    p.V_pack_nom_V = 811.44;
    p.V_pack_min_V = 630;
    p.V_pack_max_V = 919.8;
    p.pack_count_vehicle = 3;
    p.C_branch_Ah = 278;
    p.E_branch_nom_kWh = 225.6;
    p.branch_mass_kg = 1370;
    p.Cp_battery_J_per_kgK = 1000;
    p.Cth_branch_J_per_K = p.branch_mass_kg * p.Cp_battery_J_per_kgK;
    p.branch_area_m2 = 8.0;
    p.h_conv_W_per_m2K = 5.0;
    p.h_conv_scan_W_per_m2K = [0 2 5 10 20];
    p.enable_heat_loss = true;
    p.thermal_boundary = 'convection';
    p.R_th_branch_K_per_W = 1 / (p.h_conv_W_per_m2K * p.branch_area_m2);
    p.thermal_assumption_cn = ['电池包比热容、低温预热时冷却液/泵阀状态未提供; ', ...
        '当前按Cp=1000J/kg/K和弱对流散热作粗筛占位'];

    % OCV表:
    % 根据SOC插值得到单体开路电压，再乘以串数得到电池包电压。当前未加入OCV温度修正。
    p.ocv_soc_bp = [0 0.05 0.10 0.15 0.20 0.25 0.30 0.35 ...
        0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 ...
        0.90 0.95 1.00];
    p.ocv_cell_V = [2.688 3.166 3.203 3.222 3.249 3.267 3.285 ...
        3.288 3.289 3.290 3.291 3.296 3.326 3.329 3.329 ...
        3.329 3.329 3.330 3.332 3.334 3.484];

    % 电池内阻表:
    % 附件1给的是电芯级1s BOL放电DCR，这里换算成一个252S1P电池包支路电阻。
    % 这不是高频AC阻抗Re(Z)，所以只能作为高频脉冲发热粗筛的保守参考。
    p.R_data_SOC = [0.10 0.20 0.50 0.90];
    p.R_data_T_C = [-20 25];
    R_cell_1s_mOhm = [ ...
        2.36 2.32 2.23 2.09; ...
        0.33 0.33 0.31 0.29];
    p.R_branch_table_ohm = R_cell_1s_mOhm * 1e-3 * p.N_series;
    p.R_heat_factor_default = 1.00;
    p.R_heat_factor_scan = [0.30 0.50 0.70 1.00];
    p.R_branch_source = ['附件1 1s BOL放电DCR, 电芯mOhm换算为252S1P支路; ', ...
        '未获得高频AC阻抗/HPPC温度-SOC全表; R_heat_factor用于高频阻抗敏感性'];

    % 电机/逆变器约束:
    % Ld用于当前零速/堵转RL近似计算，Lq暂作参考。电机RMS和峰值电流用于硬限流缩放。
    % motor_Rs_ohm按“三相14mOhm为三相总等效”解释，因此除以3得到每相等效值；
    % 该解释需要供应商资料最终确认。
    p.motor_count = 2;
    p.motor_Ld_H = 0.2605e-3;     % 附件2, 550A附近Ld均值
    p.motor_Lq_H = 0.3927e-3;     % 附件2, 550A附近Lq均值, for reference
    p.motor_Rs_ohm = 14e-3 / 3;   % 三相14mOhm@25C interpreted as total three-phase
    p.motor_Rs_source_cn = '三相14±0.5mOhm@25C, 模型按每相等效约4.67mOhm处理';
    p.I_motor_rms_limit_A = 550;  % 550Arms short-time electrical boundary
    p.I_motor_peak_limit_A = sqrt(2) * p.I_motor_rms_limit_A;
    p.I_motor_rms_continuous_A = 320;
    p.I_motor_rms_short_A = 550;
    p.I_motor_rms_limit_default_A = 550;
    p.I_motor_rms_limit_scan_A = [320 450 550];
    p.motor_current_limit_note_cn = ['550Arms来自60s/30s等级约束, ', ...
        '320Arms为>=30min持续电流; 当前图表显示电气能力, 长时热耐久需单独验证'];

    p.inverter_V_nom_V = 800;
    p.inverter_V_min_V = 600;
    p.inverter_V_max_V = 910;
    p.inverter_UV_protect_V = 580;
    p.inverter_OV_protect_V = 930;
    p.f_default_Hz = 1250;
    p.f_control_min_Hz = 1250;
    p.f_control_max_Hz = 4000;
    p.duty_default = 0.50;
    p.branch_hf_peak_limit_A = inf;  % BMS high-frequency limit not supplied.
    p.current_amplitude_scale_default = 1.00;
    p.current_amplitude_scale_scan = [0.40 0.60 0.80 1.00 1.20];

    % 逆变器损耗占位参数:
    % 当前没有目标硬件损耗图或器件热模型，因此这些参数只用于损耗量级估算，
    % 不能用于逆变器结温、寿命或连续工作能力结论。
    p.V_ce0 = 0.8;
    p.r_ce = 2.5e-3;
    p.V_f0 = 0.7;
    p.r_f = 2.0e-3;
    p.E_on = 25e-3;
    p.E_off = 20e-3;
    p.E_rr = 15e-3;
    p.I_ref_sw = 400;
    p.V_ref_sw = 800;

    % 电池30s/60s参考窗口:
    % 这些窗口按SOC 50%参考整理，只用于低频/准直流规格参考展示，
    % 不是kHz脉冲回充半周的硬限流边界。
    p.current_window_T_C = [-20 -10 0 10];
    p.branch_charge_30s_ref_A = [3.6 13.4 47.4 136.0];
    p.branch_charge_60s_ref_A = [23 73 216 474] ./ 3.291;
    p.branch_discharge_30s_ref_A = [320 767 1515 2071] ./ 3.291;
    p.branch_discharge_60s_ref_A = p.branch_discharge_30s_ref_A;

    % 析锂风险参考接口:
    % 当前缺少目标电芯低温EIS、HPPC和析锂试验边界，因此该模型只输出风险参考裕度。
    % 它不应被解释为已标定的BMS硬保护逻辑。
    p.battery_current_limit_mode = 'plating_adaptive';
    p.apply_discharge_spec_limit_in_plating_mode = false;
    p.current_window_duration_s = 60;
    p.current_window_SOC_ref = 0.50;
    p.current_window_N_parallel_ref = 1;
    p.N_parallel_branch = 1;
    p.C_cell_Ah = p.C_branch_Ah;
    p.plating_R_ct_ref = 0.12e-3;
    p.plating_Ea_ct = 3600;
    p.plating_R_SEI_ref = 0.015e-3;
    p.plating_Ea_SEI = 2500;
    p.plating_C_dl = 1.5;
    p.plating_k_safety = 0.85;

    % 仿真默认工况与扫描范围:
    % temperature/frequency/duty/current_amplitude_scale用于全量粗筛；
    % branch_mismatch_sets用于检查三包支路阻抗不一致导致的不均流；
    % dual_motor_sync_correlation用于双电机电池侧电流同步风险边界。
    p.temperature_list_C = [-20 -10 0];
    p.SOC_default = 0.50;
    p.frequency_scan_Hz = [1250 2000 3000 4000];
    p.duty_scan = [0.40 0.50 0.60];
    p.branch_mismatch_sets = [ ...
        1.00 1.00 1.00; ...
        0.90 1.00 1.10];
    p.branch_mismatch_labels = {'nominal', 'R_90_100_110'};
    p.dual_motor_sync_correlation_default = 1.00;
    p.dual_motor_sync_correlation_scan = [1.00 0.75 0.50 0.00 -0.50];
    p.dual_motor_sync_note_cn = ['双电机同步相关系数rho仅用于L0.5控制风险边界: ', ...
        'rho=1表示电池侧电流理想同相合成, rho=0表示不同频/不锁相长期平均近似, ', ...
        'rho<0表示反相趋势风险; 该口径不替代真实PWM/dq控制仿真'];
    p.T_amb_C = -20;
    p.T_init_C = -20;
    p.T_target_C = 0;
    p.t_end_min = 30;
    p.dt_s = 5;
end


%% ------------------------------------------------------------------------
% Local functions from build_4500_27_study_cases.m

function study = build_4500_27_study_cases(p)
%BUILD_4500_27_STUDY_CASES Study settings for the 4500-27 screening run.
% 中文说明:
% 本函数把参数库p中的“扫描范围”和“默认工况”整理成study结构体。
% p表示车型和部件参数，study表示本次仿真怎么扫。这样后续可以保持同一套车型参数，
% 只替换study来做不同的工况矩阵。

    study = struct();
    % 全量扫描维度: 温度、SOC、频率、占空比、电流幅值、内阻倍率、电机限流和支路不均衡。
    study.temperature_list_C = p.temperature_list_C;
    study.SOC = p.SOC_default;
    study.frequency_scan_Hz = p.frequency_scan_Hz;
    study.duty_scan = p.duty_scan;
    study.default_temperature_C = p.T_init_C;
    study.default_frequency_Hz = p.f_default_Hz;
    study.default_duty = p.duty_default;
    study.current_amplitude_scale_scan = p.current_amplitude_scale_scan;
    study.default_current_amplitude_scale = p.current_amplitude_scale_default;
    study.R_heat_factor_scan = p.R_heat_factor_scan;
    study.default_R_heat_factor = p.R_heat_factor_default;
    study.motor_rms_limit_scan_A = p.I_motor_rms_limit_scan_A;
    study.default_motor_rms_limit_A = p.I_motor_rms_limit_default_A;
    study.branch_mismatch_sets = p.branch_mismatch_sets;
    study.branch_mismatch_labels = p.branch_mismatch_labels;

    % 双电机同步相关性:
    % rho=1表示电池侧电流理想同相叠加；rho=0表示长期平均不锁相近似；
    % rho<0表示反相趋势风险边界。它不能替代真实PWM和电流环时域仿真。
    study.default_motor_sync_correlation = p.dual_motor_sync_correlation_default;
    study.motor_sync_correlation_scan = p.dual_motor_sync_correlation_scan;

    % 瞬态仿真时间设置，用于估算30min内平均温度和等效SOC变化。
    study.t_end_min = p.t_end_min;
    study.dt_s = p.dt_s;
end


%% ------------------------------------------------------------------------
% Local functions from define_pulse_topology.m

function topology = define_pulse_topology(topology_id)
%DEFINE_PULSE_TOPOLOGY Returns pulse-heating architecture definitions.
% 中文说明:
% 本函数定义4500-27整车电池包和电机如何接入脉冲加热回路。
% 当前只保留vehicle_4500_27，即三包并联整体输出，不假设单包可独立接入电驱。

    topology_id = lower(string(topology_id));
    case_template = struct('id', '', 'name', '', 'branch_count', 0, ...
        'motor_count', 0, 'type', '', 'description', '');

    switch topology_id
        case "vehicle_4500_27"
            % 当前4500-27实车约束方案:
            % 参数表说明三个电池包并联整体输出且不可独立接入电驱，因此只评估
            % “三包并联单电机”和“三包并联双电机”两种真实可接入边界。
            cases = repmat(case_template, 1, 2);
            cases(1).id = '三包并联单电机';
            cases(1).name = '三包并联整体输出，单电机脉冲';
            cases(1).branch_count = 3;
            cases(1).motor_count = 1;
            cases(1).type = 'whole_branch_sync';
            cases(1).description = ['参数表约束下的实车可行边界: 三个电池包非独立输出、并联输出、不可独立接入电驱, ', ...
                '因此所有电池包作为一个并联系统共同参与; 仅一台电机/逆变器施加堵转脉冲, 作为低复杂度基准方案'];

            cases(2).id = '三包并联双电机';
            cases(2).name = '三包并联整体输出，双电机脉冲';
            cases(2).branch_count = 3;
            cases(2).motor_count = 2;
            cases(2).type = 'whole_branch_sync';
            cases(2).description = ['参数表约束下的实车主方案: 三个电池包作为不可拆分的并联高压源共同给双电机/逆变器脉冲回路供能, ', ...
                '两台电机同步施加堵转脉冲; 只评估电机侧激励强度、频率、占空比和支路分流, 不假设单包独立接入'];

            topology = struct('id', 'vehicle_4500_27', 'name', '4500-27实车可接入方案', ...
                'short_name', '4500-27实车约束', 'branch_count', 3, 'cases', cases);

        otherwise
            error('未知脉冲加热拓扑: %s。', topology_id);
    end
end


%% ------------------------------------------------------------------------
% Local functions from solve_pulse_heating_case.m

function result = solve_pulse_heating_case(p, study, topology)
%SOLVE_PULSE_HEATING_CASE Runs scans and default transient simulations.
% 中文说明:
% 本函数是批量求解器。它完成三类输出:
% 1) result.results: 全量参数扫描；
% 2) result.summary: 默认工况摘要；
% 3) result.sensitivity: 报告用敏感性汇总。
% 所有单点物理计算都委托给eval_circuit_operating_point。

    result_rows = struct([]);
    row_idx = 0;

    % 全量扫描:
    % 逐一遍历拓扑方案、支路不均衡、内阻倍率、电机限流、温度、频率、
    % 占空比和电流幅值系数。每个组合生成一行结果。
    for i_case = 1:numel(topology.cases)
        c = topology.cases(i_case);
        for i_mis = 1:numel(study.branch_mismatch_labels)
            mismatch = get_case_mismatch(study, i_mis, c.branch_count);
            for i_R = 1:numel(study.R_heat_factor_scan)
                for i_lim = 1:numel(study.motor_rms_limit_scan_A)
                    p_case = apply_sensitivity_params(p, ...
                        study.R_heat_factor_scan(i_R), ...
                        study.motor_rms_limit_scan_A(i_lim));
                    for T_C = study.temperature_list_C
                        for f_Hz = study.frequency_scan_Hz
                            for duty = study.duty_scan
                                for amplitude_scale = study.current_amplitude_scale_scan
                                    op = eval_circuit_operating_point(p_case, c, T_C, ...
                                        study.SOC, f_Hz, duty, mismatch, amplitude_scale, ...
                                        study.default_motor_sync_correlation);
                                    row_idx = row_idx + 1;
                                    row = make_result_row(p_case, c, study, i_mis, ...
                                        T_C, f_Hz, duty, op);
                                    if row_idx == 1
                                        result_rows = row;
                                    else
                                        result_rows(row_idx) = row;
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    result = struct();
    result.results = struct2table(result_rows);

    % 默认工况摘要和瞬态仿真用于报告主结论；敏感性汇总用于解释参数影响。
    [result.summary, result.sims] = build_default_summary(p, study, topology);
    result.sensitivity = build_sensitivity_summary(p, study, topology);
    result.topology = topology;
end

function row = make_result_row(p, c, study, i_mis, T_C, f_Hz, duty, op)
    % 将一个工作点op展开成表格行。字段尽量保留工程含义，方便后续Excel筛选。
    row = struct();
    row.case_id = c.id;
    row.case_name = c.name;
    row.branch_count = c.branch_count;
    row.mismatch_label = study.branch_mismatch_labels{i_mis};
    row.T_init_C = T_C;
    row.SOC = study.SOC;
    row.frequency_Hz = f_Hz;
    row.duty = duty;
    row.current_amplitude_scale = op.current_amplitude_scale;
    row.motor_sync_correlation = op.motor_sync_correlation;
    row.battery_current_sync_factor = op.battery_current_sync_factor;
    row.battery_heating_sync_factor = op.battery_heating_sync_factor;
    row.R_heat_factor = op.R_heat_factor;
    row.motor_rms_limit_A = op.motor_rms_limit_A;
    row.effective_current_scale = op.effective_current_scale;
    row.dTdt_C_per_min = op.dTdt_C_per_min;
    row.time_to_0C_min = op.time_to_target_min;
    row.P_battery_kW = op.P_battery_W / 1000;
    row.P_motor_kW = op.P_motor_W / 1000;
    row.P_inverter_kW = op.P_inverter_W / 1000;
    row.P_heat_loss_kW = op.P_loss_W / 1000;
    row.P_net_kW = op.P_net_W / 1000;
    row.heating_efficiency_pct = op.heating_efficiency * 100;
    row.I_motor_rms_A = op.I_motor_rms_A;
    row.I_motor_peak_A = op.I_motor_peak_A;
    row.I_branch_rms_max_A = op.I_branch_rms_max_A;
    row.I_branch_peak_max_A = op.I_branch_peak_max_A;
    row.I_bus_rms_A = op.I_bus_rms_A;
    row.I_switch_rms_A = op.I_switch_rms_A;
    row.motor_rms_margin = op.current_limits.motor_rms_margin;
    row.motor_peak_margin = op.current_limits.motor_peak_margin;
    row.branch_peak_margin = op.current_limits.branch_peak_margin;
    row.frequency_margin = op.frequency_margin;
    row.plating_reference_margin = op.plating_reference_margin;
    row.spec_charge_30s_A = op.safety.spec_charge_30s_A;
    row.spec_discharge_30s_A = op.safety.spec_discharge_30s_A;
    row.spec_charge_60s_A = op.safety.spec_charge_60s_A;
    row.spec_discharge_60s_A = op.safety.spec_discharge_60s_A;
    row.plating_charge_reference_A = op.safety.plating_charge_reference_A;
    row.branch_heat_spread_pct = op.branch_heat_spread_pct;
    row.branch_energy_spread_30min_kWh = op.branch_energy_spread_30min_kWh;
    row.current_scale = op.current_scale;
    row.limiting_factor = op.limiting_factor;
    row.safety_status = op.safety.status;
    row.E_battery_heat_30min_kWh = op.P_battery_W / 1000 * p.t_end_min / 60;
    row.E_motor_loss_30min_kWh = op.P_motor_W / 1000 * p.t_end_min / 60;
    row.E_inverter_loss_30min_kWh = op.P_inverter_W / 1000 * p.t_end_min / 60;
    row.E_heat_loss_30min_kWh = op.P_loss_W / 1000 * p.t_end_min / 60;
    row.E_net_heat_30min_kWh = op.P_net_W / 1000 * p.t_end_min / 60;
    row.E_total_loss_equiv_30min_kWh = op.P_total_electric_W / 1000 * p.t_end_min / 60;
    row.energy_equiv_SOC_delta_30min_pct = estimate_energy_equiv_soc_delta_pct(p, c, study.SOC, ...
        row.E_total_loss_equiv_30min_kWh);
    row.coulombic_SOC_delta_30min_pct = nan;
    row.SOC_accounting_note = soc_accounting_note();
    row.P_branch_1_kW = get_vector_value(op.P_branch_W, 1) / 1000;
    row.P_branch_2_kW = get_vector_value(op.P_branch_W, 2) / 1000;
    row.P_branch_3_kW = get_vector_value(op.P_branch_W, 3) / 1000;
    row.note = op.note;
end

function [summary, sims] = build_default_summary(p, study, topology)
    % 对每个拓扑方案运行默认工况，并同时保存30min瞬态曲线。
    summary_rows = struct([]);
    sims = repmat(struct(), 1, numel(topology.cases));

    for i_case = 1:numel(topology.cases)
        c = topology.cases(i_case);
        mismatch = get_case_mismatch(study, 1, c.branch_count);
        op = eval_circuit_operating_point(p, c, study.default_temperature_C, ...
            study.SOC, study.default_frequency_Hz, study.default_duty, ...
            mismatch, study.default_current_amplitude_scale, ...
            study.default_motor_sync_correlation);
        sim = simulate_pulse_heating_case(p, study, c, mismatch);

        sims(i_case).case_id = c.id;
        sims(i_case).case_name = c.name;
        sims(i_case).data = sim;

        row = make_summary_row(p, c, sim, op);
        if i_case == 1
            summary_rows = row;
        else
            summary_rows(i_case) = row;
        end
    end

    summary = struct2table(summary_rows);
end

function row = make_summary_row(p, c, sim, op)
    % 将默认工况的瞬态结果和初始工作点合并成摘要行。
    % 注意: energy_equiv_SOC是总不可逆损耗折算，不是库仑积分SOC。
    row = struct();
    row.case_id = c.id;
    row.case_name = c.name;
    row.branch_count = c.branch_count;
    row.architecture_summary = c.description;
    row.dTdt_initial_C_per_min = op.dTdt_C_per_min;
    row.T_end_30min_C = sim.T_mean_C(end);
    row.time_to_0C_min = estimate_target_time(sim.t_min, sim.T_mean_C, p.T_target_C);
    row.E_total_loss_equiv_to_0C_kWh = interpolate_metric_at_target(sim.t_min, ...
        sim.T_mean_C, sim.E_total_electric_kWh, p.T_target_C);
    row.energy_equiv_SOC_delta_to_0C_pct = (sim.SOC(1) - interpolate_metric_at_target( ...
        sim.t_min, sim.T_mean_C, sim.SOC, p.T_target_C)) * 100;
    row.coulombic_SOC_delta_to_0C_pct = nan;
    row.P_battery_kW = op.P_battery_W / 1000;
    row.P_motor_kW = op.P_motor_W / 1000;
    row.P_inverter_kW = op.P_inverter_W / 1000;
    row.P_heat_loss_kW = op.P_loss_W / 1000;
    row.P_net_kW = op.P_net_W / 1000;
    row.heating_efficiency_pct = op.heating_efficiency * 100;
    row.I_motor_rms_A = op.I_motor_rms_A;
    row.I_motor_peak_A = op.I_motor_peak_A;
    row.I_branch_rms_max_A = op.I_branch_rms_max_A;
    row.I_branch_peak_max_A = op.I_branch_peak_max_A;
    row.I_bus_rms_A = op.I_bus_rms_A;
    row.branch_heat_spread_pct = op.branch_heat_spread_pct;
    row.current_scale = op.current_scale;
    row.current_amplitude_scale = op.current_amplitude_scale;
    row.motor_sync_correlation = op.motor_sync_correlation;
    row.battery_current_sync_factor = op.battery_current_sync_factor;
    row.battery_heating_sync_factor = op.battery_heating_sync_factor;
    row.R_heat_factor = op.R_heat_factor;
    row.motor_rms_limit_A = op.motor_rms_limit_A;
    row.effective_current_scale = op.effective_current_scale;
    row.limiting_factor = op.limiting_factor;
    row.safety_status = op.safety.status;
    row.frequency_margin = op.frequency_margin;
    row.plating_reference_margin = op.plating_reference_margin;
    row.spec_charge_30s_A = op.safety.spec_charge_30s_A;
    row.spec_discharge_30s_A = op.safety.spec_discharge_30s_A;
    row.spec_charge_60s_A = op.safety.spec_charge_60s_A;
    row.spec_discharge_60s_A = op.safety.spec_discharge_60s_A;
    row.plating_charge_reference_A = op.safety.plating_charge_reference_A;
    row.E_battery_heat_30min_kWh = sim.E_battery_heat_kWh(end);
    row.E_motor_loss_30min_kWh = sim.E_motor_loss_kWh(end);
    row.E_inverter_loss_30min_kWh = sim.E_inverter_loss_kWh(end);
    row.E_heat_loss_30min_kWh = sim.E_heat_loss_kWh(end);
    row.E_net_heat_30min_kWh = sim.E_net_heat_kWh(end);
    row.E_total_loss_equiv_30min_kWh = sim.E_total_electric_kWh(end);
    row.energy_equiv_SOC_delta_30min_pct = (sim.SOC(1) - sim.SOC(end)) * 100;
    row.energy_equiv_SOC_end_pct = sim.SOC(end) * 100;
    row.coulombic_SOC_delta_30min_pct = nan;
    row.SOC_accounting_note = soc_accounting_note();
    row.initial_judgement = make_case_judgement(op);
    row.note = op.note;
end

function sim = simulate_pulse_heating_case(p, study, c, mismatch, sim_cfg)
    % 30min零维瞬态仿真:
    % 每个时间步根据当前平均温度和SOC重新计算电气工作点，再用每支路净热功率更新支路温度。
    % 审查备注: 当前电气分流使用mean(T_branch)插值电阻，支路温差不会反馈到分流比例。
    % 如果后续重点分析支路热失衡，应改为每个支路分别按温度插值电阻。
    if nargin < 5
        sim_cfg = struct('frequency_Hz', study.default_frequency_Hz, ...
            'duty', study.default_duty, ...
            'current_amplitude_scale', study.default_current_amplitude_scale, ...
            'motor_sync_correlation', study.default_motor_sync_correlation, ...
            'SOC', study.SOC, 'T_init_C', p.T_init_C);
    end
    n_steps = floor(study.t_end_min * 60 / study.dt_s) + 1;
    t_s = (0:n_steps-1)' * study.dt_s;
    T_branch = zeros(n_steps, c.branch_count);
    SOC = zeros(n_steps, 1);
    P_branch = zeros(n_steps, c.branch_count);
    P_battery = zeros(n_steps, 1);
    P_motor = zeros(n_steps, 1);
    P_inverter = zeros(n_steps, 1);
    P_loss = zeros(n_steps, 1);
    P_net = zeros(n_steps, 1);
    E_battery_heat = zeros(n_steps, 1);
    E_motor_loss = zeros(n_steps, 1);
    E_inverter_loss = zeros(n_steps, 1);
    E_heat_loss = zeros(n_steps, 1);
    E_net_heat = zeros(n_steps, 1);
    E_total_electric = zeros(n_steps, 1);
    dTdt = zeros(n_steps, 1);
    I_motor_rms = zeros(n_steps, 1);
    I_motor_peak = zeros(n_steps, 1);
    I_branch_rms_max = zeros(n_steps, 1);
    I_branch_peak_max = zeros(n_steps, 1);
    I_bus_rms = zeros(n_steps, 1);

    T_branch(1, :) = sim_cfg.T_init_C;
    SOC(1) = sim_cfg.SOC;

    % 主时间循环。k对应当前时刻，k+1用显式欧拉法推进温度和等效SOC。
    for k = 1:n_steps
        op = eval_circuit_operating_point(p, c, mean(T_branch(k, :)), SOC(k), ...
            sim_cfg.frequency_Hz, sim_cfg.duty, mismatch, ...
            sim_cfg.current_amplitude_scale, sim_cfg.motor_sync_correlation);
        heat = eval_heat_balance(p, op.P_branch_W, T_branch(k, :), c.branch_count);

        P_branch(k, :) = op.P_branch_W;
        P_battery(k) = heat.P_battery_W;
        P_motor(k) = op.P_motor_W;
        P_inverter(k) = op.P_inverter_W;
        P_loss(k) = heat.P_loss_W;
        P_net(k) = heat.P_net_W;
        dTdt(k) = heat.dTdt_C_per_min;
        I_motor_rms(k) = op.I_motor_rms_A;
        I_motor_peak(k) = op.I_motor_peak_A;
        I_branch_rms_max(k) = op.I_branch_rms_max_A;
        I_branch_peak_max(k) = op.I_branch_peak_max_A;
        I_bus_rms(k) = op.I_bus_rms_A;

        if k < n_steps
            % 能量积分，单位换算为kWh，便于和整车能耗/SOC口径对齐。
            dt_h = study.dt_s / 3600;
            E_battery_heat(k+1) = E_battery_heat(k) + P_battery(k) / 1000 * dt_h;
            E_motor_loss(k+1) = E_motor_loss(k) + P_motor(k) / 1000 * dt_h;
            E_inverter_loss(k+1) = E_inverter_loss(k) + P_inverter(k) / 1000 * dt_h;
            E_heat_loss(k+1) = E_heat_loss(k) + P_loss(k) / 1000 * dt_h;
            E_net_heat(k+1) = E_net_heat(k) + P_net(k) / 1000 * dt_h;
            E_total_electric(k+1) = E_total_electric(k) + ...
                op.P_total_electric_W / 1000 * dt_h;
            T_branch(k+1, :) = T_branch(k, :) + heat.P_net_branch_W / ...
                p.Cth_branch_J_per_K * study.dt_s;

            % 等效SOC折算:
            % 用总不可逆电功率消耗折算SOC下降，包含电池发热、电机损耗和逆变器损耗。
            % 这不是BMS库仑计量SOC，因此coulombic_SOC_delta保持nan。
            E_total_kWh = c.branch_count * p.N_series * interp1( ...
                p.ocv_soc_bp, p.ocv_cell_V, SOC(k), 'linear', 'extrap') * ...
                p.C_branch_Ah / 1000;
            SOC(k+1) = max(0, SOC(k) - ...
        op.P_total_electric_W * study.dt_s / 3.6e6 / max(E_total_kWh, eps));
        end
    end

    sim = struct();
    sim.t_min = t_s / 60;
    sim.T_branch_C = T_branch;
    sim.T_mean_C = mean(T_branch, 2);
    sim.SOC = SOC;
    sim.energy_equiv_SOC = SOC;
    sim.SOC_accounting_note = soc_accounting_note();
    sim.P_branch_W = P_branch;
    sim.P_battery_W = P_battery;
    sim.P_motor_W = P_motor;
    sim.P_inverter_W = P_inverter;
    sim.P_loss_W = P_loss;
    sim.P_net_W = P_net;
    sim.E_battery_heat_kWh = E_battery_heat;
    sim.E_motor_loss_kWh = E_motor_loss;
    sim.E_inverter_loss_kWh = E_inverter_loss;
    sim.E_heat_loss_kWh = E_heat_loss;
    sim.E_net_heat_kWh = E_net_heat;
    sim.E_total_electric_kWh = E_total_electric;
    sim.dTdt_C_per_min = dTdt;
    sim.I_motor_rms_A = I_motor_rms;
    sim.I_motor_peak_A = I_motor_peak;
    sim.I_branch_rms_max_A = I_branch_rms_max;
    sim.I_branch_peak_max_A = I_branch_peak_max;
    sim.I_bus_rms_A = I_bus_rms;
end

function table_out = build_sensitivity_summary(p, study, topology)
    % 敏感性汇总分两部分:
    % 先扫内阻倍率和电机限流矩阵，再追加报告常用的电流幅值、频率、散热、内阻和双电机同步性扫描。
    rows = struct([]);
    row_idx = 0;
    t_eval_min = [10 20 30];

    for i_case = 1:numel(topology.cases)
        c = topology.cases(i_case);
        for i_mis = 1:numel(study.branch_mismatch_labels)
            mismatch = get_case_mismatch(study, i_mis, c.branch_count);
            for i_R = 1:numel(study.R_heat_factor_scan)
                for i_lim = 1:numel(study.motor_rms_limit_scan_A)
                    p_case = apply_sensitivity_params(p, ...
                        study.R_heat_factor_scan(i_R), ...
                        study.motor_rms_limit_scan_A(i_lim));
                    sim = simulate_pulse_heating_case(p_case, study, c, mismatch);
                    op = eval_circuit_operating_point(p_case, c, ...
                        study.default_temperature_C, study.SOC, ...
                        study.default_frequency_Hz, study.default_duty, ...
                        mismatch, study.default_current_amplitude_scale, ...
                        study.default_motor_sync_correlation);

                    row_idx = row_idx + 1;
                    row = make_sensitivity_row(p_case, c, study, i_mis, ...
                        sim, op, t_eval_min, 'R_heat_limit_matrix');
                    if row_idx == 1
                        rows = row;
                    else
                        rows(row_idx) = row;
                    end
                end
            end
        end
    end

    rows = append_report_sensitivity_rows(rows, row_idx, ...
        p, study, topology, t_eval_min);
    table_out = struct2table(rows);
end

function rows = append_report_sensitivity_rows(rows, row_idx, ...
        p, study, topology, t_eval_min)
    % 报告敏感性扫描默认聚焦“三包并联双电机”，因为它是当前实车主方案。
    c = get_topology_case(topology, '三包并联双电机');
    mismatch = ones(1, c.branch_count);
    i_mis = 1;

    for amp_scale = p.current_amplitude_scale_scan
        [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
            c, mismatch, i_mis, t_eval_min, 'current_amplitude', ...
            study.default_frequency_Hz, study.default_duty, amp_scale, ...
            study.SOC, p.R_heat_factor_default, ...
            p.I_motor_rms_limit_default_A, p.h_conv_W_per_m2K, ...
            study.default_motor_sync_correlation);
    end

    for f_Hz = p.frequency_scan_Hz
        [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
            c, mismatch, i_mis, t_eval_min, 'frequency', ...
            f_Hz, study.default_duty, study.default_current_amplitude_scale, ...
            study.SOC, p.R_heat_factor_default, ...
            p.I_motor_rms_limit_default_A, p.h_conv_W_per_m2K, ...
            study.default_motor_sync_correlation);
    end

    for h_conv = p.h_conv_scan_W_per_m2K
        [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
            c, mismatch, i_mis, t_eval_min, 'h_conv_boundary', ...
            study.default_frequency_Hz, study.default_duty, ...
            study.default_current_amplitude_scale, study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, h_conv, ...
            study.default_motor_sync_correlation);
    end

    for R_heat_factor = p.R_heat_factor_scan
        [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
            c, mismatch, i_mis, t_eval_min, 'R_heat_factor', ...
            study.default_frequency_Hz, study.default_duty, ...
            study.default_current_amplitude_scale, study.SOC, ...
            R_heat_factor, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K, study.default_motor_sync_correlation);
    end

    for rho = study.motor_sync_correlation_scan
        [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
            c, mismatch, i_mis, t_eval_min, 'dual_motor_sync_correlation', ...
            study.default_frequency_Hz, study.default_duty, ...
            study.default_current_amplitude_scale, study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K, rho);
    end
end

function [rows, row_idx] = append_one_report_row(rows, row_idx, p, study, ...
        c, mismatch, i_mis, t_eval_min, sensitivity_axis, f_Hz, duty, ...
        amp_scale, SOC0, R_heat_factor, motor_limit_A, h_conv, motor_sync_correlation)
    % 追加一行报告敏感性结果。不同sensitivity_axis只改变一个主变量，其余使用默认值。
    if nargin < 17 || isempty(motor_sync_correlation)
        motor_sync_correlation = study.default_motor_sync_correlation;
    end
    p_case = apply_sensitivity_params(p, R_heat_factor, motor_limit_A, h_conv);
    sim_cfg = struct('frequency_Hz', f_Hz, 'duty', duty, ...
        'current_amplitude_scale', amp_scale, 'SOC', SOC0, ...
        'T_init_C', study.default_temperature_C, ...
        'motor_sync_correlation', motor_sync_correlation);
    sim = simulate_pulse_heating_case(p_case, study, c, mismatch, sim_cfg);
    op = eval_circuit_operating_point(p_case, c, ...
        study.default_temperature_C, SOC0, f_Hz, duty, mismatch, amp_scale, ...
        motor_sync_correlation);
    row_idx = row_idx + 1;
    rows(row_idx) = make_sensitivity_row(p_case, c, study, i_mis, sim, ...
        op, t_eval_min, sensitivity_axis, sim_cfg);
end

function c = get_topology_case(topology, case_id)
    % 按case_id从topology中查找方案，避免报告扫描写死数组序号。
    idx = find(strcmp({topology.cases.id}, case_id), 1, 'first');
    if isempty(idx)
        error('PulseHeating:MissingTopologyCase', ...
            'Cannot find topology case "%s".', case_id);
    end
    c = topology.cases(idx);
end

function row = make_sensitivity_row(p, c, study, i_mis, sim, op, t_eval_min, ...
        sensitivity_axis, sim_cfg)
    % 将一个敏感性仿真结果整理为表格行，包含10/20/30min温度、到0C时间、
    % 等效SOC、功率、电流、限制来源和推荐等级。
    if nargin < 9
        sim_cfg = struct('frequency_Hz', study.default_frequency_Hz, ...
            'duty', study.default_duty, ...
            'current_amplitude_scale', study.default_current_amplitude_scale, ...
            'motor_sync_correlation', study.default_motor_sync_correlation, ...
            'SOC', study.SOC, 'T_init_C', study.default_temperature_C);
    end
    row = struct();
    row.case_id = c.id;
    row.case_name = c.name;
    row.mismatch_label = study.branch_mismatch_labels{i_mis};
    row.sensitivity_axis = sensitivity_axis;
    row.R_heat_factor = op.R_heat_factor;
    row.motor_rms_limit_A = op.motor_rms_limit_A;
    row.h_conv_W_per_m2K = p.h_conv_W_per_m2K;
    row.frequency_Hz = sim_cfg.frequency_Hz;
    row.duty = sim_cfg.duty;
    row.current_amplitude_scale = sim_cfg.current_amplitude_scale;
    row.motor_sync_correlation = op.motor_sync_correlation;
    row.battery_current_sync_factor = op.battery_current_sync_factor;
    row.battery_heating_sync_factor = op.battery_heating_sync_factor;
    row.SOC_init_pct = sim_cfg.SOC * 100;
    row.T_10min_C = interp1(sim.t_min, sim.T_mean_C, t_eval_min(1), 'linear', 'extrap');
    row.T_20min_C = interp1(sim.t_min, sim.T_mean_C, t_eval_min(2), 'linear', 'extrap');
    row.T_30min_C = interp1(sim.t_min, sim.T_mean_C, t_eval_min(3), 'linear', 'extrap');
    row.time_to_0C_min = estimate_target_time(sim.t_min, sim.T_mean_C, p.T_target_C);
    row.E_total_loss_equiv_to_0C_kWh = interpolate_metric_at_target(sim.t_min, ...
        sim.T_mean_C, sim.E_total_electric_kWh, p.T_target_C);
    row.energy_equiv_SOC_delta_to_0C_pct = (sim.SOC(1) - interpolate_metric_at_target( ...
        sim.t_min, sim.T_mean_C, sim.SOC, p.T_target_C)) * 100;
    row.coulombic_SOC_delta_to_0C_pct = nan;
    row.E_total_loss_equiv_30min_kWh = sim.E_total_electric_kWh(end);
    row.energy_equiv_SOC_delta_30min_pct = (sim.SOC(1) - sim.SOC(end)) * 100;
    row.energy_equiv_SOC_delta_per_C_pct = row.energy_equiv_SOC_delta_30min_pct / ...
        max(row.T_30min_C - sim_cfg.T_init_C, eps);
    row.coulombic_SOC_delta_30min_pct = nan;
    row.SOC_accounting_note = soc_accounting_note();
    row.P_battery_initial_kW = op.P_battery_W / 1000;
    row.P_motor_initial_kW = op.P_motor_W / 1000;
    row.P_inverter_initial_kW = op.P_inverter_W / 1000;
    row.P_total_loss_equiv_initial_kW = op.P_total_electric_W / 1000;
    row.heating_efficiency_initial_pct = op.heating_efficiency * 100;
    row.I_motor_rms_A = op.I_motor_rms_A;
    row.I_motor_peak_A = op.I_motor_peak_A;
    row.I_branch_rms_max_A = op.I_branch_rms_max_A;
    row.I_branch_peak_max_A = op.I_branch_peak_max_A;
    row.I_bus_rms_A = op.I_bus_rms_A;
    row.limiting_factor = op.limiting_factor;
    row.safety_status = op.safety.status;
    row.recommendation_level = make_recommendation_level(op, row.time_to_0C_min, ...
        row.energy_equiv_SOC_delta_to_0C_pct);
    row.note = op.note;
end

function level = make_recommendation_level(op, time_to_0C_min, soc_to_0C_pct)
    % 粗筛推荐等级:
    % A/B/C/D只用于排序下一步验证优先级，不是安全放行结论。
    if isfinite(time_to_0C_min) && time_to_0C_min <= 20 && ...
            (isnan(soc_to_0C_pct) || soc_to_0C_pct <= 5) && ...
            op.current_limits.motor_rms_margin >= 1.0
        level = 'A_建议进入L1验证';
    elseif isfinite(time_to_0C_min) && time_to_0C_min <= 30 && ...
            op.current_limits.motor_rms_margin >= 1.0
        level = 'B_备选或降额讨论';
    elseif op.dTdt_C_per_min >= 0.5
        level = 'C_有温升但约束偏弱';
    else
        level = 'D_不建议主攻';
    end
end

function p_case = apply_sensitivity_params(p, R_heat_factor, motor_rms_limit_A, h_conv)
    % 基于基础参数p生成一个敏感性参数副本，避免修改原始p。
    p_case = p;
    p_case.R_heat_factor_current = R_heat_factor;
    p_case.I_motor_rms_limit_A = motor_rms_limit_A;
    p_case.I_motor_peak_limit_A = sqrt(2) * motor_rms_limit_A;
    if nargin >= 4
        p_case.h_conv_W_per_m2K = h_conv;
        p_case.R_th_branch_K_per_W = 1 / max(h_conv * p_case.branch_area_m2, eps);
    end
end

function mismatch = get_case_mismatch(study, idx, branch_count)
    % 根据当前方案支路数量截取阻抗不均衡系数。4500-27当前方案为三包并联。
    row = study.branch_mismatch_sets(idx, :);
    if all(abs(row - 1) < 1e-12)
        mismatch = ones(1, branch_count);
    else
        mismatch = row(1:branch_count);
    end
end

function t_target = estimate_target_time(t_min, T_C, T_target_C)
    % 根据瞬态温度曲线线性插值得到达到目标温度的时间；未达到则返回inf。
    idx = find(T_C >= T_target_C, 1, 'first');
    if isempty(idx)
        t_target = inf;
    elseif idx == 1
        t_target = t_min(1);
    else
        t1 = t_min(idx-1);
        t2 = t_min(idx);
        T1 = T_C(idx-1);
        T2 = T_C(idx);
        t_target = t1 + (T_target_C - T1) * (t2 - t1) / max(T2 - T1, eps);
    end
end

function value = interpolate_metric_at_target(t_min, T_C, metric, T_target_C)
    % 在达到目标温度的时刻插值得到能量或SOC等指标。
    t_target = estimate_target_time(t_min, T_C, T_target_C);
    if isinf(t_target)
        value = nan;
    else
        value = interp1(t_min, metric, t_target, 'linear', 'extrap');
    end
end

function soc_delta_pct = estimate_energy_equiv_soc_delta_pct(p, c, SOC, E_total_kWh)
    % 把总不可逆损耗折算为电池总可用能量占比，用于估算等效SOC消耗。
    E_branch_kWh = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap') * p.C_branch_Ah / 1000;
    E_total_available_kWh = c.branch_count * E_branch_kWh;
    soc_delta_pct = E_total_kWh / max(E_total_available_kWh, eps) * 100;
end

function note = soc_accounting_note()
    % 统一解释SOC口径，避免把等效SOC误解为BMS库仑SOC。
    note = ['energy_equiv_SOC_delta为总不可逆损耗折算口径, 包含电池发热、电机损耗和逆变器损耗; ', ...
        'coulombic_SOC_delta为库仑/净Ah口径, 当前L0.5模型未估算。'];
end

function value = get_vector_value(x, idx)
    % 安全读取支路向量，支路不存在时返回NaN，保证表格字段数量固定。
    if numel(x) >= idx
        value = x(idx);
    else
        value = nan;
    end
end

function judgement = make_case_judgement(op)
    % 默认工况的中文初筛判断，用于摘要表。判断依据是温升速率和电机电流裕度。
    if op.dTdt_C_per_min >= 1.0 && ...
            op.current_limits.motor_rms_margin >= 1.0 && ...
            op.current_limits.motor_peak_margin >= 1.0
        judgement = '建议进入参数补充和更细模型';
    elseif op.dTdt_C_per_min >= 0.5
        judgement = '有加热潜力, 需重点核对电流和开关边界';
    else
        judgement = '简化模型下温升偏弱, 暂不建议优先深入';
    end
end


%% ------------------------------------------------------------------------
% Local functions from eval_circuit_operating_point.m

function op = eval_circuit_operating_point(p, c, T_C, SOC, f_Hz, duty, mismatch, current_amplitude_scale, motor_sync_correlation)
%EVAL_CIRCUIT_OPERATING_POINT Electrical, loss, thermal, and limit snapshot.
% 中文说明:
% 本函数是零维模型的单点工作点计算核心。给定一个拓扑方案、温度、SOC、
% 频率、占空比、支路阻抗不均衡和电流幅值系数，计算电池支路电流、发热、
% 电机/逆变器损耗、温升速率以及安全参考边界。

    % 如果调用者没有给电流幅值系数，默认按1.0，即不额外降额或放大。
    if nargin < 8 || isempty(current_amplitude_scale)
        current_amplitude_scale = 1.0;
    end
    % 如果调用者没有给双电机同步相关系数，默认按理想同相同步处理。
    if nargin < 9 || isempty(motor_sync_correlation)
        motor_sync_correlation = 1.0;
    end

    % 先由温度和SOC插值得到每个电池包支路的内阻，再叠加支路不均衡系数。
    % V_branch是单个电池包支路的开路电压，后续作为RL脉冲回路的电压来源。
    R_branch = interp_branch_resistance(p, T_C, SOC) .* mismatch(:)';
    V_branch = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap');

    n = c.branch_count;

    switch c.type
        case 'whole_branch_sync'
            % 整体同步型拓扑:
            % 多个电池包并联为一个高压源，单电机或双电机在同一母线侧施加脉冲。
            % 电池支路电流按电导分配，电机电流再由同步相关系数折算到电池侧RMS电流。
            motor_count = get_case_motor_count(c, p);
            R_eq = 1 / sum(1 ./ R_branch);
            R_loop = p.motor_Rs_ohm + motor_count * R_eq;

            % 开环电压驱动下的自然PWM/RL电流。
            % 这里回答的是“给定电压、R、L、频率、占空比时自然会形成多大电流”。
            raw = calc_pwm_operating_current(V_branch, R_loop, ...
                p.motor_Ld_H, f_Hz, duty);

            % current_amplitude_scale代表控制器目标电流或调制降额系数。
            % 它不是物理上凭空缩放电流；后续更细模型应拆成目标电流和可用电压/调制比。
            raw.i_rms = raw.i_rms * current_amplitude_scale;
            raw.i_max = raw.i_max * current_amplitude_scale;
            raw.i_min = raw.i_min * current_amplitude_scale;
            raw.i_pp = raw.i_pp * current_amplitude_scale;
            raw.i_peak = raw.i_peak * current_amplitude_scale;
            motor_sync_correlation = clamp_motor_sync_correlation( ...
                motor_sync_correlation, motor_count);

            % 并联支路按电导分流。支路电阻越小，分到的电流越大。
            conductance_share = (1 ./ R_branch) ./ sum(1 ./ R_branch);

            % 双电机RMS合成使用相关系数rho；峰值按同时叠加处理，偏保守。
            raw_pack_rms = calc_pack_rms_from_motor_rms(raw.i_rms, ...
                motor_count, motor_sync_correlation);
            raw_pack_peak = motor_count * raw.i_peak;
            raw_branch_rms = raw_pack_rms .* conductance_share;
            raw_branch_peak = raw_pack_peak .* conductance_share;
            limits_raw = eval_current_limits(p, raw.i_rms, raw.i_peak, ...
                max(raw_branch_rms), max(raw_branch_peak));

            % 如果原始/目标电流超过硬限制，按current_scale整体降额。
            % 当前硬限制主要是电机RMS、峰值和可选的电池高频峰值。
            i_motor_rms = raw.i_rms * limits_raw.current_scale;
            i_motor_peak = raw.i_peak * limits_raw.current_scale;
            i_pack_rms = calc_pack_rms_from_motor_rms(i_motor_rms, ...
                motor_count, motor_sync_correlation);
            i_pack_peak = motor_count * i_motor_peak;
            branch_rms = i_pack_rms .* conductance_share;
            branch_pk = i_pack_peak .* conductance_share;
            P_branch = branch_rms.^2 .* R_branch;

            % 电机铜耗和逆变器损耗只做量级估算。逆变器损耗参数不是目标硬件损耗图。
            losses = eval_losses(p, i_motor_rms, f_Hz, V_branch, motor_count);
            P_motor_W = losses.P_motor_W;
            P_inverter_W = losses.P_inverter_W;
            I_bus_rms_A = i_pack_rms;
            I_switch_rms_sq = i_motor_rms^2;
            I_motor_rms_ref = i_motor_rms;
            I_motor_peak_ref = i_motor_peak;
            current_scale = limits_raw.current_scale;
            effective_current_scale = current_amplitude_scale * current_scale;
            limiting_factor = limits_raw.limiting_factor;
            branch_rms_sq = branch_rms.^2;
            branch_peak = branch_pk;
            battery_current_sync_factor = calc_sync_current_factor( ...
                motor_count, motor_sync_correlation);
            battery_heating_sync_factor = battery_current_sync_factor^2;

        otherwise
            error('未知架构类型: %s', c.type);
    end

    % 热平衡和安全参考判断:
    % heat给出发热、散热和初始温升速率；safety给出频率、电流、规格窗口和析锂参考状态。
    heat = eval_heat_balance(p, P_branch, T_C * ones(1, n), n);
    P_total_electric_W = heat.P_battery_W + P_motor_W + P_inverter_W;
    branch_heat_energy_30min_kWh = P_branch * p.t_end_min / 60 / 1000;
    spec_ref = get_branch_current_window_ref(p, T_C);
    current_limits = eval_current_limits(p, I_motor_rms_ref, I_motor_peak_ref, ...
        max(sqrt(branch_rms_sq)), max(branch_peak));
    current_limits.current_scale = current_scale;
    current_limits.limiting_factor = char(limiting_factor);
    safety = eval_safety_limits(p, c, T_C, SOC, f_Hz, current_limits, spec_ref);

    % 整理单点计算结果。op会被全量扫描表、默认摘要和瞬态仿真共同使用。
    op = struct();
    op.P_branch_W = P_branch;
    op.P_battery_W = heat.P_battery_W;
    op.P_loss_branch_W = heat.P_loss_branch_W;
    op.P_loss_W = heat.P_loss_W;
    op.P_net_W = heat.P_net_W;
    op.P_motor_W = P_motor_W;
    op.P_inverter_W = P_inverter_W;
    op.P_total_electric_W = P_total_electric_W;
    op.heating_efficiency = heat.P_battery_W / max(P_total_electric_W, eps);
    op.dTdt_C_per_min = heat.dTdt_C_per_min;
    op.time_to_target_min = estimate_target_time_from_rate(p, T_C, heat.dTdt_C_per_min);
    op.I_motor_rms_A = I_motor_rms_ref;
    op.I_motor_peak_A = I_motor_peak_ref;
    op.I_branch_rms_A = sqrt(branch_rms_sq);
    op.I_branch_peak_A = branch_peak;
    op.I_branch_rms_max_A = max(op.I_branch_rms_A);
    op.I_branch_peak_max_A = max(op.I_branch_peak_A);
    op.I_bus_rms_A = I_bus_rms_A;
    op.I_switch_rms_A = sqrt(I_switch_rms_sq);
    op.current_amplitude_scale = current_amplitude_scale;
    op.motor_sync_correlation = motor_sync_correlation;
    op.battery_current_sync_factor = battery_current_sync_factor;
    op.battery_heating_sync_factor = battery_heating_sync_factor;
    op.R_heat_factor = get_R_heat_factor(p);
    op.motor_rms_limit_A = p.I_motor_rms_limit_A;
    op.current_scale = current_scale;
    op.effective_current_scale = effective_current_scale;
    op.limiting_factor = char(limiting_factor);
    op.branch_heat_spread_pct = spread_pct(P_branch);
    op.branch_energy_spread_30min_kWh = ...
        max(branch_heat_energy_30min_kWh) - min(branch_heat_energy_30min_kWh);
    op.current_limits = current_limits;
    op.safety = safety;
    op.branch_charge_30s_ref_A = spec_ref.charge_30s_A;
    op.branch_discharge_30s_ref_A = spec_ref.discharge_30s_A;
    op.branch_charge_60s_ref_A = spec_ref.charge_60s_A;
    op.branch_discharge_60s_ref_A = spec_ref.discharge_60s_A;
    op.branch_peak_margin = current_limits.branch_peak_margin;
    op.frequency_margin = safety.frequency_margin;
    op.plating_reference_margin = safety.plating_reference_margin;
    op.note = build_note(p, c, op, spec_ref);
end

function R_branch = interp_branch_resistance(p, T_C, SOC)
    % 将温度和SOC限制在已有表格范围内，避免外推到未提供数据的区域。
    T_q = min(max(T_C, min(p.R_data_T_C)), max(p.R_data_T_C));
    SOC_q = min(max(SOC, min(p.R_data_SOC)), max(p.R_data_SOC));
    R_branch = interp2(p.R_data_SOC, p.R_data_T_C, ...
        p.R_branch_table_ohm, SOC_q, T_q, 'linear');
    R_branch = R_branch * get_R_heat_factor(p);
end

function factor = get_R_heat_factor(p)
    % 高频等效阻抗倍率。用于把1s DCR调整为可能的高频发热阻抗敏感性。
    if isfield(p, 'R_heat_factor_current')
        factor = p.R_heat_factor_current;
    elseif isfield(p, 'R_heat_factor_default')
        factor = p.R_heat_factor_default;
    else
        factor = 1.0;
    end
end

function ref = get_branch_current_window_ref(p, T_C)
    % 读取当前温度下的30s/60s规格参考窗口。这里只作为参考边界，不作为kHz脉冲硬限制。
    T_q = min(max(T_C, min(p.current_window_T_C)), max(p.current_window_T_C));
    ref = struct();
    ref.charge_30s_A = interp1(p.current_window_T_C, ...
        p.branch_charge_30s_ref_A, T_q, 'linear');
    ref.discharge_30s_A = interp1(p.current_window_T_C, ...
        p.branch_discharge_30s_ref_A, T_q, 'linear');
    ref.charge_60s_A = interp1(p.current_window_T_C, ...
        p.branch_charge_60s_ref_A, T_q, 'linear');
    ref.discharge_60s_A = interp1(p.current_window_T_C, ...
        p.branch_discharge_60s_ref_A, T_q, 'linear');
end

function raw = calc_pwm_operating_current(Vdc, R, L, f, D)
    % 包装RL方波电流计算，并额外给出峰值绝对值。
    [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D);
    raw = struct();
    raw.i_rms = i_rms;
    raw.i_max = i_max;
    raw.i_min = i_min;
    raw.i_pp = i_pp;
    raw.i_peak = max(abs([i_max i_min]));
end

function [i_rms, i_max, i_min, i_pp] = calc_pwm_current_v2(Vdc, R, L, f, D)
    % 用周期稳态RL方波响应计算电流最大值、最小值、峰峰值和RMS值。
    % 适用边界: 零速/堵转近似下的等效R-L回路，不包含电流环带宽、PWM死区或调制饱和。
    T_period = 1 / f;
    t_on = D * T_period;
    t_off = (1 - D) * T_period;

    if R <= 0 || L <= 0
        % 极端保护分支，避免无效R或L导致除零。正常物理参数不应进入这里。
        i_max = Vdc / max(R, eps);
        i_min = -i_max;
        i_pp = i_max - i_min;
        i_rms = abs(i_max);
        return;
    end

    tau = L / R;
    Vs = Vdc / R;
    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp(t_off / tau);
    denom = exp_a - 1;

    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;
    i_pp = i_max - i_min;

    A1 = i_min - Vs;
    int_sq1 = Vs^2 * t_on + 2 * Vs * A1 * tau * (1 - exp(-t_on/tau)) + ...
        A1^2 * tau/2 * (1 - exp(-2*t_on/tau));
    A2 = i_max + Vs;
    int_sq2 = Vs^2 * t_off - 2 * Vs * A2 * tau * (1 - exp(-t_off/tau)) + ...
        A2^2 * tau/2 * (1 - exp(-2*t_off/tau));
    i_rms = sqrt(max((int_sq1 + int_sq2) / T_period, 0));
end

function motor_count = get_case_motor_count(c, p)
    % 优先使用拓扑工况自身定义的电机数量；没有定义时退回参数库默认值。
    if isfield(c, 'motor_count') && c.motor_count > 0
        motor_count = c.motor_count;
    else
        motor_count = p.motor_count;
    end
end

function rho = clamp_motor_sync_correlation(rho, motor_count)
    % 相关系数限制在数学上可行的范围，避免RMS合成出现负方差。
    if motor_count <= 1
        rho = 1.0;
        return;
    end
    rho_min = -1 / (motor_count - 1);
    rho = min(max(rho, rho_min), 1.0);
end

function i_pack_rms = calc_pack_rms_from_motor_rms(i_motor_rms, motor_count, rho)
    % 多电机电流在电池侧的RMS合成:
    % rho=1为同相叠加，rho=0为不相关RMS合成，rho<0为反相趋势边界。
    if motor_count <= 1
        i_pack_rms = i_motor_rms;
        return;
    end
    rms_sq_factor = motor_count + motor_count * (motor_count - 1) * rho;
    i_pack_rms = i_motor_rms * sqrt(max(rms_sq_factor, 0));
end

function factor = calc_sync_current_factor(motor_count, rho)
    % 将当前同步相关性折算成相对理想同相同步的电池侧RMS电流系数。
    if motor_count <= 1
        factor = 1.0;
        return;
    end
    ideal_sync_factor = motor_count;
    actual_factor = sqrt(max(motor_count + motor_count * ...
        (motor_count - 1) * rho, 0));
    factor = actual_factor / ideal_sync_factor;
end

function pct = spread_pct(x)
    % 计算支路之间的相对离散度，用于提示支路发热不均衡。
    if isempty(x) || mean(abs(x)) <= eps
        pct = 0;
    else
        pct = (max(x) - min(x)) / mean(abs(x)) * 100;
    end
end

function t_target = estimate_target_time_from_rate(p, T_C, dTdt_C_per_min)
    % 用当前初始温升速率线性估算到目标温度的时间；瞬态摘要会用温度曲线再精算一次。
    if dTdt_C_per_min > 0 && T_C < p.T_target_C
        t_target = (p.T_target_C - T_C) / dTdt_C_per_min;
    else
        t_target = inf;
    end
end

function note = build_note(p, c, op, spec_ref)
    % 生成面向报告阅读者的中文判断语句。它不是新的物理计算，只是把关键边界串起来。
    pieces = strings(1, 0);
    if op.dTdt_C_per_min >= 0.5
        pieces(end+1) = "温升有初步意义";
    else
        pieces(end+1) = "温升偏弱";
    end
    if op.current_scale < 0.999
        pieces(end+1) = "已触发电机/MCU限流";
    else
        pieces(end+1) = "未触发电机/MCU限流";
    end
    if op.I_branch_peak_max_A > spec_ref.discharge_30s_A || ...
            op.I_branch_peak_max_A > spec_ref.charge_30s_A
        pieces(end+1) = "支路峰值高于30s窗口参考, 高频边界需试验确认";
    end
    if c.branch_count == 1 && get_case_motor_count(c, p) >= 2
        pieces(end+1) = "双电机集中单支路, 需核对支路过流和高压盒路径";
    elseif c.branch_count >= 3
        pieces(end+1) = "三包并联分流, 需核对包间均衡和母线压力";
    end
    if get_case_motor_count(c, p) >= 2 && op.motor_sync_correlation < 0.999
        pieces(end+1) = "双电机电池侧同步相关性低于理想同步, 用于控制风险边界";
    end
    if isfield(p, 'branch_hf_peak_limit_A') && isfinite(p.branch_hf_peak_limit_A)
        pieces(end+1) = "已启用电池高频峰值硬限制";
    end
    pieces(end+1) = string(op.safety.status);
    note = char(join(pieces, '; '));
end


%% ------------------------------------------------------------------------
% Local functions from eval_losses.m

function losses = eval_losses(p, I_rms, f_Hz, V_dc, motor_count)
%EVAL_LOSSES Motor copper loss and simplified inverter losses.
% 中文说明:
% 本函数估算电机铜耗和逆变器损耗。它用于能量口径和效率粗筛，
% 不是逆变器结温或器件寿命模型。

    if nargin < 5 || isempty(motor_count)
        motor_count = 1;
    end

    % 电机铜耗按I_rms^2*R估算，并乘以电机数量。
    % 结果对motor_Rs_ohm解释很敏感，需要确认供应商14mOhm的测量口径。
    losses = struct();
    losses.P_motor_W = motor_count * I_rms^2 * p.motor_Rs_ohm;
    losses.P_inverter_W = motor_count * calc_inverter_loss(p, I_rms, f_Hz, V_dc);
end

function P_inv = calc_inverter_loss(p, I_rms, f, V_dc)
    % 简化逆变器损耗:
    % P_cond为导通损耗占位，P_sw为开关损耗占位。参数未来自目标硬件损耗图。
    if I_rms <= 0
        P_inv = 0;
        return;
    end
    I_avg = 2 / pi * I_rms;
    P_cond = 2 * (p.V_ce0 * I_avg + p.r_ce * I_rms^2) + ...
             2 * (p.V_f0 * I_avg + p.r_f * I_rms^2);
    E_sw_total = p.E_on + p.E_off + p.E_rr;
    P_sw = 2 * f * E_sw_total * (I_rms / p.I_ref_sw) * ...
        (V_dc / p.V_ref_sw);
    P_inv = max(P_cond + P_sw, 0);
end


%% ------------------------------------------------------------------------
% Local functions from eval_heat_balance.m

function heat = eval_heat_balance(p, P_branch_W, T_branch_C, branch_count)
%EVAL_HEAT_BALANCE Battery heat generation, heat loss, and temperature rate.
% 中文说明:
% 本函数把电池支路发热功率转换成温升速率。核心关系是:
% 净加热功率 = 电池内阻发热 - 对外散热；
% 温升速率 = 净加热功率 / 电池热容。

    % 每个支路分别计算散热，再汇总为整车电池总发热、总散热和总净热功率。
    P_loss_branch_W = calc_branch_heat_loss(p, T_branch_C);
    P_battery_W = sum(P_branch_W);
    P_loss_W = sum(P_loss_branch_W);
    P_net_branch_W = P_branch_W - P_loss_branch_W;
    P_net_W = sum(P_net_branch_W);
    Cth_total = branch_count * p.Cth_branch_J_per_K;

    % 输出热平衡结果。dTdt_C_per_min是平均温升速率，不代表单体内部温差。
    heat = struct();
    heat.P_branch_W = P_branch_W;
    heat.P_battery_W = P_battery_W;
    heat.P_loss_branch_W = P_loss_branch_W;
    heat.P_loss_W = P_loss_W;
    heat.P_net_branch_W = P_net_branch_W;
    heat.P_net_W = P_net_W;
    heat.dTdt_C_per_min = P_net_W / Cth_total * 60;
end

function P_loss = calc_branch_heat_loss(p, T_branch_C)
    % 散热边界:
    % enable_heat_loss=false时按绝热处理；否则根据thermal_boundary选择弱对流或热阻模型。
    if isfield(p, 'enable_heat_loss') && ~p.enable_heat_loss
        P_loss = zeros(size(T_branch_C));
        return;
    end

    thermal_boundary = "convection";
    if isfield(p, 'thermal_boundary')
        thermal_boundary = lower(string(p.thermal_boundary));
    end

    % 低于环境温度时不计算从环境吸热。当前默认T_init=T_amb=-20C，影响较小；
    % 若后续研究电池低于环境温度的回温，需要重新审查这个边界。
    dT = max(T_branch_C - p.T_amb_C, 0);
    switch thermal_boundary
        case {"none", "ignore", "adiabatic"}
            P_loss = zeros(size(T_branch_C));
        case {"convection", "natural_convection"}
            P_loss = p.h_conv_W_per_m2K * p.branch_area_m2 .* dT;
        case "thermal_resistance"
            if ~isfield(p, 'R_th_branch_K_per_W') || ...
                    p.R_th_branch_K_per_W <= 0 || ~isfinite(p.R_th_branch_K_per_W)
                error('thermal_resistance模式下R_th_branch_K_per_W必须为正有限值。');
            end
            P_loss = dT ./ p.R_th_branch_K_per_W;
        otherwise
            error('未知热边界类型: %s。', thermal_boundary);
    end
end


%% ------------------------------------------------------------------------
% Local functions from eval_current_limits.m

function limits = eval_current_limits(p, I_motor_rms_A, I_motor_peak_A, I_branch_rms_A, I_branch_peak_A)
%EVAL_CURRENT_LIMITS Current scaling and margins for motor and branch limits.
% 中文说明:
% 本函数统一处理电流硬限制。输入是未缩放或已缩放后的电机/支路电流，
% 输出current_scale和各类裕度。裕度>=1表示未超过对应限制。

    % 如果没有单独给支路电流，就用电机电流代替，兼容单支路或旧调用方式。
    if nargin < 4 || isempty(I_branch_rms_A)
        I_branch_rms_A = I_motor_rms_A;
    end
    if nargin < 5 || isempty(I_branch_peak_A)
        I_branch_peak_A = I_motor_peak_A;
    end

    scale = 1;
    factor = "none";

    % 电机RMS电流限制，通常对应MCU/电机短时热电流能力。
    if isfinite(p.I_motor_rms_limit_A) && I_motor_rms_A > p.I_motor_rms_limit_A
        scale = min(scale, p.I_motor_rms_limit_A / I_motor_rms_A);
        factor = "motor_rms";
    end
    % 电机峰值电流限制，防止瞬时峰值超过器件或控制器保护边界。
    if isfinite(p.I_motor_peak_limit_A) && I_motor_peak_A > p.I_motor_peak_limit_A
        new_scale = p.I_motor_peak_limit_A / I_motor_peak_A;
        if new_scale < scale
            factor = "motor_peak";
        elseif new_scale == scale && factor ~= "none"
            factor = factor + "+motor_peak";
        end
        scale = min(scale, new_scale);
    end
    % 电池支路高频峰值限制。当前4500-27参数中为inf，表示尚未收到BMS高频硬限值。
    if isfield(p, 'branch_hf_peak_limit_A') && ...
            isfinite(p.branch_hf_peak_limit_A) && I_branch_peak_A > p.branch_hf_peak_limit_A
        new_scale = p.branch_hf_peak_limit_A / I_branch_peak_A;
        if new_scale < scale
            factor = "battery_hf_peak";
        end
        scale = min(scale, new_scale);
    end

    % 输出缩放系数、触发来源和裕度。注意: 30s/60s规格窗口和析锂参考不在这里做硬限流。
    limits = struct();
    limits.current_scale = scale;
    limits.limiting_factor = char(factor);
    limits.I_motor_rms_A = I_motor_rms_A;
    limits.I_motor_peak_A = I_motor_peak_A;
    limits.I_branch_rms_A = I_branch_rms_A;
    limits.I_branch_peak_A = I_branch_peak_A;
    limits.motor_rms_margin = p.I_motor_rms_limit_A / max(I_motor_rms_A, eps);
    limits.motor_peak_margin = p.I_motor_peak_limit_A / max(I_motor_peak_A, eps);
    if isfield(p, 'branch_hf_peak_limit_A') && isfinite(p.branch_hf_peak_limit_A)
        limits.branch_peak_margin = p.branch_hf_peak_limit_A / max(I_branch_peak_A, eps);
    else
        limits.branch_peak_margin = inf;
    end
end


%% ------------------------------------------------------------------------
% Local functions from eval_safety_limits.m

function safety = eval_safety_limits(p, ~, T_C, SOC, f_Hz, current_limits, spec_ref)
%EVAL_SAFETY_LIMITS Electrical and battery safety references for screening.
% Spec-window and plating limits are displayed as references until calibrated
% high-frequency cell data are available.
% 中文说明:
% 本函数把电气硬限制和电池安全参考边界整理成状态字段。当前只有电机/控制器
% 电流、配置的电池高频峰值和频率上限参与硬状态判断；30s/60s规格窗口与
% 析锂模型只作为参考提示，不能视为目标电芯已验证的BMS硬保护。

    % 频率裕度。>=1表示当前频率不超过控制器参考上限。
    frequency_margin = inf;
    if isfield(p, 'f_control_max_Hz') && isfinite(p.f_control_max_Hz)
        frequency_margin = p.f_control_max_Hz / max(f_Hz, eps);
    end
    frequency_ok = frequency_margin >= 1.0;

    % 电气硬限制状态: 电机RMS、峰值、电池高频峰值和频率。
    motor_rms_ok = current_limits.motor_rms_margin >= 1.0;
    motor_peak_ok = current_limits.motor_peak_margin >= 1.0;
    branch_peak_ok = current_limits.branch_peak_margin >= 1.0;
    hard_current_scaled = isfield(current_limits, 'current_scale') && ...
        current_limits.current_scale < 0.999;
    electrical_ok = motor_rms_ok && motor_peak_ok && branch_peak_ok && frequency_ok;

    % 电池参考边界:
    % spec_ref来自30s/60s规格窗口；battery_ref来自简化析锂参考模型。
    % 二者当前只用于输出margin和文字提示，不反向修改电流。
    battery_ref = calc_battery_reference_limit(p, f_Hz, T_C, SOC);
    I_branch_peak = current_limits.I_branch_peak_A;
    spec_30s_charge_margin = spec_ref.charge_30s_A / max(I_branch_peak, eps);
    spec_30s_discharge_margin = spec_ref.discharge_30s_A / max(I_branch_peak, eps);
    spec_60s_charge_margin = spec_ref.charge_60s_A / max(I_branch_peak, eps);
    spec_60s_discharge_margin = spec_ref.discharge_60s_A / max(I_branch_peak, eps);
    plating_reference_margin = battery_ref.plating_charge_peak_A / max(I_branch_peak, eps);
    plating_reference_ok = plating_reference_margin >= 1.0;

    % 组合成人可读状态。这里的“析锂参考边界提示”只是风险提示，不是试验结论。
    status = strings(1, 0);
    if electrical_ok && ~hard_current_scaled
        status(end+1) = "电气硬限制满足";
    elseif electrical_ok && hard_current_scaled
        status(end+1) = "已按电流硬限制缩放";
    else
        if ~frequency_ok
            status(end+1) = "频率超控制器参考上限";
        end
        if hard_current_scaled || ~motor_rms_ok || ~motor_peak_ok || ~branch_peak_ok
            status(end+1) = "已触发电流硬限制缩放";
        end
    end

    if plating_reference_ok
        status(end+1) = "析锂参考边界未触发";
    else
        status(end+1) = "析锂参考边界提示";
    end
    status(end+1) = "30s/60s规格窗口仅作低频参考";

    safety = struct();
    safety.enabled = true;
    safety.status = char(join(status, '; '));
    safety.electrical_ok = electrical_ok;
    safety.frequency_ok = frequency_ok;
    safety.motor_rms_ok = motor_rms_ok;
    safety.motor_peak_ok = motor_peak_ok;
    safety.branch_peak_ok = branch_peak_ok;
    safety.plating_ok = plating_reference_ok;
    safety.plating_hard_limit_enabled = false;
    safety.frequency_margin = frequency_margin;
    safety.spec_30s_charge_margin = spec_30s_charge_margin;
    safety.spec_30s_discharge_margin = spec_30s_discharge_margin;
    safety.spec_60s_charge_margin = spec_60s_charge_margin;
    safety.spec_60s_discharge_margin = spec_60s_discharge_margin;
    safety.plating_reference_margin = plating_reference_margin;
    safety.spec_charge_30s_A = spec_ref.charge_30s_A;
    safety.spec_discharge_30s_A = spec_ref.discharge_30s_A;
    safety.spec_charge_60s_A = spec_ref.charge_60s_A;
    safety.spec_discharge_60s_A = spec_ref.discharge_60s_A;
    safety.plating_charge_reference_A = battery_ref.plating_charge_peak_A;
    safety.battery_reference_mode = battery_ref.model;
    safety.note = ['电机/控制器电流和配置的电池高频峰值为硬限制; ', ...
        '规格书30s/60s窗口与析锂模型当前仅作参考展示, 未作为4500-27硬限流。'];
end

function ref = calc_battery_reference_limit(p, f_Hz, T_C, SOC)
    % 将p中的电池安全参数整理后，调用简化电池电流参考模型。
    params = build_battery_limit_params(p);
    [limit, info] = battery_current_limit_model( ...
        f_Hz, T_C, SOC, p.N_parallel_branch, p.C_cell_Ah, params);

    ref = struct();
    ref.model = limit.model;
    ref.charge_peak_A = limit.charge_peak;
    ref.discharge_peak_A = limit.discharge_peak;
    ref.spec_charge_peak_A = limit.spec_charge_peak;
    ref.spec_discharge_peak_A = limit.spec_discharge_peak;
    ref.plating_charge_peak_A = limit.plating_charge_peak;
    ref.C_rate_plating = info.C_rate_plating;
end

function params = build_battery_limit_params(p)
    % 把参数库字段映射成电池参考模型需要的字段名。这里不做新物理假设。
    params = struct();
    params.limit_mode = p.battery_current_limit_mode;
    params.apply_discharge_spec_limit_in_plating_mode = ...
        p.apply_discharge_spec_limit_in_plating_mode;
    params.current_window_duration_s = p.current_window_duration_s;
    params.current_window_SOC_ref = p.current_window_SOC_ref;
    params.current_window_N_parallel_ref = p.current_window_N_parallel_ref;
    params.current_window_T = p.current_window_T_C;
    params.current_window_charge_30s = p.branch_charge_30s_ref_A;
    params.current_window_discharge_30s = p.branch_discharge_30s_ref_A;
    params.current_window_charge_60s = p.branch_charge_60s_ref_A;
    params.current_window_discharge_60s = p.branch_discharge_60s_ref_A;
    params.R_ct_ref = p.plating_R_ct_ref;
    params.Ea_ct = p.plating_Ea_ct;
    params.R_SEI_ref = p.plating_R_SEI_ref;
    params.Ea_SEI = p.plating_Ea_SEI;
    params.C_dl = p.plating_C_dl;
    params.k_safety = p.plating_k_safety;
    params.R_total_for_alpha = [];
    params.L_for_alpha = [];
end

function [limit, info] = battery_current_limit_model( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params)
    % 简化电池电流边界模型:
    % spec_window模式直接使用规格窗口；plating_adaptive模式用简化负极阻抗估算充电半周参考峰值。
    % 审查备注: 这里的enabled_as_limit是内部模型状态，顶层并未把析锂参考作为硬限流执行。
    params = fill_default_params(params);

    spec = calc_spec_window(T_C, SOC, N_parallel, params);
    [I_plating_peak, plating] = calc_plating_limit( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params);

    mode = lower(string(params.limit_mode));
    switch mode
        case "off"
            charge_peak = inf;
            discharge_peak = inf;
            enabled_as_limit = false;
        case "spec_window"
            charge_peak = spec.charge_peak;
            discharge_peak = spec.discharge_peak;
            enabled_as_limit = true;
        case "plating_adaptive"
            charge_peak = I_plating_peak;
            if params.apply_discharge_spec_limit_in_plating_mode
                discharge_peak = spec.discharge_peak;
            else
                discharge_peak = inf;
            end
            enabled_as_limit = true;
        otherwise
            error('未知电池侧限流模式: %s。', params.limit_mode);
    end

    limit = struct();
    limit.charge_peak = max(charge_peak, 0);
    limit.discharge_peak = max(discharge_peak, 0);
    limit.enabled_as_limit = enabled_as_limit;
    limit.model = char(mode);
    limit.spec_charge_peak = spec.charge_peak;
    limit.spec_discharge_peak = spec.discharge_peak;
    limit.plating_charge_peak = I_plating_peak;

    info = struct();
    info.spec = spec;
    info.plating = plating;
    info.params = params;
    info.charge_relaxation_vs_spec = I_plating_peak ./ max(spec.charge_peak, eps);
    info.C_rate_plating = I_plating_peak ./ (C_cell_Ah * N_parallel);
end

function params = fill_default_params(params)
    % 给缺失字段补默认值，保证旧调用方式不报错。默认值是粗筛占位，不是目标电芯标定值。
    if ~isfield(params, 'limit_mode')
        params.limit_mode = 'plating_adaptive';
    end
    if ~isfield(params, 'apply_discharge_spec_limit_in_plating_mode')
        params.apply_discharge_spec_limit_in_plating_mode = false;
    end
    if ~isfield(params, 'current_window_duration_s')
        params.current_window_duration_s = 30;
    end
    if ~isfield(params, 'current_window_SOC_ref')
        params.current_window_SOC_ref = 0.50;
    end
    if ~isfield(params, 'current_window_N_parallel_ref')
        params.current_window_N_parallel_ref = 1;
    end
    if ~isfield(params, 'R_ct_ref')
        params.R_ct_ref = 0.12e-3;
    end
    if ~isfield(params, 'Ea_ct')
        params.Ea_ct = 3600;
    end
    if ~isfield(params, 'R_SEI_ref')
        params.R_SEI_ref = 0.015e-3;
    end
    if ~isfield(params, 'Ea_SEI')
        params.Ea_SEI = 2500;
    end
    if ~isfield(params, 'C_dl')
        params.C_dl = 1.5;
    end
    if ~isfield(params, 'k_safety')
        params.k_safety = 0.85;
    end
    if ~isfield(params, 'U_e_func')
        params.U_e_func = @(soc) max(0.04, 0.30 - 0.28 * soc);
    end
    if ~isfield(params, 'R_total_for_alpha')
        params.R_total_for_alpha = [];
    end
    if ~isfield(params, 'L_for_alpha')
        params.L_for_alpha = [];
    end
end

function spec = calc_spec_window(T_C, SOC, N_parallel, params)
    % 按温度插值得到30s或60s充放电规格窗口。
    % SOC高于参考SOC时，充电窗口做经验降额；该降额仅用于风险提示。
    has_spec = isfield(params, 'current_window_T') && ...
        isfield(params, 'current_window_charge_30s') && ...
        isfield(params, 'current_window_discharge_30s') && ...
        isfield(params, 'current_window_charge_60s') && ...
        isfield(params, 'current_window_discharge_60s');

    if ~has_spec
        spec = struct('charge_peak', inf, 'discharge_peak', inf, ...
            'T_query', T_C, 'duration_s', params.current_window_duration_s);
        return;
    end

    T_query = min(max(T_C, min(params.current_window_T)), max(params.current_window_T));
    if params.current_window_duration_s <= 30
        charge_table = params.current_window_charge_30s;
        discharge_table = params.current_window_discharge_30s;
    else
        charge_table = params.current_window_charge_60s;
        discharge_table = params.current_window_discharge_60s;
    end

    scale = N_parallel / params.current_window_N_parallel_ref;
    charge_peak = interp1(params.current_window_T, charge_table, T_query, 'linear') * scale;
    discharge_peak = interp1(params.current_window_T, discharge_table, T_query, 'linear') * scale;

    if SOC > params.current_window_SOC_ref
        charge_peak = charge_peak * max(0.25, 1 - 1.2*(SOC - params.current_window_SOC_ref));
    end

    spec = struct();
    spec.charge_peak = max(charge_peak, 0);
    spec.discharge_peak = max(discharge_peak, 0);
    spec.T_query = T_query;
    spec.duration_s = params.current_window_duration_s;
end

function [I_plating_limit, info] = calc_plating_limit( ...
        f_Hz, T_C, SOC, N_parallel, C_cell_Ah, params)
    % 析锂参考边界的简化估算:
    % 温度影响R_ct和R_SEI，频率影响负极等效阻抗，U_e_func提供负极安全电位余量。
    % 当前缺少目标电芯电化学标定，因此只能作为参考裕度，不作为定量安全结论。
    T_ref_K = 298.15;
    T_K = T_C + 273.15;

    R_ct_T = params.R_ct_ref .* exp(params.Ea_ct .* (1./T_K - 1/T_ref_K));
    R_SEI_T = params.R_SEI_ref .* exp(params.Ea_SEI .* (1./T_K - 1/T_ref_K));
    f_ct_T = 1 ./ (2 * pi .* R_ct_T .* params.C_dl);
    Z_neg_mag = R_SEI_T + R_ct_T ./ sqrt(1 + (f_Hz ./ f_ct_T).^2);
    U_e = params.U_e_func(SOC);

    k_wave_sq = 4/pi;
    k_wave_tri = 8/pi^2;
    if ~isempty(params.L_for_alpha) && ~isempty(params.R_total_for_alpha)
        alpha = params.R_total_for_alpha .* (1 ./ f_Hz) ./ params.L_for_alpha;
        k_waveform = k_wave_tri + (k_wave_sq - k_wave_tri) .* (1 - exp(-alpha/2));
    else
        k_waveform = k_wave_sq;
        alpha = nan(size(f_Hz));
    end

    I_plating_limit = N_parallel .* U_e ./ (k_waveform .* Z_neg_mag) .* params.k_safety;

    info = struct();
    info.U_e = U_e;
    info.R_ct_T = R_ct_T;
    info.R_SEI_T = R_SEI_T;
    info.f_ct_T = f_ct_T;
    info.Z_neg_mag = Z_neg_mag;
    info.k_waveform = k_waveform;
    info.alpha = alpha;
    info.C_rate_limit = I_plating_limit ./ (C_cell_Ah * N_parallel);
end


%% ------------------------------------------------------------------------
% Local functions from print_pulse_heating_summary.m

function print_pulse_heating_summary(summary, topology)
%PRINT_PULSE_HEATING_SUMMARY Command-window summary for one topology group.
% 中文说明:
% 本函数只负责把默认工况摘要打印到命令行，不参与物理计算。
% 打印内容重点包括初始温升速率、到0C时间、30min温度、电池发热、电流和限制来源。

    % 表头。这里的“等效SOC”是总不可逆损耗折算口径，不是BMS库仑SOC。
    fprintf('\n--- %s ---\n', topology.name);
    fprintf('%s默认工况架构摘要:\n', topology.name);
    fprintf('%-18s %-34s %10s %10s %10s %10s %10s %10s %10s %12s\n', ...
        '方案', '名称', 'dT/dt', '到0Cmin', '到0C等效kWh', 'T30min', '电池kW', '到0C等效SOC%', '支路A', '限制');
    for k = 1:height(summary)
        % 每个拓扑方案打印一行，例如三包并联单电机、三包并联双电机。
        fprintf('%-18s %-34s %10.3f %10.2f %10.2f %10.2f %10.1f %10.3f %10.0f %12s\n', ...
            summary.case_id{k}, truncate_text(summary.case_name{k}, 34), ...
            summary.dTdt_initial_C_per_min(k), summary.time_to_0C_min(k), ...
            summary.E_total_loss_equiv_to_0C_kWh(k), summary.T_end_30min_C(k), ...
            summary.P_battery_kW(k), ...
            summary.energy_equiv_SOC_delta_to_0C_pct(k), ...
            summary.I_branch_rms_max_A(k), summary.limiting_factor{k});
    end
    % 用初始温升速率选出当前占位参数下的最高温升方案。它只是粗筛排序，不是安全结论。
    [~, best_idx] = max(summary.dTdt_initial_C_per_min);
    fprintf('\n%s当前占位参数下温升最高: %s\n', ...
        topology.short_name, summary.case_name{best_idx});
    fprintf('注意: 30s/60s规格窗口只作为低频参考边界, 不作为kHz脉冲硬限制。\n');
    fprintf('等效SOC为总不可逆损耗折算口径, 包含电池发热、电机损耗和逆变器损耗。\n');
    fprintf('库仑SOC/净Ah偏置当前未估算, 不能用等效SOC替代BMS真实SOC判断。\n');
    fprintf('安全接口: %s\n\n', summary.safety_status{best_idx});
end

function out = truncate_text(in, n)
    % 控制命令行表格宽度，避免长中文方案名破坏排版。
    s = char(in);
    if strlength(string(s)) > n
        out = char(extractBefore(string(s), n));
    else
        out = s;
    end
end


%% ------------------------------------------------------------------------
% Local functions from plot_pulse_heating_results.m

function plot_pulse_heating_results(result, p, study, topology)
%PLOT_PULSE_HEATING_RESULTS Report-oriented figures for 4500-27 screening.
% 中文说明:
% 本文件只负责把求解结果画成报告图，不改变物理计算结果。所有电流、功率、
% 温升和安全状态都来自result或内部复用eval_circuit_operating_point的报告工况计算。

    summary = result.summary;
    results = result.results;
    sens = result.sensitivity;
    sims = result.sims;

    % 图1: 原理、默认电流波形、默认温升和能量分配。
    plot_principle_and_default_case(summary, sims, p, study, topology);
    % 图2: 当前主方案对电流幅值、频率、散热和内阻等参数的敏感性。
    plot_dual_motor_sensitivity(sens, results, p, study, topology);
    % 图3: 单电机和双电机方案对比，以及单电机在不同幅值下的边界。
    plot_single_motor_comparison(summary, results, sens, p, study, topology);
end

function plot_principle_and_default_case(summary, sims, p, study, topology)
    % 汇报图1:
    % 左侧画当前L0.5等效电路；中间给出默认双电机脉冲下的电机/电池侧电流示意；
    % 右侧和下方展示30min温升曲线与能量分配。
    figure('Name', [topology.short_name, ' 汇报图1 原理与默认工况'], ...
        'Color', 'w', 'Position', [40 40 1600 920]);
    tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile([1 1]);
    draw_equivalent_circuit(p, study);

    waveform = build_default_waveform(p, study);

    nexttile;
    yyaxis left;
    plot(waveform.t_ms, waveform.i_motor_A, 'LineWidth', 1.8);
    hold on;
    yline(p.I_motor_peak_limit_A, '--r', ...
        sprintf('550Arms -> %.0fApeak', p.I_motor_peak_limit_A), ...
        'LineWidth', 1.1);
    yline(-p.I_motor_peak_limit_A, '--r', 'HandleVisibility', 'off', ...
        'LineWidth', 1.1);
    ylabel('电机电流 (A)');
    yyaxis right;
    stairs(waveform.t_ms, waveform.v_motor_V, 'LineWidth', 1.4);
    ylabel('电机端等效电压 (V)');
    hold off;
    xlabel('时间 (ms)');
    title('双电机同步: 单台电机两周期电压/电流');
    grid on;

    nexttile;
    yyaxis left;
    plot(waveform.t_ms, waveform.i_branch_A, 'LineWidth', 1.8);
    ylabel('单包支路电流 (A)');
    yyaxis right;
    plot(waveform.t_ms, waveform.i_bus_A, '--', 'LineWidth', 1.4);
    hold on;
    hold off;
    ylabel('双电机母线等效电流 (A)');
    xlabel('时间 (ms)');
    title('电池侧电流: 三包分流后单包电流更小');
    legend({'单包支路电流', '双电机母线等效电流'}, 'Location', 'best');
    grid on;

    nexttile([1 2]);
    plot_default_temperature(sims, p, summary, study);

    nexttile;
    plot_energy_pie(summary);
end

function draw_equivalent_circuit(p, ~)
    % 画等效电路示意:
    % 三个电池包并联整体输出，连接双逆变器/双电机等效R-L支路。
    % 该图用于说明模型边界，不代表完整高压盒、母线电容和三相PWM拓扑。
    axis off;
    hold on;
    title('当前L0.5模型等效电路原理');
    xlim([0 12]);
    ylim([0 10]);

    % DC buses.
    plot([2.5 8.1], [8.2 8.2], 'k-', 'LineWidth', 2.0);
    plot([2.5 8.1], [1.5 1.5], 'k-', 'LineWidth', 2.0);
    text(5.3, 8.55, sprintf('HV bus %.0fV nominal', p.V_pack_nom_V), ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');

    % Three parallel battery packs.
    y_pack = [6.9 4.9 2.9];
    for k = 1:3
        draw_battery_branch(0.9, y_pack(k), sprintf('Pack %d\n252S 278Ah', k));
        plot([2.45 2.5], [y_pack(k) 8.2], 'k-', 'LineWidth', 1.0);
        plot([2.45 2.5], [y_pack(k) 1.5], 'k-', 'LineWidth', 1.0);
    end
    text(0.7, 9.35, sprintf('三包并联整体输出\n不可独立接入电驱'), ...
        'FontWeight', 'bold', 'Interpreter', 'none');

    % Two synchronized inverter-motor RL branches.
    draw_inverter_motor_branch(8.1, 6.6, 'MCU/Motor 1');
    draw_inverter_motor_branch(8.1, 3.4, 'MCU/Motor 2');
    text(8.8, 0.65, '双电机同步堵转脉冲; 电机等效R-L负载', ...
        'HorizontalAlignment', 'center');
    hold off;
end

function draw_battery_branch(x, y, label)
    % 画单个电池包支路符号。仅用于图示，不参与计算。
    plot([x x+0.25], [y y], 'k-', 'LineWidth', 1.2);
    plot([x+0.25 x+0.25], [y-0.45 y+0.45], 'k-', 'LineWidth', 1.8);
    plot([x+0.45 x+0.45], [y-0.25 y+0.25], 'k-', 'LineWidth', 1.8);
    rectangle('Position', [x+0.65, y-0.35, 0.35, 0.70], ...
        'Curvature', 0.1, 'EdgeColor', 'k', 'LineWidth', 1.2);
    text(x+0.82, y, 'R', 'HorizontalAlignment', 'center');
    plot([x+1.0 x+1.55], [y y], 'k-', 'LineWidth', 1.2);
    text(x+0.7, y-0.92, label, 'HorizontalAlignment', 'center', ...
        'FontSize', 9, 'Interpreter', 'none');
end

function draw_inverter_motor_branch(x, y, label)
    % 画逆变器和电机R-L等效支路。真实控制器的电流环、PWM死区和器件热模型不在该示意图中。
    rectangle('Position', [x-0.15, y-0.75, 1.15, 1.5], ...
        'EdgeColor', [0.15 0.35 0.65], 'LineWidth', 1.5);
    text(x+0.42, y, 'Inverter', 'HorizontalAlignment', 'center', ...
        'FontWeight', 'bold');
    plot([x x], [8.4 y+0.75], 'k-', 'LineWidth', 1.2);
    plot([x x], [y-0.75 1.6], 'k-', 'LineWidth', 1.2);
    plot([x+1.0 x+1.55], [y y], 'k-', 'LineWidth', 1.2);
    rectangle('Position', [x+1.55, y-0.32, 0.45, 0.64], ...
        'Curvature', 0.2, 'EdgeColor', 'k', 'LineWidth', 1.2);
    text(x+1.78, y, 'R', 'HorizontalAlignment', 'center');
    plot([x+2.0 x+2.35], [y y], 'k-', 'LineWidth', 1.2);
    draw_inductor(x+2.35, y);
    text(x+2.35, y-0.95, label, 'HorizontalAlignment', 'center', ...
        'FontSize', 9);
end

function draw_inductor(x, y)
    % 绘制电感线圈符号，仅用于报告图形表达。
    theta = linspace(0, pi, 30);
    x0 = x;
    for k = 1:5
        xx = x0 + (k-1)*0.22 + 0.11 * (1 - cos(theta));
        yy = y + 0.18 * sin(theta);
        plot(xx, yy, 'k-', 'LineWidth', 1.2);
    end
    plot([x+1.1 x+1.45], [y y], 'k-', 'LineWidth', 1.2);
    text(x+0.58, y+0.55, 'L_d', 'HorizontalAlignment', 'center');
end

function waveform = build_default_waveform(p, study)
    % 构造默认工况的两周期示意波形:
    % 用简化RL响应生成单台电机电流，再按三包分流得到单包支路电流。
    % 这是示意波形，不是开关级PWM或dq坐标闭环仿真。
    SOC = study.SOC;
    T_C = study.default_temperature_C;
    f = study.default_frequency_Hz;
    D = study.default_duty;
    motor_count = 2;

    V_oc = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, SOC, ...
        'linear', 'extrap');
    R_branch = interp2(p.R_data_SOC, p.R_data_T_C, ...
        p.R_branch_table_ohm, SOC, T_C, 'linear') * ...
        p.R_heat_factor_default;
    R_eq = R_branch / 3;
    R_loop = p.motor_Rs_ohm + motor_count * R_eq;
    L = p.motor_Ld_H;
    T_period = 1 / f;
    t_on = D * T_period;
    tau = L / R_loop;
    Vs = V_oc / R_loop;

    alpha = T_period / tau;
    beta = t_on / tau;
    exp_a = exp(alpha);
    exp_b = exp(beta);
    exp_ab = exp((T_period - t_on) / tau);
    denom = exp_a - 1;
    i_max = Vs * (exp_a - 2 * exp_ab + 1) / denom;
    i_min = Vs * (2 * exp_b - exp_a - 1) / denom;

    t = linspace(0, 2 * T_period, 900);
    t_mod = mod(t, T_period);
    i_motor = zeros(size(t));
    v_motor = zeros(size(t));
    on = t_mod <= t_on;
    i_motor(on) = Vs + (i_min - Vs) .* exp(-t_mod(on) / tau);
    v_motor(on) = V_oc;
    t_off = t_mod(~on) - t_on;
    i_motor(~on) = -Vs + (i_max + Vs) .* exp(-t_off / tau);
    v_motor(~on) = -V_oc;

    i_bus = motor_count * i_motor;
    i_branch = i_bus / 3;

    waveform = struct();
    waveform.t_ms = t * 1000;
    waveform.i_motor_A = i_motor;
    waveform.v_motor_V = v_motor;
    waveform.i_bus_A = i_bus;
    waveform.i_branch_A = i_branch;
end

function plot_default_temperature(sims, p, summary, study)
    % 绘制默认工况30min平均温度曲线，并标出目标温度0C。
    % 温度来自solve_pulse_heating_case中的显式时间推进。
    hold on;
    for k = 1:numel(sims)
        sim = sims(k).data;
        plot(sim.t_min, sim.T_mean_C, 'LineWidth', 2.2, ...
            'DisplayName', sims(k).case_name);
    end
    yline(p.T_target_C, 'k:', '0C目标', 'LineWidth', 1.2, ...
        'HandleVisibility', 'off');
    xline(20, '--', '20min参考', 'LineWidth', 1.1, ...
        'HandleVisibility', 'off');
    hold off;
    xlabel('时间 (min)');
    ylabel('平均电池温度 (C)');
    row = summary(strcmp(summary.case_id, '三包并联双电机'), :);
    default_text = sprintf(['默认工况: -20C, SOC %.0f%%, %.0fHz, D=%.2f, ', ...
        '单电机 %.0fArms, 电池包OCV %.0fV, 逆变器额定 %.0fV'], ...
        study.SOC * 100, study.default_frequency_Hz, study.default_duty, ...
        row.I_motor_rms_A, p.N_series * interp1(p.ocv_soc_bp, ...
        p.ocv_cell_V, study.SOC, 'linear', 'extrap'), p.inverter_V_nom_V);
    title({'默认工况Time-temperature曲线', default_text});
    legend('Location', 'northwest');
    grid on;
end

function plot_energy_pie(summary)
    % 绘制双电机默认方案30min能量分配:
    % 电池发热、电机损耗、逆变器损耗和散热损失均来自summary。
    row = summary(strcmp(summary.case_id, '三包并联双电机'), :);
    energy = [row.E_battery_heat_30min_kWh, row.E_motor_loss_30min_kWh, ...
        row.E_inverter_loss_30min_kWh];
    total_electric = row.E_total_loss_equiv_30min_kWh;
    battery_heat_efficiency_pct = row.E_battery_heat_30min_kWh / ...
        max(total_electric, eps) * 100;
    labels = {sprintf('电池自身发热 %.1fkWh', energy(1)), ...
        sprintf('电机铜耗 %.1fkWh', energy(2)), ...
        sprintf('控制器损耗 %.1fkWh', energy(3))};
    pie(energy, labels);
    title({'默认双电机方案能量分布', ...
        sprintf('电池加热效率 %.1f%% = %.1f/%.1f kWh', ...
        battery_heat_efficiency_pct, row.E_battery_heat_30min_kWh, ...
        total_electric)});
end

function plot_dual_motor_sensitivity(~, ~, p, study, topology)
    % 汇报图2:
    % 聚焦三包并联双电机主方案，分别扫描电流幅值、频率、散热边界和电池内阻倍率。
    % 这些图用于判断趋势和优先补参方向，不代表控制器可实现性已经验证。
    figure('Name', [topology.short_name, ' 汇报图2 双电机性能敏感性'], ...
        'Color', 'w', 'Position', [60 60 1600 920]);
    tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_current_sensitivity(p, study);

    nexttile;
    plot_frequency_sensitivity(p, study);

    nexttile;
    plot_heat_boundary_sensitivity(p, study);

    nexttile;
    plot_resistance_sensitivity(p, study);
end

function plot_current_sensitivity(p, study)
    % 电流幅值敏感性:
    % current_amplitude_scale越大，电池I^2R热源通常越强，但也更容易触发电机/MCU限流。
    amp_list = p.current_amplitude_scale_scan;
    T20 = zeros(size(amp_list));
    SOC_per_C = zeros(size(amp_list));
    I_motor = zeros(size(amp_list));
    for k = 1:numel(amp_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, amp_list(k), study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
        I_motor(k) = m.I_motor_rms_A;
    end
    plot(I_motor, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.85 0.33 0.10]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(I_motor, T20, SOC_per_C);
    hold off;
    xlabel('实际单电机RMS电流 (Arms)');
    ylabel('20min终温 (C)');
    title('电流大小影响');
    subtitle('标注为单位温升等效SOC消耗: %SOC/C');
    grid on;
end

function plot_frequency_sensitivity(p, study)
    % 频率敏感性:
    % 在相同电压和RL参数下，频率改变会改变电流纹波和RMS电流，从而影响电池发热。
    f_list = p.frequency_scan_Hz;
    T20 = zeros(size(f_list));
    SOC_per_C = zeros(size(f_list));
    for k = 1:numel(f_list)
        m = simulate_report_case(p, study, f_list(k), study.default_duty, ...
            study.default_current_amplitude_scale, study.SOC, ...
            p.R_heat_factor_default, p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(f_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.47 0.67 0.19]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(f_list, T20, SOC_per_C);
    hold off;
    xlabel('频率 (Hz)');
    ylabel('20min终温 (C)');
    title('频率大小影响');
    subtitle('当前固定电压幅值口径下, 高频会降低电流纹波');
    grid on;
end

function plot_heat_boundary_sensitivity(p, study)
    % 散热边界敏感性:
    % h_conv越大，散热越强，30min末温度越低。当前h_conv是粗筛占位参数。
    h_list = p.h_conv_scan_W_per_m2K;
    T20 = zeros(size(h_list));
    SOC_per_C = zeros(size(h_list));
    for k = 1:numel(h_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, study.default_current_amplitude_scale, ...
            study.SOC, p.R_heat_factor_default, ...
            p.I_motor_rms_limit_default_A, h_list(k));
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(h_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.18 0.42 0.70]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    xline(p.h_conv_W_per_m2K, '--', '默认h', 'LineWidth', 1.1);
    annotate_soc_per_C(h_list, T20, SOC_per_C);
    hold off;
    xlabel('等效换热系数 h (W/m^2/K)');
    ylabel('20min终温 (C)');
    title('电池加热环境边界影响');
    subtitle('液冷/泵阀/环境不确定性折算为等效对流换热系数');
    grid on;
end

function plot_resistance_sensitivity(p, study)
    % 电池发热阻抗倍率敏感性:
    % R_heat_factor用于反映高频等效阻抗可能低于1s DCR的情况。
    R_list = p.R_heat_factor_scan;
    T20 = zeros(size(R_list));
    SOC_per_C = zeros(size(R_list));
    for k = 1:numel(R_list)
        m = simulate_report_case(p, study, study.default_frequency_Hz, ...
            study.default_duty, study.default_current_amplitude_scale, ...
            study.SOC, R_list(k), p.I_motor_rms_limit_default_A, ...
            p.h_conv_W_per_m2K);
        T20(k) = m.T20_C;
        SOC_per_C(k) = m.energy_equiv_SOC_delta_per_C_pct;
    end
    plot(R_list, T20, '-o', 'LineWidth', 2.0, ...
        'Color', [0.49 0.18 0.56]);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    annotate_soc_per_C(R_list, T20, SOC_per_C);
    hold off;
    xlabel('高频发热电阻系数 R_{heat}/DCR');
    ylabel('20min终温 (C)');
    title('高频电阻变化敏感性');
    subtitle('决定电池自身发热量级, 是当前最大不确定性');
    grid on;
end

function plot_single_motor_comparison(summary, results, sens, p, study, topology)
    % 汇报图3:
    % 对比三包并联单电机和双电机默认温升，并展示单电机不同电流幅值下的初始温升与限制来源。
    figure('Name', [topology.short_name, ' 汇报图3 单电机对比'], ...
        'Color', 'w', 'Position', [80 80 1450 760]);
    tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot_single_vs_dual_temperature(summary, sens, p);

    nexttile;
    plot_single_motor_limit_scan(results, study);
end

function plot_single_vs_dual_temperature(summary, sens, ~)
    % 单电机和双电机默认方案温度对比。双电机通常提供更强电池侧RMS电流和热源。
    rows = strcmp(sens.sensitivity_axis, 'R_heat_limit_matrix') & ...
        strcmp(sens.mismatch_label, 'nominal') & sens.R_heat_factor == 1 & ...
        sens.motor_rms_limit_A == 550;
    data = sens(rows, :);
    labels = categorical(data.case_id);
    labels = reordercats(labels, data.case_id);
    bar(labels, [data.T_20min_C, data.T_30min_C], 'grouped');
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    hold off;
    ylabel('平均电池温度 (C)');
    title('默认极限参考下: 单电机仍难以满足要求');
    legend({'20min', '30min'}, 'Location', 'northwest');
    grid on;

    row_single = summary(strcmp(summary.case_id, '三包并联单电机'), :);
    text(1, row_single.T_end_30min_C + 1.2, '30min仍未到0C', ...
        'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

function plot_single_motor_limit_scan(results, study)
    % 单电机方案的电流幅值扫描:
    % 只取默认温度、频率、占空比、内阻倍率和限流条件，避免把多维扫描混在一起。
    rows = strcmp(results.case_id, '三包并联单电机') & ...
        results.T_init_C == study.default_temperature_C & ...
        strcmp(results.mismatch_label, 'nominal') & results.R_heat_factor == 1 & ...
        results.motor_rms_limit_A == 550 & results.duty == study.default_duty;
    data = results(rows, :);
    amp_vals = unique(data.current_amplitude_scale, 'stable');
    T20 = zeros(size(amp_vals));
    I_motor = zeros(size(amp_vals));
    for k = 1:numel(amp_vals)
        subset = data(data.current_amplitude_scale == amp_vals(k), :);
        [~, idx] = max(subset.dTdt_C_per_min);
        T20(k) = study.default_temperature_C + subset.dTdt_C_per_min(idx) * 20;
        I_motor(k) = subset.I_motor_rms_A(idx);
    end
    yyaxis left;
    plot(amp_vals, T20, '-o', 'LineWidth', 2.0);
    hold on;
    yline(0, 'k:', '0C目标', 'LineWidth', 1.1);
    ylabel('最佳频率下20min终温估算 (C)');
    yyaxis right;
    plot(amp_vals, I_motor, '--s', 'LineWidth', 1.8);
    yline(550, '--r', '550Arms短时参考', 'LineWidth', 1.1);
    ylabel('单电机RMS电流 (A)');
    hold off;
    xlabel('单电机电流幅值系数');
    title('单电机推高幅值后的收益有限');
    grid on;
end

function annotate_soc_per_C(x, y, soc_per_C_pct)
    % 在图上标注单位温升等效SOC消耗，帮助比较加热效率。
    for k = 1:numel(x)
        if isnan(soc_per_C_pct(k)) || isinf(soc_per_C_pct(k))
            label = '-- %/C';
        else
            label = sprintf('%.2f%%/C', soc_per_C_pct(k));
        end
        text(x(k), y(k), ['  ', label], 'FontSize', 9, ...
            'VerticalAlignment', 'bottom');
    end
end

function m = simulate_report_case(p, study, f_Hz, duty, amp_scale, SOC0, ...
        R_heat_factor, motor_limit_A, h_conv)
    % 绘图专用的轻量仿真函数:
    % 为敏感性图快速生成30min温度、到0C时间和等效SOC。逻辑与主求解器保持同一物理口径。
    p_case = p;
    p_case.R_heat_factor_current = R_heat_factor;
    p_case.I_motor_rms_limit_A = motor_limit_A;
    p_case.I_motor_peak_limit_A = sqrt(2) * motor_limit_A;
    p_case.h_conv_W_per_m2K = h_conv;
    p_case.R_th_branch_K_per_W = 1 / max(h_conv * p_case.branch_area_m2, eps);
    c = struct('id', '三包并联双电机', ...
        'name', '三包并联整体输出，双电机脉冲', 'branch_count', 3, ...
        'motor_count', 2, 'type', 'whole_branch_sync');
    mismatch = ones(1, 3);
    dt_s = study.dt_s;
    t_end_s = 30 * 60;
    n_steps = floor(t_end_s / dt_s) + 1;
    t_s = (0:n_steps-1)' * dt_s;
    T_branch = zeros(n_steps, 3);
    SOC = zeros(n_steps, 1);
    E_total_kWh = zeros(n_steps, 1);
    I_motor = zeros(n_steps, 1);
    T_branch(1, :) = study.default_temperature_C;
    SOC(1) = SOC0;

    for k = 1:n_steps
        op = eval_circuit_operating_point(p_case, c, mean(T_branch(k, :)), ...
            SOC(k), f_Hz, duty, mismatch, amp_scale);
        heat = eval_heat_balance(p_case, op.P_branch_W, T_branch(k, :), 3);
        I_motor(k) = op.I_motor_rms_A;
        if k < n_steps
            E_total_kWh(k+1) = E_total_kWh(k) + ...
                op.P_total_electric_W / 1000 * dt_s / 3600;
            T_branch(k+1, :) = T_branch(k, :) + ...
                heat.P_net_branch_W / p_case.Cth_branch_J_per_K * dt_s;
            E_available_kWh = 3 * p_case.N_series * interp1( ...
                p_case.ocv_soc_bp, p_case.ocv_cell_V, SOC(k), ...
                'linear', 'extrap') * p_case.C_branch_Ah / 1000;
            SOC(k+1) = max(0, SOC(k) - op.P_total_electric_W * ...
                dt_s / 3.6e6 / max(E_available_kWh, eps));
        end
    end

    T_mean = mean(T_branch, 2);
    m = struct();
    m.T20_C = interp1(t_s / 60, T_mean, 20, 'linear', 'extrap');
    m.T30_C = T_mean(end);
    m.energy_equiv_SOC_delta_30min_pct = (SOC(1) - SOC(end)) * 100;
    m.delta_T_30min_C = m.T30_C - study.default_temperature_C;
    m.energy_equiv_SOC_delta_per_C_pct = m.energy_equiv_SOC_delta_30min_pct / ...
        max(m.delta_T_30min_C, eps);
    m.E_total_loss_equiv_30min_kWh = E_total_kWh(end);
    m.coulombic_SOC_delta_30min_pct = nan;
    m.I_motor_rms_A = I_motor(1);
end
