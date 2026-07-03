function heat = eval_heat_balance(p, P_branch_W, T_branch_C, branch_count)
%EVAL_HEAT_BALANCE Battery heat generation, heat loss, and temperature rate.
% 中文说明:
% 本函数把电池支路发热功率转换成温升速率。核心关系是:
% 净加热功率 = 电池内阻发热 - 对外散热；
% 温升速率 = 净加热功率 / 电池热容。

    % 每个支路分别计算散热，再汇总为整车电池总发热、总散热和总净热功率。
    P_loss_branch_W = calc_branch_heat_loss(p, T_branch_C);
    P_battery_W = sum(P_branch_W);
    P_loss_W = sum(P_loss_branch_W);
    P_net_branch_W = P_branch_W - P_loss_branch_W;
    P_net_W = sum(P_net_branch_W);
    Cth_total = branch_count * p.Cth_branch_J_per_K;

    % 输出热平衡结果。dTdt_C_per_min是平均温升速率，不代表单体内部温差。
    heat = struct();
    heat.P_branch_W = P_branch_W;
    heat.P_battery_W = P_battery_W;
    heat.P_loss_branch_W = P_loss_branch_W;
    heat.P_loss_W = P_loss_W;
    heat.P_net_branch_W = P_net_branch_W;
    heat.P_net_W = P_net_W;
    heat.dTdt_C_per_min = P_net_W / Cth_total * 60;
end

function P_loss = calc_branch_heat_loss(p, T_branch_C)
    % 散热边界:
    % enable_heat_loss=false时按绝热处理；否则根据thermal_boundary选择弱对流或热阻模型。
    if isfield(p, 'enable_heat_loss') && ~p.enable_heat_loss
        P_loss = zeros(size(T_branch_C));
        return;
    end

    thermal_boundary = "convection";
    if isfield(p, 'thermal_boundary')
        thermal_boundary = lower(string(p.thermal_boundary));
    end

    % 低于环境温度时不计算从环境吸热。当前默认T_init=T_amb=-20C，影响较小；
    % 若后续研究电池低于环境温度的回温，需要重新审查这个边界。
    dT = max(T_branch_C - p.T_amb_C, 0);
    switch thermal_boundary
        case {"none", "ignore", "adiabatic"}
            P_loss = zeros(size(T_branch_C));
        case {"convection", "natural_convection"}
            P_loss = p.h_conv_W_per_m2K * p.branch_area_m2 .* dT;
        case "thermal_resistance"
            if ~isfield(p, 'R_th_branch_K_per_W') || ...
                    p.R_th_branch_K_per_W <= 0 || ~isfinite(p.R_th_branch_K_per_W)
                error('thermal_resistance模式下R_th_branch_K_per_W必须为正有限值。');
            end
            P_loss = dT ./ p.R_th_branch_K_per_W;
        otherwise
            error('未知热边界类型: %s。', thermal_boundary);
    end
end
