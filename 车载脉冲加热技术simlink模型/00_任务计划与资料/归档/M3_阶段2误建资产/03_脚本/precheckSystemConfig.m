function result = precheckSystemConfig(systemConfig)
%precheckSystemConfig Check M3 configuration metadata before Active operation.

arguments
    systemConfig (1,1) struct
end

componentNames = ["battery"; "hvPath"; "inverter"; "motor"; ...
    "control"; "thermal"; "protection"; "scenario"];
compatibilityNames = ["voltage"; "current"; "powerEnergy"; "thermal"; ...
    "controlTiming"; "mechanical"; "protection"; "dataSource"];
allowedSourceTags = ["OFFICIAL"; "LITERATURE"; "ENGINEERING_DEFAULT"; ...
    "PLATFORM_DEFAULT"];
blockers = strings(64, 1);
blockerCount = 0;
limitations = strings(0, 1);
researchScope = "";
systemConfigId = "";

if ~isfield(systemConfig, 'systemConfigId') || ...
        ~isstring(systemConfig.systemConfigId) || ...
        ~isscalar(systemConfig.systemConfigId) || ...
        strlength(strtrim(systemConfig.systemConfigId)) == 0
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_system_config_id";
else
    systemConfigId = systemConfig.systemConfigId;
end

if ~isfield(systemConfig, 'isContractBaseline') || ...
        ~islogical(systemConfig.isContractBaseline) || ...
        ~isscalar(systemConfig.isContractBaseline)
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_contract_baseline_flag";
elseif systemConfig.isContractBaseline
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "contract_baseline_not_runnable";
end

if ~isfield(systemConfig, 'candidatePathId') || ...
        ~isstring(systemConfig.candidatePathId) || ...
        ~isscalar(systemConfig.candidatePathId) || ...
        strlength(strtrim(systemConfig.candidatePathId)) == 0 || ...
        systemConfig.candidatePathId == "PLACEHOLDER"
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_candidate_path";
end

if ~isfield(systemConfig, 'components') || ~isstruct(systemConfig.components)
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_components";
else
    for componentIndex = 1:numel(componentNames)
        componentName = componentNames(componentIndex);
        if ~isfield(systemConfig.components, componentName)
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "missing_component_" + componentName;
            continue
        end

        component = systemConfig.components.(componentName);
        requiredFields = ["id"; "status"; "sourceTag"; "identityScope"; ...
            "requiredParametersComplete"];
        if ~isstruct(component) || ~all(isfield(component, requiredFields))
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "incomplete_component_" + componentName;
            continue
        end

        if ~isstring(component.id) || ~isscalar(component.id) || ...
                strlength(strtrim(component.id)) == 0 || component.id == "PLACEHOLDER"
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "missing_component_id_" + componentName;
        end

        if ~isstring(component.status) || ~isscalar(component.status) || ...
                component.status ~= "complete"
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "incomplete_component_status_" + componentName;
        end

        if ~isstring(component.sourceTag) || ~isscalar(component.sourceTag) || ...
                ~any(component.sourceTag == allowedSourceTags)
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "missing_component_source_" + componentName;
        end

        if ~isstring(component.identityScope) || ~isscalar(component.identityScope) || ...
                strlength(strtrim(component.identityScope)) == 0 || ...
                component.identityScope == "PLACEHOLDER"
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "missing_component_identity_" + componentName;
        end

        if ~islogical(component.requiredParametersComplete) || ...
                ~isscalar(component.requiredParametersComplete) || ...
                ~component.requiredParametersComplete
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "incomplete_component_parameters_" + componentName;
        end

        if componentName == "control"
            if ~isfield(component, 'candidatePathId') || ...
                    ~isstring(component.candidatePathId) || ...
                    ~isscalar(component.candidatePathId) || ...
                    ~isfield(systemConfig, 'candidatePathId') || ...
                    component.candidatePathId ~= systemConfig.candidatePathId
                blockerCount = blockerCount + 1;
                blockers(blockerCount) = "control_candidate_path_mismatch";
            end
        end
    end
end

if ~isfield(systemConfig, 'compatibility') || ~isstruct(systemConfig.compatibility)
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_compatibility";
else
    for compatibilityIndex = 1:numel(compatibilityNames)
        compatibilityName = compatibilityNames(compatibilityIndex);
        if ~isfield(systemConfig.compatibility, compatibilityName) || ...
                ~isstring(systemConfig.compatibility.(compatibilityName)) || ...
                ~isscalar(systemConfig.compatibility.(compatibilityName)) || ...
                systemConfig.compatibility.(compatibilityName) ~= "pass"
            blockerCount = blockerCount + 1;
            blockers(blockerCount) = "compatibility_not_pass_" + compatibilityName;
        end
    end
end

if ~isfield(systemConfig, 'optionalDataGaps') || ...
        ~isstring(systemConfig.optionalDataGaps) || ...
        ~isvector(systemConfig.optionalDataGaps)
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_optional_data_gaps";
elseif ~isempty(systemConfig.optionalDataGaps)
    limitations = unique(systemConfig.optionalDataGaps(:), 'stable');
end

if ~isfield(systemConfig, 'researchScope') || ...
        ~isstring(systemConfig.researchScope) || ...
        ~isscalar(systemConfig.researchScope)
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_research_scope";
elseif ~isempty(limitations) && strlength(strtrim(systemConfig.researchScope)) == 0
    blockerCount = blockerCount + 1;
    blockers(blockerCount) = "missing_research_scope";
else
    researchScope = systemConfig.researchScope;
end

blockers = blockers(1:blockerCount);

if ~isempty(blockers)
    status = "blocked";
    activeAllowed = false;
elseif ~isempty(limitations)
    status = "research_limited";
    activeAllowed = true;
else
    status = "ready_for_active";
    activeAllowed = true;
end

result = struct( ...
    'systemConfigId', systemConfigId, ...
    'status', status, ...
    'activeAllowed', activeAllowed, ...
    'blockers', unique(blockers, 'stable'), ...
    'limitations', limitations, ...
    'researchScope', researchScope, ...
    'checkedComponents', componentNames, ...
    'checkedCompatibility', compatibilityNames);
end
