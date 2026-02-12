# CryoNet 修复方案（不改代码版）

## 1. 目标与原则

1. 先恢复可编译可发布状态，再修行为一致性，再补测试与文档。
2. 优先处理“编译阻断”和“状态机错误”。
3. 每个修复都必须配套最小可回归测试（单元测试或集成测试）。
4. API 行为变更要在 README 和变更日志中明确说明。

## 2. 问题清单与修复策略

### P0（必须先修）

1. `UIKit` 在 macOS 条件下误导入导致编译失败  
文件：`Sources/CryoNet/Manager/DownloadManager.swift`  
修复：拆分条件编译，`UIKit` 仅 iOS/tvOS，`Photos` 仅支持平台按需导入。  
验收：`swift build` / `swift test` 在 macOS 通过。

2. 上传暂停不释放并发槽位，队列可能卡死  
文件：`Sources/CryoNet/Manager/UploadManager.swift`  
修复：`pauseTask` 时对 `currentUploadingCount` 做对称递减，并触发 `checkAndStartNext()`。  
验收：3 并发下暂停 1 个任务后，待队列自动补位。

3. 下载 `pauseTask` 会把非下载态任务错误置为 `paused`  
文件：`Sources/CryoNet/Manager/DownloadManager.swift`  
修复：仅 `downloading` 允许暂停，其他状态直接 return。  
验收：`completed/failed/cancelled` 调用 pause 不变更状态。

### P1（高优先）

4. 请求头覆盖逻辑与注释相反  
文件：`Sources/CryoNet/Core/CryoNet.swift`  
修复：同名 header 保留最后一个值（请求级覆盖全局）。  
验收：同名 `Authorization` 传入时以请求级为准。

5. `defaultTimeout` 配置未生效  
文件：`Sources/CryoNet/Core/CryoNet.swift`、`Sources/CryoNet/Model/Requests/RequestModel.swift`  
修复：建立“请求超时优先级”策略。  
建议：`RequestModel` 明确是否设置过超时，未设置时回退 `CryoNetConfiguration.defaultTimeout`。  
验收：未显式配置请求超时时，实际 timeout 等于全局配置。

6. `streamRequest` 忽略 `parameters` 与 timeout  
文件：`Sources/CryoNet/Core/CryoNet.swift`  
修复：将 `parameters` 编码进请求，应用 `model.overtime`。  
验收：流式 GET 可携带 query，超时可配置。

### P2（中优先）

7. SDK 层 `fatalError` 崩溃风险  
文件：`Sources/CryoNet/Manager/DownloadManager.swift`  
修复：无效 URL 改为可恢复错误路径（返回失败任务或抛错接口）。  
验收：传入非法 URL 不崩溃，可收到失败状态/错误原因。

8. 上传完成回调里存在潜在并发/竞态风险  
文件：`Sources/CryoNet/Manager/UploadManager.swift`  
修复：统一在 actor 内一次性写回任务状态与模型，避免多处异步写 `tasks[id]`。  
验收：高并发下 `model` 不丢失，状态不回退。

9. 管理池的删除 API 是 fire-and-forget，行为不确定  
文件：`Sources/CryoNet/Manager/DownloadManagerPool.swift`、`Sources/CryoNet/Manager/UploadManagerPool.swift`  
修复：移除内部 `Task`，改为 actor 内顺序 await 执行。  
验收：`removeManager/removeAll` 返回时资源已清理完毕。

### P3（工程质量）

10. 测试覆盖几乎为空  
文件：`Tests/CryoNetTests/CryoNetTests.swift`  
修复：补状态机与配置行为测试。  
验收：关键路径有自动化覆盖并稳定通过。

## 3. 具体实施顺序（建议）

1. 修 P0 + 先跑构建。
2. 修 P1 的 header/timeout/stream 参数。
3. 修 P2 的崩溃点与竞态。
4. 补测试。
5. 更新 README 与 CHANGELOG。

## 4. 测试计划（最小集）

1. 构建测试  
`swift build`（macOS）必须通过。

2. 下载状态机测试  
覆盖 `idle -> downloading -> paused -> downloading -> completed`。  
覆盖 `completed` 后调用 `pauseTask` 不应改变状态。  
覆盖 `cancelTask/removeTask` 的差异。

3. 上传状态机测试  
覆盖并发上限、暂停释放槽位、队列补位。  
覆盖取消后恢复流程。  
覆盖完成时模型写回一致性。

4. 配置行为测试  
覆盖 header 同名覆盖顺序。  
覆盖默认 timeout 与请求级 timeout 优先级。  
覆盖 streamRequest 参数编码与 timeout。

## 5. 文档同步要求

1. README 增加“超时优先级规则”说明。
2. README 明确 `cancel/remove` 语义差异。
3. README 明确上传当前是否支持 delegate（如未实现则只写闭包/查询）。
4. CHANGELOG 记录行为变更（特别是 header 覆盖与 pause 语义）。

## 6. 交付验收标准

1. 在 macOS 上可编译可测试。
2. 上传/下载状态机行为与文档一致。
3. 无 `fatalError` 的输入型崩溃。
4. 核心路径测试覆盖并稳定。
5. README 示例与实际 API 完全一致。
