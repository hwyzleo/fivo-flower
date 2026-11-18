# FIVO 的花花 — SPEC 设计

- 文档版本：v2.0

> **变更提示（2026-11-17，补丁 12）**：AI 小花灵（植物识别、养护问答）、AI 订单解析增强、AI 服务配置与 Keychain 凭据管理已从 App 中移除；右上角「提醒中心」此前已在补丁 10 移除。本文档中相关章节仅作为历史设计记录保留，不再代表当前实现。当前版本不发起任何网络请求，订单导入仅使用设备端 OCR 与本地解析，未授权的通知由「养护日历」Tab 兜底。

- 对应需求：[SPEC 需求](./SPEC_REQUIREMENTS.md)
- 实施安排：[SPEC 开发计划](./SPEC_DEVELOPMENT_PLAN.md)
- 视觉参考：[项目根目录 ui.png](../../ui.png)，仅参考风格，不复制其页面布局

## 1. 技术设计

### 1.1 技术选型

| 项目 | 选择 | 说明 |
|---|---|---|
| UI | SwiftUI | iOS 17+，声明式页面与组件复用 |
| 状态管理 | Observation + MVVM | `@Observable` ViewModel，页面状态与持久化解耦 |
| 本地持久化 | SwiftData | 本地优先，使用版本化 schema 和显式迁移 |
| 图片 | PhotosUI + 本地文件管理 | 原图/缩略图分离，数据库只保存相对路径 |
| OCR | Vision `RecognizeTextRequest` | 默认设备端执行，支持中文和英文 |
| AI | 可替换 Provider + `async/await` | 业务层不依赖具体厂商 SDK |
| 通知 | UserNotifications | 本地通知与应用内周期待办 |
| 导出 | JSON/ZIP 备份、CSV、系统分享面板 | 备份带 schema 版本，CSV 使用 UTF-8 |
| 凭据 | Keychain | API Key 不进入 SwiftData、日志和备份 |

首版采用单一 Xcode App Target，按模块目录组织，不提前拆分过多 Swift Package。业务逻辑使用协议隔离，为后续 iCloud 同步和测试替身预留边界。

### 1.2 模块结构

```text
FivoFlower/
├── App/                    # App 入口、依赖装配、路由
├── Domain/                 # 业务模型、计算规则、Repository/Service 协议
├── Data/                   # SwiftData Model、Repository、迁移、文件存储
├── DesignSystem/           # 色彩、材质、阴影、按钮、卡片、输入组件
├── Features/
│   ├── Garden/             # 花房、植物详情、编辑、分类筛选
│   ├── Import/             # OCR、订单确认、导入记录
│   ├── Growth/             # 状态、照片、统计
│   ├── Care/               # 养护、批量动作、提醒、养护日历与状态计算
│   ├── Journal/            # 单株和全局时间线
│   ├── Ledger/             # 账本、工具资材、金额统计
│   ├── AI/                 # 识别、问答、上下文选择
│   └── Settings/           # 设置、备份、导出、隐私
└── Services/               # OCR、AI、通知、备份、图片、权限
```

### 1.3 依赖方向

`Feature → Domain Service/Repository Protocol → Data/Service Implementation`。

- View 不直接执行 OCR、网络、通知或文件恢复。
- ViewModel 负责展示状态和用户意图，纯业务计算放在无 UI 依赖的 Domain 服务。
- SwiftData `@Model` 不直接作为 AI DTO 或备份格式，避免持久化变化扩散到外部接口。
- 所有写操作由 Repository 在明确事务边界内完成。

## 2. 导航与交互结构

```text
RootTabView
├── 花房
│   ├── 植物详情
│   │   ├── 编辑植物
│   │   ├── 当前养护状态
│   │   ├── 状态切换 / 状态历史
│   │   ├── 照片浏览 / 封面裁剪
│   │   ├── 单株日志 / 日志详情 / 新增日志
│   │   └── 单株统计
│   ├── AI 小花灵
│   │   ├── 养护问答
│   │   ├── 植物识别
│   │   └── AI 服务配置引导
│   └── 设置
├── 档案日志
│   └── 日志详情 / 筛选
├── ＋（模态动作面板）
│   ├── 手动添加植物
│   ├── 订单截图导入
│   ├── 记养护（支持批量）
│   ├── 添加工具资材
│   └── 记一笔
├── 花园账本
│   ├── 账目 / 工具库（页内分段）
│   ├── 账目详情 / 编辑
│   ├── 工具详情 / 库存调整
│   └── 金额统计
└── 日历
    ├── 月份与日期切换
    └── 当日养护待办 / 完成
```

