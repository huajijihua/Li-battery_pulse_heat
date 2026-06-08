# COMSOL 多并联电池包-双电机脉冲加热模型

本目录用于生成可在 COMSOL Desktop 内交互运行的“多并联电池包 + 双电机 + 双控制器”脉冲加热模型。

## 当前正式模型

正式构建脚本：

```powershell
python .\build_multi_pack_dual_motor_pulse_heating_comsol.py
```

默认输出：

- `multi_pack_dual_motor_pulse_heating.mph`

脚本只保存正式 `.mph`，不再导出 CSV、summary、扫描表、MAT 或 PNG 结果文件。

## 运行前提

确认 COMSOL Server 已在 `localhost:2036` 运行。若端口不同，可先设置环境变量 `COMSOL_PORT`。

自动建模和保存阶段建议只保留 COMSOL Server，不要同时打开连接到同一端口的 COMSOL Desktop 客户端，避免保存时出现文件锁定或 Server 被其他客户端占用。

## 模型结构

- 电路拓扑固定为最多 3 个并联电池包和 2 套电机控制器支路。
- 每个电池包支路包含 OCV、电池内阻、等效支路开关、SOC 积分、独立热容、内阻发热和对流散热。
- 每套电机控制器支路采用等效脉冲源 + 电机等效电感 + 电机等效电阻，不展开完整三相六桥臂。
- 安全限制在 COMSOL 内以变量和图组显示，包括电池电流参考超限、电机/控制器电流超限、母线电压参考越界和析锂风险电流幅值参考标志。
- 析锂风险当前只作为待标定参考标志，不作为自动降额硬限制。

## 内置方案参数

默认保存为“双支路同步”工况。也可以在生成时指定初始参数预设：

```powershell
python .\build_multi_pack_dual_motor_pulse_heating_comsol.py --scenario dual_branch_sync
python .\build_multi_pack_dual_motor_pulse_heating_comsol.py --scenario triple_branch_sync
python .\build_multi_pack_dual_motor_pulse_heating_comsol.py --scenario single_motor_single_pack
python .\build_multi_pack_dual_motor_pulse_heating_comsol.py --scenario dual_motor_focus_pack
```

在 COMSOL Desktop 中也可以直接修改以下参数切换方案：

| 参数 | 含义 |
|---|---|
| `pack1_enable`、`pack2_enable`、`pack3_enable` | 电池包是否参与，1 为参与，0 为断开 |
| `motor1_enable`、`motor2_enable` | 电机控制器支路是否参与，1 为参与，0 为断开 |
| `focus_pack_index` | 集中加热目标包编号，用于目标包变量显示 |
| `f_pulse` | 脉冲频率，默认 1250 Hz |
| `duty` | 占空比，默认 0.50 |
| `phase_m1`、`phase_m2` | 两套控制器相位，单位为一个周期的比例 |
| `pulse_amp_scale` | 脉冲电压幅值系数 |

四类方案的默认开关组合：

| 方案 | 电池包 | 电机控制器 |
|---|---|---|
| 双支路电池，双电机整体同步脉冲 | pack1、pack2 | motor1、motor2 |
| 三支路电池，双电机整体同步脉冲 | pack1、pack2、pack3 | motor1、motor2 |
| 单电机给单支路脉冲 | pack1 | motor1 |
| 双电机集中给单支路脉冲 | pack1 | motor1、motor2 |

## 默认参数口径

- 初始温度：`-20 degC`
- 初始 SOC：`50%`
- 默认频率：`1250 Hz`
- 默认占空比：`0.50`
- 单个电池包：`192S1P`、`324 Ah`
- 电机/控制器参考限制：`550 Arms`、`778 Apeak`

这些参数沿用当前 3806/0528 经验占位口径，只用于架构粗筛和模型接口验证，不作为目标车型最终定量结论。收到真实电池包、电机、控制器和高压盒参数后，应先更新 COMSOL 参数，再重新运行工况。

## 结果查看

生成的 `.mph` 内部已建立基础图组：

- 支路电流与母线电流
- SOC 与 OCV
- 电池温度与发热功率
- 功率与能量累计
- 电流边界与安全标志

在 COMSOL Desktop 中打开 `multi_pack_dual_motor_pulse_heating.mph` 后，可直接运行 `默认瞬态脉冲加热工况` 并查看上述图组。

## 历史原型

以下文件保留为单支路原型和历史验证记录，不作为当前正式交付主线：

- `build_single_branch_pulse_heating_comsol.py`
- `single_branch_pulse_heating_lts_units_ocv_circuit.mph`
- `single_branch_pulse_heating_default_summary.csv`
- `single_branch_frequency_duty_scan.csv`
