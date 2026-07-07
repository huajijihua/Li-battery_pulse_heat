# Simscape 脉冲加热材料池与模型候选比较 v01

日期：2026-07-06
阶段：材料池盘点、功能比较、可复用性判断。
范围：MATLAB/Simulink/Simscape 优先；不生成或修改 .slx；AMESim 仅作为后续不足时的备选。
工具：OpenCode 专属 MATLAB MCP（R2025b），load_system+find_system 只读盘点，未打开任何 .slx 模型。

本文件只回答"有哪些成熟材料、候选模型和可复用组件"。通用模型规格、接口契约、实施路线在后续文档中单独定义。

## 1. 结论先行

脉冲加热新一代模型应走 **Simscape-first** 路线，以本机 Simscape 物理网络为主骨架，不继续以 L0.5 零维 MATLAB 函数模型为主骨架。理由：

1. 本机 R2025b 已装 Simscape Battery、Simscape Electrical、Motor Control Blockset、Powertrain Blockset，电池 ECM + 热模型 + 逆变器 + PMSM + FOC + SVPWM 全链路组件齐备。
2. 电池侧优先采用 Simscape Battery 的 Battery Equivalent Circuit + thermalLumpedMass + coolingPlate，热电耦合在 Simscape 物理网络内闭合。
3. 电驱侧优先采用 Simscape Electrical 的 PMSM、IGBT/MOSFET 逆变器、FOC Controller、SVPWM Generator；需要 mapped 损耗时用 Powertrain Blockset 的 mapped motor/inverter。
4. 控制链优先参考 Motor Control Blockset 的 FOC、死区补偿、电流环和参数估计块。
5. 旧 L0.5 零维模型只保留为参数、边界、KPI 口径和方程来源参考，不作为新模型物理核心。

**数据策略**：现有 4500-27 测试数据很少，不作为建模前提。先用官方示例参数、文献范围、工程默认和占位假设把通用模型结构和物质流走通，把数据缺口标出来；模型成立后再向实验人员索取详细数据。这与 PEMFC 项目的 Core Model 思路一致——通用模型体系优先，数据只用来走通流程和 sanity check。

暂不进入 AMESim。触发条件见第 7 节。

## 2. 已确认材料池

### 2.1 本机 Simscape 库（B1-B10）

