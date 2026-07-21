function results = runM403BControlComparison(runMode, numWorkers)
% Run the M4-03B Reference / Platform complete-ledger control comparison.
%
% After M4-01C (complete thermal/energy ledger) and M4-02B (parameter
% sensitivity under the same ledger), this runner compares control strategies
% at the same port direction, heat-source definitions, and protection/de-rating
% aperture. The scenario scan runs on a parallel pool when more than one
% scenario is selected and the Parallel Computing Toolbox is available.
%
%   runM403BControlComparison("all")        % default 2 workers
%   runM403BControlComparison("all", 4)     % up to 4 workers (cap)
%   runM403BControlComparison("all", 1)     % force serial (no pool)
%
% The physical baseline parameters are fixed at M4-02B nominal values.
% Only control strategy parameters (frequency, amplitude, duty cycle,
% limiting configuration) are varied across scenarios.
%
% This file is the M4-03B runner. The M4-03A runner (runM403ControlComparison.m)
% and its CSV output are frozen historical evidence and must not be re-run
% or overwritten. M4-03B asserts EnergyLedgerValid=1, ElectricalLedgerValid=1,
% and all independent recomputation AbsError < 1e-10.

if nargin < 1
    runMode = "all";
end
if nargin < 2
    numWorkers = [];
end

runMode = string(runMode);
modelName = 'pulse_heating_official_spine_v04';
assert(bdIsLoaded(modelName), ...
    'Load the active V4 model before running the M4-03B control comparison.');

scriptDir = fileparts(mfilename('fullpath'));
modelRoot = fileparts(scriptDir);
resultsDir = fullfile(modelRoot, '04_仿真结果');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

csvPath = fullfile(resultsDir, 'M4-03B_control_comparison_v01.csv');
paths = resolveBlockPaths(modelName);
scenarios = createScenarios();

[scenarioIndices, enforceLedgerAssertions] = selectScenarios(scenarios, runMode);
selectedScenarios = scenarios(scenarioIndices, :);
nScen = height(selectedScenarios);

nWorkers = resolveWorkerCount(numWorkers, nScen);
usePar = (nScen > 1) && (nWorkers > 1) && license('test', 'Distrib_Computing_Toolbox');

records = repmat(emptyRecord(), nScen, 1);
tStart = tic;

if usePar
    pool = ensurePool(nWorkers);
    modelDir = fullfile(modelRoot, '02_模型');
    addpath(modelDir);
    fprintf('M4-03B parallel: %d scenarios on %d workers (parsim).\n', nScen, pool.NumWorkers);
    simIn = cell(1, nScen);
    for k = 1:nScen
        in = Simulink.SimulationInput(modelName);
        simIn{k} = applyScenario(in, modelName, paths, selectedScenarios(k, :));
    end
    simOut = parsim([simIn{:}], 'ShowProgress', 'on', 'UseFastRestart', 'off');
    for k = 1:nScen
        simout = simOut(k);
        if ~isempty(simout.ErrorMessage)
            error('Scenario %s simulation failed: %s', ...
                char(selectedScenarios.Scenario_ID(k)), simout.ErrorMessage);
        end
        records(k) = collectRecord(simout, selectedScenarios(k, :), enforceLedgerAssertions);
    end
else
    fprintf('M4-03B serial: %d scenarios.\n', nScen);
    for k = 1:nScen
        scenario = selectedScenarios(k, :);
        in = Simulink.SimulationInput(modelName);
        in = applyScenario(in, modelName, paths, scenario);
        out = sim(in);
        records(k) = collectRecord(out, scenario, enforceLedgerAssertions);
        fprintf('[%d/%d] done %s\n', k, nScen, scenario.Scenario_ID);
    end
end

fprintf('M4-03B scan complete: %d scenarios in %.1f min.\n', nScen, toc(tStart) / 60);

results = struct2table(records);
if enforceLedgerAssertions
    verifyResults(results);
end
if runMode == "preflight"
    verifyPreflight(results);
elseif runMode == "all"
    writetable(results, csvPath);
    fprintf('Results written to %s\n', csvPath);
end
end

function n = resolveWorkerCount(numWorkers, nScen)
DEFAULT_POOL = 2;
MAX_POOL = 4;
if isempty(numWorkers)
    n = DEFAULT_POOL;
else
    n = round(numWorkers);
end
n = min(n, MAX_POOL);
n = max(1, n);
n = min(n, nScen);
end

function pool = ensurePool(nWorkers)
pool = gcp('nocreate');
if ~isempty(pool) && pool.NumWorkers ~= nWorkers
    fprintf('Existing pool has %d workers; closing to create a %d-worker pool.\n', ...
        pool.NumWorkers, nWorkers);
    delete(pool);
    pool = gcp('nocreate');
