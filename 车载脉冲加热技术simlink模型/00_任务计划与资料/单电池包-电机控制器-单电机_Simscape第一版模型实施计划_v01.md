# 单电池包-电机控制器-单电机 Simscape 第一版模型实施计划

日期：2026-07-07
阶段：前置只读验证完成，进入实施准备
范围：MATLAB/Simulink/Simscape-first，单电池包-逆变器-PMSM 堵转脉冲加热第一版物理网络模型
工具：OpenCode 专属 MATLAB MCP（R2025b），load_system+find_system 只读验证，未打开任何 .slx 模型，未运行仿真

本文件基于 `Simscape_脉冲加热_材料池与模型候选比较_v01.md`、`逆变器调幅与简单开关建模口径.md`、`建模依据清单.md` 和 V1-V5 前置只读验证结果整理，是第一版模型实施的唯一计划入口。

> 2026-07-07 GPT审计更新：本计划中的“第一版模型”尚未完成。`pulse_heating_single_pack_v01.slx` 是开环受控源历史基线；`pulse_heating_v02.slx` 是未连通电池包替换草稿。后续执行本计划时，优先目标不是扩大功能，而是先完成 P0 连通性修复和 P1 控制/逆变器口径收敛。

> 2026-07-07 规划更新：后续实际建模以 `单电池包-控制器-单电机_规范化建模规划与操作步骤_v02.md` 为权威入口。本文件保留为 v01 前置验证和历史计划记录。

---

## 1. 目标与边界

### 1.1 目标

在 `车载脉冲加热技术simlink模型/` 下建立第一版 Simscape 物理网络模型，走通"目标电流 → 信号流 FOC → PWM/调制 → 明确口径的逆变器或受控源测试夹具 → PMSM 堵转 → 252S1P 电池包+热"完整物质流，输出温升/电流/损耗/电压裕度 KPI。

### 1.2 第一版边界

- 单电池包（优先使用 Battery Pack Builder 生成的 252S1P Pack；单 BEC 只允许作为历史基线或临时单电芯验证）
- 单 PMSM 堵转（omega=0，自然退化为 RL 支路，保留热模型）
- 逆变器口径必须在模型内明确：Average-Value VSC / 两电平变换器 / 受控源测试夹具三选一，不允许文档写平均值逆变器而模型用受控源
- 信号流自建 FOC（Clarke/Park/PI/PWM，用 Simulink 标准信号流块）
- 先 PWM 调制，第二版再升级 SVPWM
- 数据用官方示例/文献默认值，缺口标 `PLACEHOLDER`

### 1.3 禁止项

- 不自建 MATLAB Function 实现电池/电机/逆变器物理
- 不用 L0.5 零维函数模型作物理核心
- 不用理想电流源代替逆变器功率回路
- 不直接按 XML/文本修改 .slx

---

## 2. 前置只读验证结果（V1-V5）

验证日期：2026-07-07。工具：MATLAB MCP evaluate_matlab_code，load_system+find_system 只读查询。未打开任何 .slx 模型，未运行仿真，未干扰其他 MATLAB session。

### 2.1 V1 电池 ECM 块

- 块名：Battery Equivalent Circuit
- 库路径：`batt_lib/Cells/Battery Equivalent Circuit`
- BlockType：SimscapeBlock
- 端口：LConn:1 RConn:1（电气 +、-）
- 关键参数：BatteryCapacity、OpenCircuitVoltage、R0、R1/Tau1、R2/Tau2、R3/Tau3、ThermalModel、BatteryThermalMass、TemperatureBreakpoints、R0Thermal/R1Thermal/R2Thermal（温度依赖）
- DialogParameters 总数：522
- 验证结论：直接可用。ECM 含 OCV/R0/RC 网络/热端口/T-SOC 依赖/老化，Q=I²R 自动传入热模型。

### 2.2 V2 电池热模型

- 来源 1：BEC 块自带 `ThermalModel` 枚举参数（ConstantTemperature / LumpedTemperature / MultipleTemperatures）+ `BatteryThermalMass` 参数（默认 100 J/K）
- 来源 2：`batt_lib/Thermal` 子系统含 Edge Cooling、Parallel Channels、U-shaped Channels 冷却块（LConn:2 RConn:4）
- 验证结论：第一版用 BEC 自带 LumpedTemperature 模式，无需另加热质量块。后期需要液冷时再用 batt_lib/Thermal 冷却块。