| 编号 | 材料 | 本地路径 | 初步价值 |
|---|---|---|---|
| B1 | Simscape Battery batt_lib.slx | battery/library/m/ | 最高。Battery ECM/Table-Based/Thermal(Edge/Parallel/U-shaped)/Cyclers/HIL |
| B2 | +batt/+cells/*.ssc 源码 | battery/library/m/+batt/ | 最高。batteryEquivalentCircuit/thermalLumpedMass/SPM/老化/coolingPlate |
| B3 | batteryecm_lib.slx | battery/shared_library/m/ | 高。独立 ECM 块 |
| B4 | hppcTestHarness.slx | battery/parameterization/m/models/ | 高。HPPC 参数辨识参考 |
| B5 | Simscape Battery SLI 库 | battery/sli/m/ | 中。ThermalMgmt/CurrentMgmt/Protection/Estimators/Balancing |
| B6 | Simscape Electrical ee_lib.slx | elec/library/m/ | 最高。Electromechanical/Semiconductors&Converters/Sources/Passive/Sensors |
| B7 | Simscape Electrical sps*Lib 系列 | elec/assistant/m/transform/ | 最高。PMSM/FOC/SVPWM/IGBT/Inverter/ControlledSource/ClarkePark/Battery |
| B8 | electricdrivelib.slx | elec/assistant/m/transform/ | 高。电驱系统组织参考 |
| B9 | Powertrain Blockset autolib* | autoblks/ | 高。mappedmotor/inverter/fluxpmsm/pmsminterior/exterior/datasheetbattery |
| B10 | Motor Control Blockset mcb*lib | mcb/mcbblocks/ | 高。foc/deadtimecomp/plant/controls/pmsmparamest/sensorless/pll |

注：以上路径均位于 D:/matlab2025b/toolbox/physmod/ 或 D:/matlab2025b/toolbox/ 下。

### 2.2 GitHub 官方模型与现有资产（B11-B23）

| 编号 | 材料 | 来源 | 初步价值 |
|---|---|---|---|
| B11 | Simscape-Battery-Electric-Vehicle-Model (151星) | GitHub mathworks, branch=R2025b | 最高。BEV 完整电驱链路 |
| B12 | Battery-Pack-Model-Simscape (124星) | GitHub mathworks | 最高。电池包热管理串并联，对应三包并联 |
| B13 | Design-motor-controllers-with-Simscape-Electrical (275星) | GitHub mathworks + 视频 | 最高。FOC/SVPWM/电流环完整实现 |
| B14 | Battery-Model-Parameter-Estimation-Using-Impedance-Data (12星) | GitHub mathworks | 高。EIS 阻抗参数估计，对应 Re(Z,T,SOC,f) |
| B15 | pmsm-drive-optimization (32星) | GitHub mathworks | 中高。PMSM 效率与损耗 |
| B16 | import-motorcad-thermal-simulink (16星) | GitHub mathworks | 中。Motor-CAD 热模型导入 |
| B17 | Battery-Electric-Vehicle-Motor-Cooling-Simscape (15星) | GitHub mathworks | 中。液冷电机热管理 |
| B18 | EV-with-MATLAB-and-Simulink (42星) | GitHub mathworks | 中。battery/power-electronics/thermal 资源索引 |
| B19 | vehicle-modeling (33星) | GitHub mathworks | 中。Powertrain Blockset 建模 |
| B20 | battery-modeling-solutions-with-simscape (6星) | GitHub mathworks | 中。ECM 参数估计/包建模/均衡 |
| B21 | 现有 L0.5 零维模型 | 项目自研，历史资产 | 中。参数/KPI/边界/方程参考，不作为物理核心 |
| B22 | 4500-27 参数表与规格书 | 项目参数证据链 | 中高。3包并联/811V/CAM255PT56/BC5_324Ah |
| B23 | 文献依据资料 21篇论文专利 | 项目文献证据链 | 高。FOC/SVPWM/频域热源/析锂/电驱加热案例 |

GitHub 仓库链接见第 8 节。

## 3. 关键候选模型比较

| 候选 | 架构性质 | 电热耦合 | 对脉冲加热适配性 | 取舍 |
|---|---|---|---|---|
| Simscape Battery Battery Equivalent Circuit | Simscape ECM 物理网络 | 内阻热+热端口+RC动态 | 强。Q=I2R 自动传入热模型，可升级 Re(Z,f) | 推荐电池主骨架 |
| Simscape Battery Battery (Table-Based) | 表格化 ECM | OCV/R 随 T/SOC 表格 | 强。适合有 HPPC 数据后参数化 | 备选电池块 |
| Simscape Electrical PMSM + 逆变器 | Simscape 物理网络 | 绕组铜耗+逆变器损耗 | 强。堵转 RL + FOC + SVPWM 全链路 | 推荐电驱主骨架 |
| Powertrain Blockset mapped motor/inverter | mapped 查表 | 损耗 map | 中。系统级快速仿真，但高频堵转可能超 map 范围 | 损耗参考或粗筛 |
| Motor Control Blockset FOC/死区/电流环 | 控制库块 | 不含热 | 强。电流环、死区、调制限制是 L1 核心 | 推荐控制层 |
| L0.5 零维 MATLAB 函数 | 信号流脚本 | 解析公式 | 弱。无物理端口、无热电耦合 | 只做基准参考 |
| GitHub BEV Model (B11) | 完整车载 Simscape | 完整 | 中高。电驱链路完整，需剥离行驶工况聚焦堵转 | 主参考骨架 |
| GitHub Battery-Pack-Model (B12) | 电池包热管理 | 完整热 | 强。串并联+冷却板，对应三包并联 | 电池包主参考 |
| GitHub Motor-Controllers (B13) | 电机控制器 | 控制层 | 强。FOC/SVPWM/电流环完整 | 控制层主参考 |
| GitHub Impedance-Estimation (B14) | EIS 参数估计 | 辨识流程 | 强。Re(Z,f) 升级路径 | 参数化参考 |

## 4. 设备级取舍矩阵

### 4.1 电池与热管理

| 设备/功能 | 推荐来源 | 备选来源 | 物理内核关注点 | 取舍 |
|---|---|---|---|---|
| 电池电芯 ECM | batt_lib/Cells/Battery Equivalent Circuit (B1/B2) | batteryecm_lib/Battery (B3)；Battery(Table-Based) | OCV、R0、R1C1/R2C2、T/SOC 依赖、热端口 | 第一版用 ECM+默认参数跑通；有 HPPC/EIS 后参数化 |
| 电池热模型 | batt_lib/Thermal + thermalLumpedMass.ssc (B2) | thermalHeightDistributedMass；coolingPlate 系列 | 集总热容、散热系数、冷却板连接 | 第一版集总热质量+弱对流边界 |
| 电池包拓扑 | Battery Pack Model Builder (B1文档) + GitHub B12 | 手工搭三包并联 | 串并联、均流、支路电流 | 三包并联整体输出，参考 B12 |
| HPPC/EIS 参数化 | hppcTestHarness.slx (B4) + GitHub B14 | Battery Parameter Estimation 文档 | R0/R1/R2 辨识、Re(Z,f) 频域 | 先用默认/文献值；有数据后用 B4/B14 |
| 冷却/散热 | batt_lib/Thermal coolingPlate 系列 (B1) | Simscape Fluids/Thermal Liquid | 冷却板、液冷、环境散热 | 第一版简化热边界，预留冷却接口 |

### 4.2 电驱与控制

| 设备/功能 | 推荐来源 | 备选来源 | 物理内核关注点 | 取舍 |
|---|---|---|---|---|
| 逆变器(开关级) | ee_lib/Semiconductors IGBT/MOSFET (B6) | spsIGBTLib/spsUniversalBridgeLib (B7) | 导通/开关损耗、死区、结温 | 需波形细节时用开关级 |
| 逆变器(平均值) | spsInverterThreePhaseLib/spsTwoLevelConverterLib (B7) | Powertrain autolibinverter (B9) | 调制比、电压饱和、损耗 map | 策略筛选阶段优先用平均值 |
| PMSM 电机 | ee_lib/Electromechanical PMSM (B6) | spsPermanentMagnetSynchronousMachineLib (B7)；autolibfluxpmsm (B9) | Ld/Lq/Rs/磁链、堵转 RL、转矩 | 堵转脉冲用 RL 简化或完整 PMSM |
| FOC 控制器 | mcbfoclib (B10) + spsFieldOrientedControllerLib (B7) | GitHub B13 | Clarke/Park、电流环 PI、抗饱和 | 直接复用 MCB FOC 块 |
| SVPWM/PWM | spsSVPWMGenerator2LevelLib (B7) + mcbcontrolslib (B10) | spsPWMGenerator2LevelLib | 调制比、最小脉宽、死区 | 第一版 SVPWM 2-level |
| 死区/最小脉宽 | mcbdeadtimecomplib (B10) | 手工补偿 | 死区时间、最小脉宽限制 | L1 电流可实现性必备 |
| Clarke/Park 变换 | spsabctodq0Lib/spsdq0toabcLib (B7) | MCB 内置 | 坐标变换 | 直接复用 |
| 受控脉冲源 | spsControlledCurrentSourceLib/spsControlledVoltageSourceLib (B7) | ee_lib/Sources | 电流/电压命令注入 | 控制接口与测试用 |
| 母线/DC-link | ee_lib/Passive RLC + 电容 | sps 系列 | 母线电容、纹波 | 第一版简化 DC-link |
| 传感器 | ee_lib/Sensors + sps*MeasurementLib (B6/B7) | BMS SLI 库 (B5) | 电压/电流/温度/SOC | 直接复用 |
| 电机热模型 | GitHub B16/B17 | 集总热质量 | 绕组温升、结温 | 第一版绕组热质量+散热 |

## 5. 本机库深入盘点

盘点日期：2026-07-06。工具：MATLAB MCP evaluate_matlab_code，load_system+find_system 只读查询。未打开任何 .slx 模型，未运行仿真，未干扰其他 MATLAB session。

### 5.1 Simscape Battery（batt_lib）

库文件：batt_lib.slx

顶层块：
- Cells：Battery、Battery (Table-Based)、Battery Equivalent Circuit、Electrochemical、Fuel Cell Equivalent Circuit
- Connectors：Array of Electrical Nodes Connector
- Cyclers：Charger、Cycler、Discharger
- HIL：Active Interface、Passive Balancing Interface、Passive Interface
- Thermal：Array of Thermal Nodes Connector、Edge Cooling、Parallel Channels、U-shaped Channels

ssc 源码关键组件（+batt/+cells/）：
- batteryEquivalentCircuit.ssc：ECM 核心，含 OCV、R0、RC 网络、热端口、T/SOC 依赖
- batteryRCEquivalentCircuitTableBased.ssc：表格化 RC，适合 HPPC 数据
- thermalLumpedMass.ssc：集总热质量
- thermalHeightDistributedMass.ssc：分布式热质量
- +electrochemical/batterySingleParticle.ssc：单粒子模型（高保真备选）
- batteryCalendarAging.ssc、batteryCyclingAging.ssc：老化模型
- +thermal/coolingPlateFlatPlate.ssc、coolingPlateWithParallelChannels.ssc、coolingPlateWithFlatChannels.ssc、coolingPlateWithEdgeCooling.ssc

ECM 共享库 batteryecm_lib.slx：Battery、Battery (Table-Based)。
HPPC 台架 hppcTestHarness.slx：ECM 参数辨识流程参考。
BMS SLI 库：BatteryThermalManagement、BatteryCurrentManagement、BatteryProtection、BatteryEstimators、BatterySoeEstimators、BatteryPowerEstimators、BatteryBalancing。

对脉冲加热的判断：Battery Equivalent Circuit + thermalLumpedMass + coolingPlate 可直接构成电池电热耦合主骨架；ECM 的 R0/RC 损耗自动传入热模型，实现 Q=I2R；有 EIS 数据后可升级为 Re(Z,T,SOC,f) 表格。

### 5.2 Simscape Electrical（ee_lib + sps*Lib）

主库 ee_lib.slx 顶层子系统：
- Electromechanical：电机（PMSM、IM、BLDC 等）
- Semiconductors & Converters：IGBT、MOSFET、Diode、半桥/全桥变换器
- Sources：受控电压/电流源、脉冲源
- Passive：RLC、变压器
- Sensors & Transducers：电压/电流/温度传感器
- Control、Connectors & References、Switches & Breakers、Integrated Circuits、Utilities、Additional Components

SPS 库关键块（sps*Lib.slx，每个文件对应一个块类型）：
- 电机：spsPermanentMagnetSynchronousMachineLib(PMSM)、spsAsynchronousMachine*(IM)、spsDCMachineLib、spsSwitchedReluctanceMotorLib、spsStepperMotorLib
- 逆变器/变换器：spsInverterThreePhaseLib、spsTwoLevelConverterLib、spsThreeLevelBridgeLib、spsUniversalBridgeLib、spsHalfBridgeConverterLib、spsFullBridgeConverterLib、spsBuckConverterLib、spsBoostConverterLib
- 功率器件：spsIGBTLib、spsIGBTDiodeLib、spsMosfetLib、spsDiodeLib、spsIdealSwitchLib、spsGtoLib、spsDetailedThyristorLib
- 控制器：spsFieldOrientedControllerLib(FOC)、spsSVPWMGenerator2LevelLib、spsSVPWMGenerator3LevelLib、spsSpaceVectorModulatorLib、spsPWMGenerator2LevelLib、spsPWMGenerator3LevelLib、spsCurrentControllerBrushlessDCLib、spsVectorControllerPMSMLib、spsDirectTorqueControllerLib、spsSpeedControllerACLib、spsOvermodulationLib
- 变换：spsabctodq0Lib、spsdq0toabcLib、spsAlphaBetaZerotoabcLib、spsdq0toAlphaBetaZeroLib、spsAlphaBetaZerotodq0Lib
- 源：spsControlledCurrentSourceLib、spsControlledVoltageSourceLib、spsDCVoltageSourceLib、spsACVoltageSourceLib、spsACCurrentSourceLib
- 电池/电容：spsBatteryLib、spsSupercapacitorLib、spsFuelCellStackLib、spsPVArrayLib
- 测量：spsVoltageMeasurementLib、spsCurrentMeasurementLib、spsPowerLib、spsRMSLib、spsTHDLib、spsMultimeterLib

对脉冲加热的判断：PMSM + 逆变器 + FOC + SVPWM + Clarke/Park + ControlledSource 构成完整电驱控制链路；堵转脉冲加热时 PMSM 可简化为 RL 支路，但 FOC/SVPWM/死区/调制限制必须保留以判断电流可实现性。

### 5.3 Powertrain Blockset 与 Motor Control Blockset

Powertrain Blockset（autolib*）关键库：
- mapped 模型：autolibmappedmotor.slx（mapped 电机）、autolibmappedmotorcommon.slx、autolibinverter.slx（逆变器）、autolibdatasheetbattery.slx（datasheet 电池）
- PMSM：autolibfluxpmsm.slx（flux PMSM）、autolibpmsminterior.slx（IPMSM）、autolibpmsmexterior.slx（SPMSM）、autolibpmsmcommon.slx
- 其他电机：autolibim.slx（IM）、autolibbldc.slx（BLDC）
- 系统：autolibdcdc.slx、autolibboost.slx（DC-DC）、autolibmotorctrlr.slx（电机控制器）、autolibdrivetrain.slx、autolibvehdyn.slx、autolibemachines.slx
- 电池：autolibdatasheetbattery.slx、autolibbatterycommon.slx

Motor Control Blockset（mcb*lib）关键库：
- 控制：mcbfoclib.slx（FOC）、mcbcontrolslib.slx（控制）、mcbcontrollergainlib.slx（增益整定）、mcbdeadtimecomplib.slx（死区补偿）
- 被控对象：mcbplantlib.slx（plant）、mcbhdlplantlib.slx
- PMSM：mcbpmsmiflib.slx、mcbpmsmnonlinearlib.slx、mcbpmsmvflib.slx、mcbpmsmparamestlib.slx（参数估计）
- 估计器：mcbsensorlessestimatorlib.slx（无感）、mcbplllib.slx（PLL）、mcbpositiondecoderlib.slx、mcbresolverdecoderlib.slx
- 其他：mcbsynrmnonlinearlib.slx、mcbsrmlib.slx、mcbmultiphasemathlib.slx、mcbacimparamestlib.slx

对脉冲加热的判断：Powertrain mapped motor/inverter 适合系统级快速仿真和损耗参考，但 1250 Hz 堵转脉冲可能超出 map 工况范围，第一版不宜作为主骨架。MCB 的 FOC、死区补偿、电流环和参数估计块是 L1 电流可实现性模型的核心控制组件，应直接复用。

## 6. GitHub 官方模型盘点

| 仓库 | 星数 | 对脉冲加热的价值与定位 |
|---|---|---|
| Simscape-Battery-Electric-Vehicle-Model (B11) | 151 | BEV 纵向动力分析，含电池+电机+逆变器+热管理完整链路。default_branch=R2025b 与本机匹配。主参考骨架，需剥离行驶工况聚焦堵转脉冲 |
| Battery-Pack-Model-Simscape (B12) | 124 | 电池包热管理，串并联 cell 模块+冷却板。直接对应三包并联结构。电池包主参考 |
| Design-motor-controllers-with-Simscape-Electrical (B13) | 275 | 电机控制器设计视频配套模型。FOC/SVPWM/电流环完整实现。控制层主参考 |
| Battery-Model-Parameter-Estimation-Using-Impedance-Data (B14) | 12 | 阻抗数据参数估计。直接对应 Re(Z,T,SOC,f) 升级路径。有 EIS 数据后参数化参考 |
| pmsm-drive-optimization (B15) | 32 | PMSM 效率优化与控制参数。电机损耗和效率 map 参考 |
| import-motorcad-thermal-simulink (B16) | 16 | Motor-CAD 热模型导入 Simscape。电机绕组热模型参考 |
| Battery-Electric-Vehicle-Motor-Cooling-Simscape (B17) | 15 | BEV 液冷电机。电驱热管理参考 |
| EV-with-MATLAB-and-Simulink (B18) | 42 | EV 资源集合，含 battery/fuel-cell/power-electronics/thermal-management 索引 |
| vehicle-modeling (B19) | 33 | Powertrain Blockset 车辆建模。整车系统组织参考 |
| battery-modeling-solutions-with-simscape (B20) | 6 | 电池建模方案：ECM 参数估计、包建模、均衡、SOH |

注意：GitHub 仓库未下载到本地。后续需要参考某个仓库时，应在单独工作副本中克隆，不直接污染项目目录。仓库许可证为 MathWorks 产品配合使用的 other/NOASSERTION，可在 MATLAB/Simulink 环境内参考复用。

## 7. 路线摘要与 AMESim 触发条件

### 7.1 初版模型建议

不应直接复制任何一个现成模型作为最终模型。第一版应以"通用脉冲加热系统模型体系"为目标，先用官方库组件+默认/文献参数把结构和物质流走通：

1. 电池包：Simscape Battery Battery Equivalent Circuit + thermalLumpedMass，三包并联整体输出，参数先用默认/文献值，缺口标出
2. 电驱：逆变器用平均值或 Universal Bridge，PMSM 用 RL 简化或完整 PMSM；第一版不上详细开关级，避免 1250 Hz 全开关细节把仿真刚性拖死
3. 控制：FOC + SVPWM 电流环，保留死区、调制限制、电压饱和接口
4. 脉冲电流：参数化高频双向脉冲（频率、占空比、幅值可切换），不每个方案重建拓扑
5. 热量分配：电池内阻热（ECM 自动）、电机铜耗、逆变器损耗、环境散热
6. 输出 KPI：温升、SOC 消耗、RMS/峰值/平均电流、母线电流、功率、电压平台、安全边界

第一版数据策略：先用官方示例参数、文献范围、工程默认跑通模型，把数据缺口标出来。4500-27 测试数据只用于走通流程和 sanity check，不作为建模前提。模型成立后再向实验人员索取 EIS/HPPC/电机 LdLq/逆变器损耗等详细数据。

### 7.2 AMESim 触发条件

进入 AMESim 的触发条件不是"Simscape 建模变难"，而是以下任一长期无法解决：

1. Simulink/Simscape 找不到合适的电热/冷却/电驱复用结构
2. Simscape 求解刚性长期无法接受（1250 Hz 脉冲+热网络+电网络耦合）
3. 需要更专业的一维热管理、液冷、部件匹配库
4. 需要和供应商 AMESim 模型对接

当前判断：本机 Simscape Battery + Simscape Electrical + MCB + Powertrain 组件足以支撑第一版脉冲加热物理网络，不需要进入 AMESim。

## 8. 证据链接

### 8.1 GitHub 仓库

- https://github.com/mathworks/Simscape-Battery-Electric-Vehicle-Model
- https://github.com/mathworks/Battery-Pack-Model-Simscape
- https://github.com/mathworks/Design-motor-controllers-with-Simscape-Electrical
- https://github.com/mathworks/Battery-Model-Parameter-Estimation-Using-Impedance-Data
- https://github.com/mathworks/pmsm-drive-optimization
- https://github.com/mathworks/import-motorcad-thermal-simulink
- https://github.com/mathworks/Battery-Electric-Vehicle-Motor-Cooling-Simscape
- https://github.com/mathworks/EV-with-MATLAB-and-Simulink
- https://github.com/mathworks/vehicle-modeling
- https://github.com/mathworks/battery-modeling-solutions-with-simscape-and-measured-data

### 8.2 本机库路径（均位于 D:/matlab2025b/toolbox/ 下）

- physmod/battery/library/m/batt_lib.slx（Simscape Battery 主库）
- physmod/battery/library/m/+batt/+cells/（ssc 组件源码）
- physmod/battery/shared_library/m/batteryecm_lib.slx
- physmod/battery/parameterization/m/models/hppcTestHarness.slx
- physmod/battery/sli/m/（BMS SLI 库）
- physmod/elec/library/m/ee_lib.slx（Simscape Electrical 主库）
- physmod/elec/assistant/m/transform/（sps*Lib 系列 + electricdrivelib）
- autoblks/autoblks/ 和 autoblks/autoblksshared/（Powertrain Blockset）
- mcb/mcbblocks/（Motor Control Blockset）

### 8.3 现有项目资产

- 零维脉冲加热仿真模型-4500-27型整车/（L0.5 历史资产，参数/KPI/方程参考）
- 脉冲加热参数整理汇总/部件参数原始表/（4500-27 参数证据链）
- 建模依据资料/（21 篇论文专利 + 建模依据清单.md）
- 零维脉冲加热仿真模型-4500-27型整车/00_任务计划与资料/逆变器调幅与简单开关建模口径.md（控制链方程来源）

### 8.4 参考方法论

- PEMFC 项目材料池方法：E:/agentwork_pemfc_cEGR_0519/Simulink_PEMFC_cEGR_材料池与模型候选比较_v01.md
- PEMFC 项目模型规格方法：E:/agentwork_pemfc_cEGR_0519/Simulink_PEMFC_cEGR_通用模型规格与实施路线_v01.md
