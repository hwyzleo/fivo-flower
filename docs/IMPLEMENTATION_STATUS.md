# FIVO 的花花 — 实现状态

- 更新日期：2026-11-17
- 对应版本：MVP v1.0 代码骨架与核心流程
- 验证命令：`./scripts/ci.sh`（Debug 构建 + 单元/集成测试 + UI 测试）

## 1. 里程碑状态

| 里程碑 | 状态 | 已实现 | 剩余/差距 |
|---|---|---|---|
| M0 工程与质量基础 | 完成 | SwiftUI iOS 17 工程、SwiftData 版本化 Schema、内存测试容器、Repository/Service 协议、统一错误类型、单元/UI 测试 Target、CI 脚本、显示名与权限文案 | — |
| M1 设计系统与本地数据骨架 | 完成 | 色板/字体/间距/圆角/柔光阴影 Token、SoftCard/输入/搜索/主按钮/Icon 按钮/Chip/状态标签/空错状态/Toast、缩略图与原图分离、相对路径、日期与金额工具、Debug 设计系统预览页 | 长列表超大样本实测未执行 |
| M2 花房与植物档案 | 完成 | 手动增改、校验、可选同步生成采购账目、初始生长状态开始日期开关与日期校验、复制、详情、封面裁剪、照片墙/全屏/设封面/删除、死亡/赠送/恢复/删除、分类数量、陪伴天数、搜索/筛选/排序、植物长按多选与批量养护入口、订单截图展示与删除 | 订单截图“替换”未提供（可删除后重新导入）；照片 EXIF 拍摄时间未读取 |
| M3 生长状态、日志与统计 | 完成 | 预设/自定义状态、单进行中约束、切换、历史更正与重叠校验、自动/手动日志、单株与全局时间线及筛选、日志图片缩略图/多图数量/只读详情/全屏图片、喷梗间隔/频率/开花时长、单株与全局年度统计 | 自动日志详情未提供编辑源记录入口 |
| M4 养护动作与周期 | 完成 | 内置/自定义养护类型与历史快照、单株/批量记录、照片/用量、当前养护状态与唯一添加/修改周期入口、每 N 天/周/月/年、仅完成后生成下一待办、修改周期自动调整、手动/批量养护自动完成对应待办、日历每日待办、本地通知与前台对账、低库存提醒与单个关闭、权限拒绝提示 | 完成提醒默认同时生成养护记录，未提供“只完成不记录”开关；类型排序未提供拖拽 UI |
| M5 订单导入 | 基本完成 | PhotosPicker/相机、Vision OCR、本地订单解析、确认页与低置信度提示、重复提示、多截图、失败回退、可选采购账目 | 未提供“未完成导入记录”继续入口 |
| M6 工具资材、账本与统计 | 基本完成 | 工具分类/档案/照片、消耗品库存与历史、低库存、设备手动状态、账目 CRUD、支出/收入/退款、来源关联、搜索/筛选、累计投入/分类汇总/月度趋势、价格同步确认、删除保留账目 | 账本分类排序、工具批量操作未实现；工具列表使用原图（未分离缩略图） |
| M7 设置、备份与导出 | 完成 | 设置页、养护/生长类型管理、权限入口、版本化 `.fivoflower` 备份（ZIP/manifest/data/媒体）、校验+安全备份+整体替换、损坏包保护、植物/账本 CSV 导出与分享、清空数据、隐私说明 | 备份未包含未完成订单导入的临时附件（设计允许清除缓存）；iCloud 云盘备份未实现（见 M9） |
| M8 集成、性能与 TestFlight | 部分完成 | 81 个单元/集成测试、14 个 UI 测试、空状态/错误文案、无障碍标签、减少动态效果阴影、浅色模式 | 大样本性能、VoiceOver 全路径、Dynamic Type 极限、真机矩阵、TestFlight 构建与隐私清单未执行 |
| M9 iCloud 云盘备份与恢复 | 完成 | `CloudBackupServicing` 与 `CloudBackupService`、iCloud Documents 容器与 Info.plist/entitlements、协调写入与占位下载、`fivoflower-<设备>-<时间>` 命名与保留清理、设置页云端卡片、后台 24h 自动备份、iCloud 不可用降级 | 未在真机 + 真实 iCloud 账号验收；「文件」App 可见性与跨设备互见需真机确认 |