通用规则：

- 新增保存后显示轻量成功反馈，并跳转到新档案或可撤销提示。
- 表单有未保存修改时，关闭需确认。
- 破坏性操作使用确认对话框；按钮文案明确“删除植物”“清空全部数据”。
- 所有异步操作具备加载、取消、失败重试，禁止重复提交。

## 3. 页面设计

### 3.1 花房首页

从上到下：

1. 标题“Fivo的花花”，右侧 AI 小花灵、提醒、设置。
2. 搜索框：品种、别名、编号、店名。
3. 横向分类胶囊：全部、活 1 年、活 2 年、活大于 2 年、死了、送了、未分类，附数量。
4. 筛选与排序栏：生长状态、平台、位置、排序；已生效条件显示数量。
5. 双列植物卡片网格。卡片使用封面、名称、状态标签、陪伴天数和位置；死亡/赠送降低封面饱和度但保持文字对比度。
6. 空状态：无植物时提供“添加植物”和“订单导入”；无筛选结果时提供“清除筛选”。

长按植物卡片进入多选模式并选中该卡片，多选模式下点击卡片只切换选择状态，不进入详情。选择栏展示已选数量，提供全选、取消和“批量养护”；发起时将所选植物 ID 传入现有批量养护表单，保存或取消后退出多选并清理选择。普通模式点击卡片仍进入详情。

分类数量及天数由领域计算器产生，不在 View 内各自实现。

### 3.2 植物新增/编辑

分组表单：基本信息、购买信息、养护环境、其他信息。

- 品种名称必填，其余字段渐进展示，降低首屏复杂度。
- 入手价使用小数键盘；购买日期使用日历选择。
- 来源链接只做格式提示，不强制联网验证。
- 手动新增提供“同时生成采购账目”开关，默认关闭；开启后复用购买日期、入手价、平台和店名生成植物采购支出，金额为空或为 0 时不生成账目并给出说明。
- 初始生长状态提供“设置开始日期”开关，关闭时 `PlantCreationOptions.initialStageStartedAt` 为 `nil` 并使用创建时间；开启时通过日期选择器传入所选日期，持久化前统一转为当前时区当日零点，且 Repository 拒绝未来日期。初始日志和档案创建时间仍使用实际创建时间。
- 编辑价格且存在自动采购账目时，提供独立“同步更新采购账目”开关，默认关闭。
- 保存时一次事务写入植物、初始生长状态、封面关联、初始日志及可选账目。

### 3.3 订单导入

步骤条：选择截图 → 识别中 → 确认识别结果 → 完成。

- 多截图按卡片横向切换，每张独立显示状态和错误。
- OCR 在本地执行；AI 增强仅发送 OCR 文本，除非未来明确增加图像解析授权。
- 字段旁展示“需确认”状态，不用红绿色作为唯一提示。
- 确认页可修改品种、日期、金额、平台、店名、编号、规格、来源链接等。
- “生成采购账目”默认开启，金额为空时自动关闭并说明。
- 重复导入仅警告，不强制阻断。
- 后台识别切换页面后可通过导入记录继续查看；取消识别不得产生正式植物。

### 3.4 植物详情

