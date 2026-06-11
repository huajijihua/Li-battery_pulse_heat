function result = solve_pulse_heating_case(p, study, topology)
%SOLVE_PULSE_HEATING_CASE Runs scans and default transient simulations.

    result_rows = struct([]);
    row_idx = 0;

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
    [result.summary, result.sims] = build_default_summary(p, study, topology);
    result.sensitivity = build_sensitivity_summary(p, study, topology);
    result.topology = topology;
end

function row = make_result_row(p, c, study, i_mis, T_C, f_Hz, duty, op)
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
    idx = find(strcmp({topology.cases.id}, case_id), 1, 'first');
    if isempty(idx)
        error('PulseHeating:MissingTopologyCase', ...
            'Cannot find topology case "%s".', case_id);
    end
    c = topology.cases(idx);
end

function row = make_sensitivity_row(p, c, study, i_mis, sim, op, t_eval_min, ...
        sensitivity_axis, sim_cfg)
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
    row = study.branch_mismatch_sets(idx, :);
    if all(abs(row - 1) < 1e-12)
        mismatch = ones(1, branch_count);
    elseif branch_count == 2 && numel(row) >= 3
        mismatch = [row(1), row(3)];
    else
        mismatch = row(1:branch_count);
    end
end

function t_target = estimate_target_time(t_min, T_C, T_target_C)
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
    t_target = estimate_target_time(t_min, T_C, T_target_C);
    if isinf(t_target)
        value = nan;
    else
        value = interp1(t_min, metric, t_target, 'linear', 'extrap');
    end
end

function soc_delta_pct = estimate_energy_equiv_soc_delta_pct(p, c, SOC, E_total_kWh)
    E_branch_kWh = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap') * p.C_branch_Ah / 1000;
    E_total_available_kWh = c.branch_count * E_branch_kWh;
    soc_delta_pct = E_total_kWh / max(E_total_available_kWh, eps) * 100;
end

function note = soc_accounting_note()
    note = ['energy_equiv_SOC_delta为总不可逆损耗折算口径, 包含电池发热、电机损耗和逆变器损耗; ', ...
        'coulombic_SOC_delta为库仑/净Ah口径, 当前L0.5模型未估算。'];
end

function value = get_vector_value(x, idx)
    if numel(x) >= idx
        value = x(idx);
    else
        value = nan;
    end
end

function judgement = make_case_judgement(op)
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