end
if isempty(pool)
    pool = parpool('local', nWorkers);
end
end

function [scenarioIndices, enforceLedgerAssertions] = selectScenarios(scenarios, runMode)
enforceLedgerAssertions = true;

switch runMode
    case "preflight"
        scenarioIndices = find(scenarios.Preflight);
    case "all"
        scenarioIndices = 1:height(scenarios);
    case "diagnose_b01"
        scenarioIndices = find(scenarios.Scenario_ID == "C00_Base");
        enforceLedgerAssertions = false;
    otherwise
        prefix = "diagnose:";
        if startsWith(runMode, prefix)
            scenarioId = extractAfter(runMode, prefix);
            scenarioIndices = find(scenarios.Scenario_ID == scenarioId);
            assert(isscalar(scenarioIndices), ...
                'Unknown or non-unique diagnostic scenario: %s', scenarioId);
            enforceLedgerAssertions = false;
        else
            error('Unsupported run mode: %s', runMode);
        end
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
paths.Ambient = Simulink.ID.getFullName([modelName ':514']);
paths.Coolant = Simulink.ID.getFullName([modelName ':515']);
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
% 11 control strategy scenarios, all using M4-02B nominal physical parameters.
% Dimensions: frequency (25/50/100 Hz), duty bias (25/50/75%), amplitude
% (20/40/60 A), limiting (Id limit, duty limit, mode), shutdown (status).

nominal = nominalValues();

scenarioId = ["C00_Base"; "C01_Freq_Low"; "C02_Freq_High"; ...
    "C03_Duty_Low"; "C04_Duty_High"; "C05_Amplitude_Low"; ...
    "C06_Amplitude_High"; "C07_LimitId_Low"; "C08_LimitDuty_Low"; ...
    "C09_LimitMode_Active"; "C10_LimitStatus_Off"];
strategyFamily = ["baseline"; "frequency"; "frequency"; "duty_bias"; ...
    "duty_bias"; "amplitude"; "amplitude"; "limiting"; "limiting"; ...
    "limiting"; "shutdown"];

N = numel(scenarioId);

% Pulse control parameters
idAmplitude = [40; 40; 40; 40; 40; 20; 60; 40; 40; 40; 40];
pulseFrequency = [50; 25; 100; 50; 50; 50; 50; 50; 50; 50; 50];
positiveDuty = [50; 50; 50; 25; 75; 50; 50; 50; 50; 50; 50];

% Limit/protection configuration
limitId = [40; 40; 40; 40; 40; 20; 60; 20; 40; 40; 40];
limitFrequency = [50; 25; 100; 50; 50; 50; 50; 50; 50; 50; 50];
limitDuty = [50; 50; 50; 25; 75; 50; 50; 50; 25; 50; 50];
limitPhase = zeros(N, 1);
limitMode = [4; 4; 4; 4; 4; 4; 4; 4; 4; 3; 4];
limitStatus = [6; 6; 6; 6; 6; 6; 6; 6; 6; 6; 0];

% Physical parameters: all fixed at M4-02B nominal
hvPathR = repmat(nominal.HVPath_R_Ohm, N, 1);
dcLinkC = repmat(nominal.DCLink_C_F, N, 1);
rs = repmat(nominal.Rs_Ohm, N, 1);
rBattHeat = repmat(nominal.R_batt_heat_Ohm, N, 1);
cBatt = repmat(nominal.C_batt_J_K, N, 1);
ron = repmat(nominal.IGBT_Ron_Ohm, N, 1);
vf = repmat(nominal.IGBT_Vf_V, N, 1);
eon = repmat(nominal.IGBT_Eon_J, N, 1);
eoff = repmat(nominal.IGBT_Eoff_J, N, 1);
tdead = repmat(nominal.PWM_tdead_s, N, 1);
cInv = repmat(nominal.C_inv_J_K, N, 1);
rthInv = repmat(nominal.Rth_inv_K_W, N, 1);
ambient = repmat(nominal.Ambient_K, N, 1);
coolant = repmat(nominal.Coolant_K, N, 1);

windowStop = repmat(0.08, N, 1);
auditPublishGuard = repmat(5 * 2e-6, N, 1);
stopTime = windowStop + auditPublishGuard;
windowDuration = repmat(0.04, N, 1);
windowStart = windowStop - windowDuration;

preflight = false(N, 1);
preflight([1, 3, 4]) = true;  % C00_Base, C02_Freq_High, C03_Duty_Low