1. 大封面与名称，右上编辑；封面支持查看和更换。
2. 陪伴天数主卡片，展示分类和位置。
3. 当前养护状态卡片：按启用的养护动作逐行展示上次操作和下次待办；上次操作取该动作最新养护记录，下次待办取同动作最早一条未完成记录。无记录或无周期分别显示“未记录”“未设置下次待办”。每行右侧始终显示“设置周期”：无周期时进入添加页，有未完成周期时进入修改页，预填当前植物、动作、标题、周期和下次时间；保存或取消后重新加载养护状态。
4. 当前生长状态卡片：状态、持续天数、开始日期，主按钮“切换状态”。
5. 快捷操作：拍照记录、记养护、写日志。
6. 页内分段：概览、日志、照片、统计。
7. 概览展示购买信息、植料、位置、来源链接和订单截图。
8. 死亡/赠送植物顶部显示归档条，并提供恢复入口。

状态切换表单保存时，上一段状态与新段状态使用相同事件时间。结束开花时可引导返回养叶养根，但仍由用户确认。

### 3.5 照片与封面

- 照片墙按时间倒序，标识其来源状态、养护或日志。
- 全屏浏览支持缩放、删除、设封面。
- 封面编辑使用方形裁剪框，保存独立裁剪参数或派生图，不修改原始照片。
- 列表使用缩略图；原图仅详情和导出时读取。

### 3.6 养护与提醒

- “记养护”先选动作，再选植物；默认带入发起页面植物，批量模式使用多选网格。
- 动作类型采用图标 + 文案，不只用颜色区分。
- 用量和单位作为可选组合字段。
- 周期设置与养护记录分离：可只记录不设置周期，也可创建未来养护计划。植物详情是添加/修改周期的唯一入口，编辑器支持预填植物、动作、标题、重复方式和下次待办时间。
- 重复方式仅包括每 N 天、每 N 周、每 N 月、每 N 年，N 最小为 1。周按 7N 天计算；月/年按日历月份计算，目标月没有同日时取月末。
- 只有完成当前待办才生成下一条，不提供跳过。日历完成同时写养护记录；修改周期只更新当前未完成待办，以最近养护时间（无记录时为周期创建时间）加新周期重算。
- 手动或批量记录养护时，按植物和动作查找最早未完成待办，同事务标记完成并生成下一条，下一时间为实际养护时间加周期；没有对应待办时只写养护记录。
- 底部“日历”使用自定义月历网格选择自然日，按 `dueAt` 过滤待办；有待办日期在数字下方显示红色“N 项”标记并使用浅红背景，无待办日期不显示标记。支持前后月份切换、回到今天和相邻月份日期选择，不提供新建周期或跳过按钮。
- 日历待办展示植物、动作、到期时间和重复规则，可完成；操作后刷新当日列表、通知调度及植物养护状态，不展示低库存提醒和历史任务。
- 当前养护状态由纯领域计算器从动作类型、养护日志和周期待办派生，不新增冗余持久化字段；动作 ID 优先匹配，历史快照名称用于兼容已删除动作。
- 启动时清理 `recurrenceRaw` 无法解析为新周期的旧记录；旧 `every:N` 每 N 天编码继续有效，旧仅一次和按星期记录不做兼容。

### 3.7 档案日志

- 顶部植物筛选、类型筛选、日期筛选。
- 时间线按日期分组，卡片显示类型、摘要和时间；单株及全局日志有关联图片时，右侧显示第一张缩略图，多图叠加总数，无图不保留右侧占位。
- 图片通过日志的 `sourceType + sourceID` 与照片来源关联：手动日志、养护和生长状态分别匹配对应来源，照片新增日志匹配照片 ID；不复制图片引用到日志模型。
- 资料修改日志只保存字段级摘要，例如“修改了植料、摆放位置”，避免敏感旧值无意义堆积。
- 点击日志由当前详情页显式设置日志路由并进入只读详情，避免与外层植物详情路由混用；详情展示完整时间、文字、植物及全部关联图片，图片可全屏查看；源记录已删除时保留必要摘要并显示“来源已删除”。

### 3.8 花园账本与工具库

页内分段“账目”“工具库”，避免增加底部 Tab。

账目页：

1. 累计投入及植物/工具资材拆分。
2. 月份或年度筛选。
3. 分类汇总和月度趋势。
4. 搜索、分类过滤和交易列表。
5. 主按钮“记一笔”。

工具库页：

