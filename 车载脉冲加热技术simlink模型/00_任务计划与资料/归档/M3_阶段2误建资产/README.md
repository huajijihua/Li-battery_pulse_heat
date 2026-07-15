# M3 阶段 2 误建资产归档

归档日期：2026-07-15
归档阶段：阶段 3，资产归档收口
来源：`车载脉冲加热技术simlink模型/03_脚本/`

本目录保存阶段 1 分析清理中登记、经阶段 2 共同确认后按计划归档的 3 个 MATLAB 脚本和 2 个测试：

- `03_脚本/computeWindowMetrics.m`
- `03_脚本/createM3ContractConfig.m`
- `03_脚本/precheckSystemConfig.m`
- `03_脚本/tests/computeWindowMetricsTest.m`
- `03_脚本/tests/precheckSystemConfigTest.m`

这些文件是前一轮越界实施产生的独立资产，不是当前 M3 活动脚本。即使其中的静态检查或单元测试曾通过，也不构成 Simulink 模型验收、物理正确性、设备匹配、Active 准入或 M3 已确认实施路线的证据。

本次归档不涉及活动 V4 模型、M2/V4-I 冻结证据、`.slxc`、`slprj/` 或其他仿真缓存。空的 `车载脉冲加热技术simlink模型/outputs/` 目录已在此前按用户授权删除。