## 2. 自动化测试

```bash
./scripts/ci.sh unit   # 81 tests
./scripts/ci.sh ui     # 14 tests（iOS 17.2 模拟器）
```

覆盖重点：

- 分类：购买当天、周年前后、闰日、死亡/赠送、未来日期。
- 天数：开始当天第 1 天、跨月/跨年、归档截止日、未来日期拒绝。
- 状态机：连续切换单进行中、历史更正重叠、归档阻止切换、恢复新建养叶养根。
- 统计：相邻喷梗间隔、单次无平均、进行中开花排除、年度过滤。
- 账本：Decimal 两位精度、关联退款冲减、未关联退款不计、收入不冲减、周期与月度趋势。
- 库存：增加/减少/校准、负库存拒绝、低库存边界。
- 导入：本地字段解析、订单号重复提示。
- 备份：备份—清空—恢复一致、损坏/版本拒绝不改变数据、ZIP 路径与 CRC 校验、CSV 中文与 BOM。
- 集成：建株事务、初始状态默认/指定开始日期与未来日期拒绝、零金额不生成采购账目、批量养护批次、提醒下一次触发、删除档案保留账目、类型删除保留历史快照。
- 本次增强：养护状态上次/下次时间、一次性提醒排除、已删除动作名称快照、日历按日过滤待办与月历日期数量标记、日志图片来源关联与稳定排序。
- UI：底部养护日历、长按多选两株并进入批量养护、照片分段与既有核心流程回归。

## 3. 体验修订（2026-11-16）

- 订单导入已选截图改为固定 3:4 缩略图横向列表，修复原图固有尺寸撑破布局、图片溢出屏幕的问题。
- 植物详情与添加照片的照片墙改为固定 1:1 缩略图网格，避免不同尺寸图片堆叠错位。
- 订单金额解析改为成交价优先（实付/实付款/成交价/到手价/应付 > 合计/总价），并排除原价、单价、划线价；支持“实付”换行后接金额。
- 商品名称解析改为按植物关键词、长度、元数据噪声打分选择标题行，并去除规格尺寸/营销词、按逗号截取品种名，避免把卖家昵称误当品种。
- 店铺识别支持卖家昵称、店铺名称、掌柜等标签，并过滤“信用/保障/包邮”等噪声。
- 平台识别补充常见平台名与域名（淘宝/天猫、闲鱼/goofish、拼多多、京东、抖音、小红书、微店、转转、得物）。
- 订单识别失败或字段缺失时仍以“需确认”标出，不阻断手动修改。

新增测试：成交价优先、换行金额、原价/单价排除、卖家昵称与标题分离、域名识别平台。

补丁 2（OCR 文本混入 App 页面）：
- 根因：系统相册多选会保留上次选择，误选的 App 截图（花房/植物详情）与订单截图一起被 OCR，导致“出花梗·第 1 天”等页面文字混入订单字段。
- 每次选择后清空 PhotosPicker 绑定，下次打开为全新选择；已选截图提供单张移除按钮。
- 新增 `OrderOCRTextSelector`：对每张截图的 OCR 文本打分，忽略含“当前生长状态/已陪伴/切换状态/花房”等 App 页面特征或与订单无关的文本块；全部为 App 页面时直接报错，不再生成错误草稿。
- 多张订单截图（商品页 + 支付页）仍会合并解析；确认页展示“已忽略 N 张”提示。
- 返回重选、关闭页面会清理临时附件，避免跨次导入残留。

新增测试：App 截图 + 订单截图混合时只取订单文本、全部为 App 页面时拒绝解析、多张订单截图合并。

补丁 3（封面图片撑宽卡片/详情页）：
- 根因：`StoredImage` 直接对 `Image` 使用 `aspectRatio(.fill)`，横图或非方形图会按固有比例产生超宽布局尺寸；`clipped()` 只裁剪绘制，不约束布局。
- `StoredImage` 改为 `Color.clear` 接受父视图尺寸 + `overlay` 绘制图片 + 裁切，图片不再参与宽度计算。
- 修复花房卡片、详情页封面、照片全屏、工具卡片/详情、编辑页封面预览等所有图片入口。
- UI 测试种子数据改为交替极宽/极高比例图片，并新增卡片不超出屏幕宽度的 UI 回归测试。