### 2.3 V3 平均值逆变器

- 块名：Average-Value Inverter (Three-Phase)
- 库路径：`ee_lib/Semiconductors & Converters/Converters/Average-Value Inverter (Three-Phase)`
- BlockType：SimscapeBlock
- 端口：LConn:2 RConn:1（DC+、DC-、三相 AC、1 个控制端口）
- 关键参数：port_option、FRated(60)、PhaseShift(0)、voltage_ratio(sqrt(6)/pi)、Pfixed、v_on、v_off
- 验证结论：直接可用。第一版平均值模型避免 1250 Hz 开关级刚性。voltage_ratio 控制调制比。

### 2.4 V4 FOC 控制器

- ee_lib/Control 子系统：空，无独立 Simscape FOC 块
- sps 域 `elec_conv_Field_OrientedControlInd`：SPS（Specialized Power Systems）组件，是"FOC+电机+逆变器"一体的完整驱动系统，不是单独 FOC 控制器，端口为 LConn:3 RConn:0 Inport:2 Outport:4
- sps 域 `spsFieldOrientedControllerLib`：空库
- MCB 域 `mcbfoclib`：存在（exist=4），但接口偏代码生成导向，与 Simscape 物理网络对接需适配
- 验证结论：Simscape 物理网络库中没有独立规范 FOC 块。决策：用 Simulink 信号流标准块自建 Clarke/Park/PI/PWM，通过 PS-Simulink Converter 与物理网络对接。

### 2.5 V5 PMSM

- 块名：PMSM
- 库路径：`ee_lib/Electromechanical/Permanent Magnet/PMSM`
- BlockType：SimscapeBlock
- 端口：LConn:2 RConn:2（三相 a,b,c + 机械 R,S）
- 关键参数（57 个核心参数）：
  - 电气：Ld、Lq、L0、Ls、Rs、nPolePairs、pm_flux_linkage、torque_constant、back_emf_constant
  - 饱和：idVec、iqVec、LdMatrix、LqMatrix、PmMatrix、ktMatrix、keMatrix
  - 机械：J（惯性）、lam（阻尼）
  - 热：stator_thermal_mass、rotor_thermal_mass、Rm_percent_rotor、Rd_percent_rotor、temperatureA/B/C/R
  - 损耗：losses_oc、losses_sc、f_losses、Isc_losses
  - 状态：i_d、i_q、torque、angular_velocity、angular_position
- 验证结论：直接可用。堵转时设 omega=0，自然退化为 RL 支路且保留热模型。含定子/转子热质量和温度端口，支持电热耦合。

### 2.6 补充验证：传感器与辅助块

- Current Sensor (Three-Phase)：`ee_lib/Sensors & Transducers/Current Sensor (Three-Phase)`，SimscapeBlock，已确认存在
- Current and Voltage Sensor (Three-Phase)：`ee_lib/Sensors & Transducers/Current and Voltage Sensor (Three-Phase)`，已确认存在
- ee_lib/Passive：含 RLC 等无源元件，DC-link 电容可用
- ee_lib/Sources：含受控电压/电流源（备用）

---

## 3. 已确认的复用块清单

| 角色 | 块名 | 库路径 | BlockType | 端口 | 复用性质 |
|---|---|---|---|---|---|
| 电池 ECM | Battery Equivalent Circuit | `batt_lib/Cells/Battery Equivalent Circuit` | SimscapeBlock | LConn:1 RConn:1 | 直接拖拽 |
| 电池热模型 | BEC 自带 ThermalModel+BatteryThermalMass | BEC 参数 | 内含 | — | 设参数即可 |
| 逆变器 | Average-Value Inverter (Three-Phase) | `ee_lib/Semiconductors & Converters/Converters/Average-Value Inverter (Three-Phase)` | SimscapeBlock | LConn:2 RConn:1 | 直接拖拽 |
| PMSM | PMSM | `ee_lib/Electromechanical/Permanent Magnet/PMSM` | SimscapeBlock | LConn:2 RConn:2 | 直接拖拽 |
| 电流传感 | Current Sensor (Three-Phase) | `ee_lib/Sensors & Transducers/Current Sensor (Three-Phase)` | SimscapeBlock | 已确认 | 直接拖拽 |
| DC-link 电容 | ee_lib/Passive 电容 | `ee_lib/Passive` | SimscapeBlock | 待查具体块 | 直接拖拽 |
| PS-Simulink 转换 | PS-Simulink Converter / Simulink-PS Converter | Simscape 标准库 | SubSystem | 标准 | 直接拖拽 |
| FOC 信号流 | Discrete PI / Trigonometric Function / Math Operations | Simulink 标准库 | 信号流 | 标准 | 信号流自建 |
| PWM 发生 | PWM Generator | Simulink 标准库或 spsPWMGenerator2Level | 信号流 | 待确认接口 | 信号流自建 |

