function cfg = plotConfig()
%% PLOTCONFIG  M4 结果图表共享配置
%  返回结构体，包含所有绘图函数共用的颜色、字体和图形设置。
%  不包含文件保存功能——所有图表以 MATLAB 在线图形形式显示，
%  未经用户许可不生成图片文件。

cfg = struct();

%% 图形设置
cfg.fontName   = 'Arial';   % 全局字体
cfg.fontSize   = 11;        % 坐标轴字体大小
cfg.titleSize  = 13;        % 标题字体大小
cfg.labelSize  = 12;        % 轴标签字体大小
cfg.figurePos  = [100 100 1000 650];   % 默认图形尺寸
cfg.figurePosWide = [100 100 1100 550];
cfg.gridOn     = 'on';

%% 配色方案
% 物理电气量 — 蓝色系
cfg.color.physical    = [0.00 0.45 0.74];
cfg.color.physicalLt  = [0.40 0.70 0.90];
% 控制量 — 绿/青色系
cfg.color.control     = [0.20 0.63 0.17];
% 铜耗/逆变器损耗 — 暖色系
cfg.color.cuLoss      = [0.85 0.33 0.10];
cfg.color.invLoss     = [0.93 0.69 0.13];
cfg.color.hvLoss      = [0.47 0.67 0.19];
% 电池热源/储能 — 红/紫系
cfg.color.battHeat    = [0.49 0.18 0.56];
cfg.color.thermal     = [0.64 0.08 0.18];
cfg.color.thermalStore= [0.80 0.30 0.40];
% 铁耗/机械
cfg.color.ironLoss    = [0.30 0.75 0.93];
cfg.color.mech        = [0.80 0.80 0.80];
% 储能/未建模
cfg.color.dcStorage   = [0.30 0.30 0.30];
cfg.color.unmodeled   = [0.50 0.50 0.50];
% 调色板 — 通用分类
cfg.palette.categorical = [
    0.00 0.45 0.74;   % 蓝
    0.85 0.33 0.10;   % 橙红
    0.93 0.69 0.13;   % 金
    0.49 0.18 0.56;   % 紫
    0.47 0.67 0.19;   % 橄榄绿
    0.20 0.63 0.17;   % 绿
    0.30 0.75 0.93;   % 青
    0.50 0.50 0.50];  % 灰
% 低/高值颜色（参数敏感性用）
cfg.color.lowVal  = [0.00 0.45 0.74];
cfg.color.highVal = [0.85 0.33 0.10];
end