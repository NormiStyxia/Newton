# 第一阶段迁移实现说明

## 已完成边界

- 采用编辑器策略 A：Maker 只读取 Phaser 导出的关卡 JSON，运行时编辑器不迁移。
- 所有 9 个正式关卡及 2 个隔离关卡 JSON 均按字节复制并由 `LevelData -> RuntimeFactory -> UrhoX instance` 加载；墙、发射台、目标、弹簧、按钮、门及频道逻辑均已接入。
- 画面使用原 Phaser 的 `1880 × 840` 设计空间和响应式布局参数；NanoVG 以 DPR 感知的 Mode A 渲染顶部 HUD、实验区、Newton 面板、规则卡、机关、目标扫描器、结果面板和回放控制。
- 苹果保留原版拖拽限制、最小发射距离、速度/角速度系数、场地规则、相位穿墙、弹性墙、按钮 HOLD/TOGGLE、门 anti-crush、弹簧冷却/一次性和目标停留判定。
- 已迁移卡牌预备、手牌重排、方向停稳手势、0.05 子弹时间、690ms 燃烧、修正拳、轨迹记录和 0.5×/1×/2×回放。
- 原版 `SynthAudio.ts` 的发射、规则生效、碰撞、修正拳、成功和重置音效已按其振荡器、包络、噪声和低通参数派生为 WAV；运行时保留原版 80ms 碰撞去重。
- 不保留运行时几何体替代方案；苹果、发射台和 Newton 肖像使用原资源派生或原始 PNG，其他原版矢量图形按其绘制参数使用 NanoVG 重建。

## 坐标与单位换算

原项目的关卡坐标为 `1400 × 700`，实验视口为 `1500 × 596`，整体设计空间为 `1880 × 840`：

- 位置：`viewportX = levelX / 1400 × 1500`，`viewportY = levelY / 700 × 596`。
- 物体尺寸：沿用原 `CoordinateConverter.objectScale = 596 / 700`。
- UrhoX 世界：`100 viewport pixels = 1 meter`，Y 轴反向。
- JSON 顺时针视觉旋转转换为 UrhoX 的负角度。
- 原 Matter 重力 `WORLD_FORCE_SCALE = 0.001` 在 60 Hz、100 px/m 下对应约 `10 m/s²`。
- 原 Matter 发射速度（px/step）乘 `60 / 100` 转为 Box2D 的 m/s。

这些换算集中在 `scripts/migration/CoordinateMapper.lua`，运行时工厂不自行猜测比例。

## 资源约束

原 Phaser SVG 保持只读且不被运行时直接引用。Maker 使用独立 PNG 资源，来源、SHA-256 和尺寸记录在 `phase1_asset_manifest.json`；由原版 Web Audio 参数派生的 WAV 及其 SHA-256 记录在 `phase1_audio_manifest.json`。全部关卡副本与原始 JSON 保持 SHA-256 一致。旧的 `solid.png`/几何背景派生物已删除。

## FAST_VALIDATE

验证范围：

1. 校验全部 11 个源关卡与 Maker 副本的 SHA-256、schema、正式关卡对象边界和完整对象类型集合。
2. 校验坐标往返、地面映射、原 SVG/PNG 与派生 PNG 的 SHA-256 和图片尺寸，以及原版 SynthAudio 源、派生 WAV 和 Maker 元数据。
3. 以基准、宽屏、窄屏和 DPR=2 样本数值校验 NanoVG Mode A、DPR 缩放、布局及输入逆变换，并静态确认 Box2D trigger、苹果刚体、目标资源、卡牌燃烧/子弹时间、回放、音频触发和编辑器排除边界。
4. Lua 文件另以 Lua 5.3 语法解析器检查；Maker Lua LSP 仍需在其工具重新可用后作为远端构建前置检查。

不执行整关试玩，也不执行 Maker 远端 build/submit。

可重复执行：

```powershell
python migration/fast_validate_phase1.py
```
