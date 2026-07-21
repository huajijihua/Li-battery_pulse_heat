function results = runM401CThermalLedger(runMode)
% Run M4-01C Reference thermal and complete energy ledger checks.

if nargin < 1
    runMode = "all";
end

runMode = string(runMode);
modelName = 'pulse_heating_official_spine_v04';
assert(bdIsLoaded(modelName), ...
    'Load the active V4 model before running the M4-01C ledger checks.');

scriptDir = fileparts(mfilename('fullpath'));
resultsDir = fullfile(fileparts(scriptDir), '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

csvPath = fullfile(resultsDir, 'M4-01C_thermal_ledger_v01.csv');
scenarios = createScenarios();

switch runMode
    case {"all", "preflight"}
        scenarioIndices = 1:height(scenarios);
    otherwise
        error('Unsupported run mode: %s', runMode);
end

records = repmat(emptyRecord(), numel(scenarioIndices), 1);
for k = 1:numel(scenarioIndices)
    scenario = scenarios(scenarioIndices(k), :);
    in = Simulink.SimulationInput(modelName);
    in = in.setModelParameter('StopTime', scalarText(scenario.StopTime_s));
    out = sim(in);

    records(k) = collectRecord(out, scenario);
    results = struct2table(records(1:k));
    writetable(results, csvPath);
end

results = struct2table(records);
verifyResults(results);
end

function scenarios = createScenarios()
scenarios = table( ...
    ["T00_UnfinishedWindow"; "T01_CompletedWindow"], ...
    ["unfinished"; "completed"], ...
    [0.005; 0.04], ...
    [NaN; 0.03], ...
    [NaN; 0.04], ...
    'VariableNames', {'Scenario_ID', 'Window_State', 'StopTime_s', ...
    'Window_Start_s', 'Window_Stop_s'});
end

function record = collectRecord(out, scenario)
kpi = getSignal(out, 'SystemKPI');
kpiData = signalData(kpi);
assert(size(kpiData, 2) >= 45, 'SystemKPI does not expose the M4-01C ledger fields.');

record = emptyRecord();
record.Scenario_ID = scenario.Scenario_ID;
record.Window_State = scenario.Window_State;
record.SimulationStop_s = out.tout(end);
record.ClosedLoop_Final = lastValue(getSignal(out, 'EnClosedLoop_Active'));
record.MaxAbsSpeed_rad_s = max(abs(signalData(getSignal(out, 'MechSpeed_rad_s'))));
record.GateOverlap_Count = gateOverlapCount(getSignal(out, 'PWM_Gates'));
record.GateComplementMismatch_Count = gateMismatchCount(getSignal(out, 'PWM_Gates'));
record.EnergyLedgerValid_Final = lastValue(getSignal(out, 'full_ledger_valid'));
record.ElectricalLedgerValid_Final = kpiData(end, 45);
record.DeltaE_batt_Model_J = kpiData(end, 35);
record.P_dc_link_storage_Model_W = kpiData(end, 32);
record.P_thermal_storage_Model_W = kpiData(end, 39);
record.P_heat_rejection_Model_W = kpiData(end, 40);
record.P_mech_Model_W = kpiData(end, 38);
record.P_unmodeled_Model_W = kpiData(end, 42);
record.Residual_dc_link_Model_W = kpiData(end, 43);

assert(abs(record.SimulationStop_s - scenario.StopTime_s) < 1e-9, ...
    'Simulation did not reach the requested stop time.');
assert(record.GateOverlap_Count == 0, 'Gate overlap detected.');
assert(record.GateComplementMismatch_Count == 0, 'Gate complement mismatch detected.');
assert(record.ClosedLoop_Final == 1, 'Closed-loop mode was not active at the end of the run.');
assert(record.MaxAbsSpeed_rad_s < 1e-9, 'Zero-speed boundary was violated.');

if scenario.Window_State == "unfinished"
    record.ThermalFields_AllNaN = double(all(isnan([record.DeltaE_batt_Model_J, ...
        record.P_thermal_storage_Model_W, record.P_heat_rejection_Model_W, ...
        record.P_unmodeled_Model_W])));
    return;
end

windowStart = scenario.Window_Start_s;
windowStop = scenario.Window_Stop_s;
windowDuration = windowStop - windowStart;
vBatt = getSignal(out, 'V_batt');
iBatt = getSignal(out, 'I_batt');
vDc = getSignal(out, 'V_dc_bus');
iDc = getSignal(out, 'I_dc');
eDc = getSignal(out, 'E_dc_link');
pHv = getSignal(out, 'P_hv_loss');

record.Window_Start_s = windowStart;
record.Window_Stop_s = windowStop;
record.P_batt_heat_Mean_W = windowKpiMean(kpi, 9, windowStart, windowStop);
record.P_cu_Mean_W = windowKpiMean(kpi, 10, windowStart, windowStop);
record.P_iron_Mean_W = windowKpiMean(kpi, 11, windowStart, windowStop);
record.P_inv_Mean_W = windowKpiMean(kpi, 12, windowStart, windowStop);
record.P_hv_loss_Mean_W = windowMean(pHv, windowStart, windowStop);
record.P_heat_input_Recalc_W = record.P_batt_heat_Mean_W + ...
    record.P_cu_Mean_W + record.P_iron_Mean_W + record.P_inv_Mean_W + ...
    record.P_hv_loss_Mean_W;
record.DeltaE_batt_Recalc_J = -windowIntegralSum(vBatt, iBatt, kpi, 9, ...
    windowStart, windowStop);
record.P_dc_link_storage_Recalc_W = windowEnergyRate(eDc, windowStart, windowStop);
record.P_thermal_balance_Error_W = record.P_heat_input_Recalc_W - ...
    record.P_thermal_storage_Model_W - record.P_heat_rejection_Model_W;
record.P_unmodeled_Recalc_W = -record.DeltaE_batt_Model_J / windowDuration - ...
    record.P_dc_link_storage_Model_W - record.P_thermal_storage_Model_W - ...
    record.P_heat_rejection_Model_W - record.P_mech_Model_W;
record.Residual_dc_link_Recalc_W = windowProductMean(vBatt, iBatt, ...
    windowStart, windowStop) - record.P_hv_loss_Mean_W - ...
    record.P_dc_link_storage_Model_W - windowProductMean(vDc, iDc, ...
    windowStart, windowStop);
record.DeltaE_batt_AbsError_J = abs(record.DeltaE_batt_Model_J - ...
    record.DeltaE_batt_Recalc_J);
record.P_dc_link_storage_AbsError_W = abs(record.P_dc_link_storage_Model_W - ...
    record.P_dc_link_storage_Recalc_W);
record.P_unmodeled_AbsError_W = abs(record.P_unmodeled_Model_W - ...
    record.P_unmodeled_Recalc_W);
record.Residual_dc_link_AbsError_W = abs(record.Residual_dc_link_Model_W - ...
    record.Residual_dc_link_Recalc_W);
record.ThermalFields_AllNaN = 0;
end

function verifyResults(results)
unfinished = results(results.Window_State == "unfinished", :);
completed = results(results.Window_State == "completed", :);

assert(unfinished.EnergyLedgerValid_Final == 0, ...
    'Unfinished window unexpectedly reports a complete energy ledger.');
assert(unfinished.ElectricalLedgerValid_Final == 0, ...
    'Unfinished window unexpectedly reports an electrical ledger.');
assert(unfinished.ThermalFields_AllNaN == 1, ...
    'Unfinished window must retain unavailable thermal ledger fields as NaN.');
assert(completed.EnergyLedgerValid_Final == 1, ...
    'Completed window did not report a complete energy ledger.');
assert(completed.ElectricalLedgerValid_Final == 1, ...
    'Completed window did not retain the electrical ledger flag.');
assert(completed.ThermalFields_AllNaN == 0, ...
    'Completed window did not publish the thermal ledger fields.');
assert(completed.DeltaE_batt_AbsError_J < 1e-10, ...
    'Battery energy independent recomputation failed.');
assert(completed.P_dc_link_storage_AbsError_W < 1e-10, ...
    'DC-link storage independent recomputation failed.');
assert(abs(completed.P_thermal_balance_Error_W) < 1e-10, ...
    'Thermal source/storage/rejection balance failed.');
assert(completed.P_unmodeled_AbsError_W < 1e-10, ...
    'System unmodeled-power independent recomputation failed.');
assert(completed.Residual_dc_link_AbsError_W < 1e-10, ...
    'DC boundary residual independent recomputation failed.');
end

function signal = getSignal(out, name)
names = out.logsout.getElementNames;
assert(any(strcmp(names, name)), 'Required logged signal is missing: %s', name);
signal = out.logsout.get(name).Values;
end

function value = windowKpiMean(signal, column, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data(:, column)) / (stopTime - startTime);
end

function value = windowMean(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data) / (stopTime - startTime);
end

function value = windowProductMean(firstSignal, secondSignal, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
time = unique([firstTime; secondTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
value = trapz(time, first .* second) / (stopTime - startTime);
end

function value = windowIntegralSum(firstSignal, secondSignal, kpiSignal, column, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
[kpiTime, kpiData] = windowData(kpiSignal, startTime, stopTime);
time = unique([firstTime; secondTime; kpiTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
loss = interp1(kpiTime, kpiData(:, column), time, 'linear', 'extrap');
value = trapz(time, first .* second + loss);
end

function value = windowEnergyRate(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = (data(end) - data(1)) / (stopTime - startTime);
end

function [time, data] = windowData(signal, startTime, stopTime)
rawTime = signal.Time(:);
rawData = signalData(signal);
[sortedTime, order] = sort(rawTime);
sortedData = rawData(order, :);
[uniqueTime, lastIndex] = unique(sortedTime, 'last');
uniqueData = sortedData(lastIndex, :);
inside = uniqueTime > startTime & uniqueTime < stopTime;
time = [startTime; uniqueTime(inside); stopTime];
data = interp1(uniqueTime, uniqueData, time, 'linear', 'extrap');
end

function data = signalData(signal)
data = double(signal.Data);
if isvector(data)
    data = data(:);
end
assert(size(data, 1) == numel(signal.Time), 'Unexpected logged signal orientation.');
end

function value = lastValue(signal)
data = signalData(signal);
value = data(end, 1);
end

function count = gateOverlapCount(signal)
gates = signalData(signal) > 0.5;
count = sum((gates(:, 1) & gates(:, 2)) | (gates(:, 3) & gates(:, 4)) | ...
    (gates(:, 5) & gates(:, 6)));
end

function count = gateMismatchCount(signal)
gates = signalData(signal) > 0.5;
count = sum((gates(:, 1) == gates(:, 2)) | (gates(:, 3) == gates(:, 4)) | ...
    (gates(:, 5) == gates(:, 6)));
end

function text = scalarText(value)
text = num2str(value, '%.15g');
end

function record = emptyRecord()
record = struct( ...
    'Scenario_ID', "", ...
    'Window_State', "", ...
    'SimulationStop_s', NaN, ...
    'Window_Start_s', NaN, ...
    'Window_Stop_s', NaN, ...
    'ClosedLoop_Final', NaN, ...
    'MaxAbsSpeed_rad_s', NaN, ...
    'GateOverlap_Count', NaN, ...
    'GateComplementMismatch_Count', NaN, ...
    'EnergyLedgerValid_Final', NaN, ...
    'ElectricalLedgerValid_Final', NaN, ...
    'ThermalFields_AllNaN', NaN, ...
    'DeltaE_batt_Model_J', NaN, ...
    'DeltaE_batt_Recalc_J', NaN, ...
    'DeltaE_batt_AbsError_J', NaN, ...
    'P_batt_heat_Mean_W', NaN, ...
    'P_hv_loss_Mean_W', NaN, ...
    'P_inv_Mean_W', NaN, ...
    'P_cu_Mean_W', NaN, ...
    'P_iron_Mean_W', NaN, ...
    'P_heat_input_Recalc_W', NaN, ...
    'P_dc_link_storage_Model_W', NaN, ...
    'P_dc_link_storage_Recalc_W', NaN, ...
    'P_dc_link_storage_AbsError_W', NaN, ...
    'P_thermal_storage_Model_W', NaN, ...
    'P_heat_rejection_Model_W', NaN, ...
    'P_thermal_balance_Error_W', NaN, ...
    'P_mech_Model_W', NaN, ...
    'P_unmodeled_Model_W', NaN, ...
    'P_unmodeled_Recalc_W', NaN, ...
    'P_unmodeled_AbsError_W', NaN, ...
    'Residual_dc_link_Model_W', NaN, ...
    'Residual_dc_link_Recalc_W', NaN, ...
    'Residual_dc_link_AbsError_W', NaN);
end
