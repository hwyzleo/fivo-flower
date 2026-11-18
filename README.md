# FIVO 的花花

个人植物养护、植物档案与花园资产管理 iOS 应用。iPhone 竖屏、iOS 17+、SwiftUI + SwiftData，本地优先，无需注册。

## 快速开始

```bash
# 构建
xcodebuild -project FivoFlower.xcodeproj -scheme FivoFlower \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.2' \
  CODE_SIGNING_ALLOWED=NO build

# 或使用封装脚本
./scripts/ci.sh build
./scripts/ci.sh unit   # 单元 + 集成测试
./scripts/ci.sh ui     # UI 测试
./scripts/ci.sh        # 全部
```

用 Xcode 打开 `FivoFlower.xcodeproj` 后可直接运行 `FivoFlower` scheme。工程使用 Xcode 文件系统同步目录，新增 Swift 文件会自动加入 Target。

- 最低系统：iOS 17.0
- 设备：iPhone 竖屏
- 显示名：FIVO 的花花
- Bundle ID：`net.hwyz.fivo.flowers`（测试 Target：`net.hwyz.fivo.flowers.tests` / `net.hwyz.fivo.flowers.uitests`）

## 功能概览

| 模块 | 能力 |
|---|---|
| 花房 | 分类数量、搜索、状态/平台/位置筛选、排序、双列卡片、长按多选与批量养护、空状态 |
| 植物档案 | 新增/编辑/复制、可选采购账目、初始状态开始日期、分类与陪伴天数、当前养护状态与唯一周期设置入口、封面裁剪、照片墙、死亡/赠送/恢复/删除 |
| 生长状态 | 预设与自定义状态、单进行中状态、切换、历史更正、单株/全局统计 |
| 日志 | 状态、养护、照片、资料修改、归档等自动日志；手动日志；图片缩略图与数量、只读详情、全局筛选时间线 |
| 养护与周期 | 内置/自定义养护类型、单株与批量记录、照片/用量、每 N 天/周/月/年周期、手动养护自动完成待办、带日期数量标记的每日待办日历、低库存提醒 |
| 订单导入 | 多截图、Vision OCR、本地解析、字段确认、重复提示、可选采购账目、手动回退 |
| 账本与工具 | 支出/收入/退款、分类汇总、月度趋势、账目搜索筛选、工具档案、库存历史、设备手动状态 |
| 数据安全 | `.fivoflower` 版本化备份（ZIP + manifest + data + 媒体）、校验后整体替换、自动安全备份、CSV 导出、清空数据；iCloud 云盘备份与从云端恢复（备份包维度，非实时同步） |

## 架构

```text
FivoFlower/
├── App/              # App 入口、环境装配、根导航与新增动作面板
├── Domain/           # 纯业务模型、计算规则、Repository/Service 协议
├── Data/             # SwiftData 记录、FivoDataStore、备份 DTO 与文件服务
├── DesignSystem/     # Tactile Soft UI Token、组件、图片加载与相机
├── Features/         # Garden / Growth / Journal / Care / Import / Ledger / Settings
└── Services/         # OCR、通知、ZIP
```

- View 只依赖 `AppEnvironment` 暴露的 Repository/Service 协议。
- 领域计算（分类、陪伴天数、状态统计、账本口径、库存）为纯 Swift，可注入 `Calendar` 与时间。
- 单次业务写入共享同一个 SwiftData `ModelContext`，只在操作结束时 `save()`，保证植物、日志、账目等不会半写入。
- 杂志式 `@Model` 与备份/网络 DTO 分离；备份金额使用字符串以保持精度。
- 图片数据库只存相对路径，原图与缩略图分离；封面裁剪生成独立派生图。

## 测试

- 单元测试：`FivoFlowerTests/DomainRulesTests.swift`
  - 分类/周年/闰日、陪伴与状态天数、喷梗间隔与开花时长、金额精度与校验、退款口径、库存、提醒重复规则、订单解析与 AI 字段合并、CSV 转义。
- 集成测试：`FivoFlowerTests/DataStoreIntegrationTests.swift`
  - 建株事务（状态 + 日志 + 账目 + 封面）、状态切换唯一进行中、历史更正重叠、归档/恢复、删除保留账目、批量养护、提醒下一次触发、库存边界、导入重复。
- 备份测试：`FivoFlowerTests/BackupIntegrationTests.swift`
  - 备份—清空—恢复 round-trip、损坏包不改变现有数据、版本拒绝、ZIP 路径安全、CSV 中文/BOM。
- 云端备份测试：`FivoFlowerTests/CloudBackupTests.swift`
  - 命名与上传、同分钟覆盖、列表过滤、保留策略（最近 7 份 + 每周最早 1 份）、清理不越界、未登录/云盘关闭降级、下载中与文件缺失、云端恢复 round-trip、删除、24 小时自动备份。
- 增强规则测试：`FivoFlowerTests/CareAndJournalEnhancementTests.swift`
  - 当前养护状态、日历待办过滤、日志图片来源关联。
- UI 测试：`FivoFlowerUITests/AppFlowUITests.swift`
  - 空花房创建植物、长按多选与批量养护、养护日历、种子数据详情与状态切换面板、手动记账、设置页备份到 iCloud。

## 合规说明

App 不发起任何网络请求：无 AI Provider、无第三方 SDK、无自有服务端。全部数据（植物、照片、日志、养护、工具、账目）默认仅保存在设备本地沙盒，备份文件由用户自行导出与保管。

**iCloud 云盘备份（可选，对应 FR-DATA-007~012）**：开启后把同一份 `.fivoflower` 备份包写入用户**本人**的 iCloud 云盘（「文件」App 的「FIVO 的花花备份」目录中可见），用于历史版本回滚与跨设备搬数据。数据只经过 Apple iCloud，不经过任何自有服务器或第三方服务，可随时关闭并删除云端包。该功能不含实时多设备同步（CloudKit 数据库同步仍属首版后迭代）。

## 文档

- [SPEC 需求](docs/spec/SPEC_REQUIREMENTS.md)
- [SPEC 设计](docs/spec/SPEC_DESIGN.md)
- [SPEC 开发计划](docs/spec/SPEC_DEVELOPMENT_PLAN.md)
- [实现状态与已知差距](docs/IMPLEMENTATION_STATUS.md)
- 视觉参考：`ui.png`