- 分类筛选、搜索和低库存筛选。
- 工具卡片显示照片、名称、数量/库存、位置和价格。
- 设备“使用中”开关必须标注“仅记录状态”，不展示虚假在线状态。
- 库存调整采用增加/减少/直接校准三种方式，并写库存历史。

### 3.9 AI 小花灵

- 首页提供“植物识别”和“养护问答”两个主入口。
- 问答页顶部可添加/移除当前植物上下文，并明确展示将发送的数据范围。
- 识别结果按候选展示，不将低置信度结果写成确定事实。
- 回答下方保留“AI 建议仅供参考”说明。
- 未配置 Provider 时展示配置说明，其他 Tab 不受影响。
- 网络请求支持停止；失败保留用户输入，避免重试时重写。

### 3.10 设置与数据管理

分组：提醒、养护类型、生长状态、AI 服务、数据管理、隐私与关于。

- 备份展示文件内容、创建时间和版本。
- 恢复先解析到临时目录并完成全量校验，再显示摘要；替换前自动生成当前数据安全备份。
- API Key 使用安全输入框，保存到 Keychain；设置页只显示掩码。
- 清空数据与恢复均不可仅靠滑动或单次点击执行。

## 4. 数据设计

以下字段描述逻辑模型，具体 SwiftData 类型可在实现时做持久化适配。所有实体默认包含 `id: UUID`、`createdAt`、`updatedAt`；需要同步预留的实体增加可选 `deletedAt`。

### 4.1 Plant

| 字段 | 类型/规则 |
|---|---|
| name | String，品种名称，必填 |
| alias / plantCode / specification | String? |
| acquiredAt | Date?，购买日期 |
| purchasePrice | Decimal?，非负 |
| currency | String，默认 CNY |
| platform / storeName / sourceURL | String? |
| medium / location / notes | String? |
| lifeStatus | active / dead / gifted |
| lifeEventAt / lifeEventReason / giftRecipient | 归档信息 |
| coverPhotoID | UUID? |
| orderScreenshotIDs | 关联原始截图 |

索引建议：`name`、`alias`、`plantCode`、`acquiredAt`、`lifeStatus`、`updatedAt`。

### 4.2 GrowthStageDefinition 与 GrowthSession

`GrowthStageDefinition`：`key`、`name`、`isBuiltIn`、`isEnabled`、`sortOrder`、`colorToken`。

`GrowthSession`：`plantID`、`stageID`、`startedAt`、`endedAt?`、`note`。

约束：同一植物最多一条 `endedAt == nil` 的记录；`endedAt >= startedAt`，且同株 Session 时间区间不得重叠。当前状态取未结束 Session，历史按开始时间倒序；更正历史后须重新计算统计。

### 4.3 PlantPhoto

`plantID`、`originalRelativePath`、`thumbnailRelativePath`、`capturedAt`、`caption`、`sourceType`、`sourceID`、`coverCropData?`。

- 原始截图可使用独立 `OrderAttachment`，避免与普通生长照片混在照片墙。
- 文件删除与数据库删除保持一致；事务失败不得留下不可追踪的正式引用。

### 4.4 CareActionType、CareLog 与 CareReminder

`CareActionType`：`key`、`nameSnapshotRequired`、`isBuiltIn`、`isEnabled`、`sortOrder`。

`CareLog`：`plantID`、`actionTypeID?`、`actionNameSnapshot`、`occurredAt`、`note`、`dosage?`、`unit?`、`batchID?`。

`CareReminder`（周期待办）：`plantID`、`actionTypeID`、`title`、`dueAt`、`recurrence`、`status`、`completedAt`、`notificationID`、`groupID?`。每株记录独立；当前未完成记录是修改周期的目标，已完成记录仅作为历史。`recurrence` 仅允许每 N 天/周/月/年，完成时使用实际养护时间作为下一条计算锚点。

### 4.5 JournalEntry

`plantID`、`kind`、`occurredAt`、`title`、`body`、`sourceType?`、`sourceID?`、`isManual`。

自动日志使用稳定的 `sourceType + sourceID + kind` 唯一约束防重复；手动日志无源关联。

### 4.6 ToolItem 与 StockAdjustment

