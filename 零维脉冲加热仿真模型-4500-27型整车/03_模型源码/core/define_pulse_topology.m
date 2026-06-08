function topology = define_pulse_topology(topology_id)
%DEFINE_PULSE_TOPOLOGY Returns pulse-heating architecture definitions.

    topology_id = lower(string(topology_id));
    case_template = struct('id', '', 'name', '', 'branch_count', 0, ...
        'motor_count', 0, 'type', '', 'description', '');

    switch topology_id
        case "dual_branch"
            cases = repmat(case_template, 1, 3);
            cases(1).id = '双支路整体同步';
            cases(1).name = '双支路电池，双电机整体同步脉冲';
            cases(1).branch_count = 2;
            cases(1).motor_count = 2;
            cases(1).type = 'whole_branch_sync';
            cases(1).description = '两个电池支路共同参与, 两台电机同步脉冲, 用于判断双支路整车架构的总加热能力、支路分流和母线压力';

            cases(2).id = '单电机单支路';
            cases(2).name = '单电机给单支路脉冲';
            cases(2).branch_count = 1;
            cases(2).motor_count = 1;
            cases(2).type = 'whole_branch_sync';
            cases(2).description = '一台电机作用于一个电池支路, 作为单个电机和单个电池支路的基础加热能力基准';

            cases(3).id = '双电机单支路';
            cases(3).name = '双电机集中给单支路脉冲';
            cases(3).branch_count = 1;
            cases(3).motor_count = 2;
            cases(3).type = 'whole_branch_sync';
            cases(3).description = '两台电机同时作用于一个电池支路, 用于判断整体同步脉冲电流不足时的集中加热能力和单支路风险';

            topology = struct('id', 'dual_branch', 'name', '双支路相关方案', ...
                'short_name', '双支路相关', 'branch_count', 2, 'cases', cases);

        case "triple_branch"
            cases = repmat(case_template, 1, 3);
            cases(1).id = '三支路整体同步';
            cases(1).name = '三支路电池，双电机整体同步脉冲';
            cases(1).branch_count = 3;
            cases(1).motor_count = 2;
            cases(1).type = 'whole_branch_sync';
            cases(1).description = '三个电池支路共同参与, 两台电机同步脉冲, 用于判断三支路架构下电流分散后温升是否仍有意义';

            cases(2).id = '单电机单支路';
            cases(2).name = '单电机给单支路脉冲';
            cases(2).branch_count = 1;
            cases(2).motor_count = 1;
            cases(2).type = 'whole_branch_sync';
            cases(2).description = '一台电机作用于一个电池支路, 作为单个电机和单个电池支路的基础加热能力基准';

            cases(3).id = '双电机单支路';
            cases(3).name = '双电机集中给单支路脉冲';
            cases(3).branch_count = 1;
            cases(3).motor_count = 2;
            cases(3).type = 'whole_branch_sync';
            cases(3).description = '两台电机同时作用于一个电池支路, 用于判断整体同步脉冲电流不足时的集中加热能力和单支路风险';

            topology = struct('id', 'triple_branch', 'name', '三支路相关方案', ...
                'short_name', '三支路相关', 'branch_count', 3, 'cases', cases);

        case "vehicle_4500_27"
            cases = repmat(case_template, 1, 2);
            cases(1).id = '三包并联单电机';
            cases(1).name = '三包并联整体输出，单电机脉冲';
            cases(1).branch_count = 3;
            cases(1).motor_count = 1;
            cases(1).type = 'whole_branch_sync';
            cases(1).description = ['参数表约束下的实车可行边界: 三个电池包非独立输出、并联输出、不可独立接入电驱, ', ...
                '因此所有电池包作为一个并联系统共同参与; 仅一台电机/逆变器施加脉冲, 或两台电机轮换等效为单电机平均激励'];

            cases(2).id = '三包并联双电机';
            cases(2).name = '三包并联整体输出，双电机脉冲';
            cases(2).branch_count = 3;
            cases(2).motor_count = 2;
            cases(2).type = 'whole_branch_sync';
            cases(2).description = ['参数表约束下的实车主方案: 三个电池包作为不可拆分的并联高压源共同给双电机/逆变器脉冲回路供能, ', ...
                '只评估电机侧激励强度、频率、占空比和支路分流, 不假设单包独立接入'];

            topology = struct('id', 'vehicle_4500_27', 'name', '4500-27实车可接入方案', ...
                'short_name', '4500-27实车约束', 'branch_count', 3, 'cases', cases);

        otherwise
            error('未知脉冲加热拓扑: %s。', topology_id);
    end
end