补丁 4（配置 AI 后首页仍显示“未启用”）：
- 根因：`AppSettingsStore` 不是 Observable，AI 首页在 Tab 切换回来时没有刷新，读取到的仍是首次渲染时的 `.none`。
- 新增 `AppEnvironment.settingsRevision`，AI 配置保存/清除 Key 时递增；`AIHomeView` 与设置页读取该版本号，配置变更后立即刷新服务名称与可用状态。
- UI 测试模式不再强制显示 Mock；新增 UI 测试：从花房设置中配置 Mock → 从花房右上角进入 AI → 断言显示“开发 Mock / 可用”。
- 问答测试改为先通过设置页配置 Mock，覆盖真实配置路径。

补丁 5（AI 问答输入框与封面自动抠图）：
- AI 养护问答输入框增加底部留白（92pt），键盘弹出时底部 Tab 栏自动隐藏，输入框与发送按钮始终位于 Tab 栏/键盘上方。
- 新增封面编辑器：选择封面后进入裁剪页，可选「自动抠图（本地）」。
  - 使用 iOS Vision `VNGenerateForegroundInstanceMaskRequest` 设备端主体分割，不联网、不需要配置 AI，也不会把图片上传给 AI 服务。
  - 抠图结果合成到柔和底色，仍可拖动/缩放构图。
  - 模拟器不支持该推理能力，入口会显示说明；真机可用。
- 详情页“裁剪设封面”与编辑植物页“选择/更换封面”均接入同一编辑器。
- 新增 UI 回归测试：从花房右上角进入 AI 后可使用问答输入框；抠图服务在模拟器返回受控能力提示。

补丁 6（植物养护交互、日志详情与养护日历）：
- 花房植物卡片支持长按多选、全选/取消和批量养护，修复长按释放额外触发点击导致首株选择反转的问题。
- 单株与全局日志按来源关联图片，列表右侧展示首图及多图数量，点击可进入只读详情并全屏查看。
- 手动添加植物新增默认关闭的“同时生成采购账目”，复用现有建株事务；空或零金额不生成账目。
- 植物详情在已陪伴与当前生长状态之间新增当前养护状态，按动作展示最近操作及最早的待处理周期提醒。
- AI 小花灵移至花房右上角，原底部入口改为养护日历，支持日期切换、当日待办、完成、跳过和新建提醒。
- 新增 5 个单元/集成测试及 2 个 UI 测试；全量 57 个单元/集成测试与 11 个 UI 测试通过。

补丁 7（日志路由与月历待办标记）：
- 修复单株日志点击被外层植物路由接管、重复进入植物详情的问题；改为由当前详情页显式推送日志详情。
- 系统 `DatePicker` 月历替换为自定义 7 列月历，支持月份切换、相邻月日期选择及回到今天。
- 有待办日期在数字下方显示红色“N 项”，并增加浅红背景；完成事项不计入数量。
- 新增月历日期数量计算单元测试、日志详情跳转及日历数量标记 UI 回归；全量 58 个单元/集成测试与 13 个 UI 测试通过。

补丁 8（初始生长状态开始日期）：
- 添加植物的初始生长状态增加“设置开始日期”开关；关闭时使用创建当天，开启时可选择今天或过去日期。
- 指定日期统一按当前时区当日零点写入首段状态，档案创建及初始日志仍使用实际创建时间；未来日期在 Repository 层拒绝。
- 新增默认/指定日期及未来日期集成测试和开关 UI 测试；全量 60 个单元/集成测试与 14 个 UI 测试通过。

补丁 9（植物详情快捷设置提醒）：
- 当前养护状态中没有下次周期提醒的动作，右侧显示“设置提醒”；已有周期提醒的动作不显示该按钮。
- 提醒编辑器新增可选预填参数，从具体动作进入时默认选中当前植物和养护动作，并生成同名提醒标题；其他入口行为不变。
- 为按钮提供按动作区分的无障碍名称，新增预填 UI 回归；全量 60 个单元/集成测试与 15 个 UI 测试通过。

