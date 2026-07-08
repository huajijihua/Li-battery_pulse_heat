function kpi = compute_kpi_v02(simOut, caseName, modeName, commandAmplitude, modulationLimit)
%COMPUTE_KPI_V02 Compute minimal v03-B3 audit KPIs from SimulationOutput.
%
% This first v02 KPI pass only uses logged signals that already exist in
% pulse_heating_single_pack_v03. Fields that need battery EIS, BMS limits,
% inverter deadtime, or switching loss data are intentionally left to v03-C.

    if nargin < 5
        modulationLimit = 0.95;
    end

    kpi = struct();
    kpi.caseName = string(caseName);
    kpi.mode = string(modeName);
    kpi.commandAmplitude = commandAmplitude;

    kpi.Id_ref_rms_A = signalRms(simOut, "Id_ref_log");
    kpi.Id_fb_rms_A = signalRms(simOut, "Id_fb_log");
    kpi.Iq_fb_rms_A = signalRms(simOut, "Iq_fb_log");
    kpi.tracking_error_rms_A = signalRms(simOut, "Id_error_log");

    kpi.I_motor_phase_rms_A = signalRms(simOut, "Iabc_motor_log");
    kpi.I_motor_phase_peak_A = signalPeak(simOut, "Iabc_motor_log");
    kpi.I_battery_terminal_rms_A = signalRms(simOut, "I_battery_terminal_log");
    kpi.V_battery_terminal_rms_V = signalRms(simOut, "V_battery_terminal_log");

    kpi.md_rms = signalRms(simOut, "md_cmd_log");
    kpi.mq_rms = signalRms(simOut, "mq_cmd_log");
    kpi.mabc_peak = signalPeak(simOut, "mabc_cmd_log");
    kpi.is_modulation_saturated = kpi.mabc_peak >= 0.98 * modulationLimit;
    kpi.limiting_factor = classifyLimit(kpi);
end

function factor = classifyLimit(kpi)
    if isnan(kpi.mabc_peak)
        factor = "data_gap";
    elseif kpi.is_modulation_saturated
        factor = "modulation_saturation";
    elseif kpi.tracking_error_rms_A > 0.5 * max(kpi.Id_ref_rms_A, 1)
        factor = "tracking_error_high";
    else
        factor = "none_observed";
    end
end

function value = signalRms(simOut, signalName)
    data = signalDataAfterSettling(simOut, signalName);
    if isempty(data)
        value = NaN;
    else
        value = rms(data, "all");
    end
end

function value = signalPeak(simOut, signalName)
    data = signalDataAfterSettling(simOut, signalName);
    if isempty(data)
        value = NaN;
    else
        value = max(abs(data), [], "all");
    end
end

function data = signalDataAfterSettling(simOut, signalName)
    names = simOut.who;
    if ~any(strcmp(names, signalName))
        data = [];
        return;
    end

    ts = simOut.get(signalName);
    data = squeeze(ts.Data);
    if isempty(data)
        data = [];
        return;
    end

    if isvector(data)
        data = data(:);
    elseif size(data, 1) < size(data, 2) && size(data, 2) == numel(ts.Time)
        data = data';
    end

    startIdx = max(1, round(0.2 * size(data, 1)));
    data = data(startIdx:end, :);
end