`ToolItem`：`name`、`category`、`brand`、`specification`、`purchasedAt`、`purchasePrice`、`quantity`、`location`、`photoID`、`notes`、`isConsumable`、`stock`、`stockUnit`、`lowStockThreshold`、`lowStockEnabled`、`isDevice`、`isPoweredOn`。

`StockAdjustment`：`toolID`、`mode`、`delta?`、`resultingStock`、`occurredAt`、`note`。库存不得为负；直接校准记录调整后的结果。

### 4.7 LedgerEntry

`kind: expense/income/refund`、`title`、`category`、`amount: Decimal`、`currency`、`occurredAt`、`platform`、`storeName`、`plantID?`、`toolID?`、`note`、`sourceType?`、`sourceID?`、`relatedEntryID?`。

- `amount` 始终存正数，由 `kind` 决定计算方向。
- 自动采购账目使用 `sourceType + sourceID` 防重复。
- 档案删除后关联 ID 可置空，但保留原标题和来源摘要。

### 4.8 OrderImportRecord

`attachmentIDs`、`rawOCRText`、`recognizedDraftJSON`、`status`、`orderNumber?`、`failureMessage?`、`importedPlantID?`。仅用于继续导入、排错和重复提示；可在设置中清除未完成的识别缓存。

### 4.9 同步预留

首版不启用 CloudKit，但遵守：

- 使用稳定 UUID，不以数据库行号作为业务标识。
- 业务时间使用 UTC 存储，展示时转当前时区；自然日统计保留所需日历语义。
- 图片使用相对路径，不持久化沙盒绝对路径。
- Repository 不暴露 SwiftData 特有查询给 AI、备份和 View。
- Schema、备份格式分别版本化，迁移必须可测试。

## 5. 关键服务设计

### 5.1 领域计算

`PlantClassificationService`、`PlantDurationCalculator`、`PlantStatisticsService`、`PlantCareStatusCalculator`、`CareCalendarCalculator` 和 `LedgerCalculator` 为纯 Swift 类型，输入显式数据、日期和 `Calendar`，便于测试固定日期、周期提醒、闰年、周年和跨时区场景。

### 5.2 状态切换

```text
validate newStartedAt
→ 查询当前未结束 GrowthSession
→ 以同一时间结束旧 Session
→ 创建新 Session
→ 写自动 JournalEntry
→ 提交事务
→ 更新首页/详情/统计展示
```

并发保存通过 Repository 内串行事务及唯一约束防止两个进行中 Session。

### 5.3 OCR 与订单解析

```text
PhotosPicker
→ 本地持久化临时附件
→ Vision OCR
→ LocalOrderParser（金额、日期、平台等基础解析）
→ 可选 AIProvider.parseOrder(ocrText)
→ DTO 校验和字段置信度合并
→ OrderDraft 确认页
→ 用户确认后事务落库
→ 清理无效临时文件
```

AI 输出只接受预定义 JSON 字段；额外字段忽略，无效字段回退为 `nil`，不得因单个字段错误丢弃全部 OCR 结果。

### 5.4 AI Provider

```swift
protocol AIProviding {
    func identifyPlant(image: PreparedImage) async throws -> PlantIdentification
    func parseOrder(ocrText: String) async throws -> OrderAIDraft
    func reply(
        messages: [AIChatMessage],
        context: PlantAIContext?
    ) async throws -> AIChatReply
}
```

实现：

- `MockAIProvider`：确定性数据、延迟和错误注入，供 Preview 与自动化测试。
- `OpenAICompatibleAIProvider`：可配置 Base URL、Model、API Key，使用多模态输入及结构化 JSON 输出；仅作为通用 HTTP 适配，不在业务层暴露厂商字段。
- 后续新增厂商只需增加 Adapter 和设置项。

发布安全约束：TestFlight 可使用用户自行配置并保存在 Keychain 的凭据；若未来提供共享开发者凭据，必须改用受控后端代理，不得把共享密钥嵌入 App。

### 5.5 通知

通知 ID 与本地 Reminder ID 一一对应。创建、完成、删除和修改周期时同步更新系统 pending request。App 启动及进入前台时对账本地待办与系统通知，清理旧周期后同步移除无效通知，避免重复调度。

