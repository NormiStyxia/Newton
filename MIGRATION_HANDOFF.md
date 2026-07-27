# 《牛顿看了想打人》TapTap Maker 迁移交接

## 项目位置

- 原 Phaser 3 项目：`D:\System Files\Download\牛顿\牛顿`
- 新 TapTap Maker 项目：`D:\System Files\Download\牛顿-maker`
- Maker App ID：`bac66748-5aca-4a5c-9188-54cefd824f21`
- Maker 主分支：`main`

## 已确认迁移策略

采用编辑器策略 A：

- Phaser 项目继续作为外部关卡编辑器和玩法原型。
- 每关独立保存并导出纯 JSON。
- Maker/UrhoX 运行时只消费导出的关卡 JSON。
- JSON 是关卡真相；Phaser 和 UrhoX 对象都只是运行实例。
- 第一阶段不把 Phaser 运行时编辑器迁移到 Maker。

## 技术迁移方向

- TypeScript/Phaser Scene 改写为 Maker Lua 模块。
- Phaser Matter 运行层改写为 UrhoX/Box2D 对应组件。
- Phaser Graphics/Text/DOM UI 改写为 NanoVG/UrhoX UI。
- 浏览器输入、Tween、AudioContext、localStorage 和 Vite `/api/levels` 不可直接搬用，需要 Maker 适配层。
- 优先复用纯数据和纯逻辑：关卡 JSON、对象 schema、规则卡数据、主题常量、回放记录结构和纯函数测试语义。

## 原项目已有系统

- 苹果发射与 Matter 碰撞。
- 规则卡、方向手势、子弹时间、燃烧特效。
- 牛顿怒气与修正拳。
- 墙体、发射器、目标 Sensor、弹簧、按钮、门及频道系统。
- Phaser 运行时关卡编辑器、Inspector、撤销/重做、JSON 导入导出和热更新。
- 轨迹记录与回放相关结构。
- `data/levels` 下有 9 个关卡 JSON。

## 硬性约束

- 不修改苹果、卡牌、发射台、墙体、门、按钮、弹簧、观察窗和角色等已有 SVG 源文件。
- 不修改 SVG path、viewBox、fill、stroke、transform 或内部节点。
- 若 Maker 运行时必须转换格式，只能在新项目创建独立派生资源，原 SVG 保持字节级不变。
- 不修改原 Phaser 项目的物理参数、规则效果和关卡数据来迁就迁移。
- 原 Phaser 工作区存在持续开发中的未提交改动；不得重置、覆盖或清理。
- 未经明确要求，不执行 Maker 远端 build/submit。
- 验证默认采用 FAST_VALIDATE，不完整试玩整关。

## Maker 初始化状态

- 官方 Maker CLI `0.0.27` 初始化成功。
- PAT 和 TapTap 登录状态有效。
- Git、Python 3.12、Maker Lua LSP 可用。
- AI dev kit、`engine-docs`、`examples`、`templates`、`urhox-libs` 已安装。
- `.maker-mcp/config.json` 已绑定上述 App ID。
- 新项目尚未创建 `scripts/main.lua`，也尚未远端构建。

## 新任务建议起点

1. 先读取本项目 `AGENTS.md` 和 Maker 开发套件文档。
2. 只读审计原 Phaser 项目的关卡 schema、坐标系统、对象注册表、规则入口和资源清单。
3. 在 Maker 项目建立引擎无关的 `LevelData -> RuntimeFactory -> UrhoX instance` 边界。
4. 先迁移一个最小垂直切片：读取一关 JSON，绘制固定 GameplayViewport，生成发射器、苹果、地面和目标 Sensor。
5. 验证坐标映射与 Box2D 碰撞后，再迁移卡牌、机关、回放和外围 UI。

新任务首条指令可使用：

> 读取 `MIGRATION_HANDOFF.md`、`AGENTS.md` 和 Maker 开发套件说明，检查原 Phaser 项目后开始迁移第一阶段。采用编辑器策略 A，不修改任何原 SVG，不执行远端构建，先完成可验证的本地最小垂直切片。
