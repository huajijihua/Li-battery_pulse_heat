"""Build a COMSOL single-branch pulse-heating prototype via Python.

This script connects to a running COMSOL Multiphysics Server and creates a
single battery-branch / single motor / single controller prototype.  The
battery is represented by the Electrical Circuit interface's Battery Open
Circuit Voltage element, so a separate Lumped Battery physics interface is not
required for this first interface-validation model.  The branch temperature is
solved by the Lumped Thermal System interface's own thermal-mass dependent
variable.
"""

from __future__ import annotations

import csv
import math
import os
from pathlib import Path

import mph
import numpy as np


ROOT = Path(__file__).resolve().parent
MODEL_PATH = ROOT / "single_branch_pulse_heating_lts_units_ocv_circuit.mph"
SUMMARY_CSV = ROOT / "single_branch_pulse_heating_default_summary.csv"
SCAN_CSV = ROOT / "single_branch_frequency_duty_scan.csv"


def connect(port: int | None = None) -> mph.Client:
    """连接已启动的 COMSOL Server。"""
    if port is None:
        port = int(os.environ.get("COMSOL_PORT", "2036"))
    return mph.Client(port=port, host="localhost")


def safe_remove(client: mph.Client, model: mph.Model) -> None:
    try:
        client.remove(model)
    except Exception:
        pass


def np_last(value: object) -> float:
    arr = np.asarray(value, dtype=float)
    return float(arr.reshape(-1)[-1])


def np_max_abs(value: object) -> float:
    arr = np.asarray(value, dtype=float)
    return float(np.max(np.abs(arr)))


def np_rms(value: object) -> float:
    arr = np.asarray(value, dtype=float).reshape(-1)
    return float(math.sqrt(np.mean(arr * arr)))


def evaluate(model: mph.Model, expression: str, unit: str) -> object:
    return model.evaluate(expression, unit=unit)


def set_parameters(model) -> None:
    p = model.param()
    p.set("N_series", "192", "单支路串联单体数")
    p.set("C_branch", "324[A*h]", "单支路容量")
    p.set("SOC0", "0.50", "初始SOC")
    p.set("T_init", "253.15[K]", "初始支路温度，-20摄氏度")
    p.set("T_amb", "253.15[K]", "环境温度，-20摄氏度")
    p.set("R_branch", "0.397[ohm]", "单支路低温内阻")
    p.set("L_motor", "0.26[mH]", "电机等效d轴电感")
    p.set("R_motor", "0.020[ohm]", "电机等效绕组电阻")
    p.set("Cth_branch", "1244e3[J/K]", "电池支路集总热容")
    p.set("A_branch", "9[m^2]", "电池支路换热面积")
    p.set("h_conv", "8[W/(m^2*K)]", "对流换热系数")
    p.set("Rth_branch", "1/(h_conv*A_branch)", "支路到环境等效热阻")
    p.set("f_pulse", "1250[Hz]", "默认脉冲频率")
    p.set("duty", "0.50", "默认占空比")
    p.set("cycles_solve", "8", "接口验证求解周期数")
    p.set("steps_per_cycle", "40", "每个脉冲周期输出点数")
    p.set("Vdrive_amp", "2*N_series*3.32[V]", "脉冲电压源高低电平幅值")
    p.set("Vdrive_offset", "-N_series*3.32[V]", "脉冲电压源偏置")
    p.set("tr_pulse", "1e-6[s]", "脉冲上升时间")
    p.set("tf_pulse", "1e-6[s]", "脉冲下降时间")
    p.set("I_motor_rms_limit", "550[A]", "电机/控制器RMS电流参考边界")
    p.set("I_motor_peak_limit", "778[A]", "电机/控制器峰值电流参考边界")


def create_circuit(comp) -> None:
    comp.physics().create("cir", "Circuit")
    cir = comp.physics("cir")
    cir.label("电路：OCV电池支路-电机-控制器")
    cir.feature("gnd1").label("电路参考地")

    cir.create("OCV1", "BatteryOpenCircuitVoltage")
    ocv = cir.feature("OCV1")
    ocv.label("电池支路开路电压")
    ocv.set("Connections", ["1", "0"])
    ocv.set("Q_cell0", "C_branch")
    ocv.set("SOC_cell0", "SOC0")
    ocv.set("Temp", "comp1.lts.T_bat")
    ocv.set("Tref", "298.15[K]")
    ocv.set("SOC_Eocv", [0.10, 0.20, 0.50, 0.90])
    ocv.set(
        "Eocv",
        [
            f"{192 * 3.18}[V]",
            f"{192 * 3.24}[V]",
            f"{192 * 3.32}[V]",
            f"{192 * 3.42}[V]",
        ],
    )
    ocv.set("SOC_dEocvdT", [0.10, 0.90])
    ocv.set("dEocvdT", ["0[V/K]", "0[V/K]"])

    cir.create("Rbat", "Resistor")
    rbat = cir.feature("Rbat")
    rbat.label("电池支路内阻")
    rbat.set("Connections", ["1", "2"])
    rbat.set("R", "R_branch")

    cir.create("Lmot", "Inductor")
    lmot = cir.feature("Lmot")
    lmot.label("电机等效电感")
    lmot.set("Connections", ["2", "3"])
    lmot.set("L", "L_motor")
    lmot.set("i", "0[A]")

    cir.create("Rmot", "Resistor")
    rmot = cir.feature("Rmot")
    rmot.label("电机等效绕组电阻")
    rmot.set("Connections", ["3", "4"])
    rmot.set("R", "R_motor")

    cir.create("Vdrv", "VoltageSource")
    vdrv = cir.feature("Vdrv")
    vdrv.label("控制器等效脉冲电压源")
    vdrv.set("Connections", ["4", "0"])
    vdrv.set("sourceType", "PulseSource")
    vdrv.set("value", "Vdrive_amp")
    vdrv.set("offset", "Vdrive_offset")
    vdrv.set("td", "0[s]")
    vdrv.set("tr", "tr_pulse")
    vdrv.set("tf", "tf_pulse")
    vdrv.set("pw", "duty/f_pulse")
    vdrv.set("Tper", "1/f_pulse")