scenarios = table(scenarioId, strategyFamily, idAmplitude, pulseFrequency, ...
    positiveDuty, limitId, limitFrequency, limitDuty, limitPhase, limitMode, ...
    limitStatus, hvPathR, dcLinkC, rs, rBattHeat, cBatt, ron, vf, eon, eoff, ...
    tdead, cInv, rthInv, ambient, coolant, stopTime, auditPublishGuard, ...
    windowStart, windowStop, windowDuration, preflight, ...
    'VariableNames', {'Scenario_ID', 'Strategy_Family', 'Id_Amplitude_A', ...
    'Pulse_Frequency_Hz', 'Positive_Duty_Percent', 'LimitId_A', ...
    'LimitFrequency_Hz', 'LimitDuty_Percent', 'LimitPhase_deg', ...
    'LimitMode', 'LimitStatus', 'HVPath_R_Ohm', 'DCLink_C_F', 'Rs_Ohm', ...
    'R_batt_heat_ref_Ohm', 'C_batt_J_K', 'IGBT_Ron_Ohm', 'IGBT_Vf_V', ...
    'IGBT_Eon_J', 'IGBT_Eoff_J', 'PWM_tdead_s', 'C_inv_J_K', ...
    'Rth_inv_K_W', 'Ambient_K', 'Coolant_K', 'StopTime_s', ...
    'Audit_Publish_Guard_s', 'Window_Start_s', 'Window_Stop_s', ...
    'Window_Duration_s', 'Preflight'});
end

function nominal = nominalValues()
% M4-02B nominal physical parameter baseline (frozen).
nominal = struct( ...
    'HVPath_R_Ohm', 0.01, ...
    'DCLink_C_F', 470e-6, ...
    'Rs_Ohm', 0.013, ...
    'R_batt_heat_Ohm', 0.4198, ...
    'C_batt_J_K', 26000, ...
    'IGBT_Ron_Ohm', 1e-3, ...
    'IGBT_Vf_V', 0.8, ...
    'IGBT_Eon_J', 22.86e-3, ...
    'IGBT_Eoff_J', 17.14e-3, ...
    'PWM_tdead_s', 1e-6, ...
    'C_inv_J_K', 3.06, ...
    'Rth_inv_K_W', 0.0966666666666667, ...
    'Ambient_K', 263.15, ...
    'Coolant_K', 263.15);
end