明确排除项：
- 不自建 MATLAB Function 实现电池/电机/逆变器物理
- 不用 L0.5 零维函数模型作物理核心（仅作参数/KPI/方程口径参考）
- 不用 Powertrain mapped 模型作主骨架（高频堵转可能超 map 工况范围）
- 第一版不上开关级 IGBT 详细模型（避免刚性）
- 不用 sps 域 elec_conv_Field_OrientedControlInd 完整驱动系统（SPS 组件，含电机+逆变器一体，难以与 BEC 电池热模型耦合）

---

## 4. 模型架构

### 4.1 第一版拓扑

```text
[电池 BEC (ECM + LumpedThermal)]
   │ +, - (electrical)
   ├── DC-link 电容 (ee_lib/Passive)
   └── Average-Value Inverter DC+ / DC-
            │ 三相 AC (a, b, c)
            ├── PMSM 三相 (a, b, c)
            │      └── 机械端口: 堵转 (omega=0, T_load=0)
            └── Current Sensor (Three-Phase) → PS-Simulink Converter
                    │ Ia, Ib, Ic (信号)
                    ▼
              [Clarke/Park] (信号流自建) ← theta (堵转可设 0 或固定角)
                    │ Id_fb, Iq_fb
                    ▼
              [PI 电流环] ← Id_ref, Iq_ref (脉冲命令发生器)
                    │ Vd_ref, Vq_ref
                    ▼
              [逆 Park] → Valpha, Vbeta
                    ▼
              [PWM Generator] → 调制信号 → 逆变器控制端口

脉冲命令发生器: 参数化高频双向脉冲 (频率/占空比/幅值可切换)
热网络: BEC 自带热模型, 散热边界 → 环境
KPI 输出: 温升/SOC/RMS/峰值/平均电流/母线电流/功率/电压裕度/限制来源
```

### 4.2 信号流与物理网络接口

- 物理网络（Simscape）：电池 BEC、DC-link、逆变器、PMSM、电流传感器
- 信号流（Simulink）：Clarke/Park/PI/逆 Park/PWM/脉冲命令发生器
- 桥接：PS-Simulink Converter（物理→信号）、Simulink-PS Converter（信号→物理）
- 采样时间：统一采样时间或用 Rate Transition 避免冲突

### 4.3 堵转工况处理

- PMSM 机械端口：omega=0（堵转），T_load=0
- 堵转时 PMSM d/q 轴电压方程退化为：u_d ≈ R_s·i_d + L_d·di_d/dt，u_q ≈ R_s·i_q + L_q·di_q/dt
- theta 角处理：堵转时转子不动，theta 可设为固定值或由初始位置决定；第一版先设 theta=0 验证物质流

---

## 5. 实施步骤

### 阶段 1：目录与参数脚本

1. 目录结构已建立：
   - `00_任务计划与资料/`（本文件、接口契约、参数来源）
   - `01_参数库/`（参数脚本，从 L0.5 继承可复用值）
   - `02_模型/`（.slx 模型文件）
   - `03_脚本/`（运行/扫描/后处理脚本）
   - `04_仿真结果/`
   - `05_模型说明.md`
2. 从 L0.5 `02_参数库/build_4500_27_pulse_heating_params.m` 提取单包参数（OCV、R0、RC、热容、散热系数、Ld/Lq/Rs/磁链），标注来源和可信等级；缺项用官方示例/文献默认值填充并标 `PLACEHOLDER`。

### 阶段 2：核心块接口契约文档

3. 基于 V1-V5 验证结果，写 `00_任务计划与资料/接口契约_v01.md`：每个块的端口名、参数名、物理域、上下游对接关系。

### 阶段 3：模型搭建（SATK MCP / Simulink API）

