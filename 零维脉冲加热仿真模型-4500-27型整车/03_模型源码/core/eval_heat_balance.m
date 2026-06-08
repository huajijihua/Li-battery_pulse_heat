function heat = eval_heat_balance(p, P_branch_W, T_branch_C, branch_count)
%EVAL_HEAT_BALANCE Battery heat generation, heat loss, and temperature rate.

    P_loss_branch_W = calc_branch_heat_loss(p, T_branch_C);
    P_battery_W = sum(P_branch_W);
    P_loss_W = sum(P_loss_branch_W);
    P_net_branch_W = P_branch_W - P_loss_branch_W;
    P_net_W = sum(P_net_branch_W);
    Cth_total = branch_count * p.Cth_branch_J_per_K;

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
    if isfield(p, 'enable_heat_loss') && ~p.enable_heat_loss
        P_loss = zeros(size(T_branch_C));
        return;
    end

    thermal_boundary = "convection";
    if isfield(p, 'thermal_boundary')
        thermal_boundary = lower(string(p.thermal_boundary));
    end

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
