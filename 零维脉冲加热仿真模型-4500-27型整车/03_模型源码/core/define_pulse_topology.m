function topology = define_pulse_topology(topology_id)
%DEFINE_PULSE_TOPOLOGY Returns pulse-heating architecture definitions.
% 中文说明:
% 本函数定义4500-27整车电池包和电机如何接入脉冲加热回路。
% 当前只保留vehicle_4500_27，即三包并联整体输出，不假设单包可独立接入电驱。

    topology_id = lower(string(topology_id));
    case_template = struct('id', '', 'name', '', 'branch_count', 0, ...
        'motor_count', 0, 'type', '', 'description', '');

    switch topology_id
        case "vehicle_4500_27"
            % 当前4500-27实车约束方案:
            % 参数表说明三个电池包并联整体输出且不可独立接入电驱，因此只评估
            % “三包并联单电机”和“三包并联双电机”两种真实可接入边界。
            cases = repmat(case_template, 1, 2);
            cases(1).id = '三包并联单电机';
            cases(1).name = '三包并联整体输出，单电机脉冲';
            cases(1).branch_count = 3;
            cases(1).motor_count = 1;
            cases(1).type = 'whole_branch_sync';
            cases(1).description = ['参数表约束下的实车可行边界: 三个电池包非独立输出、并联输出、不可独立接入电驱, ', ...
                '因此所有电池包作为一个并联系统共同参与; 仅一台电机/逆变器施加堵转脉冲, 作为低复杂度基准方案'];

            cases(2).id = '三包并联双电机';
            cases(2).name = '三包并联整体输出，双电机脉冲';
            cases(2).branch_count = 3;
            cases(2).motor_count = 2;
            cases(2).type = 'whole_branch_sync';
            cases(2).description = ['参数表约束下的实车主方案: 三个电池包作为不可拆分的并联高压源共同给双电机/逆变器脉冲回路供能, ', ...
                '两台电机同步施加堵转脉冲; 只评估电机侧激励强度、频率、占空比和支路分流, 不假设单包独立接入'];

            topology = struct('id', 'vehicle_4500_27', 'name', '4500-27实车可接入方案', ...
                'short_name', '4500-27实车约束', 'branch_count', 3, 'cases', cases);

        otherwise
            error('未知脉冲加热拓扑: %s。', topology_id);
    end
end