补丁 10（周期待办重构，SPEC v2.0）：
- 删除右上角提醒中心及日历新建按钮，植物详情“设置周期”成为唯一添加/修改入口，所有动作始终显示。
- 周期仅支持每 N 天/周/月/年，移除仅一次、按星期和跳过；月/年按日历计算并在目标月无同日时取月末。
- 只有完成后才生成下一待办；修改当前未完成周期时按最近养护时间（无记录按创建时间）重算。
- 手动及批量养护在同一事务内完成对应最早待办，并以实际养护时间生成下一条，不重复创建养护日志；完成后立即对账系统通知。
- 启动时清理旧仅一次和按星期记录，保留有效每 N 天数据；备份恢复同样过滤无效周期。
- 新增周期修改、手动/批量联动、旧数据清理集成测试和添加/修改周期 UI 回归；全量 64 个单元/集成测试与 16 个 UI 测试通过。

补丁 11（Bundle ID 与钥匙串命名空间对齐）：
- 应用 Bundle ID 由 `net.hwyz.fivo.flower` 改为 `net.hwyz.fivo.flowers`，与开发者后台注册的 App ID 一致；测试 Target 由 `com.fivo.flower.*` 统一为 `net.hwyz.fivo.flowers.tests` / `net.hwyz.fivo.flowers.uitests`。
- 钥匙串 service 由 `com.fivo.flower.credentials` 改为 `net.hwyz.fivo.flowers.credentials`（`KeychainStore.defaultService`）。
- `AppSettingsStore` 初始化时对历史 service 做一次幂等迁移（新值存在则不动、失败保留旧条目下次重试），成功后清理旧条目。
- 已知限制：钥匙串默认 access group 含 Bundle ID 前缀，旧安装包写入的条目在新安装下通常不可读，AI API Key 需重新填写；`AppSettingsStore` 一直以钥匙串实际内容推导 `hasAPIKey`，设置页会如实显示未配置并允许重填。
- 无需任何 App ID capability；构建产物 `CFBundleIdentifier` 已校为 `net.hwyz.fivo.flowers`，68 个单元/集成测试通过。

## 4. 已知差距与后续建议

1. 未完成订单导入的“导入记录”列表未提供 UI；数据层已保存 `OrderImportRecord`，可在此基础上补充。
2. 工具图片未生成缩略图；大量工具时列表性能需优化（同植物照片的缩略图策略）。
3. 自定义养护类型/生长状态的排序尚未提供拖拽 UI；`sortOrder` 字段已就绪。
4. 订单原始截图不支持原位替换，只能删除照片后重新导入。
5. 备份恢复后封面派生裁剪图依赖备份内的 `covers/` 文件，已在备份中打包；跨设备恢复后需验证图片方向/色彩一致性。
6. 大样本性能、真机权限拒绝矩阵、VoiceOver 与最大 Dynamic Type 仍需按 M8 执行。
7. 通知对账在启动与回到前台执行；系统时间大幅跳变后的重复通知仍需真机验证。

## 5. 发布门槛检查

- P0：未发现崩溃、数据丢失或账目/计时错误；关键写入有事务边界与自动化测试。
- P1：核心流程均有实现与测试；备份恢复、权限拒绝替代路径（应用内提醒、手动导入）已覆盖。
- P2：视觉/文案细节、排序 UI、性能优化可记录后迭代。

上线前仍需完成：TestFlight 构建与审核材料、真机设备矩阵。

