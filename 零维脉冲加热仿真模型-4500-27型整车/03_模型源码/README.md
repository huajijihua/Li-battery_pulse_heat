# 4500-27模型源码说明

## 主入口

```matlab
run_4500_27_pulse_heating_screening
```

该入口用于 4500-27 型整车更新参数下的实车约束方案评估。

当前方案边界：

- 三包并联整体输出，单电机脉冲；
- 三包并联整体输出，双电机脉冲。

## 模块结构

- `build_4500_27_study_cases.m`：当前仿真工况和扫描范围。
- `core/define_pulse_topology.m`：4500-27 当前实车接入拓扑。
- `core/eval_circuit_operating_point.m`：单点电气、损耗、热和边界计算。
- `core/solve_pulse_heating_case.m`：全量扫描、默认瞬态和敏感性汇总。
- `limits/`：电流硬限制和安全参考边界。
- `plot/`：命令行摘要和报告图绘制。

## 输出

主入口会生成 MATLAB 图窗，并把当前结果写出到：

```text
../05_仿真结果/4500_27_screening/
```

包括：

- `4500_27_summary.csv`
- `4500_27_scan_results.csv`
- `4500_27_sensitivity_summary.csv`
- `4500_27_fig01.png`
- `4500_27_fig02.png`
- `4500_27_fig03.png`

## 使用边界

当前模型是零维集总粗筛模型，用于判断温升量级、能耗、电流压力和方案排序。

该模型不能证明：

- BMS 允许高频低温回充半周；
- MCU 一定支持驻车零速高频电流闭环；
- 电机退磁、NVH 和寿命满足要求；
- 逆变器结温和器件寿命满足要求；
- 整车最终安全可行。