def create_lumped_thermal_interface(comp) -> None:
    comp.physics().create("lts", "LumpedThermalSystem")
    lts = comp.physics("lts")
    lts.label("集总热系统：电池支路温升")

    lts.create("tm1", "ThermalMass")
    tm = lts.feature("tm1")
    tm.label("电池支路热容")
    tm.set("Connections", ["bat"])
    tm.set("inputType", "ThermalCapacitance")
    tm.set("C", "Cth_branch")
    tm.set("Ti", "T_init")
    tm.set("includeTemperature", True)

    lts.create("qsrc1", "HeatRateNode")
    qsrc = lts.feature("qsrc1")
    qsrc.label("电池内阻发热")
    qsrc.set("Connections", ["bat"])
    qsrc.set("inputType", "HeatRate")
    qsrc.set("P0", "P_bat_ohmic")
    qsrc.set("T_init", "T_init")
    qsrc.set("includeTemperature", True)

    lts.create("conv1", "HeatRateNode")
    conv = lts.feature("conv1")
    conv.label("电池支路对流散热")
    conv.set("Connections", ["bat"])
    conv.set("inputType", "ConvectiveHeatRate")
    conv.set("A", "A_branch")
    conv.set("HeatTransferCoefficientType", "UserDef")
    conv.set("h", "h_conv")
    conv.set("Text", "T_amb")
    conv.set("T_init", "T_init")
    conv.set("includeTemperature", True)


def create_variables(comp) -> None:
    comp.variable().create("var1")
    var = comp.variable("var1")
    var.label("脉冲加热接口变量")
    var.set("I_branch", "cir.Rbat.i", "电池支路电流")
    var.set("I_motor", "cir.Rmot.i", "电机等效电流")
    var.set("P_bat_ohmic", "cir.Rbat.i^2*R_branch", "电池支路内阻发热")
    var.set("P_motor_cu", "cir.Rmot.i^2*R_motor", "电机等效铜耗")
    var.set("P_heat_loss", "(lts.T_bat-T_amb)/Rth_branch", "支路对流散热功率")
    var.set("P_net_battery", "P_bat_ohmic-P_heat_loss", "电池净加热功率")
    var.set("dTdt_branch", "P_net_battery/Cth_branch", "电池温升速率，可按 K/s 或 K/min 显示")
    var.set("T_branch", "lts.T_bat", "电池支路温度")
    var.set("SOC_branch", "cir.OCV1.SOC", "OCV元件积分得到的支路SOC")
    var.set("E_ocv_branch", "cir.OCV1.E_OCV", "支路开路电压")
    var.set("motor_rms_margin_ref", "I_motor_rms_limit/(sqrt(cir.Rmot.i^2)+1e-12[A])", "瞬时电流相对RMS参考边界的比例")
    var.set("motor_peak_margin_ref", "I_motor_peak_limit/(abs(cir.Rmot.i)+1e-12[A])", "瞬时电流相对峰值参考边界的比例")


def create_results(model) -> None:
    result = model.result()
    result.create("pg_curr", "PlotGroup1D")
    model.result("pg_curr").label("电流与SOC")
    model.result("pg_curr").set("xlabel", "时间 (s)")
    model.result("pg_curr").set("ylabel", "电流 / SOC")
    model.result("pg_curr").feature().create("glob1", "Global")
    model.result("pg_curr").feature("glob1").label("支路电流与SOC")
    model.result("pg_curr").feature("glob1").set("expr", ["I_branch", "SOC_branch"])
    model.result("pg_curr").feature("glob1").set("unit", ["A", "1"])

    result.create("pg_heat", "PlotGroup1D")
    model.result("pg_heat").label("电池支路热响应")
    model.result("pg_heat").set("xlabel", "时间 (s)")
    model.result("pg_heat").set("ylabel", "温度 / 功率")
    model.result("pg_heat").feature().create("glob1", "Global")
    model.result("pg_heat").feature("glob1").label("温度与发热功率")
    model.result("pg_heat").feature("glob1").set(
        "expr", ["T_branch", "P_bat_ohmic", "P_motor_cu", "P_heat_loss"]
    )
    model.result("pg_heat").feature("glob1").set("unit", ["degC", "W", "W", "W"])


