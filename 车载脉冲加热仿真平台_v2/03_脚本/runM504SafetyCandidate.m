function results = runM504SafetyCandidate(runMode)
% Run the M5-04 safety candidate and rejection logic checks.
%
% The model remains the only source of the physical signals. This runner
% injects scenario values with SimulationInput, collects scalar audit data,
% and performs independent safety-candidate checks without changing model defaults.
%
%   runM504SafetyCandidate("all")
%   runM504SafetyCandidate("preflight")
%   runM504SafetyCandidate("diagnose:4.1-A")

if nargin < 1
    runMode = "all";
end
runMode = string(runMode);

modelName = 'pulse_heating_v2_platform_v01';
assert(bdIsLoaded(modelName), ...
    'Load the v2 model before running the M5-04 safety candidate checks.');

scriptDir = fileparts(mfilename('fullpath'));
platformRoot = fileparts(scriptDir);
resultsDir = fullfile(platformRoot, '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end
csvPath = fullfile(resultsDir, 'M5-04_safety_candidate_ledger_v01.csv');

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

    % Scenario-specific variable overrides for qualification injection tests
    if scenario.Ue_override ~= -1
        in = in.setVariable('Ue_neg_default', scenario.Ue_override);
    end
    if scenario.UOCV_override ~= -1
        in = in.setVariable('UOCV_default', scenario.UOCV_override);
    end
    if scenario.chem_override ~= -1
        in = in.setVariable('chemistry_matched', scenario.chem_override);
    end
    if scenario.wf_override ~= -1
        in = in.setVariable('waveform_applicable', scenario.wf_override);
    end

    out = sim(in);
    records(k) = collectRecord(out, scenario);
    fprintf('[%d/%d] %s complete\n', k, height(selected), scenario.Scenario_ID);
end

results = struct2table(records);
% Ensure all numeric columns are plain double arrays (not cell).
numCols = {'U_neg_est_V','I_limit_li_plating_A','U_terminal_peak_V', ...
    'U_terminal_valley_V','I_limit_voltage_A','f_boundary_Hz', ...
    'ProtectionStatus','ProtectionReason','DeviceProtection_Evaluable', ...
    'U_neg_est_Recalc_V','I_limit_li_Recalc_A','U_neg_AbsError_V'};
for c = 1:numel(numCols)
    if iscell(results.(numCols{c}))
        results.(numCols{c}) = cell2mat(results.(numCols{c}));
    end
end
verifyResults(results);
if runMode == "all"
    writetable(results, csvPath);
    fprintf('M5-04 results written to %s\n', csvPath);
end
fprintf('M5-04 scan complete: %d scenarios in %.1f s.\n', ...
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
%
% Override columns: -1 means "use default (do not override)".
% Ue_override: NaN to inject NaN, or a numeric value.
% UOCV_override: NaN or numeric.
% chem_override: 0 or 1.
% wf_override: 0 or 1.
%
% Scenarios:
% 4.1-A: bn=0 baseline -> all safety candidates NaN, UNKNOWN
% 4.1-B: bn=0.3 Id=10 -> U_neg_est finite (CANDIDATE), DeviceProtection=0
% 4.1-C: bn=0.5 Id=10 -> strong commutation, I_limit candidate readable
% 4.1-D: bn=0.3 Id=20 -> high current, limit trigger
% 4.1-E: qualification injection -> chemistry=1, waveform=1, Ue/UOCV valid
%         -> verify CANDIDATE->EVALUABLE gate logic (test only)
% 4.1-F: rejection test -> inject invalid params, verify NaN propagation
scenarios = table( ...
    ["4.1-A"; "4.1-B"; "4.1-C"; "4.1-D"; "4.1-E"; "4.1-F"], ...
    [0.0; 0.3; 0.5; 0.3; 0.3; 0.3], ...
    [0.0; 10.0; 10.0; 20.0; 10.0; 10.0], ...
    repmat(0.05, 6, 1), ...
    repmat(0.03, 6, 1), ...
    repmat(0.04, 6, 1), ...
    [NaN; NaN; NaN; NaN; 0.05; NaN], ...
    [NaN; NaN; NaN; NaN; 3.7; NaN], ...
    [-1; -1; -1; -1; 1; -1], ...
    [-1; -1; -1; -1; 1; -1], ...
    'VariableNames', {'Scenario_ID', 'bn', 'Id_ref_A', 'StopTime_s', ...
    'Window_Start_s', 'Window_Stop_s', ...
    'Ue_override', 'UOCV_override', 'chem_override', 'wf_override'});
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

% Gate and structural checks
[tGate, gates] = readSignal(out, 'PWM_Gates');
record.GateOverlap_Count = gateOverlapCount(tGate, gates);
record.GateComplementMismatch_Count = gateMismatchCount(tGate, gates);
record.GateBothOff_Count = gateBothOffCount(tGate, gates);

[~, speed] = readSignal(out, 'MechSpeed_rad_s');
record.MaxAbsSpeed_rad_s = max(abs(speed));
record.ClosedLoop_Final = lastScalar(out, 'EnClosedLoop_Active');

[~, wcFlag] = readSignal(out, 'RMS_Window_Complete');
record.RMS_WindowComplete_Any = double(max(wcFlag) > 0.5);

% Safety candidate outputs (last sample = window-completed latch)
record.U_neg_est_V = lastScalarOrNaN(out, 'U_neg_est_V4K');
record.I_limit_li_plating_A = lastScalarOrNaN(out, 'I_limit_li_plating_V4K');
record.U_terminal_peak_V = lastScalarOrNaN(out, 'U_terminal_peak_V4K');
record.U_terminal_valley_V = lastScalarOrNaN(out, 'U_terminal_valley_V4K');
record.I_limit_voltage_A = lastScalarOrNaN(out, 'I_limit_voltage_V4K');
record.f_boundary_Hz = lastScalarOrNaN(out, 'f_boundary_V4K');
record.ProtectionStatus = lastScalarOrNaN(out, 'ProtectionStatus_V4K');
record.ProtectionReason = lastScalarOrNaN(out, 'ProtectionReason_V4K');
record.DeviceProtection_Evaluable = lastScalarOrNaN(out, 'DeviceProtection_Evaluable_V4K');

% Independent recompute of U_neg_est for audit
[~, iRms] = readSignal(out, 'I_batt_rms_window');
iRmsLast = iRms(end);
Re_Z_dc = evalin('base','ECM_R0') + evalin('base','ECM_R1') + evalin('base','ECM_R2');
D3 = evalin('base','D3_ratio');
Ue = getScenarioUe(scenario);
if isnan(Ue) || ~isfinite(Ue)
    record.U_neg_est_Recalc_V = NaN;
    record.I_limit_li_Recalc_A = NaN;
else
    Re_Z_neg_dc = Re_Z_dc * D3;
    record.U_neg_est_Recalc_V = abs(iRmsLast) * Re_Z_neg_dc;
    if Re_Z_neg_dc > 0
        record.I_limit_li_Recalc_A = Ue / Re_Z_neg_dc;
    else
        record.I_limit_li_Recalc_A = Inf;
    end
end
record.U_neg_AbsError_V = abs(record.U_neg_est_V - record.U_neg_est_Recalc_V);
end

function Ue = getScenarioUe(scenario)
if scenario.Ue_override ~= -1
    Ue = scenario.Ue_override;
else
    Ue = evalin('base','Ue_neg_default');
end
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
    'RMS_WindowComplete_Any', NaN, ...
    'U_neg_est_V', NaN, 'I_limit_li_plating_A', NaN, ...
    'U_terminal_peak_V', NaN, 'U_terminal_valley_V', NaN, ...
    'I_limit_voltage_A', NaN, 'f_boundary_Hz', NaN, ...
    'ProtectionStatus', NaN, 'ProtectionReason', NaN, ...
    'DeviceProtection_Evaluable', NaN, ...
    'U_neg_est_Recalc_V', NaN, 'I_limit_li_Recalc_A', NaN, ...
    'U_neg_AbsError_V', NaN);
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

function value = lastScalarOrNaN(out, name)
try
    value = lastScalar(out, name);
    if ~isfinite(value)
        value = NaN;
    end
catch
    value = NaN;
end
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

function text = scalarText(value)
if isnan(value)
    text = 'NaN';
else
    text = sprintf('%.17g', value);
end
end

function verifyResults(results)
assert(all(results.SimulationStop_s >= results.StopTime_s - 1e-9 | ...
    isnan(results.SimulationStop_s)), 'A scenario did not reach StopTime.');
assert(all(results.Logsout_Count == 45), 'M5-04 logsout count is not 45.');
assert(all(results.GateOverlap_Count == 0), 'Gate overlap detected.');
assert(all(results.GateComplementMismatch_Count(results.bn == 0) == 0), ...
    'bn=0 did not retain strict gate complementarity.');
assert(all(results.GateComplementMismatch_Count(results.bn > 0) > 0), ...
    'bn>0 did not produce an auditable dead-time state.');
assert(all(results.ClosedLoop_Final == 1), 'Closed-loop mode was not active.');
assert(all(results.MaxAbsSpeed_rad_s < 1e-9), 'Zero-speed boundary was violated.');
assert(all(results.RMS_WindowComplete_Any == 1), ...
    'The fixed RMS window never completed during the run.');

% Extract columns as plain arrays for robust scalar indexing.
protStatus = table2array(results(:, {'ProtectionStatus'}));
protEval = table2array(results(:, {'DeviceProtection_Evaluable'}));
uNegEst = table2array(results(:, {'U_neg_est_V'}));
fBound = table2array(results(:, {'f_boundary_Hz'}));
scenId = results.Scenario_ID;

% 4.1-A through 4.1-D and 4.1-F: DeviceProtection_Evaluable must be 0
nonEval = scenId ~= "4.1-E";
if any(nonEval)
    assert(all(protEval(nonEval) == 0), ...
        'DeviceProtection_Evaluable was not 0 in a non-EVALUABLE scenario.');
end

% 4.1-A (bn=0, Id=0, Ue=NaN): should be UNKNOWN (ProtectionStatus=0)
idxA = find(scenId == "4.1-A", 1);
if ~isempty(idxA)
    assert(protStatus(idxA) == 0, ...
        '4.1-A did not produce UNKNOWN protection status.');
    assert(isnan(uNegEst(idxA)), ...
        '4.1-A did not propagate NaN for U_neg_est.');
end

% 4.1-B through 4.1-D (bn>0, Ue=NaN): should be UNKNOWN (U_neg NaN -> reason=1)
for s = ["4.1-B", "4.1-C", "4.1-D"]
    idx = find(scenId == s, 1);
    if ~isempty(idx)
        assert(isnan(uNegEst(idx)), ...
            '%s did not propagate NaN for U_neg_est with Ue=NaN.', s);
        assert(protStatus(idx) == 0, ...
            '%s did not produce UNKNOWN status with U_neg=NaN.', s);
    end
end

% 4.1-E (qualification injection): should reach EVALUABLE (status=2, eval=1)
idxE = find(scenId == "4.1-E", 1);
if ~isempty(idxE)
    assert(protStatus(idxE) == 2, ...
        '4.1-E did not reach EVALUABLE protection status.');
    assert(protEval(idxE) == 1, ...
        '4.1-E did not set DeviceProtection_Evaluable=1.');
    assert(isfinite(uNegEst(idxE)), ...
        '4.1-E did not produce finite U_neg_est.');
    assert(isfinite(fBound(idxE)), ...
        '4.1-E did not produce finite f_boundary.');
end

% 4.1-F (rejection test with NaN Ue): must stay UNKNOWN
idxF = find(scenId == "4.1-F", 1);
if ~isempty(idxF)
    assert(protStatus(idxF) == 0, ...
        '4.1-F did not maintain UNKNOWN status.');
    assert(protEval(idxF) == 0, ...
        '4.1-F did not maintain DeviceProtection_Evaluable=0.');
    assert(isnan(uNegEst(idxF)), ...
        '4.1-F did not propagate NaN for U_neg_est.');
end
end