### 5.6 备份格式

建议使用扩展名 `.fivoflower`，本质为 ZIP：

```text
manifest.json       # formatVersion、appVersion、createdAt、实体数量、校验信息
data.json           # 与 SwiftData 解耦的版本化 DTO
Media/              # 原图、缩略图、订单附件
```

恢复流程：临时解压 → 大小/路径安全校验 → manifest 与 DTO 全量解析 → 媒体引用完整性校验 → 展示摘要 → 当前数据安全备份 → 替换 → 重建缩略图及通知。API Key、设备特定通知 ID 不导出。

## 6. Tactile Soft UI 设计系统

### 6.1 色彩

| Token | 值/用途 |
|---|---|
| `surfaceBase` | `#ECEEF2`，主背景 |
| `surfaceElevated` | `#EDEFF2`，卡片与浮层 |
| `accentGradient` | `#FFE27D → #FFAE34`，主按钮、进度环、滑块和重点波浪线 |
| `textPrimary` | 建议 `#30332F`，标题与关键数字 |
| `textSecondary` | 建议 `#656B67`，辅助信息，需通过对比度检查 |
| `danger` | 柔和但满足对比度的砖红色，仅用于危险操作和错误 |

柔金渐变上的文字统一使用深色，不使用白字。成功、警告、错误除颜色外同时提供图标或文字。

### 6.2 光影与材质

- 外凸卡片：左上高光 `-8, -8, 20, white 95%`；右下阴影 `8, 8, 20, rgb(190,198,210) 45%`。
- 内凹搜索框/滑道：使用相反方向的内阴影视觉，不对外再叠加厚重阴影。
- 主操作按钮采用柔金渐变与轻外阴影，按下时缩放至约 0.98 并减弱阴影。
- 背景可有极轻颗粒纹理，但不得降低文字可读性。
- 同一视觉层级不叠加多层重阴影；长列表优先使用简化的可复用阴影，避免离屏渲染性能问题。

### 6.3 形状、间距与字体

- 4 pt 基础网格，主要间距 8 / 12 / 16 / 20 / 24 / 32。
- 大卡片圆角 24–28，普通卡片 20，输入框与按钮 16–20，胶囊使用高度一半。
- 使用系统字体，标题 Semibold/Bold，正文 Regular，数字可使用 rounded 设计。
- 支持 Dynamic Type；大卡片在文字放大时改为纵向布局。
- 页面水平安全边距建议 20，底部内容避开中央新增按钮。

### 6.4 基础组件

`SoftCard`、`InsetSearchField`、`GoldPrimaryButton`、`SoftIconButton`、`StatusPill`、`ProgressRing`、`FilterChip`、`SoftTextField`、`PhotoThumbnail`、`EmptyStateView`、`ErrorStateView`、`ConfirmDestructiveDialog`。

所有组件提供默认、按下、禁用、加载、错误及无障碍状态，避免每个 Feature 独立实现阴影和颜色。

## 7. 权限、异常与隐私文案

- 相机：用于拍摄植物、养护记录和 AI 识别照片。
- 相册：用于选择订单截图、植物照片和封面；优先使用 PhotosPicker，避免无必要的全相册权限。
- 通知：用于养护和低库存提醒，在创建第一条提醒时申请。
- 网络：无系统权限弹窗，但 AI 首次使用时说明将发送的数据类型和服务方。

异常原则：本地保存失败不丢表单；图片失败不阻断文字记录；AI 失败不回退为虚假结果；备份恢复失败保持原库不变。

## 8. 可测试性要求

- 日期计算、分类、状态机、日志图片关联、养护状态、日历筛选和账本公式不依赖 SwiftUI。
- Repository、AI、OCR、通知和文件服务均有协议及测试替身。
- Preview 使用内存 SwiftData 容器和 Mock 图片，不访问真实用户数据。
- 备份 DTO 做编解码 round-trip；AI Adapter 做固定响应契约测试。
- 关键页面提供 UI 测试可识别的 accessibility identifier，同时保留自然语言无障碍标签。