def create_study(model) -> None:
    study = model.study()
    study.create("std1")
    model.study("std1").label("默认瞬态工况")
    model.study("std1").create("time", "Transient")
    time = model.study("std1").feature("time")
    time.label("瞬态求解")
    time.set("tlist", "range(0,1/(f_pulse*steps_per_cycle),cycles_solve/f_pulse)")
    time.set("usertol", True)
    time.set("rtol", "1e-4")
    time.setSolveFor("/physics/cir", True)
    time.setSolveFor("/physics/lts", True)


def build_model(client: mph.Client) -> mph.Model:
    model = client.create("single_branch_pulse_heating_lts_ocv_circuit")
    java = model.java
    java.label("单支路脉冲加热模型：OCV电路与集总热")
    java.modelPath(str(ROOT))
    java.component().create("comp1", True)
    comp = java.component("comp1")
    comp.label("组件：单支路电池-电机-控制器")

    set_parameters(java)
    create_circuit(comp)
    create_lumped_thermal_interface(comp)
    create_variables(comp)
    create_study(java)
    create_results(java)

    java.description(
        "单支路脉冲加热原型模型。电池采用电路物理场中的开路电压元件表示，"
        "串联电池支路内阻、电机等效电感/电阻和控制器等效脉冲电压源。"
        "电池温度由集总热系统中的电池支路热容节点求解，内阻发热和对流散热"
        "也放在集总热系统内，用于当前阶段的接口打通和数量级验证。"
    )
    return model


def evaluate_default(model: mph.Model) -> dict[str, float]:
    values = {
        "I_branch_rms_A": np_rms(evaluate(model, "I_branch", "A")),
        "I_branch_peak_A": np_max_abs(evaluate(model, "I_branch", "A")),
        "I_motor_rms_A": np_rms(evaluate(model, "I_motor", "A")),
        "I_motor_peak_A": np_max_abs(evaluate(model, "I_motor", "A")),
        "SOC_end": np_last(evaluate(model, "SOC_branch", "1")),
        "E_ocv_end_V": np_last(evaluate(model, "E_ocv_branch", "V")),
        "T_end_C": np_last(evaluate(model, "T_branch", "degC")),
        "P_bat_ohmic_end_W": np_last(evaluate(model, "P_bat_ohmic", "W")),
        "P_motor_cu_end_W": np_last(evaluate(model, "P_motor_cu", "W")),
        "dTdt_end_C_per_min": np_last(evaluate(model, "dTdt_branch", "K/min")),
    }
    values["motor_rms_margin_ref"] = 550.0 / max(values["I_motor_rms_A"], 1e-12)
    values["motor_peak_margin_ref"] = 778.0 / max(values["I_motor_peak_A"], 1e-12)
    return values


def write_summary(row: dict[str, float]) -> None:
    with SUMMARY_CSV.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=list(row.keys()))
        writer.writeheader()
        writer.writerow(row)


def run_scan(model: mph.Model) -> list[dict[str, float]]:
    rows: list[dict[str, float]] = []
    for freq in [500, 800, 1000, 1250, 1500, 2000]:
        for duty in [0.4, 0.5, 0.6]:
            model.parameter("f_pulse", f"{freq}[Hz]")
            model.parameter("duty", f"{duty}")
            model.java.study("std1").run()
            row = evaluate_default(model)
            row["frequency_Hz"] = freq
            row["duty"] = duty
            rows.append(row)
    fields = ["frequency_Hz", "duty"] + [
        k for k in rows[0].keys() if k not in {"frequency_Hz", "duty"}
    ]
    with SCAN_CSV.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    return rows


def main() -> None:
    client = connect()
    model = build_model(client)
    try:
        model.java.study("std1").run()
        default_row = evaluate_default(model)
        write_summary(default_row)
        run_scan(model)

        model.parameter("f_pulse", "1250[Hz]")
        model.parameter("duty", "0.50")
        model.java.study("std1").run()
        model.save(MODEL_PATH)

        print(f"COMSOL model saved: {MODEL_PATH}")
        print(f"Default summary saved: {SUMMARY_CSV}")
        print(f"Frequency/duty scan saved: {SCAN_CSV}")
        print(
            "Default result: "
            f"I_rms={default_row['I_branch_rms_A']:.3f} A, "
            f"I_peak={default_row['I_branch_peak_A']:.3f} A, "
            f"T_end={default_row['T_end_C']:.6f} degC, "
            f"SOC_end={default_row['SOC_end']:.8f}"
        )
    finally:
        safe_remove(client, model)


if __name__ == "__main__":
    main()