4. 以 `02_模型/pulse_heating_v02.slx` 为草稿修复，或新建 `pulse_heating_single_pack_v03.slx`；不得继续把 `v01` 当作当前规范模型。
5. 按 SATK model_edit 小步闭环添加块（每步 model_read depth=0 read-back 验证，结构改动后跑 model_check）：
   - 5a：252S1P Battery_Pack + DC-link 电容 + 电气参考 + 热边界
   - 5b：明确口径的逆变器/受控源测试夹具 + PMSM（DC 侧接电池，AC 侧接 PMSM）
   - 5c：Current Sensor (Three-Phase) + PS-Simulink Converter
   - 5d：信号流 Clarke/Park/PI/逆 Park/PWM
   - 5e：脉冲命令发生器（参数化）
   - 5f：KPI 输出（To Workspace / Scope）

### 阶段 4：参数化与最小仿真

6. 用 model_query_params / model_resolve_params 设置参数：
   - Battery_Pack：OCV/R0/RC/ThermalModel/热容/温度依赖 R，电压应约为 252 倍单体 OCV
   - PMSM：Ld/Lq/Rs/Pm/J/stator_thermal_mass，omega=0 堵转
   - 逆变器：voltage_ratio
   - PI：Kp/Ki
   - 脉冲：频率/占空比/幅值
7. 最小仿真：单工况（如 1250 Hz、50% duty、Id_ref=100A、T_init=-20°C、1-5s），用 sim() 跑通，确认无刚性报错、关键输出非空、电池包端电压量级正确。30s 仿真和 KPI 汇总必须在短时连通性验证之后再做。

### 阶段 5：KPI 输出与口径对齐

8. 按《逆变器调幅口径》第 5 节统一输出字段：
   - `f_sw_Hz`、`duty`/`modulation_index`
   - `I_raw_peak_A`、`I_raw_rms_A`（开环电压驱动自然电流）
   - `I_target_A`/`current_amplitude_scale`（控制器目标）
   - `I_actual_peak_A`、`I_actual_rms_A`（限制后实际电流）
   - `V_required_V`、`V_available_V`
   - `limiting_factor`（电压饱和、MCU 限流、电池限流、频率越界）
   - `P_battery_W`、`P_motor_W`、`P_inverter_W`
9. 与 L0.5 `4500_27_summary.csv` 做 sanity check：温升量级、电流压力量级是否一致（不要求精确匹配，量级合理即可）。

### 阶段 6：文档与验收

10. 写 `05_模型说明.md`：模型结构、参数来源、数据缺口、已验证/未验证项、使用边界。
11. 验收检查（对照《建模依据清单》第 6 节）：
    - 电池热源有来源：I_rms²·R 或 I²·Re(Z)
    - 电机绕组有来源：PMSM d/q 方程低速 RL 简化
    - 逆变器控制有来源：FOC/SVPWM 链条和 PI 电流环
    - 电流调幅有来源：Id/Iq 闭环、Ud/Uq 调制
    - 安全边界有来源：电机/MCU 电流限制、电池电压/SOC/温度、析锂参考边界
    - 任何"可实现电流"都必须说明是否经过电压饱和、控制器限流、电池边界和高压路径边界检查

---

## 6. 数据策略

- 第一版：官方示例参数 + 文献范围 + 工程默认，缺口标 `PLACEHOLDER`。
- 4500-27 测试数据：仅作 sanity check，不作为建模前提。
- 模型成立后：向实验人员索取 EIS/HPPC/LdLq/逆变器损耗详细数据再参数化。
- 数据策略与 PEMFC 项目 Core Model 思路一致：通用模型体系优先，数据只用来走通流程和 sanity check。

必须补充的工程参数（第一版标 PLACEHOLDER，模型成立后索取）：

| 缺口 | 用途 | 影响 |
|---|---|---|
| 控制器电流环带宽、采样周期、PWM 周期 | 判断目标电流能否跟踪 | 影响 Simulink 闭环可信度 |
| 控制器最大调制比、电压限幅、最小脉宽、死区时间 | 判断 V_required ≤ V_available | 影响电流调幅可实现性 |
| MCU 峰值/RMS 电流、过流阈值、热降额 | 安全限制 | 影响可用加热电流 |
| 电机 Ld(I,T)、Lq(I,T)、Rs(T) | 电流动态和损耗 | 影响频率-电流关系 |
| 电池低温 EIS/HPPC，尤其 Re(Z,T,SOC,f) | 频域热源项 | 影响发热功率和温升 |
| 电池高频/脉冲析锂试验边界 | 安全边界 | 影响能否定量限流 |
| 高压盒、接触器、熔断器、线束电流限制 | 拓扑可实现性 | 影响集中单支路方案风险 |
| 逆变器损耗图或器件开关损耗参数 | 控制器热风险 | 影响持续加热能力 |