补丁 12（移除 AI 功能，2026-11-17）：
- 删除 AI 小花灵（植物识别、养护问答）、AI 订单解析增强、AI 服务设置与 Keychain 凭据管理，共移除 6 个源文件：`AIProviders.swift`、`AIModels.swift`、`Features/AI/*`、`OrderDraftMerger.swift`、`AppSettingsStore.swift`。
- `OrderDraft` / `OrderDraftField` 与 AI 无关，迁至新文件 `Domain/Models/OrderModels.swift`。
- 同时清理 `SettingsStoring` 协议、`AppEnvironment.settings/settingsRevision/settingsDidChange/makeAIProvider`、设置页 AI 卡片与隐私说明中的 AI 段落、花房右上角 AI 入口、隐私说明与备份文案中的 API Key 表述。
- 订单导入保留完整能力：多截图、Vision OCR、本地解析、字段确认、重复提示、手动回退，全部在设备端完成。
- App 现状：无任何网络请求、无第三方 SDK、无服务端、无账号体系。
- 测试：删除 1 个 AI 字段合并单元测试与 3 个 AI UI 测试及 `configureMockAI` 辅助方法；67 个单元/集成测试通过，UI 测试 13 个（`testPhotoGridShowsSquareThumbnails` 为 LazyVGrid 渲染计数的既有回归问题，与本次改动无关）。

补丁 13（iCloud 云盘备份，2026-11-17）：
- 需求：在现有本地 `.fivoflower` 备份之上，把同一份备份包写入用户本人 iCloud 云盘，支持历史版本回滚与跨设备搬数据；对应 SPEC 需求 FR-DATA-007~012、SPEC 设计 5.7、SPEC 开发计划 M9。
- 触发：设置页手动「立即备份到 iCloud」+ 退到后台且距上次成功 >24h 自动一次；不做写操作级上传。
- 命名与保留：`fivoflower-<设备名>-<yyyyMMdd-HHmm>.fivoflower`，每设备最近 7 份 + 每周最早 1 份 × 4；清理只作用于本设备命名的包。
- 内容：与现有备份完全一致（原图、缩略图、封面、订单附件），`formatVersion` 不变；不做「仅数据轻包」。
- 恢复：沿用「校验 → 摘要 → 安全备份 → 二次确认 → 整体替换」，不做跨备份合并。
- 明确不做：实时多设备数据同步、CloudKit 数据库同步与字段级冲突合并（仍属首版后迭代）。
- 实现方式：复用 `FileBackupService.createBackup()` 产物，经 `NSFileCoordinator`（`.forReplacing`）重命名移入容器，不改动备份格式与现有备份服务；`FileBackupService` 无需开放新的注入点。
- 工程配置：新增 `Config/FivoFlower.entitlements`（iCloud Documents + `com.apple.developer.ubiquity-container-identifiers`）与 `Config/Info.plist`（`NSUbiquitousContainers`），工程设置补 `CODE_SIGN_ENTITLEMENTS` 与 `INFOPLIST_FILE`（保留 `GENERATE_INFOPLIST_FILE = YES` 合并 `INFOPLIST_KEY_*`）。
- 代码：新增 `Domain/Protocols/CloudBackupServicing.swift`、`Services/CloudBackupService.swift`；`AppEnvironment` 注入 `cloudBackup`，`RootTabView` 在退到后台时触发 24h 自动备份；`BackupRestoreView` 新增云端备份卡片（可用性、自动备份开关、立即备份、云端列表、恢复与删除）；设置页隐私与备份文案同步修订。
- 测试：新增 `FivoFlowerTests/CloudBackupTests.swift` 14 项（命名与上传、同分钟覆盖、列表过滤、保留策略、清理不越界、未登录/关闭云盘降级、下载中与文件缺失、云端恢复 round-trip、删除、24h 自动备份、设备名净化）；新增 UI 测试 `testCloudBackupFromSettingsCreatesPackage`。全量 81 个单元/集成测试与 14 个 UI 测试通过（1 项为既有 `testPhotoGridShowsSquareThumbnails` 回归）。
- 修复：声明 iCloud 容器 entitlement 后，`ModelConfiguration` 的 `cloudKitDatabase` 默认 `.automatic` 会让 SwiftData 启用 CloudKit，与 `@Attribute(.unique)` 冲突导致启动崩溃（`无法创建数据容器：SwiftDataError 错误 1`）；已在 `PersistenceController.makeContainer` 显式传 `cloudKitDatabase: .none`，并在 SPEC 设计 4.9 记录该约束。
- 遗留：模拟器与 `CODE_SIGNING_ALLOWED=NO` 下无法验证真实 iCloud 容器，需真机 + 同一 Apple ID 两台设备做「文件」App 可见性与跨设备互见验收。

