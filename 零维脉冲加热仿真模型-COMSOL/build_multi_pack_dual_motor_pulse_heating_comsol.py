"""Build a COMSOL multi-pack / dual-motor pulse-heating model.

The generated model is a first engineering-validation version for a
multi-parallel battery-pack, dual-controller and dual-motor architecture.  The
topology is fixed to three possible battery-pack branches and two possible
motor/controller branches.  Users switch schemes in COMSOL by changing enable
parameters, pulse frequency, duty, phase and amplitude parameters instead of
rebuilding the circuit.

This script only creates, solves and saves the official .mph model.  It does
not write CSV, summary or scan result files.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path

import mph


ROOT = Path(__file__).resolve().parent
MODEL_PATH = ROOT / "multi_pack_dual_motor_pulse_heating.mph"


SCENARIOS: dict[str, dict[str, str]] = {
    "dual_branch_sync": {
        "scenario_id": "1",
        "pack1_enable": "1",
        "pack2_enable": "1",
        "pack3_enable": "0",
        "motor1_enable": "1",
        "motor2_enable": "1",
        "focus_pack_index": "1",
        "phase_m1": "0",
        "phase_m2": "0",
    },
    "triple_branch_sync": {
        "scenario_id": "2",
        "pack1_enable": "1",
        "pack2_enable": "1",
        "pack3_enable": "1",
        "motor1_enable": "1",
        "motor2_enable": "1",
        "focus_pack_index": "1",
        "phase_m1": "0",
        "phase_m2": "0",
    },
    "single_motor_single_pack": {
        "scenario_id": "3",
        "pack1_enable": "1",
        "pack2_enable": "0",
        "pack3_enable": "0",
        "motor1_enable": "1",
        "motor2_enable": "0",
        "focus_pack_index": "1",
        "phase_m1": "0",
        "phase_m2": "0",
    },
    "dual_motor_focus_pack": {
        "scenario_id": "4",
        "pack1_enable": "1",
        "pack2_enable": "0",
        "pack3_enable": "0",
        "motor1_enable": "1",
        "motor2_enable": "1",
        "focus_pack_index": "1",
        "phase_m1": "0",
        "phase_m2": "0",
    },
}


def connect(port: int | None = None) -> mph.Client:
    """Connect to a running COMSOL Server."""
    if port is None:
        port = int(os.environ.get("COMSOL_PORT", "2036"))
    return mph.Client(port=port, host="localhost")


def safe_remove(client: mph.Client, model: mph.Model) -> None:
    try:
        client.remove(model)
    except Exception:
        pass


def set_parameters(model) -> None:
    p = model.param()

    p.set("scenario_id", "1", "方案编号: 1双支路同步, 2三支路同步, 3单电机单支路, 4双电机集中单支路")
    p.set("focus_pack_index", "1", "集中加热目标电池包编号, 当前作为显示和人工切换参考")
    p.set("pack1_enable", "1", "电池包1参与标志, 1=参与, 0=断开")
    p.set("pack2_enable", "1", "电池包2参与标志, 1=参与, 0=断开")
    p.set("pack3_enable", "0", "电池包3参与标志, 1=参与, 0=断开")
    p.set("motor1_enable", "1", "电机控制器1参与标志, 1=参与, 0=断开")
    p.set("motor2_enable", "1", "电机控制器2参与标志, 1=参与, 0=断开")

    p.set("N_series_pack", "192", "单个并联电池包等效串联单体数, 当前为3806占位口径")
    p.set("C_pack", "324[A*h]", "单个并联电池包容量, 当前为3806占位口径")
    p.set("SOC0_pack1", "0.50", "电池包1初始SOC")
    p.set("SOC0_pack2", "0.50", "电池包2初始SOC")
    p.set("SOC0_pack3", "0.50", "电池包3初始SOC")
    p.set("T_init_pack1", "253.15[K]", "电池包1初始温度, -20 degC")
    p.set("T_init_pack2", "253.15[K]", "电池包2初始温度, -20 degC")
    p.set("T_init_pack3", "253.15[K]", "电池包3初始温度, -20 degC")
    p.set("T_amb", "253.15[K]", "环境温度, -20 degC")
    p.set("R_pack1", "0.397[ohm]", "电池包1低温等效内阻, 占位值")
    p.set("R_pack2", "0.397[ohm]", "电池包2低温等效内阻, 占位值")
    p.set("R_pack3", "0.397[ohm]", "电池包3低温等效内阻, 占位值")
    p.set("R_pack_off", "1e6[ohm]", "未参与电池包的等效断开电阻")
    p.set("R_pack1_eff", "R_pack1+R_pack_off*(1-pack1_enable)", "电池包1开关后的等效串联电阻")
    p.set("R_pack2_eff", "R_pack2+R_pack_off*(1-pack2_enable)", "电池包2开关后的等效串联电阻")
    p.set("R_pack3_eff", "R_pack3+R_pack_off*(1-pack3_enable)", "电池包3开关后的等效串联电阻")
    p.set("Cth_pack1", "1244e3[J/K]", "电池包1集总热容, 占位值")
    p.set("Cth_pack2", "1244e3[J/K]", "电池包2集总热容, 占位值")
    p.set("Cth_pack3", "1244e3[J/K]", "电池包3集总热容, 占位值")
    p.set("A_pack1", "9[m^2]", "电池包1换热面积, 占位值")
    p.set("A_pack2", "9[m^2]", "电池包2换热面积, 占位值")
    p.set("A_pack3", "9[m^2]", "电池包3换热面积, 占位值")
    p.set("h_conv", "8[W/(m^2*K)]", "电池包对流换热系数")
    p.set("Rth_pack1", "1/(h_conv*A_pack1)", "电池包1到环境等效热阻")
    p.set("Rth_pack2", "1/(h_conv*A_pack2)", "电池包2到环境等效热阻")
    p.set("Rth_pack3", "1/(h_conv*A_pack3)", "电池包3到环境等效热阻")

    p.set("L_motor1", "0.26[mH]", "电机1等效d轴电感, CAM255PT52占位")
    p.set("L_motor2", "0.26[mH]", "电机2等效d轴电感, CAM255PT52占位")
    p.set("R_motor1", "0.020[ohm]", "电机1等效绕组电阻")
    p.set("R_motor2", "0.020[ohm]", "电机2等效绕组电阻")
    p.set("R_motor_off", "1e6[ohm]", "未参与电机支路的等效断开电阻")
    p.set("R_motor1_eff", "R_motor1+R_motor_off*(1-motor1_enable)", "电机1开关后的等效电阻")
    p.set("R_motor2_eff", "R_motor2+R_motor_off*(1-motor2_enable)", "电机2开关后的等效电阻")
    p.set("R_ctrl_loss", "0.005[ohm]", "控制器导通损耗占位电阻")
    p.set("P_ctrl_switch_ref", "500[W]", "单控制器开关损耗占位参考")
    p.set("I_motor_rms_limit", "550[A]", "单电机/控制器RMS电流参考限制")
    p.set("I_motor_peak_limit", "778[A]", "单电机/控制器峰值电流参考限制")

    p.set("f_pulse", "1250[Hz]", "默认脉冲频率")
    p.set("f_pulse_ref", "1250[Hz]", "控制器损耗参考频率")
    p.set("duty", "0.50", "默认占空比")
    p.set("pulse_amp_scale", "1", "脉冲电压幅值系数")
    p.set("phase_m1", "0", "电机控制器1相位, 单位为一个周期的比例")
    p.set("phase_m2", "0", "电机控制器2相位, 单位为一个周期的比例")
    p.set("tr_pulse", "20e-6[s]", "脉冲上升时间, 第一版用有限斜率避免理想硬切换")
    p.set("tf_pulse", "20e-6[s]", "脉冲下降时间, 第一版用有限斜率避免理想硬切换")
    p.set("V_bus_ref", "N_series_pack*3.32[V]", "50%SOC附近母线参考电压")
    p.set("Vdrv1_value", "2*V_bus_ref*pulse_amp_scale*motor1_enable", "控制器1脉冲源幅值")
    p.set("Vdrv1_offset", "-V_bus_ref*pulse_amp_scale*motor1_enable", "控制器1脉冲源偏置")
    p.set("Vdrv2_value", "2*V_bus_ref*pulse_amp_scale*motor2_enable", "控制器2脉冲源幅值")
    p.set("Vdrv2_offset", "-V_bus_ref*pulse_amp_scale*motor2_enable", "控制器2脉冲源偏置")

    p.set("cycles_solve", "8", "默认求解脉冲周期数")
    p.set("steps_per_cycle", "47", "每个脉冲周期输出点数, 避免默认输出点正好落在50%占空比翻转边界")
    p.set("t_end", "(cycles_solve-0.05)/f_pulse", "默认瞬态求解结束时间, 略避开脉冲翻转边界")
    p.set("dt_out", "1/(f_pulse*steps_per_cycle)", "默认输出时间步长")

    p.set("I_pack_rms_ref", "550[A]", "单电池包RMS电流参考边界, 非硬限制")
    p.set("I_pack_peak_ref", "778[A]", "单电池包峰值电流参考边界, 非硬限制")
    p.set("I_pack_charge_30s_ref", "97.2[A]", "30s低温回充参考边界, 单个324Ah支路, 非kHz硬限制")
    p.set("I_pack_discharge_30s_ref", "388.8[A]", "30s低温放电参考边界, 单个324Ah支路, 非kHz硬限制")
    p.set("I_plating_risk_ref", "300[A]", "析锂风险参考电流幅值, 待试验/机理标定, 非硬限制")
    p.set("V_bus_min_ref", "N_series_pack*2.50[V]", "母线低压参考边界")
    p.set("V_bus_max_ref", "N_series_pack*3.65[V]", "母线高压参考边界")


def create_lumped_thermal_interface(comp) -> None:
    comp.physics().create("lts", "LumpedThermalSystem")
    lts = comp.physics("lts")
    lts.label("集总热系统：三电池包独立热节点")

    for idx in range(1, 4):
        node = f"bat{idx}"

        lts.create(f"tm{idx}", "ThermalMass")
        tm = lts.feature(f"tm{idx}")
        tm.label(f"电池包{idx}热容")
        tm.set("Connections", [node])
        tm.set("inputType", "ThermalCapacitance")
        tm.set("C", f"Cth_pack{idx}")
        tm.set("Ti", f"T_init_pack{idx}")
        tm.set("includeTemperature", True)

        lts.create(f"qsrc{idx}", "HeatRateNode")
        qsrc = lts.feature(f"qsrc{idx}")
        qsrc.label(f"电池包{idx}内阻发热")
        qsrc.set("Connections", [node])
        qsrc.set("inputType", "HeatRate")
        qsrc.set("P0", f"P_pack{idx}_ohmic")
        qsrc.set("T_init", f"T_init_pack{idx}")
        qsrc.set("includeTemperature", True)

        lts.create(f"conv{idx}", "HeatRateNode")
        conv = lts.feature(f"conv{idx}")
        conv.label(f"电池包{idx}对流散热")
        conv.set("Connections", [node])
        conv.set("inputType", "ConvectiveHeatRate")
        conv.set("A", f"A_pack{idx}")
        conv.set("HeatTransferCoefficientType", "UserDef")
        conv.set("h", "h_conv")
        conv.set("Text", "T_amb")
        conv.set("T_init", f"T_init_pack{idx}")
        conv.set("includeTemperature", True)


def create_circuit(comp) -> None:
    comp.physics().create("cir", "Circuit")
    cir = comp.physics("cir")
    cir.label("电路：三并联电池包-公共母线-双电机控制器")
    cir.feature("gnd1").label("DC- / 电路参考地")

    bus_p = "100"
    bus_n = "0"

    for idx in range(1, 4):
        pack_node = str(10 * idx + 1)

        cir.create(f"OCV{idx}", "BatteryOpenCircuitVoltage")
        ocv = cir.feature(f"OCV{idx}")
        ocv.label(f"电池包{idx}开路电压")
        ocv.set("Connections", [pack_node, bus_n])
        ocv.set("Q_cell0", "C_pack")
        ocv.set("SOC_cell0", f"SOC0_pack{idx}")
        ocv.set("Temp", f"comp1.lts.T_bat{idx}")
        ocv.set("Tref", "298.15[K]")
        ocv.set("SOC_Eocv", [0.10, 0.20, 0.50, 0.90])
        ocv.set(
            "Eocv",
            [
                "610.56[V]",
                "622.08[V]",
                "637.44[V]",
                "656.64[V]",
            ],
        )
        ocv.set("SOC_dEocvdT", [0.10, 0.90])
        ocv.set("dEocvdT", ["0[V/K]", "0[V/K]"])

        cir.create(f"Rbat{idx}", "Resistor")
        rbat = cir.feature(f"Rbat{idx}")
        rbat.label(f"电池包{idx}内阻及支路开关")
        rbat.set("Connections", [pack_node, bus_p])
        rbat.set("R", f"R_pack{idx}_eff")

    for idx in range(1, 3):
        n1 = bus_p
        n2 = str(200 + idx * 10 + 1)
        n3 = str(200 + idx * 10 + 2)

        cir.create(f"Lmot{idx}", "Inductor")
        lmot = cir.feature(f"Lmot{idx}")
        lmot.label(f"电机{idx}等效电感")
        lmot.set("Connections", [n1, n2])
        lmot.set("L", f"L_motor{idx}")
        lmot.set("i", "0[A]")

        cir.create(f"Rmot{idx}", "Resistor")
        rmot = cir.feature(f"Rmot{idx}")
        rmot.label(f"电机{idx}等效电阻及支路开关")
        rmot.set("Connections", [n2, n3])
        rmot.set("R", f"R_motor{idx}_eff")

        cir.create(f"Vdrv{idx}", "VoltageSource")
        vdrv = cir.feature(f"Vdrv{idx}")
        vdrv.label(f"控制器{idx}等效脉冲电压源")
        vdrv.set("Connections", [n3, bus_n])
        vdrv.set("sourceType", "PulseSource")
        vdrv.set("value", f"Vdrv{idx}_value")
        vdrv.set("offset", f"Vdrv{idx}_offset")
        vdrv.set("td", f"phase_m{idx}/f_pulse")
        vdrv.set("tr", "tr_pulse")
        vdrv.set("tf", "tf_pulse")
        vdrv.set("pw", "duty/f_pulse")
        vdrv.set("Tper", "1/f_pulse")


def create_variables(comp) -> None:
    comp.variable().create("var1")
    var = comp.variable("var1")
    var.label("多电池包双电机脉冲加热变量")

    for idx in range(1, 4):
        var.set(f"I_pack{idx}", f"cir.Rbat{idx}.i", f"电池包{idx}支路电流")
        var.set(f"I_pack{idx}_abs", f"abs(I_pack{idx})", f"电池包{idx}支路电流绝对值")
        var.set(f"P_pack{idx}_ohmic", f"cir.Rbat{idx}.i^2*R_pack{idx}", f"电池包{idx}内阻发热")
        var.set(f"P_pack{idx}_loss", f"(lts.T_bat{idx}-T_amb)/Rth_pack{idx}", f"电池包{idx}对流散热")
        var.set(f"P_pack{idx}_net", f"P_pack{idx}_ohmic-P_pack{idx}_loss", f"电池包{idx}净加热功率")
        var.set(f"dTdt_pack{idx}", f"P_pack{idx}_net/Cth_pack{idx}", f"电池包{idx}温升速率")
        var.set(f"T_pack{idx}", f"lts.T_bat{idx}", f"电池包{idx}温度")
        var.set(f"SOC_pack{idx}", f"cir.OCV{idx}.SOC", f"电池包{idx}SOC")
        var.set(f"E_ocv_pack{idx}", f"cir.OCV{idx}.E_OCV", f"电池包{idx}开路电压")
        var.set(
            f"pack{idx}_peak_ref_over",
            f"if(abs(I_pack{idx})>I_pack_peak_ref,1,0)",
            f"电池包{idx}峰值电流参考超限标志",
        )
        var.set(
            f"pack{idx}_rms_ref_over",
            f"if(abs(I_pack{idx})>sqrt(2)*I_pack_rms_ref,1,0)",
            f"电池包{idx}RMS参考边界瞬时等效超限标志",
        )
        var.set(
            f"pack{idx}_charge_30s_ref_over",
            f"if(-I_pack{idx}>I_pack_charge_30s_ref,1,0)",
            f"电池包{idx}30s回充参考边界超限标志",
        )
        var.set(
            f"pack{idx}_discharge_30s_ref_over",
            f"if(I_pack{idx}>I_pack_discharge_30s_ref,1,0)",
            f"电池包{idx}30s放电参考边界超限标志",
        )
        var.set(
            f"pack{idx}_plating_risk",
            f"if(abs(I_pack{idx})>I_plating_risk_ref,1,0)",
            f"电池包{idx}析锂风险电流幅值参考标志, 待标定, 非硬限制",
        )

    for idx in range(1, 3):
        var.set(f"I_motor{idx}", f"cir.Rmot{idx}.i", f"电机控制器{idx}支路电流")
        var.set(f"P_motor{idx}_cu", f"cir.Rmot{idx}.i^2*R_motor{idx}", f"电机{idx}等效铜耗")
        var.set(
            f"P_ctrl{idx}_loss",
            f"motor{idx}_enable*(cir.Rmot{idx}.i^2*R_ctrl_loss+P_ctrl_switch_ref*(f_pulse/f_pulse_ref)*abs(cir.Rmot{idx}.i)/(I_motor_rms_limit+1e-12[A]))",
            f"控制器{idx}损耗占位估算",
        )
        var.set(
            f"motor{idx}_peak_over",
            f"if(abs(I_motor{idx})>I_motor_peak_limit,1,0)",
            f"电机控制器{idx}峰值电流超限标志",
        )
        var.set(
            f"motor{idx}_rms_ref_over",
            f"if(abs(I_motor{idx})>sqrt(2)*I_motor_rms_limit,1,0)",
            f"电机控制器{idx}RMS参考边界瞬时等效超限标志",
        )

    var.set("active_pack_count", "pack1_enable+pack2_enable+pack3_enable", "参与电池包数量")
    var.set("active_motor_count", "motor1_enable+motor2_enable", "参与电机控制器数量")
    var.set("I_pack_total", "I_pack1+I_pack2+I_pack3", "三个电池包支路电流代数和")
    var.set("I_bus_motor", "I_motor1+I_motor2", "两个电机控制器支路电流代数和")
    var.set("P_bat_total", "P_pack1_ohmic+P_pack2_ohmic+P_pack3_ohmic", "电池总内阻发热")
    var.set("P_motor_total", "P_motor1_cu+P_motor2_cu", "电机总等效铜耗")
    var.set("P_ctrl_total", "P_ctrl1_loss+P_ctrl2_loss", "控制器总占位损耗")
    var.set("P_external_total", "P_motor_total+P_ctrl_total", "电池外部电器损耗")
    var.set("P_system_loss_total", "P_bat_total+P_external_total", "系统总损耗")
    var.set(
        "T_pack_avg",
        "(pack1_enable*T_pack1+pack2_enable*T_pack2+pack3_enable*T_pack3)/(active_pack_count+1e-9)",
        "参与电池包平均温度",
    )
    var.set(
        "V_bus_est",
        "(pack1_enable*(E_ocv_pack1-I_pack1*R_pack1)+pack2_enable*(E_ocv_pack2-I_pack2*R_pack2)+pack3_enable*(E_ocv_pack3-I_pack3*R_pack3))/(active_pack_count+1e-9)",
        "由电池包端电压估算的母线电压",
    )
    var.set(
        "focus_pack_current",
        "if(focus_pack_index<1.5,I_pack1,if(focus_pack_index<2.5,I_pack2,I_pack3))",
        "集中加热目标电池包电流",
    )
    var.set(
        "focus_pack_temperature",
        "if(focus_pack_index<1.5,T_pack1,if(focus_pack_index<2.5,T_pack2,T_pack3))",
        "集中加热目标电池包温度",
    )
    var.set(
        "bus_voltage_over",
        "if(V_bus_est<V_bus_min_ref,1,if(V_bus_est>V_bus_max_ref,1,0))",
        "母线电压参考越界标志",
    )
    var.set(
        "safety_risk_count",
        "pack1_peak_ref_over+pack2_peak_ref_over+pack3_peak_ref_over+motor1_peak_over+motor2_peak_over+bus_voltage_over+pack1_plating_risk+pack2_plating_risk+pack3_plating_risk",
        "安全风险标志数量, 析锂项为待标定参考",
    )


def create_study(model) -> None:
    study = model.study()
    study.create("std1")
    model.study("std1").label("默认瞬态脉冲加热工况")
    model.study("std1").create("time", "Transient")
    time = model.study("std1").feature("time")
    time.label("瞬态求解")
    time.set("tlist", "range(0,dt_out,t_end)")
    time.set("usertol", True)
    time.set("rtol", "1e-4")
    time.setSolveFor("/physics/cir", True)
    time.setSolveFor("/physics/lts", True)


def create_results(model) -> None:
    result = model.result()

    result.create("pg_curr", "PlotGroup1D")
    model.result("pg_curr").label("支路电流与母线电流")
    model.result("pg_curr").set("xlabel", "时间 (s)")
    model.result("pg_curr").set("ylabel", "电流 (A)")
    model.result("pg_curr").feature().create("glob1", "Global")
    model.result("pg_curr").feature("glob1").label("电池包、电机控制器和母线电流")
    model.result("pg_curr").feature("glob1").set(
        "expr", ["I_pack1", "I_pack2", "I_pack3", "I_motor1", "I_motor2", "I_bus_motor"]
    )
    model.result("pg_curr").feature("glob1").set("unit", ["A", "A", "A", "A", "A", "A"])

    result.create("pg_soc_ocv", "PlotGroup1D")
    model.result("pg_soc_ocv").label("SOC 与 OCV")
    model.result("pg_soc_ocv").set("xlabel", "时间 (s)")
    model.result("pg_soc_ocv").feature().create("glob1", "Global")
    model.result("pg_soc_ocv").feature("glob1").label("各电池包SOC与开路电压")
    model.result("pg_soc_ocv").feature("glob1").set(
        "expr",
        ["SOC_pack1", "SOC_pack2", "SOC_pack3", "E_ocv_pack1", "E_ocv_pack2", "E_ocv_pack3"],
    )
    model.result("pg_soc_ocv").feature("glob1").set("unit", ["1", "1", "1", "V", "V", "V"])

    result.create("pg_heat", "PlotGroup1D")
    model.result("pg_heat").label("电池温度与发热功率")
    model.result("pg_heat").set("xlabel", "时间 (s)")
    model.result("pg_heat").feature().create("glob1", "Global")
    model.result("pg_heat").feature("glob1").label("温度、温升速率与总发热")
    model.result("pg_heat").feature("glob1").set(
        "expr",
        [
            "T_pack1",
            "T_pack2",
            "T_pack3",
            "T_pack_avg",
            "dTdt_pack1",
            "dTdt_pack2",
            "dTdt_pack3",
            "P_bat_total",
        ],
    )
    model.result("pg_heat").feature("glob1").set(
        "unit", ["degC", "degC", "degC", "degC", "K/min", "K/min", "K/min", "W"]
    )

    result.create("pg_power", "PlotGroup1D")
    model.result("pg_power").label("功率与能量累计")
    model.result("pg_power").set("xlabel", "时间 (s)")
    model.result("pg_power").feature().create("glob1", "Global")
    model.result("pg_power").feature("glob1").label("电池发热、电机损耗、控制器损耗和能量累计")
    model.result("pg_power").feature("glob1").set(
        "expr",
        [
            "P_bat_total",
            "P_motor_total",
            "P_ctrl_total",
            "timeint(0,t,P_bat_total)",
            "timeint(0,t,P_motor_total)",
            "timeint(0,t,P_ctrl_total)",
        ],
    )
    model.result("pg_power").feature("glob1").set("unit", ["W", "W", "W", "J", "J", "J"])

    result.create("pg_limits", "PlotGroup1D")
    model.result("pg_limits").label("电流边界与安全标志")
    model.result("pg_limits").set("xlabel", "时间 (s)")
    model.result("pg_limits").feature().create("glob1", "Global")
    model.result("pg_limits").feature("glob1").label("电机/电池/母线/析锂风险参考标志")
    model.result("pg_limits").feature("glob1").set(
        "expr",
        [
            "motor1_peak_over",
            "motor2_peak_over",
            "pack1_peak_ref_over",
            "pack2_peak_ref_over",
            "pack3_peak_ref_over",
            "bus_voltage_over",
            "pack1_plating_risk",
            "pack2_plating_risk",
            "pack3_plating_risk",
            "safety_risk_count",
        ],
    )
    model.result("pg_limits").feature("glob1").set(
        "unit", ["1", "1", "1", "1", "1", "1", "1", "1", "1", "1"]
    )


def build_model(client: mph.Client) -> mph.Model:
    model = client.create("multi_pack_dual_motor_pulse_heating")
    java = model.java
    java.label("多并联电池包-双电机-双控制器脉冲加热模型")
    java.modelPath(str(ROOT))
    java.component().create("comp1", True)
    comp = java.component("comp1")
    comp.label("组件：三电池包并联母线与双电机控制器")

    set_parameters(java)
    create_lumped_thermal_interface(comp)
    create_circuit(comp)
    create_variables(comp)
    create_study(java)
    create_results(java)

    java.description(
        "第一版COMSOL多并联电池包-双电机-双控制器脉冲加热模型。"
        "固定建成最多三个并联电池包和两套电机控制器支路, 通过pack*_enable、"
        "motor*_enable、frequency、duty、phase和pulse_amp_scale参数切换方案。"
        "析锂只作为待标定风险标志展示, 不作为自动降额硬限制。"
        "当前参数为3806/0528经验占位口径, 仅用于架构粗筛和模型接口验证。"
    )
    return model


def apply_scenario(model: mph.Model, scenario: str) -> None:
    if scenario not in SCENARIOS:
        allowed = ", ".join(sorted(SCENARIOS))
        raise ValueError(f"Unknown scenario {scenario!r}. Allowed: {allowed}.")
    for name, value in SCENARIOS[scenario].items():
        model.parameter(name, value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--scenario",
        default="dual_branch_sync",
        choices=sorted(SCENARIOS),
        help="Initial parameter preset saved into the model.",
    )
    parser.add_argument(
        "--no-solve",
        action="store_true",
        help="Create and save the model without running the default time-dependent study.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    client = connect()
    model = build_model(client)
    try:
        apply_scenario(model, args.scenario)
        if not args.no_solve:
            model.java.study("std1").run()
        model.save(MODEL_PATH)
        print(f"COMSOL model saved: {MODEL_PATH}")
        print(f"Initial scenario: {args.scenario}")
        print("No CSV, summary, scan table, MAT or PNG files were written.")
    finally:
        safe_remove(client, model)


if __name__ == "__main__":
    main()
