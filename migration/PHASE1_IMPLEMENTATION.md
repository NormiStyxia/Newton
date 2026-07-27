# 第一阶段迁移实现说明

## 已完成边界

- 采用编辑器策略 A：Maker 只读取从 Phaser 导出的关卡 JSON。
- `LevelData -> RuntimeFactory -> UrhoX instance` 已拆为独立模块。
- 读取并校验 `level_01.json`，不改写源关卡数据。
- 固定 GameplayViewport 使用原 Phaser 玩法区域 `1500 × 596`，在实际屏幕内等比居中并留黑边。
- 已实例化发射器、苹果、地面和目标 Sensor；`wall_02` 明确延后，运行时会输出 deferred 日志。
- 苹果支持原玩法的拖拽限制、最小发射距离、速度系数和角速度系数；`R` 重置，`Z` 切换 Box2D 调试绘制。
- Sensor 使用 Box2D trigger，苹果进入/离开时更新本地 HUD 和日志。
- 未迁移编辑器、卡牌、墙体/机关、回放、完成判定与外围 UI。

## 坐标与单位换算

原项目的关卡坐标为 `1400 × 700`，固定玩法视口为 `1500 × 596`：

- 位置：`viewportX = levelX / 1400 × 1500`，`viewportY = levelY / 700 × 596`。
- 物体尺寸：沿用原 `CoordinateConverter.objectScale = 596 / 700`。
- UrhoX 世界：`100 viewport pixels = 1 meter`，Y 轴反向。
- JSON 顺时针视觉旋转转换为 UrhoX 的负角度。
- 原 Matter 重力 `WORLD_FORCE_SCALE = 0.001` 在 60 Hz、100 px/m 下对应约 `10 m/s²`。
- 原 Matter 发射速度（px/step）乘 `60 / 100` 转为 Box2D 的 m/s。

这些换算集中在 `scripts/migration/CoordinateMapper.lua`，运行时工厂不自行猜测比例。

## 资源约束

原 Phaser SVG 仅被只读渲染。Maker 使用独立派生 PNG，来源、SHA-256 与尺寸记录在 `phase1_asset_manifest.json`。源 `level_01.json` 与 Maker 副本 SHA-256 完全一致。

## FAST_VALIDATE

验证范围：

1. Maker Lua LSP 对四个 Lua 文件执行 Error 级诊断。
2. 校验关卡 schema、对象边界、坐标往返、地面与 Sensor 映射。
3. 校验关卡副本、原 SVG SHA-256、派生 PNG SHA-256 和图片尺寸。
4. 静态确认 Sensor 为 trigger、苹果/地面为刚体，并且项目没有 raw NanoVG 调用。

不执行整关试玩，也不执行 Maker 远端 build/submit。

可重复执行：

```powershell
python migration/fast_validate_phase1.py
```