## 附：补丁 13 上线前置清单（门户 / 签名 / 审核）

### 1. Apple Developer 门户（Identifiers → `net.hwyz.fivo.flowers`）

| 项 | 做法 |
|---|---|
| iCloud 能力 | 开启。新版能力页勾 **iCloud Documents**，**不勾 CloudKit** |
| 旧版能力页 | 只有 `Include CloudKit support (requires Xcode 6)` / `Compatible with Xcode 5` 两个单选框时：选前者；"iCloud Documents" 通过给 App ID **分配 iCloud 容器**表达（容器列表在 iCloud 区块内） |
| iCloud Containers | `iCloud.net.hwyz.fivo.flowers` 必须存在并关联到该 App ID |
| In-App Purchase | 灰显不可取消，属 App ID 强制项，**无需处理**，也不产生任何 entitlement |
| 自动签名 | Xcode 会在首次构建时自动创建容器并更新 App ID，可跳过手工配置 |

### 2. 签名产物校验

```bash
codesign -d --entitlements :- /path/to/FivoFlower.app | plutil -p -
security cms -D -i /path/to/FivoFlower.app/embedded.mobileprovision | plutil -p - | grep -A6 icloud
```

期望：`com.apple.developer.icloud-services = ["CloudDocuments"]`，且 `icloud-container-identifiers` / `ubiquity-container-identifiers` 均为 `iCloud.net.hwyz.fivo.flowers`；embedded profile 必须包含 `CloudDocuments`。

报 `Provisioning profile doesn't include the com.apple.developer.icloud-services entitlement` 时，说明 profile 缺少 Documents 授权：回门户把容器分配给 iCloud Documents，或让 Xcode 重新生成 profile。

entitlements 只保留三个必要键（`icloud-container-identifiers`、`icloud-services`、`ubiquity-container-identifiers`）；未使用的 `ubiquity-kvstore-identifier` 已移除，避免与开发者门户配置不一致导致签名失败。

### 3. 真机验收（同一 Apple ID 两台设备）

1. 设置 → 备份与恢复：卡片显示自动备份开关与「立即备份到 iCloud」，而不是"未登录 iCloud"。
2. 点击「立即备份到 iCloud」→ 出现 `fivoflower-<设备名>-<时间>.fivoflower`。
3. 「文件」App → iCloud 云盘 →「FIVO 的花花备份」能看到同一个文件。
4. 设备 B 打开同一页面能看到设备 A 的备份，且 A 继续备份不会覆盖 B 的文件。
5. 设备 B 从云端恢复 → 数据与源一致；恢复前自动生成安全备份。
6. 退出 Apple ID 或关闭 iCloud Drive → 卡片给出原因与设置入口，本地备份、CSV 与分享导出仍可用。

### 4. App Store Connect

- **App 隐私问卷**：仍可声明「不收集数据」。依据：备份包只写入用户本人的 iCloud，开发者与自有服务器均无法访问，且该功能默认关闭。
- **审核备注建议原文**（可直接粘贴）：

```text
App 不含任何第三方 SDK，也不接入自有服务器。
首发版本新增可选的「iCloud 云盘备份」：仅在用户主动开启后，把本地备份包写入用户本人的 iCloud 云盘
（系统「文件」App 可见），开发者无法访问其内容；功能默认关闭，未开启时数据不离开设备。
iCloud 不可用（未登录 / 关闭云盘 / 空间不足）时功能优雅降级，本地备份与 CSV 导出不受影响。
```

- 数据流、触发方式、保留策略等详细说明见线上隐私政策 6.4 节：<https://fivoflowers.hwyz.net/>

### 5. 已知约束

- 声明 iCloud 容器 entitlement 后，SwiftData 的 `ModelConfiguration` 必须显式 `cloudKitDatabase: .none`；否则会按 `.automatic` 启用 CloudKit，与 `@Attribute(.unique)` 冲突，启动即崩溃（见 SPEC 设计 4.9）。
- iCloud 容器内只放 `.fivoflower` 包，禁止放入 SwiftData `.sqlite` 等活数据库文件。
