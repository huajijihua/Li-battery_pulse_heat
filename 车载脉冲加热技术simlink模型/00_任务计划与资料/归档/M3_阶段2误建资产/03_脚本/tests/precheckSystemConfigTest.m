classdef precheckSystemConfigTest < matlab.unittest.TestCase
    %precheckSystemConfigTest Verifies SC-00 metadata blocking behavior.

    methods (TestClassSetup)
        function addSourceFolder(testCase)
            sourceFolder = fileparts(fileparts(mfilename('fullpath')));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(sourceFolder));
        end
    end

    methods (Test)
        function testContractBaselineIsBlocked(testCase)
            result = precheckSystemConfig(createM3ContractConfig());

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyFalse(result.activeAllowed);
            testCase.verifyTrue(any(result.blockers == "contract_baseline_not_runnable"));
        end

        function testCompleteMetadataIsReady(testCase)
            result = precheckSystemConfig(createCompleteMetadataConfig());

            testCase.verifyEqual(result.status, "ready_for_active");
            testCase.verifyTrue(result.activeAllowed);
            testCase.verifyEmpty(result.blockers);
        end

        function testOptionalDataGapLimitsResearch(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.optionalDataGaps = "thermal validation remains pending";
            systemConfig.researchScope = ...
                "thermal sensitivity only; no thermal safety inference";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "research_limited");
            testCase.verifyTrue(result.activeAllowed);
            testCase.verifyEqual(result.limitations, "thermal validation remains pending");
            testCase.verifyEqual(result.researchScope, ...
                "thermal sensitivity only; no thermal safety inference");
        end

        function testDataGapWithoutResearchScopeBlocksActive(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.optionalDataGaps = "thermal validation remains pending";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyTrue(any(result.blockers == "missing_research_scope"));
        end

        function testPlaceholderComponentBlocksActive(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.components.motor.identityScope = "PLACEHOLDER";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyTrue(any(result.blockers == "missing_component_identity_motor"));
        end

        function testInvalidSourceTagBlocksActive(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.components.battery.sourceTag = "";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyTrue(any(result.blockers == "missing_component_source_battery"));
        end

        function testUnknownCompatibilityBlocksActive(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.compatibility.controlTiming = "unknown";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyTrue(any(result.blockers == "compatibility_not_pass_controlTiming"));
        end

        function testControlPathMismatchBlocksActive(testCase)
            systemConfig = createCompleteMetadataConfig();
            systemConfig.components.control.candidatePathId = "OTHER-TEST-PATH";
            result = precheckSystemConfig(systemConfig);

            testCase.verifyEqual(result.status, "blocked");
            testCase.verifyTrue(any(result.blockers == "control_candidate_path_mismatch"));
        end
    end
end

function systemConfig = createCompleteMetadataConfig()
component = struct( ...
    'id', "TEST-ONLY-COMPONENT", ...
    'status', "complete", ...
    'sourceTag', "PLATFORM_DEFAULT", ...
    'identityScope', "TEST-ONLY-PLATFORM", ...
    'requiredParametersComplete', true);
controlComponent = component;
controlComponent.candidatePathId = "TEST-ONLY-PATH";

systemConfig = struct( ...
    'systemConfigId', "TEST-ONLY-SYSTEM", ...
    'isContractBaseline', false, ...
    'candidatePathId', "TEST-ONLY-PATH", ...
    'components', struct( ...
        'battery', component, ...
        'hvPath', component, ...
        'inverter', component, ...
        'motor', component, ...
        'control', controlComponent, ...
        'thermal', component, ...
        'protection', component, ...
        'scenario', component), ...
    'compatibility', struct( ...
        'voltage', "pass", ...
        'current', "pass", ...
        'powerEnergy', "pass", ...
        'thermal', "pass", ...
        'controlTiming', "pass", ...
        'mechanical', "pass", ...
        'protection', "pass", ...
        'dataSource', "pass"), ...
    'optionalDataGaps', strings(0, 1), ...
    'researchScope', "");
end
