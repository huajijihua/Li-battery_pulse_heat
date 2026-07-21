function results = runM403ControlComparison(runMode)
% Run the M4-03 Reference / Platform closed-loop pulse comparison.

if nargin < 1
    runMode = "all";
end

runMode = string(runMode);
modelName = 'pulse_heating_official_spine_v04';
assert(bdIsLoaded(modelName), ...
    'Load the active V4 model before running the M4-03 control comparison.');

scriptDir = fileparts(mfilename('fullpath'));
resultsDir = fullfile(fileparts(scriptDir), '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

csvPath = fullfile(resultsDir, 'M4-03_control_comparison_v01.csv');
stopTime = 0.08;
windowStart = 0.04;
windowStop = 0.08;
windowDuration = windowStop - windowStart;

paths = resolveBlockPaths(modelName);
scenarios = createScenarios();

switch runMode
    case "preflight"
        scenarioIndices = [1, 3, 4];
    case "all"
        scenarioIndices = 1:height(scenarios);
    otherwise
        error('Unsupported run mode: %s', runMode);
end

records = repmat(emptyRecord(), numel(scenarioIndices), 1);
for k = 1:numel(scenarioIndices)
    scenario = scenarios(scenarioIndices(k), :);
    in = Simulink.SimulationInput(modelName);
    in = in.setModelParameter('StopTime', num2str(stopTime, '%.15g'));
    in = applyScenario(in, paths, scenario, windowDuration);
    out = sim(in);

    records(k) = collectRecord(out, scenario, windowStart, windowStop, windowDuration);
    results = struct2table(records(1:k));
    writetable(results, csvPath);
end

results = struct2table(records);
if runMode == "preflight"
    verifyPreflight(results);
end
end

function paths = resolveBlockPaths(modelName)
paths.HVPosR = Simulink.ID.getFullName([modelName ':740']);
paths.HVNegR = Simulink.ID.getFullName([modelName ':741']);
paths.DCLinkC = Simulink.ID.getFullName([modelName ':742']);
paths.PMSM = Simulink.ID.getFullName([modelName ':85']);
paths.RMSWindow = Simulink.ID.getFullName([modelName ':787']);
paths.HVLossGain = Simulink.ID.getFullName([modelName ':865']);
paths.DCLinkEnergyGain = Simulink.ID.getFullName([modelName ':867']);
paths.DCLinkEnergyInitial = Simulink.ID.getFullName([modelName ':868']);
paths.RsAudit = Simulink.ID.getFullName([modelName ':633']);
paths.RPackAudit = Simulink.ID.getFullName([modelName ':661']);
paths.IGBTRon = Simulink.ID.getFullName([modelName ':649']);
paths.IGBTVf = Simulink.ID.getFullName([modelName ':650']);
paths.IdPulse = Simulink.ID.getFullName([modelName ':532']);
paths.IdScale = Simulink.ID.getFullName([modelName ':533']);
paths.IdOffset = Simulink.ID.getFullName([modelName ':534']);
paths.IqRef = Simulink.ID.getFullName([modelName ':535']);
paths.LimitId = Simulink.ID.getFullName([modelName ':537']);
paths.LimitFrequency = Simulink.ID.getFullName([modelName ':538']);
paths.LimitDuty = Simulink.ID.getFullName([modelName ':539']);
paths.LimitPhase = Simulink.ID.getFullName([modelName ':540']);
paths.LimitMode = Simulink.ID.getFullName([modelName ':541']);
paths.LimitStatus = Simulink.ID.getFullName([modelName ':542']);
paths.ClosedLoopEnable = Simulink.ID.getFullName([modelName ':310']);
end

function scenarios = createScenarios()
name = ["C00_Base"; "C01_Freq_Low"; "C02_Freq_High"; ...
    "C03_Duty_Low"; "C04_Duty_High"; "C05_Amplitude_Low"; ...
    "C06_Amplitude_High"];
family = ["baseline"; "frequency"; "frequency"; "duty_bias"; ...
    "duty_bias"; "amplitude"; "amplitude"];

scenarios = table(name, family, ...
    [40; 40; 40; 40; 40; 20; 60], ...
    [50; 25; 100; 50; 50; 50; 50], ...
    [50; 50; 50; 25; 75; 50; 50], ...
    'VariableNames', {'Scenario_ID', 'Strategy_Family', 'Id_Amplitude_A', ...
    'Pulse_Frequency_Hz', 'Positive_Duty_Percent'});
end

function in = applyScenario(in, paths, scenario, windowDuration)
% Fix M4-02 nominal physical values before varying one control quantity.
in = in.setBlockParameter(paths.HVPosR, 'R', '0.01');
in = in.setBlockParameter(paths.HVNegR, 'R', '0.01');
in = in.setBlockParameter(paths.DCLinkC, 'C', '0.00047');
in = in.setBlockParameter(paths.PMSM, 'Rs', '0.013');
in = in.setBlockParameter(paths.RMSWindow, 'Value', scalarText(windowDuration));
in = in.setBlockParameter(paths.HVLossGain, 'Gain', '0.02');
in = in.setBlockParameter(paths.DCLinkEnergyGain, 'Gain', '0.000235');
in = in.setBlockParameter(paths.DCLinkEnergyInitial, 'Value', '0');
in = in.setBlockParameter(paths.RsAudit, 'Value', '0.013');
in = in.setBlockParameter(paths.RPackAudit, 'Value', '0.126');
in = in.setBlockParameter(paths.IGBTRon, 'Value', '0.001');
in = in.setBlockParameter(paths.IGBTVf, 'Value', '1.2');

in = in.setBlockParameter(paths.IdPulse, 'Amplitude', '1');
in = in.setBlockParameter(paths.IdPulse, 'Period', ...
    scalarText(1 / scenario.Pulse_Frequency_Hz));
in = in.setBlockParameter(paths.IdPulse, 'PulseWidth', ...
    scalarText(scenario.Positive_Duty_Percent));
in = in.setBlockParameter(paths.IdPulse, 'PhaseDelay', '0');
in = in.setBlockParameter(paths.IdScale, 'Gain', ...
    scalarText(2 * scenario.Id_Amplitude_A));
in = in.setBlockParameter(paths.IdOffset, 'Bias', ...
    scalarText(-scenario.Id_Amplitude_A));
in = in.setBlockParameter(paths.IqRef, 'Value', '0');
in = in.setBlockParameter(paths.LimitId, 'Value', ...
    scalarText(scenario.Id_Amplitude_A));
in = in.setBlockParameter(paths.LimitFrequency, 'Value', ...
    scalarText(scenario.Pulse_Frequency_Hz));
in = in.setBlockParameter(paths.LimitDuty, 'Value', ...
    scalarText(scenario.Positive_Duty_Percent));
in = in.setBlockParameter(paths.LimitPhase, 'Value', '0');
in = in.setBlockParameter(paths.LimitMode, 'Value', '4');
in = in.setBlockParameter(paths.LimitStatus, 'Value', '6');
in = in.setBlockParameter(paths.ClosedLoopEnable, 'Value', '1');
end

function record = collectRecord(out, scenario, windowStart, windowStop, windowDuration)
idRef = getSignal(out, 'Id_Ref');
idFb = getSignal(out, 'Id_fb');
iqFb = getSignal(out, 'Iq_fb');
vBatt = getSignal(out, 'V_batt');
iBatt = getSignal(out, 'I_batt');
vDc = getSignal(out, 'V_dc_bus');
iDc = getSignal(out, 'I_dc');
pHv = getSignal(out, 'P_hv_loss');
kpi = getSignal(out, 'SystemKPI');
gates = getSignal(out, 'PWM_Gates');
speed = getSignal(out, 'MechSpeed_rad_s');
reactionTorque = getSignal(out, 'MechReactionTorque_Nm');
closedLoop = getSignal(out, 'EnClosedLoop_Active');
energy = getSignal(out, 'E_dc_link');
deltaEnergy = getSignal(out, 'DeltaE_dc_link');
ledgerValid = getSignal(out, 'full_ledger_valid');
storageUnknown = getSignal(out, 'P_dc_link_storage_UNKNOWN');

record = emptyRecord();
record.Scenario_ID = scenario.Scenario_ID;
record.Strategy_Family = scenario.Strategy_Family;
record.Id_Amplitude_A = scenario.Id_Amplitude_A;
record.Pulse_Frequency_Hz = scenario.Pulse_Frequency_Hz;
record.Positive_Duty_Percent = scenario.Positive_Duty_Percent;
record.Expected_Id_Mean_A = scenario.Id_Amplitude_A * ...
    (2 * scenario.Positive_Duty_Percent / 100 - 1);
record.Window_Start_s = windowStart;
record.Window_Stop_s = windowStop;
record.Window_Duration_s = windowDuration;
record.IdRef_Min_A = windowMin(idRef, windowStart, windowStop);
record.IdRef_Max_A = windowMax(idRef, windowStart, windowStop);
record.IdRef_Mean_A = windowMean(idRef, windowStart, windowStop);
record.IdRef_RMS_A = windowRms(idRef, windowStart, windowStop);
record.IdRef_PositiveFraction = positiveFraction(idRef, windowStart, windowStop);
record.IdRef_Transition_Count = transitionCount(idRef, windowStart, windowStop);
record.IdFb_Mean_A = windowMean(idFb, windowStart, windowStop);
record.IdFb_RMS_A = windowRms(idFb, windowStart, windowStop);
record.IqFb_RMS_A = windowRms(iqFb, windowStart, windowStop);
record.Id_Tracking_RMS_Error_A = windowDifferenceRms(idFb, idRef, windowStart, windowStop);
record.Vdc_Min_V = windowMin(vDc, windowStart, windowStop);
record.Vdc_Max_V = windowMax(vDc, windowStart, windowStop);
record.Vdc_Ripple_V = record.Vdc_Max_V - record.Vdc_Min_V;
record.Ibatt_RMS_A = windowRms(iBatt, windowStart, windowStop);
record.Idc_RMS_A = windowRms(iDc, windowStart, windowStop);
record.Pbatt_Mean_W = windowProductMean(vBatt, iBatt, windowStart, windowStop);
record.PdcInput_Mean_W = windowProductMean(vDc, iDc, windowStart, windowStop);
record.PhvLoss_Mean_W = windowMean(pHv, windowStart, windowStop);
record.ModulationIndex_Mean = windowKpiMean(kpi, 7, windowStart, windowStop);
record.ModulationIndex_Max = windowKpiMax(kpi, 7, windowStart, windowStop);
record.VoltageMargin_Min_V = windowKpiMin(kpi, 8, windowStart, windowStop);
record.ControlSaturation_Any = windowKpiAny(kpi, 17, windowStart, windowStop);
record.PbattHeatProxy_Mean_W = windowKpiMean(kpi, 9, windowStart, windowStop);
record.Pcu_Mean_W = windowKpiMean(kpi, 10, windowStart, windowStop);
record.PinvProxy_Mean_W = windowKpiMean(kpi, 12, windowStart, windowStop);
record.PlossKnown_Mean_W = windowKpiMean(kpi, 36, windowStart, windowStop);
record.MaxAbsSpeed_rad_s = windowMaxAbs(speed, windowStart, windowStop);
record.ReactionTorque_RMS_Nm = windowRms(reactionTorque, windowStart, windowStop);
record.ClosedLoop_Final = lastValue(closedLoop);
record.EdcLink_Final_J = lastValue(energy);
record.DeltaEdcLink_Final_J = lastValue(deltaEnergy);
record.EnergyLedgerValid_Final = lastValue(ledgerValid);
record.DCLinkStorage_AllNaN = double(all(isnan(signalData(storageUnknown))));
record.GateOverlap_Count = gateOverlapCount(gates, windowStart, windowStop);
record.GateComplementMismatch_Count = gateMismatchCount(gates, windowStart, windowStop);
record.SimulationStop_s = out.tout(end);

assert(abs(record.SimulationStop_s - windowStop) < 1e-9, 'Simulation did not reach the requested stop time.');
assert(abs(record.IdRef_Min_A + scenario.Id_Amplitude_A) < 1e-6, 'Negative Id reference was not applied.');
assert(abs(record.IdRef_Max_A - scenario.Id_Amplitude_A) < 1e-6, 'Positive Id reference was not applied.');
assert(abs(record.IdRef_PositiveFraction - scenario.Positive_Duty_Percent / 100) < 0.03, ...
    'Pulse duty override was not applied.');
assert(record.IdRef_Transition_Count >= 1, 'Pulse reference did not transition in the evaluation window.');
assert(record.GateOverlap_Count == 0, 'Gate overlap detected.');
assert(record.GateComplementMismatch_Count == 0, 'Gate complement mismatch detected.');
assert(record.ClosedLoop_Final == 1, 'Closed-loop mode was not active at the end of the run.');
assert(record.MaxAbsSpeed_rad_s < 1e-9, 'Zero-speed boundary was violated.');
assert(record.DCLinkStorage_AllNaN == 1, 'DC-link storage field changed from its declared UNKNOWN state.');
assert(record.EnergyLedgerValid_Final == 0, 'Full energy ledger unexpectedly reports valid.');
end

function verifyPreflight(results)
base = results(results.Scenario_ID == "C00_Base", :);
highFrequency = results(results.Scenario_ID == "C02_Freq_High", :);
lowDuty = results(results.Scenario_ID == "C03_Duty_Low", :);
assert(highFrequency.IdRef_Transition_Count > base.IdRef_Transition_Count, ...
    'High-frequency pulse override was not applied.');
assert(abs(lowDuty.IdRef_PositiveFraction - 0.25) < 0.03, ...
    'Low-duty pulse override was not applied.');
assert(abs(base.IdRef_RMS_A - 40) < 1e-6, 'Baseline Id reference amplitude was not applied.');
assert(abs(highFrequency.IdRef_RMS_A - 40) < 1e-6, 'High-frequency Id reference amplitude was not applied.');
end

function signal = getSignal(out, name)
names = out.logsout.getElementNames;
assert(any(strcmp(names, name)), 'Required logged signal is missing: %s', name);
signal = out.logsout.get(name).Values;
end

function value = windowMean(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data) / (stopTime - startTime);
end

function value = windowRms(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = sqrt(trapz(time, data.^2) / (stopTime - startTime));
end

function value = windowDifferenceRms(firstSignal, secondSignal, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
time = unique([firstTime; secondTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
value = sqrt(trapz(time, (first - second).^2) / (stopTime - startTime));
end

function value = windowProductMean(firstSignal, secondSignal, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
time = unique([firstTime; secondTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
value = trapz(time, first .* second) / (stopTime - startTime);
end

function value = windowKpiMean(signal, column, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data(:, column)) / (stopTime - startTime);
end

function value = windowKpiMin(signal, column, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = min(data(:, column));
end

function value = windowKpiMax(signal, column, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = max(data(:, column));
end

function value = windowKpiAny(signal, column, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = double(any(data(:, column) > 0.5));
end

function value = windowMin(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = min(data);
end

function value = windowMax(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = max(data);
end

function value = windowMaxAbs(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
value = max(abs(data));
end

function value = positiveFraction(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, double(data > 0)) / (stopTime - startTime);
end

function count = transitionCount(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
states = data > 0;
count = sum(diff(states) ~= 0);
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

function count = gateOverlapCount(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
gates = data > 0.5;
count = sum((gates(:, 1) & gates(:, 2)) | (gates(:, 3) & gates(:, 4)) | (gates(:, 5) & gates(:, 6)));
end

function count = gateMismatchCount(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
gates = data > 0.5;
count = sum((gates(:, 1) == gates(:, 2)) | (gates(:, 3) == gates(:, 4)) | (gates(:, 5) == gates(:, 6)));
end

function text = scalarText(value)
text = num2str(value, '%.15g');
end

function record = emptyRecord()
record = struct( ...
    'Scenario_ID', "", ...
    'Strategy_Family', "", ...
    'Id_Amplitude_A', NaN, ...
    'Pulse_Frequency_Hz', NaN, ...
    'Positive_Duty_Percent', NaN, ...
    'Expected_Id_Mean_A', NaN, ...
    'Window_Start_s', NaN, ...
    'Window_Stop_s', NaN, ...
    'Window_Duration_s', NaN, ...
    'IdRef_Min_A', NaN, ...
    'IdRef_Max_A', NaN, ...
    'IdRef_Mean_A', NaN, ...
    'IdRef_RMS_A', NaN, ...
    'IdRef_PositiveFraction', NaN, ...
    'IdRef_Transition_Count', NaN, ...
    'IdFb_Mean_A', NaN, ...
    'IdFb_RMS_A', NaN, ...
    'IqFb_RMS_A', NaN, ...
    'Id_Tracking_RMS_Error_A', NaN, ...
    'Vdc_Min_V', NaN, ...
    'Vdc_Max_V', NaN, ...
    'Vdc_Ripple_V', NaN, ...
    'Ibatt_RMS_A', NaN, ...
    'Idc_RMS_A', NaN, ...
    'Pbatt_Mean_W', NaN, ...
    'PdcInput_Mean_W', NaN, ...
    'PhvLoss_Mean_W', NaN, ...
    'ModulationIndex_Mean', NaN, ...
    'ModulationIndex_Max', NaN, ...
    'VoltageMargin_Min_V', NaN, ...
    'ControlSaturation_Any', NaN, ...
    'PbattHeatProxy_Mean_W', NaN, ...
    'Pcu_Mean_W', NaN, ...
    'PinvProxy_Mean_W', NaN, ...
    'PlossKnown_Mean_W', NaN, ...
    'MaxAbsSpeed_rad_s', NaN, ...
    'ReactionTorque_RMS_Nm', NaN, ...
    'ClosedLoop_Final', NaN, ...
    'EdcLink_Final_J', NaN, ...
    'DeltaEdcLink_Final_J', NaN, ...
    'EnergyLedgerValid_Final', NaN, ...
    'DCLinkStorage_AllNaN', NaN, ...
    'GateOverlap_Count', NaN, ...
    'GateComplementMismatch_Count', NaN, ...
    'SimulationStop_s', NaN);
end