function in = applyScenario(in, modelName, paths, scenario)
% Physical parameters: fixed at M4-02B nominal values.
in = in.setModelParameter('StopTime', scalarText(scenario.StopTime_s));
in = in.setBlockParameter(paths.HVPosR, 'R', scalarText(scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.HVNegR, 'R', scalarText(scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.DCLinkC, 'C', scalarText(scenario.DCLink_C_F));
in = in.setBlockParameter(paths.PMSM, 'Rs', scalarText(scenario.Rs_Ohm));
in = in.setBlockParameter(paths.RMSWindow, 'Value', scalarText(scenario.Window_Duration_s));
in = in.setBlockParameter(paths.HVLossGain, 'Gain', scalarText(2 * scenario.HVPath_R_Ohm));
in = in.setBlockParameter(paths.DCLinkEnergyGain, 'Gain', ...
    scalarText(0.5 * scenario.DCLink_C_F));
in = in.setBlockParameter(paths.DCLinkEnergyInitial, 'Value', '0');
in = in.setBlockParameter(paths.RsAudit, 'Value', scalarText(scenario.Rs_Ohm));
in = in.setBlockParameter(paths.RPackAudit, 'Value', ...
    scalarText(scenario.R_batt_heat_ref_Ohm));
in = in.setBlockParameter(paths.IGBTRon, 'Value', scalarText(scenario.IGBT_Ron_Ohm));
in = in.setBlockParameter(paths.IGBTVf, 'Value', scalarText(scenario.IGBT_Vf_V));
in = in.setBlockParameter(paths.Ambient, 'Value', scalarText(scenario.Ambient_K));
in = in.setBlockParameter(paths.Coolant, 'Value', scalarText(scenario.Coolant_K));

% Pulse control parameters: vary per scenario.
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

% Limit/protection parameters: vary per scenario.
in = in.setBlockParameter(paths.LimitId, 'Value', scalarText(scenario.LimitId_A));
in = in.setBlockParameter(paths.LimitFrequency, 'Value', ...
    scalarText(scenario.LimitFrequency_Hz));
in = in.setBlockParameter(paths.LimitDuty, 'Value', ...
    scalarText(scenario.LimitDuty_Percent));
in = in.setBlockParameter(paths.LimitPhase, 'Value', scalarText(scenario.LimitPhase_deg));
in = in.setBlockParameter(paths.LimitMode, 'Value', scalarText(scenario.LimitMode));
in = in.setBlockParameter(paths.LimitStatus, 'Value', scalarText(scenario.LimitStatus));
in = in.setBlockParameter(paths.ClosedLoopEnable, 'Value', '1');

% Thermal ledger variables (M4-01C contract): fixed at M4-02B nominal.
in = in.setVariable('M401C_T_ambient_K', scenario.Ambient_K, Workspace=modelName);
in = in.setVariable('M401C_Rth_hv_K_W', 10, Workspace=modelName);
in = in.setVariable('M401C_Rth_inv_K_W', scenario.Rth_inv_K_W, Workspace=modelName);
in = in.setVariable('M401C_C_hv_J_K', 200, Workspace=modelName);
in = in.setVariable('M401C_C_inv_J_K', scenario.C_inv_J_K, Workspace=modelName);
in = in.setVariable('M401C_C_batt_J_K', scenario.C_batt_J_K, Workspace=modelName);
in = in.setVariable('M401C_C_pmsm_stator_J_K', 100, Workspace=modelName);
in = in.setVariable('M401C_C_pmsm_rotor_J_K', 200, Workspace=modelName);
in = in.setVariable('M401C_IGBT_Iref_A', 600, Workspace=modelName);
in = in.setVariable('M401C_PWM_fsw_Hz', 2000, Workspace=modelName);
in = in.setVariable('M401C_IGBT_Eon_ref_J', scenario.IGBT_Eon_J, Workspace=modelName);
in = in.setVariable('M401C_IGBT_Eoff_ref_J', scenario.IGBT_Eoff_J, Workspace=modelName);
in = in.setVariable('M401C_IGBT_Vscale_ref', 0.228137066666667, Workspace=modelName);
in = in.setVariable('M401C_PWM_tdead_s', scenario.PWM_tdead_s, Workspace=modelName);
end

function record = collectRecord(out, scenario, enforceAssertions)
vBatt = getSignal(out, 'V_batt');
iBatt = getSignal(out, 'I_batt');
vDc = getSignal(out, 'V_dc_bus');
iDc = getSignal(out, 'I_dc');
pHv = getSignal(out, 'P_hv_loss');
kpi = getSignal(out, 'SystemKPI');
gates = getSignal(out, 'PWM_Gates');
idRef = getSignal(out, 'Id_Ref');
idFb = getSignal(out, 'Id_fb');
iqFb = getSignal(out, 'Iq_fb');
speed = getSignal(out, 'MechSpeed_rad_s');
reactionTorque = getSignal(out, 'MechReactionTorque_Nm');
closedLoop = getSignal(out, 'EnClosedLoop_Active');
eDc = getSignal(out, 'E_dc_link');
ledgerValid = getSignal(out, 'full_ledger_valid');

kpiData = signalData(kpi);
assert(size(kpiData, 2) >= 45, ...
    'SystemKPI does not expose the M4-01C ledger fields.');

startTime = scenario.Window_Start_s;
stopTime = scenario.Window_Stop_s;
duration = scenario.Window_Duration_s;
record = emptyRecord();
record.Scenario_ID = scenario.Scenario_ID;
record.Strategy_Family = scenario.Strategy_Family;
record.Id_Amplitude_A = scenario.Id_Amplitude_A;
record.Pulse_Frequency_Hz = scenario.Pulse_Frequency_Hz;
record.Positive_Duty_Percent = scenario.Positive_Duty_Percent;
record.LimitId_A = scenario.LimitId_A;
record.LimitFrequency_Hz = scenario.LimitFrequency_Hz;
record.LimitDuty_Percent = scenario.LimitDuty_Percent;
record.LimitPhase_deg = scenario.LimitPhase_deg;
record.LimitMode = scenario.LimitMode;
record.LimitStatus = scenario.LimitStatus;
record.Expected_Id_Mean_A = scenario.Id_Amplitude_A * ...
    (2 * scenario.Positive_Duty_Percent / 100 - 1);
record.HVPath_R_Ohm = scenario.HVPath_R_Ohm;
record.DCLink_C_F = scenario.DCLink_C_F;
record.Rs_Ohm = scenario.Rs_Ohm;
record.R_batt_heat_ref_Ohm = scenario.R_batt_heat_ref_Ohm;
record.C_batt_J_K = scenario.C_batt_J_K;
record.IGBT_Ron_Ohm = scenario.IGBT_Ron_Ohm;
record.IGBT_Vf_V = scenario.IGBT_Vf_V;
record.IGBT_Eon_J = scenario.IGBT_Eon_J;
record.IGBT_Eoff_J = scenario.IGBT_Eoff_J;
record.PWM_tdead_s = scenario.PWM_tdead_s;
record.C_inv_J_K = scenario.C_inv_J_K;
record.Rth_inv_K_W = scenario.Rth_inv_K_W;
record.Ambient_K = scenario.Ambient_K;
record.Coolant_K = scenario.Coolant_K;
record.Audit_Publish_Guard_s = scenario.Audit_Publish_Guard_s;
record.Window_Start_s = startTime;
record.Window_Stop_s = stopTime;
record.Window_Duration_s = duration;
record.SimulationStop_s = out.tout(end);
record.ClosedLoop_Final = lastValue(closedLoop);
record.MaxAbsSpeed_rad_s = windowMaxAbs(speed, startTime, stopTime);
record.ReactionTorque_RMS_Nm = windowRms(reactionTorque, startTime, stopTime);
record.GateOverlap_Count = gateOverlapCount(gates, startTime, stopTime);
record.GateComplementMismatch_Count = gateMismatchCount(gates, startTime, stopTime);

% Control KPI (M4-03A compatible + M4-03B additions)
record.IdRef_Min_A = windowMin(idRef, startTime, stopTime);
record.IdRef_Max_A = windowMax(idRef, startTime, stopTime);
record.IdRef_Mean_A = windowMean(idRef, startTime, stopTime);
record.IdRef_RMS_A = windowRms(idRef, startTime, stopTime);
record.IdRef_PositiveFraction = positiveFraction(idRef, startTime, stopTime);
record.IdRef_Transition_Count = transitionCount(idRef, startTime, stopTime);
record.IdFb_Mean_A = windowMean(idFb, startTime, stopTime);
record.IdFb_RMS_A = windowRms(idFb, startTime, stopTime);
record.Id_Tracking_RMS_Error_A = windowDifferenceRms(idFb, idRef, startTime, stopTime);
record.IqFb_RMS_A = windowRms(iqFb, startTime, stopTime);
record.Vdc_Min_V = windowMin(vDc, startTime, stopTime);
record.Vdc_Max_V = windowMax(vDc, startTime, stopTime);
record.Vdc_Ripple_V = record.Vdc_Max_V - record.Vdc_Min_V;
record.Ibatt_RMS_A = windowRms(iBatt, startTime, stopTime);
record.Idc_RMS_A = windowRms(iDc, startTime, stopTime);
record.ModulationIndex_Mean = windowKpiMean(kpi, 7, startTime, stopTime);
record.ModulationIndex_Max = windowKpiMax(kpi, 7, startTime, stopTime);
record.VoltageMargin_Min_V = windowKpiMin(kpi, 8, startTime, stopTime);
record.ControlSaturation_Any = windowKpiAny(kpi, 17, startTime, stopTime);

% Thermal KPI
record.T_batt_End_K = lastKpiValue(kpi, 13);
record.T_stator_End_K = lastKpiValue(kpi, 14);
record.T_rotor_End_K = lastKpiValue(kpi, 15);
record.P_batt_heat_Mean_W = windowKpiMean(kpi, 9, startTime, stopTime);
record.P_cu_Mean_W = windowKpiMean(kpi, 10, startTime, stopTime);
record.P_iron_Mean_W = windowKpiMean(kpi, 11, startTime, stopTime);
record.P_inv_Mean_W = windowKpiMean(kpi, 12, startTime, stopTime);

% Model ledger values (M4-01C fields)
record.P_hv_loss_Model_W = lastKpiValue(kpi, 31);
record.P_batt_terminal_Model_W = lastKpiValue(kpi, 29);
record.P_dc_input_Model_W = lastKpiValue(kpi, 30);
record.P_dc_link_storage_Model_W = lastKpiValue(kpi, 32);
record.DeltaE_batt_Model_J = lastKpiValue(kpi, 35);
record.P_thermal_storage_Model_W = lastKpiValue(kpi, 39);
record.P_heat_rejection_Model_W = lastKpiValue(kpi, 40);
record.P_mech_Model_W = lastKpiValue(kpi, 38);
record.P_unmodeled_Model_W = lastKpiValue(kpi, 42);
record.Residual_dc_link_Model_W = lastKpiValue(kpi, 43);
record.EnergyLedgerValid_Final = lastValue(ledgerValid);
record.ElectricalLedgerValid_Final = lastKpiValue(kpi, 45);
record.KPI_Final_Time_s = kpi.Time(end);
record.RMS_Window_Elapsed_Model_s = lastKpiValue(kpi, 26);
record.RMS_Window_Complete_Model = lastKpiValue(kpi, 27);
record.RMS_Window_s_Model = lastKpiValue(kpi, 28);

% Independent recomputation
record.P_batt_terminal_Recalc_W = windowProductMean(vBatt, iBatt, startTime, stopTime);
record.P_dc_input_Recalc_W = windowProductMean(vDc, iDc, startTime, stopTime);
record.P_hv_loss_Recalc_W = windowMean(pHv, startTime, stopTime);
record.DeltaE_batt_Recalc_J = -windowIntegralSum(vBatt, iBatt, kpi, 9, ...
    startTime, stopTime);
record.P_dc_link_storage_Recalc_W = windowEnergyRate(eDc, startTime, stopTime);
record.P_heat_input_Recalc_W = record.P_batt_heat_Mean_W + ...
    record.P_hv_loss_Recalc_W + record.P_inv_Mean_W + record.P_cu_Mean_W + ...
    record.P_iron_Mean_W;
record.P_thermal_balance_Error_W = record.P_heat_input_Recalc_W - ...
    record.P_thermal_storage_Model_W - record.P_heat_rejection_Model_W;
record.P_unmodeled_Recalc_W = -record.DeltaE_batt_Model_J / duration - ...
    record.P_dc_link_storage_Model_W - record.P_thermal_storage_Model_W - ...
    record.P_heat_rejection_Model_W - record.P_mech_Model_W;
record.Residual_dc_link_Recalc_W = record.P_batt_terminal_Recalc_W - ...
    record.P_hv_loss_Recalc_W - record.P_dc_link_storage_Model_W - ...
    record.P_dc_input_Recalc_W;

% Absolute errors
record.P_batt_terminal_AbsError_W = abs(record.P_batt_terminal_Model_W - ...
    record.P_batt_terminal_Recalc_W);
record.P_dc_input_AbsError_W = abs(record.P_dc_input_Model_W - ...
    record.P_dc_input_Recalc_W);
record.P_hv_loss_AbsError_W = abs(record.P_hv_loss_Model_W - ...
    record.P_hv_loss_Recalc_W);
record.DeltaE_batt_AbsError_J = abs(record.DeltaE_batt_Model_J - ...
    record.DeltaE_batt_Recalc_J);
record.P_dc_link_storage_AbsError_W = abs(record.P_dc_link_storage_Model_W - ...
    record.P_dc_link_storage_Recalc_W);
record.P_unmodeled_AbsError_W = abs(record.P_unmodeled_Model_W - ...
    record.P_unmodeled_Recalc_W);
record.Residual_dc_link_AbsError_W = abs(record.Residual_dc_link_Model_W - ...
    record.Residual_dc_link_Recalc_W);

% Derived coefficients
record.HVLoss_Coeff_Ohm = record.P_hv_loss_Recalc_W / ...
    windowSquaredMean(iBatt, startTime, stopTime);
record.BattHeat_Coeff_Ohm = record.P_batt_heat_Mean_W / ...
    windowSquaredMean(iBatt, startTime, stopTime);
record.CuLoss_Coeff_Ohm = record.P_cu_Mean_W / ...
    (1.5 * windowSumSquaresMean(idFb, iqFb, startTime, stopTime));

% DC-link energy formula check
record.Edc_Formula_AbsError_J = abs(lastValue(eDc) - ...
    0.5 * scenario.DCLink_C_F * lastValue(vDc)^2);
record.DeviceProtection_Evaluable = 0;
record.DeviceProtection_Status = "NOT_EVALUABLE";

validateOperationalRecord(record, scenario);
if enforceAssertions
    validateLedgerRecord(record);
end
end

function validateOperationalRecord(record, scenario)
assert(abs(record.SimulationStop_s - scenario.StopTime_s) < 1e-9, ...
    'Scenario %s did not reach the requested stop time.', record.Scenario_ID);
assert(record.GateOverlap_Count == 0, ...
    'Scenario %s detected gate overlap.', record.Scenario_ID);
assert(record.GateComplementMismatch_Count == 0, ...
    'Scenario %s detected gate complement mismatch.', record.Scenario_ID);
assert(record.ClosedLoop_Final == 1, ...
    'Scenario %s did not retain closed-loop mode.', record.Scenario_ID);
assert(record.MaxAbsSpeed_rad_s < 1e-9, ...
    'Scenario %s violated the zero-speed boundary.', record.Scenario_ID);
assert(abs(record.IdRef_Min_A + record.Id_Amplitude_A) < 1e-6, ...
    'Scenario %s: negative Id reference was not applied.', record.Scenario_ID);
assert(abs(record.IdRef_Max_A - record.Id_Amplitude_A) < 1e-6, ...
    'Scenario %s: positive Id reference was not applied.', record.Scenario_ID);
assert(abs(record.IdRef_PositiveFraction - record.Positive_Duty_Percent / 100) < 0.03, ...
    'Scenario %s: pulse duty override was not applied.', record.Scenario_ID);
assert(record.IdRef_Transition_Count >= 1, ...
    'Scenario %s: pulse reference did not transition in the evaluation window.', ...
    record.Scenario_ID);
end

function validateLedgerRecord(record)
assert(record.EnergyLedgerValid_Final == 1, ...
    'Scenario %s did not retain a complete energy ledger.', record.Scenario_ID);
assert(record.ElectricalLedgerValid_Final == 1, ...
    'Scenario %s did not retain an electrical ledger.', record.Scenario_ID);
assert(record.P_batt_terminal_AbsError_W < 1e-10, ...
    'Scenario %s: battery terminal power independent recomputation failed.', ...
    record.Scenario_ID);
assert(record.P_dc_input_AbsError_W < 1e-10, ...
    'Scenario %s: DC input power independent recomputation failed.', ...
    record.Scenario_ID);
assert(record.P_hv_loss_AbsError_W < 1e-10, ...
    'Scenario %s: HV loss independent recomputation failed.', record.Scenario_ID);
assert(record.DeltaE_batt_AbsError_J < 1e-10, ...
    'Scenario %s: battery energy independent recomputation failed.', ...
    record.Scenario_ID);
assert(record.P_dc_link_storage_AbsError_W < 1e-10, ...
    'Scenario %s: DC-link storage independent recomputation failed.', ...
    record.Scenario_ID);
assert(abs(record.P_thermal_balance_Error_W) < 1e-10, ...
    'Scenario %s: thermal source/storage/rejection balance failed.', ...
    record.Scenario_ID);
assert(record.P_unmodeled_AbsError_W < 1e-10, ...
    'Scenario %s: system unmodeled-power independent recomputation failed.', ...
    record.Scenario_ID);
assert(record.Residual_dc_link_AbsError_W < 1e-10, ...
    'Scenario %s: DC boundary residual independent recomputation failed.', ...
    record.Scenario_ID);
end

function verifyResults(results)
assert(all(results.EnergyLedgerValid_Final == 1), ...
    'At least one scenario did not retain a complete energy ledger.');
assert(all(results.ElectricalLedgerValid_Final == 1), ...
    'At least one scenario did not retain an electrical ledger.');
assert(all(results.DeviceProtection_Evaluable == 0), ...
    'Device protection status must remain explicitly not evaluable.');
end

function verifyPreflight(results)
base = results(results.Scenario_ID == "C00_Base", :);
highFreq = results(results.Scenario_ID == "C02_Freq_High", :);
lowDuty = results(results.Scenario_ID == "C03_Duty_Low", :);

assert(highFreq.IdRef_Transition_Count > base.IdRef_Transition_Count, ...
    'High-frequency pulse override was not applied.');
assert(abs(lowDuty.IdRef_PositiveFraction - 0.25) < 0.03, ...
    'Low-duty pulse override was not applied.');
assert(abs(base.IdRef_RMS_A - 40) < 1e-6, ...
    'Baseline Id reference amplitude was not applied.');
assert(abs(highFreq.IdRef_RMS_A - 40) < 1e-6, ...
    'High-frequency Id reference amplitude was not applied.');
assert(base.HVLoss_Coeff_Ohm > 0, ...
    'M4-02B nominal physical injection was not applied.');
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

function value = windowMean(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data) / (stopTime - startTime);
end

function value = windowRms(signal, startTime, stopTime)
value = sqrt(windowSquaredMean(signal, startTime, stopTime));
end

function value = windowSquaredMean(signal, startTime, stopTime)
[time, data] = windowData(signal, startTime, stopTime);
value = trapz(time, data.^2) / (stopTime - startTime);
end

function value = windowDifferenceRms(firstSignal, secondSignal, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
time = unique([firstTime; secondTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
value = sqrt(trapz(time, (first - second).^2) / (stopTime - startTime));
end

function value = windowSumSquaresMean(firstSignal, secondSignal, startTime, stopTime)
[firstTime, firstData] = windowData(firstSignal, startTime, stopTime);
[secondTime, secondData] = windowData(secondSignal, startTime, stopTime);
time = unique([firstTime; secondTime]);
first = interp1(firstTime, firstData, time, 'linear', 'extrap');
second = interp1(secondTime, secondData, time, 'linear', 'extrap');
value = trapz(time, first.^2 + second.^2) / (stopTime - startTime);
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

function value = lastKpiValue(signal, column)
data = signalData(signal);
value = data(end, column);
end

function count = gateOverlapCount(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
gates = data > 0.5;
count = sum((gates(:, 1) & gates(:, 2)) | (gates(:, 3) & gates(:, 4)) | ...
    (gates(:, 5) & gates(:, 6)));
end

function count = gateMismatchCount(signal, startTime, stopTime)
[~, data] = windowData(signal, startTime, stopTime);
gates = data > 0.5;
count = sum((gates(:, 1) == gates(:, 2)) | (gates(:, 3) == gates(:, 4)) | ...
    (gates(:, 5) == gates(:, 6)));
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
    'LimitId_A', NaN, ...
    'LimitFrequency_Hz', NaN, ...
    'LimitDuty_Percent', NaN, ...
    'LimitPhase_deg', NaN, ...
    'LimitMode', NaN, ...
    'LimitStatus', NaN, ...
    'Expected_Id_Mean_A', NaN, ...
    'HVPath_R_Ohm', NaN, ...
    'DCLink_C_F', NaN, ...
    'Rs_Ohm', NaN, ...
    'R_batt_heat_ref_Ohm', NaN, ...
    'C_batt_J_K', NaN, ...
    'IGBT_Ron_Ohm', NaN, ...
    'IGBT_Vf_V', NaN, ...
    'IGBT_Eon_J', NaN, ...
    'IGBT_Eoff_J', NaN, ...
    'PWM_tdead_s', NaN, ...
    'C_inv_J_K', NaN, ...
    'Rth_inv_K_W', NaN, ...
    'Ambient_K', NaN, ...
    'Coolant_K', NaN, ...
    'Audit_Publish_Guard_s', NaN, ...
    'Window_Start_s', NaN, ...
    'Window_Stop_s', NaN, ...
    'Window_Duration_s', NaN, ...
    'SimulationStop_s', NaN, ...
    'ClosedLoop_Final', NaN, ...
    'MaxAbsSpeed_rad_s', NaN, ...
    'ReactionTorque_RMS_Nm', NaN, ...
    'GateOverlap_Count', NaN, ...
    'GateComplementMismatch_Count', NaN, ...
    'IdRef_Min_A', NaN, ...
    'IdRef_Max_A', NaN, ...
    'IdRef_Mean_A', NaN, ...
    'IdRef_RMS_A', NaN, ...
    'IdRef_PositiveFraction', NaN, ...
    'IdRef_Transition_Count', NaN, ...
    'IdFb_Mean_A', NaN, ...
    'IdFb_RMS_A', NaN, ...
    'Id_Tracking_RMS_Error_A', NaN, ...
    'IqFb_RMS_A', NaN, ...
    'Vdc_Min_V', NaN, ...
    'Vdc_Max_V', NaN, ...
    'Vdc_Ripple_V', NaN, ...
    'Ibatt_RMS_A', NaN, ...
    'Idc_RMS_A', NaN, ...
    'ModulationIndex_Mean', NaN, ...
    'ModulationIndex_Max', NaN, ...
    'VoltageMargin_Min_V', NaN, ...
    'ControlSaturation_Any', NaN, ...
    'T_batt_End_K', NaN, ...
    'T_stator_End_K', NaN, ...
    'T_rotor_End_K', NaN, ...
    'P_batt_heat_Mean_W', NaN, ...
    'P_cu_Mean_W', NaN, ...
    'P_iron_Mean_W', NaN, ...
    'P_inv_Mean_W', NaN, ...
    'P_hv_loss_Model_W', NaN, ...
    'P_batt_terminal_Model_W', NaN, ...
    'P_dc_input_Model_W', NaN, ...
    'P_dc_link_storage_Model_W', NaN, ...
    'DeltaE_batt_Model_J', NaN, ...
    'P_thermal_storage_Model_W', NaN, ...
    'P_heat_rejection_Model_W', NaN, ...
    'P_mech_Model_W', NaN, ...
    'P_unmodeled_Model_W', NaN, ...
    'Residual_dc_link_Model_W', NaN, ...
    'EnergyLedgerValid_Final', NaN, ...
    'ElectricalLedgerValid_Final', NaN, ...
    'KPI_Final_Time_s', NaN, ...
    'RMS_Window_Elapsed_Model_s', NaN, ...
    'RMS_Window_Complete_Model', NaN, ...
    'RMS_Window_s_Model', NaN, ...
    'P_batt_terminal_Recalc_W', NaN, ...
    'P_dc_input_Recalc_W', NaN, ...
    'P_hv_loss_Recalc_W', NaN, ...
    'DeltaE_batt_Recalc_J', NaN, ...
    'P_dc_link_storage_Recalc_W', NaN, ...
    'P_heat_input_Recalc_W', NaN, ...
    'P_thermal_balance_Error_W', NaN, ...
    'P_unmodeled_Recalc_W', NaN, ...
    'Residual_dc_link_Recalc_W', NaN, ...
    'P_batt_terminal_AbsError_W', NaN, ...
    'P_dc_input_AbsError_W', NaN, ...
    'P_hv_loss_AbsError_W', NaN, ...
    'DeltaE_batt_AbsError_J', NaN, ...
    'P_dc_link_storage_AbsError_W', NaN, ...
    'P_unmodeled_AbsError_W', NaN, ...
    'Residual_dc_link_AbsError_W', NaN, ...
    'HVLoss_Coeff_Ohm', NaN, ...
    'BattHeat_Coeff_Ohm', NaN, ...
    'CuLoss_Coeff_Ohm', NaN, ...
    'Edc_Formula_AbsError_J', NaN, ...
    'DeviceProtection_Evaluable', NaN, ...
    'DeviceProtection_Status', "");
end