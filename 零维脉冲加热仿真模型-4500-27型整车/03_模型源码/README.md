# 模型源码说明

## 当前主入口

```matlab
run_4500_27_pulse_heating_screening
```

该入口用于4500-27型整车更新参数下的实车约束方案评估。

当前方案边界：

- 三包并联整体输出，单电机脉冲；
- 三包并联整体输出，双电机脉冲。

不再把单包独立接入电驱作为4500-27工程方案。

## 输出

当前入口会生成MATLAB图窗，并把结果写出到：

```text
../05_仿真结果/4500_27_screening/
```

包括：

- `4500_27_summary.csv`
- `4500_27_scan_results.csv`
- `4500_27_fig01.png`
- `4500_27_fig02.png`
- `4500_27_fig03.png`

## 历史入口

以下入口保留用于早期0528双支路/三支路通用架构回溯：

```matlab
run_dual_branch_pulse_heating
run_triple_branch_pulse_heating
run_0528_pulse_heating_screening
```

历史入口读取 `build_0528_pulse_heating_params.m` 和 `build_0528_study_cases.m`，不作为当前4500-27实车约束结论的主依据。

## 模块结构

- `core/`：拓扑定义、电路工作点、热平衡、损耗和求解器。
- `limits/`：电流限制和安全限制接口。
- `plot/`：命令行摘要和MATLAB图窗显示。

## 使用边界

当前模型是零维集总粗筛模型，用于判断温升量级、能耗、电流压力和方案排序。

该模型不能证明：

- BMS允许高频低温回充半周；
- MCU一定支持驻车零速高频电流闭环；
- 电机退磁、NVH和寿命满足要求；
- 逆变器结温和器件寿命满足要求；
- 整车最终安全可行。