---

## 7. 风险与回退

| 风险 | 触发表现 | 回退方案 |
|---|---|---|
| 平均值逆变器控制端口与信号流 PWM 不兼容 | gating 信号格式不匹配 | 改用 spsUniversalBridge + 开关级，或用受控电压源替代逆变器走通物质流 |
| 1250 Hz 脉冲致刚性 | sim() 报错或极慢 | 降载频至 100-500 Hz 走通流程，标明与目标频率差距 |
| PMSM 堵转不收敛 | 零速+高电流不收敛 | 用受控电压源 + RL 支路验证物质流，标明为开环验证 |
| BEC 热模型参数不足 | 温升不合理 | 用文献典型热容值填充，标 PLACEHOLDER |
| 信号流 FOC 与物理网络时步冲突 | PS-Simulink 转换报错或采样不一致 | 统一采样时间，或用 Rate Transition |
| FOC 信号流自建逻辑错误 | 电流不跟踪或振荡 | 先用 Id_ref=0 验证零电流稳态，再逐步加目标；参考 TI/NXP FOC 结构图 |

---

## 8. 不生成产物纪律

- 不默认导出图片/CSV/报告副本。
- 中间产物只放 `04_仿真结果/`，任务结束说明保留文件。
- .slx 正式保存前说明目的；未经授权不自动保存正式模型。
- 对 .slx 等结构化文件，使用 SATK MCP 工具或 Simulink API，不按 XML/文本硬改。

---

## 9. Codex 审核触发点

按 AGENTS.md 第 7 节，以下节点请求 Codex 审核：

1. 接口契约文档完成后（阶段 2 后）
2. 第一版模型结构搭建完成后（阶段 3 后）
3. 首次仿真走通后（阶段 4 后）
4. KPI 输出与口径对齐后（阶段 5 后）

审核重点是物理语义、证据链、边界条件、参数来源、风险表达和是否过度声称。

---

## 10. 后续演进路径（不在第一版范围内）

- 第二版：PWM 升级为 SVPWM（信号流自建或 spsSVPWMGenerator2Level）
- 第三版：平均值逆变器升级为开关级 IGBT/MOSFET（加入死区、导通压降、开关损耗）
- 多电池包：三包并联整体输出（参考 GitHub B12 Battery-Pack-Model-Simscape）
- 多电机：双电机同步堵转脉冲
- 参数化升级：有 EIS/HPPC 数据后，BEC 升级为 Re(Z,T,SOC,f) 表格；PMSM 升级为 Ld(I,T)/Lq(I,T) 饱和表
- AMESim 触发条件：见 `Simscape_脉冲加热_材料池与模型候选比较_v01.md` 第 7.2 节

---

## 11. 证据链接

### 11.1 本机库路径（均位于 D:/matlab2025b/toolbox/ 下）

- `physmod/battery/library/m/batt_lib.slx`（Simscape Battery 主库）
- `physmod/elec/library/m/ee_lib.slx`（Simscape Electrical 主库）
- `physmod/elec/assistant/m/transform/`（sps*Lib 系列，SPS 域，第一版不作为主骨架）

### 11.2 项目内依据文档

- `Simscape_脉冲加热_材料池与模型候选比较_v01.md`（材料池盘点）
- `零维脉冲加热仿真模型-4500-27型整车/00_任务计划与资料/逆变器调幅与简单开关建模口径.md`（控制链方程来源）
- `零维脉冲加热仿真模型-4500-27型整车/00_任务计划与资料/建模依据清单.md`（FOC/SVPWM/热源/安全边界方程来源）
- `零维脉冲加热仿真模型-4500-27型整车/模型目录说明.md`（L0.5 历史资产边界）
- `AGENTS.md`（项目级 agent 规则）

### 11.3 GitHub 官方模型参考（未下载，后续需要时在单独工作副本克隆）

- Simscape-Battery-Electric-Vehicle-Model（B11，BEV 完整链路，系统组织参考）
- Battery-Pack-Model-Simscape（B12，电池包串并联，后期三包并联参考）
- Design-motor-controllers-with-Simscape-Electrical（B13，FOC/SVPWM 实现参考）
- Battery-Model-Parameter-Estimation-Using-Impedance-Data（B14，EIS 参数化参考）
