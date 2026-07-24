function results = runM503FreqThermalLedger(runMode)
% Run the M5-03 frequency-domain thermal and fixed-window ledger checks.
%
% The model remains the only source of the physical signals. This runner
% injects scenario values with SimulationInput, collects scalar audit data,
% and performs independent window checks without changing model defaults.
%
%   runM503FreqThermalLedger("all")
%   runM503FreqThermalLedger("preflight")
%   runM503FreqThermalLedger("diagnose:3.1-B")

if nargin < 1
    runMode = "all";
end
runMode = string(runMode);

modelName = 'pulse_heating_v2_platform_v01';
assert(bdIsLoaded(modelName), ...
    'Load the v2 model before running the M5-03 ledger checks.');

scriptDir = fileparts(mfilename('fullpath'));
platformRoot = fileparts(scriptDir);
resultsDir = fullfile(platformRoot, '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end
csvPath = fullfile(resultsDir, 'M5-03_freq_thermal_ledger_v01.csv');

paths = resolveBlockPaths(modelName);
scenarios = createScenarios();
scenarioIndices = selectScenarios(scenarios, runMode);
selected = scenarios(scenarioIndices, :);

records = repmat(emptyRecord(), height(selected), 1);
tStart = tic;
for k = 1:height(selected)
    scenario = selected(k, :);
    in = Simulink.SimulationInput(modelName);
    in = in.setModelParameter('StopTime', scalarText(scenario.StopTime_s));
    in = in.setBlockParameter(paths.Bn, 'Value', scalarText(scenario.bn));
    in = in.setBlockParameter(paths.IdRef, 'Value', scalarText(scenario.Id_ref_A));
    out = sim(in);
    records(k) = collectRecord(out, scenario);
    fprintf('[%d/%d] %s complete\n', k, height(selected), scenario.Scenario_ID);
end

results = struct2table(records);
verifyResults(results);
if runMode == "all"
    writetable(results, csvPath);
    fprintf('M5-03 results written to %s\n', csvPath);
end
fprintf('M5-03 scan complete: %d scenarios in %.1f s.\n', ...
    height(selected), toc(tStart));
end

function paths = resolveBlockPaths(modelName)
paths.Bn = Simulink.ID.getFullName([modelName ':905']);
paths.IdRef = Simulink.ID.getFullName([modelName ':904']);
end

function scenarios = createScenarios()
% StopTime is Window_Stop + RMS_Window_s (0.04 + 0.01 = 0.05 s) because the
% MATLAB Function blocks latch the completed-window result one window later.
% The evaluation window itself remains [0.03, 0.04] s.
scenarios = table( ...
    ["3.1-A"; "3.1-B"; "3.1-C"; "3.1-D"], ...
    [0.0; 0.3; 0.5; 0.3], ...
    [0.0; 10.0; 10.0; 20.0], ...
    repmat(0.05, 4, 1), ...
    repmat(0.03, 4, 1), ...
    repmat(0.04, 4, 1), ...
    'VariableNames', {'Scenario_ID', 'bn', 'Id_ref_A', 'StopTime_s', ...
    'Window_Start_s', 'Window_Stop_s'});
end

function indices = selectScenarios(scenarios, runMode)
if runMode == "all" || runMode == "preflight"
    indices = (1:height(scenarios))';
    return;
end
prefix = "diagnose:";
assert(startsWith(runMode, prefix), 'Unsupported run mode: %s', runMode);
scenarioId = extractAfter(runMode, prefix);
indices = find(scenarios.Scenario_ID == scenarioId);
assert(isscalar(indices), 'Unknown or non-unique scenario: %s', scenarioId);
end

function record = collectRecord(out, scenario)
record = emptyRecord();
record.Scenario_ID = scenario.Scenario_ID;
record.bn = scenario.bn;
record.Id_ref_A = scenario.Id_ref_A;
record.StopTime_s = scenario.StopTime_s;
record.SimulationStop_s = out.tout(end);
record.Window_Start_s = scenario.Window_Start_s;
record.Window_Stop_s = scenario.Window_Stop_s;
record.Logsout_Count = out.logsout.numElements;

[tGate, gates] = readSignal(out, 'PWM_Gates');
record.GateOverlap_Count = gateOverlapCount(tGate, gates);
record.GateComplementMismatch_Count = gateMismatchCount(tGate, gates);
record.GateBothOff_Count = gateBothOffCount(tGate, gates);

[~, speed] = readSignal(out, 'MechSpeed_rad_s');
record.MaxAbsSpeed_rad_s = max(abs(speed));
record.ClosedLoop_Final = lastScalar(out, 'EnClosedLoop_Active');
[~, wcFlag] = readSignal(out, 'RMS_Window_Complete');
record.RMS_WindowComplete_Final = lastScalar(out, 'RMS_Window_Complete');
record.RMS_WindowComplete_Any = double(max(wcFlag) > 0.5);
record.WaveformEquivValid_Final = lastScalar(out, 'waveform_equiv_valid_V4J');
[tValid, valid] = readSignal(out, 'waveform_equiv_valid_V4J');
record.WaveformEquivValid_Count = sum(valid > 0.5 & tValid <= scenario.StopTime_s + 1e-12);

[tCurrent, iBatt] = readSignal(out, 'I_batt');
[tRms, iRms] = readSignal(out, 'I_batt_rms_window');
iRmsInterp = interp1(tRms, iRms, tCurrent, 'previous', 'extrap');
[~, kpi] = readSignal(out, 'SystemKPI');

[rZ, rZdc, fEval] = resolveEcm();
pFreqRaw = iRmsInterp.^2 * mean(rZ);
pTdRaw = iBatt.^2 * rZdc;
pM4Raw = kpi(:, 9);
windowMask = tCurrent >= scenario.Window_Start_s - 1e-12 & ...
    tCurrent <= scenario.Window_Stop_s + 1e-12;
assert(any(windowMask), 'No samples found in the M5-03 evaluation window.');
assert(all(isfinite(pFreqRaw(windowMask))), 'P_freq contains invalid window samples.');
assert(all(isfinite(pTdRaw(windowMask))), 'P_td contains invalid window samples.');
assert(all(isfinite(pM4Raw(windowMask))), 'P_M4 contains invalid window samples.');

record.P_freq_Model_W = lastScalar(out, 'P_batt_heat_freq_V4J');
record.P_freq_Recalc_W = mean(pFreqRaw(windowMask));
record.P_freq_AbsError_W = abs(record.P_freq_Model_W - record.P_freq_Recalc_W);
record.P_td_Model_W = lastScalar(out, 'P_batt_heat_td_V4J');
record.P_td_Recalc_W = mean(pTdRaw(windowMask));
record.P_td_AbsError_W = abs(record.P_td_Model_W - record.P_td_Recalc_W);
record.P_M4_Model_W = lastScalar(out, 'P_batt_heat_M4_window_V4J');
record.P_M4_Recalc_W = mean(pM4Raw(windowMask));
record.P_M4_AbsError_W = abs(record.P_M4_Model_W - record.P_M4_Recalc_W);
record.FreqTimeResidual_Model_W = lastScalar(out, 'freq_time_residual_V4J');
record.FreqTimeResidual_Recalc_W = lastScalar(out, 'P_batt_heat_harmonic_V4J') - ...
    lastScalar(out, 'P_batt_heat_td_V4J');

% Recompute the completed DFT directly from the 5000 samples in the window.
% The model output is a fixed-window latch; its value is compared separately
% from the physical frequency/time-domain residual.
[~, iWindow] = windowVector(tCurrent, iBatt, ...
    scenario.Window_Start_s, scenario.Window_Stop_s);
record.P_harmonic_Model_W = lastScalar(out, 'P_batt_heat_harmonic_V4J');
record.P_harmonic_DFT_Recalc_W = directDftHeat(iWindow, rZ, rZdc, fEval);
record.P_harmonic_DFT_Diff_W = abs(record.P_harmonic_Model_W - ...
    record.P_harmonic_DFT_Recalc_W);

record.FreqTimeResidual_AbsError_W = abs(record.FreqTimeResidual_Model_W - ...
    record.FreqTimeResidual_Recalc_W);
record.FixedWindow_AllFinite = double(all(isfinite([ ...
    record.P_freq_Model_W, record.P_harmonic_Model_W, ...
    record.P_td_Model_W, record.P_M4_Model_W, ...
    record.FreqTimeResidual_Model_W])));
end

function record = emptyRecord()
record = struct( ...
    'Scenario_ID', string(missing), ...
    'bn', NaN, 'Id_ref_A', NaN, 'StopTime_s', NaN, ...
    'SimulationStop_s', NaN, ...
    'Window_Start_s', NaN, 'Window_Stop_s', NaN, 'Logsout_Count', NaN, ...
    'ClosedLoop_Final', NaN, 'MaxAbsSpeed_rad_s', NaN, ...
    'GateOverlap_Count', NaN, 'GateComplementMismatch_Count', NaN, ...
    'GateBothOff_Count', NaN, ...
    'RMS_WindowComplete_Final', NaN, 'RMS_WindowComplete_Any', NaN, ...
    'WaveformEquivValid_Final', NaN, ...
    'WaveformEquivValid_Count', NaN, ...
    'P_freq_Model_W', NaN, 'P_freq_Recalc_W', NaN, 'P_freq_AbsError_W', NaN, ...
    'P_harmonic_Model_W', NaN, 'P_harmonic_DFT_Recalc_W', NaN, ...
    'P_harmonic_DFT_Diff_W', NaN, ...
    'P_td_Model_W', NaN, 'P_td_Recalc_W', NaN, 'P_td_AbsError_W', NaN, ...
    'P_M4_Model_W', NaN, 'P_M4_Recalc_W', NaN, 'P_M4_AbsError_W', NaN, ...
    'FreqTimeResidual_Model_W', NaN, 'FreqTimeResidual_Recalc_W', NaN, ...
    'FreqTimeResidual_AbsError_W', NaN, 'FixedWindow_AllFinite', NaN);
end

function [rZ, rZdc, fEval] = resolveEcm()
R0 = evalin('base', 'ECM_R0');
R1 = evalin('base', 'ECM_R1');
C1 = evalin('base', 'ECM_C1');
R2 = evalin('base', 'ECM_R2');
C2 = evalin('base', 'ECM_C2');
fEval = evalin('base', 'f_eval');
w = 2 * pi * fEval;
rZ = R0 + R1 ./ (1 + w.^2 * R1^2 * C1^2) + ...
    R2 ./ (1 + w.^2 * R2^2 * C2^2);
rZdc = R0 + R1 + R2;
end

function [t, data] = readSignal(out, name)
values = out.logsout.getElement(name).Values;
t = double(values.Time(:));
raw = double(values.Data);
nSamples = numel(t);
if numel(raw) == nSamples
    data = reshape(raw, nSamples, 1);
elseif size(raw, ndims(raw)) == nSamples
    data = reshape(raw, [], nSamples).';
elseif size(raw, 1) == nSamples
    data = reshape(raw, nSamples, []);
elseif size(raw, 2) == nSamples
    data = reshape(raw, [], nSamples).';
else
    error('Signal %s has incompatible time/data sizes.', name);
end
assert(size(data, 1) == nSamples, 'Signal %s has incompatible time/data sizes.', name);
end

function value = lastScalar(out, name)
[~, data] = readSignal(out, name);
value = data(end, 1);
end

function count = gateOverlapCount(t, gates)
g = gates > 0.5;
assert(size(g, 2) >= 6, 'PWM_Gates does not expose six gate channels.');
count = sum(any(g(:, [1, 3, 5]) & g(:, [2, 4, 6]), 2));
assert(numel(t) == size(g, 1));
end

function count = gateMismatchCount(t, gates)
g = gates > 0.5;
pairMismatch = (g(:, 1) == g(:, 2)) | (g(:, 3) == g(:, 4)) | (g(:, 5) == g(:, 6));
count = sum(pairMismatch);
assert(numel(t) == size(g, 1));
end

function count = gateBothOffCount(t, gates)
g = gates > 0.5;
pairBothOff = (~g(:, 1) & ~g(:, 2)) | (~g(:, 3) & ~g(:, 4)) | ...
    (~g(:, 5) & ~g(:, 6));
count = sum(pairBothOff);
assert(numel(t) == size(g, 1));
end

function [tWindow, dataWindow] = windowVector(t, data, tStart, tStop)
mask = t >= tStart - 1e-12 & t < tStop - 1e-12;
tWindow = t(mask);
dataWindow = data(mask, :);
assert(size(dataWindow, 1) == 5000, ...
    'Expected 5000 fixed-window DFT samples, got %d.', size(dataWindow, 1));
end

function heat = directDftHeat(current, rZ, rZdc, fEval)
Ts = 2e-6;
N = numel(current);
n = (0:N-1)';
heat = mean(current)^2 * rZdc;
for k = 1:numel(fEval)
    phase = 2 * pi * fEval(k) * n * Ts;
    cosineSum = sum(current .* cos(phase));
    sineSum = sum(current .* sin(phase));
    amplitude = (2 / N) * sqrt(cosineSum^2 + sineSum^2);
    heat = heat + 0.5 * amplitude^2 * rZ(k);
end
end

function text = scalarText(value)
text = sprintf('%.17g', value);
end

function verifyResults(results)
assert(all(results.SimulationStop_s >= results.StopTime_s - 1e-9 | ...
    isnan(results.SimulationStop_s)), 'A scenario did not reach StopTime.');
assert(all(results.Logsout_Count == 36), 'M5-03 logsout count is not 36.');
assert(all(results.GateOverlap_Count == 0), 'Gate overlap detected.');
assert(all(results.GateComplementMismatch_Count == results.GateBothOff_Count), ...
    'Non-complementary gate samples are not explained by dead-time states.');
assert(all(results.GateComplementMismatch_Count(results.bn == 0) == 0), ...
    'bn=0 did not retain strict gate complementarity.');
assert(all(results.GateComplementMismatch_Count(results.bn > 0) > 0), ...
    'bn>0 did not produce an auditable dead-time state.');
assert(all(results.ClosedLoop_Final == 1), 'Closed-loop mode was not active.');
assert(all(results.MaxAbsSpeed_rad_s < 1e-9), 'Zero-speed boundary was violated.');
assert(all(results.RMS_WindowComplete_Any == 1), ...
    'The fixed RMS window never completed during the run.');
assert(all(results.WaveformEquivValid_Final == 1), ...
    'The fixed DFT/thermal comparison window did not complete.');
assert(all(results.WaveformEquivValid_Count >= 5), ...
    'Expected at least five completed 10 ms windows in each 50 ms run.');
assert(all(results.FixedWindow_AllFinite == 1), ...
    'A completed M5-03 window contains an invalid thermal field.');
assert(all(results.P_harmonic_DFT_Diff_W < 1e-2), ...
    'The logged fixed-window DFT result diverges from the independent DFT.');
end
