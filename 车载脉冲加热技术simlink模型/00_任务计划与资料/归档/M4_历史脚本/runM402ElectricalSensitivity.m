function results = runM402ElectricalSensitivity(runMode)
% Run the M4-02 Reference / Platform electrical sensitivity matrix.

if nargin < 1
    runMode = "all";
end

runMode = string(runMode);
modelName = 'pulse_heating_official_spine_v04';
assert(bdIsLoaded(modelName), ...
    'Load the active V4 model before running the M4-02 sensitivity matrix.');

scriptDir = fileparts(mfilename('fullpath'));
resultsDir = fullfile(fileparts(scriptDir), '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

csvPath = fullfile(resultsDir, 'M4-02_electrical_sensitivity_v01.csv');
stopTime = 0.08;
windowStart = 0.04;
windowStop = 0.08;
windowDuration = windowStop - windowStart;

paths = resolveBlockPaths(modelName);
scenarios = createScenarios();

switch runMode
    case "preflight"
        scenarioIndices = [1, 3];
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
end

function scenarios = createScenarios()
name = ["S00_Base"; "S01_HVPathR_Low"; "S02_HVPathR_High"; ...
    "S03_DCLinkC_Low"; "S04_DCLinkC_High"; "S05_Rs_Low"; ...
    "S06_Rs_High"; "S07_RpackProxy_Low"; "S08_RpackProxy_High"; ...
    "S09_IGBTLoss_Low"; "S10_IGBTLoss_High"];
family = ["baseline"; "physical_path"; "physical_path"; ...
    "physical_path"; "physical_path"; "physical_path"; ...
    "physical_path"; "audit_proxy"; "audit_proxy"; ...
    "audit_proxy"; "audit_proxy"];

scenarios = table(name, family, ...
    [0.01; 0.005; 0.02; 0.01; 0.01; 0.01; 0.01; 0.01; 0.01; 0.01; 0.01], ...
    [470e-6; 470e-6; 470e-6; 235e-6; 940e-6; 470e-6; 470e-6; 470e-6; 470e-6; 470e-6; 470e-6], ...
    [0.013; 0.013; 0.013; 0.013; 0.013; 0.0065; 0.026; 0.013; 0.013; 0.013; 0.013], ...
    [0.126; 0.126; 0.126; 0.126; 0.126; 0.126; 0.126; 0.063; 0.252; 0.126; 0.126], ...
    [1e-3; 1e-3; 1e-3; 1e-3; 1e-3; 1e-3; 1e-3; 1e-3; 1e-3; 0.5e-3; 2e-3], ...
    [1.2; 1.2; 1.2; 1.2; 1.2; 1.2; 1.2; 1.2; 1.2; 0.9; 1.5], ...
    'VariableNames', {'Scenario_ID', 'Parameter_Family', 'HVPath_R_Ohm', ...
    'DCLink_C_F', 'Rs_Ohm', 'R_pack_proxy_Ohm', 'IGBT_Ron_ref_Ohm', 'IGBT_Vf_ref_V'});
end

function in = applyScenario(in, paths, scenario, windowDuration)
in = in.setBlockParameter(paths.HVPosR, 'R', scalarText(scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.HVNegR, 'R', scalarText(scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.DCLinkC, 'C', scalarText(scenario.DCLink_C_F));
in = in.setBlockParameter(paths.PMSM, 'Rs', scalarText(scenario.Rs_Ohm));
in = in.setBlockParameter(paths.RMSWindow, 'Value', scalarText(windowDuration));
in = in.setBlockParameter(paths.HVLossGain, 'Gain', scalarText(2 * scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.DCLinkEnergyGain, 'Gain', scalarText(0.5 * scenario.DCLink_C_F));
in = in.setBlockParameter(paths.DCLinkEnergyInitial, 'Value', '0');
in = in.setBlockParameter(paths.RsAudit, 'Value', scalarText(scenario.Rs_Ohm));
in = in.setBlockParameter(paths.RPackAudit, 'Value', scalarText(scenario.R_pack_proxy_Ohm));
in = in.setBlockParameter(paths.IGBTRon, 'Value', scalarText(scenario.IGBT_Ron_ref_Ohm));
in = in.setBlockParameter(paths.IGBTVf, 'Value', scalarText(scenario.IGBT_Vf_ref_V));
end

function record = collectRecord(out, scenario, windowStart, windowStop, windowDuration)
vBatt = getSignal(out, 'V_batt');
iBatt = getSignal(out, 'I_batt');
vDc = getSignal(out, 'V_dc_bus');
iDc = getSignal(out, 'I_dc');
pHv = getSignal(out, 'P_hv_loss');
kpi = getSignal(out, 'SystemKPI');
gates = getSignal(out, 'PWM_Gates');
idFb = getSignal(out, 'Id_fb');
iqFb = getSignal(out, 'Iq_fb');
speed = getSignal(out, 'MechSpeed_rad_s');
reactionTorque = getSignal(out, 'MechReactionTorque_Nm');
closedLoop = getSignal(out, 'EnClosedLoop_Active');
energy = getSignal(out, 'E_dc_link');
deltaEnergy = getSignal(out, 'DeltaE_dc_link');
ledgerValid = getSignal(out, 'full_ledger_valid');
storageUnknown = getSignal(out, 'P_dc_link_storage_UNKNOWN');

record = emptyRecord();
record.Scenario_ID = scenario.Scenario_ID;
record.Parameter_Family = scenario.Parameter_Family;
record.HVPath_R_Ohm = scenario.HVPath_R_Ohm;
record.DCLink_C_F = scenario.DCLink_C_F;
record.Rs_Ohm = scenario.Rs_Ohm;
record.R_pack_proxy_Ohm = scenario.R_pack_proxy_Ohm;
record.IGBT_Ron_ref_Ohm = scenario.IGBT_Ron_ref_Ohm;
record.IGBT_Vf_ref_V = scenario.IGBT_Vf_ref_V;
record.Window_Start_s = windowStart;
record.Window_Stop_s = windowStop;
record.Window_Duration_s = windowDuration;
record.Vdc_Min_V = windowMin(vDc, windowStart, windowStop);
record.Vdc_Max_V = windowMax(vDc, windowStart, windowStop);
record.Vdc_Ripple_V = record.Vdc_Max_V - record.Vdc_Min_V;
record.Ibatt_RMS_A = windowRms(iBatt, windowStart, windowStop);
record.Idc_RMS_A = windowRms(iDc, windowStart, windowStop);
record.Pbatt_Mean_W = windowProductMean(vBatt, iBatt, windowStart, windowStop);
record.PdcInput_Mean_W = windowProductMean(vDc, iDc, windowStart, windowStop);
record.PhvLoss_Mean_W = windowMean(pHv, windowStart, windowStop);
record.IbattSq_Mean_A2 = windowSquaredMean(iBatt, windowStart, windowStop);
record.HVLoss_Coeff_Ohm = record.PhvLoss_Mean_W / record.IbattSq_Mean_A2;
record.Id_Mean_A = windowMean(idFb, windowStart, windowStop);
record.Iq_Mean_A = windowMean(iqFb, windowStart, windowStop);
record.Modulation_Mean = windowKpiMean(kpi, 7, windowStart, windowStop);
record.PbattHeatProxy_Mean_W = windowKpiMean(kpi, 9, windowStart, windowStop);
record.Pcu_Mean_W = windowKpiMean(kpi, 10, windowStart, windowStop);
record.Piron_Mean_W = windowKpiMean(kpi, 11, windowStart, windowStop);
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
assert(record.GateOverlap_Count == 0, 'Gate overlap detected.');
assert(record.GateComplementMismatch_Count == 0, 'Gate complement mismatch detected.');
assert(record.ClosedLoop_Final == 1, 'Closed-loop mode was not active at the end of the run.');
assert(record.DCLinkStorage_AllNaN == 1, 'DC-link storage field changed from its declared UNKNOWN state.');
assert(record.EnergyLedgerValid_Final == 0, 'Full energy ledger unexpectedly reports valid.');
end

function verifyPreflight(results)
base = results(results.Scenario_ID == "S00_Base", :);
high = results(results.Scenario_ID == "S02_HVPathR_High", :);
assert(abs(base.HVLoss_Coeff_Ohm - 0.02) < 1e-6, 'Baseline HV loss override was not applied.');
assert(abs(high.HVLoss_Coeff_Ohm - 0.04) < 1e-6, 'High HV resistance override was not applied.');
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

function value = windowSquaredMean(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data.^2) / (stopTime - startTime);
end

function value = windowRms(signal, startTime, stopTime)
value = sqrt(windowSquaredMean(signal, startTime, stopTime));
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
    'Parameter_Family', "", ...
    'HVPath_R_Ohm', NaN, ...
    'DCLink_C_F', NaN, ...
    'Rs_Ohm', NaN, ...
    'R_pack_proxy_Ohm', NaN, ...
    'IGBT_Ron_ref_Ohm', NaN, ...
    'IGBT_Vf_ref_V', NaN, ...
    'Window_Start_s', NaN, ...
    'Window_Stop_s', NaN, ...
    'Window_Duration_s', NaN, ...
    'Vdc_Min_V', NaN, ...
    'Vdc_Max_V', NaN, ...
    'Vdc_Ripple_V', NaN, ...
    'Ibatt_RMS_A', NaN, ...
    'Idc_RMS_A', NaN, ...
    'Pbatt_Mean_W', NaN, ...
    'PdcInput_Mean_W', NaN, ...
    'PhvLoss_Mean_W', NaN, ...
    'IbattSq_Mean_A2', NaN, ...
    'HVLoss_Coeff_Ohm', NaN, ...
    'Id_Mean_A', NaN, ...
    'Iq_Mean_A', NaN, ...
    'Modulation_Mean', NaN, ...
    'PbattHeatProxy_Mean_W', NaN, ...
    'Pcu_Mean_W', NaN, ...
    'Piron_Mean_W', NaN, ...
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
