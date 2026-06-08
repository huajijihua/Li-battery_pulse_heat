function result = solve_pulse_heating_case(p, study, topology)
%SOLVE_PULSE_HEATING_CASE Runs scans and default transient simulations.

    result_rows = struct([]);
    row_idx = 0;

    for i_case = 1:numel(topology.cases)
        c = topology.cases(i_case);
        for i_mis = 1:numel(study.branch_mismatch_labels)
            mismatch = get_case_mismatch(study, i_mis, c.branch_count);
            for T_C = study.temperature_list_C
                for f_Hz = study.frequency_scan_Hz
                    for duty = study.duty_scan
                        for amplitude_scale = study.current_amplitude_scale_scan
                            op = eval_circuit_operating_point(p, c, T_C, ...
                                study.SOC, f_Hz, duty, mismatch, amplitude_scale);
                            row_idx = row_idx + 1;
                            row = make_result_row(p, c, study, i_mis, T_C, f_Hz, duty, op);
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

    result = struct();
    result.results = struct2table(result_rows);
    [result.summary, result.sims] = build_default_summary(p, study, topology);
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
    row.E_total_electric_30min_kWh = op.P_total_electric_W / 1000 * p.t_end_min / 60;
    row.SOC_delta_equiv_pct = estimate_soc_delta_pct(p, c, study.SOC, ...
        row.E_total_electric_30min_kWh);
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
            mismatch, study.default_current_amplitude_scale);
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
    row.E_total_to_0C_kWh = interpolate_metric_at_target(sim.t_min, ...
        sim.T_mean_C, sim.E_total_electric_kWh, p.T_target_C);
    row.SOC_delta_to_0C_pct = (sim.SOC(1) - interpolate_metric_at_target( ...
        sim.t_min, sim.T_mean_C, sim.SOC, p.T_target_C)) * 100;
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
    row.E_total_electric_30min_kWh = sim.E_total_electric_kWh(end);
    row.SOC_delta_equiv_pct = (sim.SOC(1) - sim.SOC(end)) * 100;
    row.SOC_end_pct = sim.SOC(end) * 100;
    row.initial_judgement = make_case_judgement(op);
    row.note = op.note;
end

function sim = simulate_pulse_heating_case(p, study, c, mismatch)
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

    T_branch(1, :) = p.T_init_C;
    SOC(1) = study.SOC;

    for k = 1:n_steps
        op = eval_circuit_operating_point(p, c, mean(T_branch(k, :)), SOC(k), ...
            study.default_frequency_Hz, study.default_duty, mismatch, ...
            study.default_current_amplitude_scale);
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

function soc_delta_pct = estimate_soc_delta_pct(p, c, SOC, E_total_kWh)
    E_branch_kWh = p.N_series * interp1(p.ocv_soc_bp, p.ocv_cell_V, ...
        SOC, 'linear', 'extrap') * p.C_branch_Ah / 1000;
    E_total_available_kWh = c.branch_count * E_branch_kWh;
    soc_delta_pct = E_total_kWh / max(E_total_available_kWh, eps) * 100;
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
