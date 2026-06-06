## 1. 统一模型扩展

- [x] 1.1 在 `QuotaSnapshot` 增加可选 `secondaryWindows: [Window]`（name / remainingPercent / resetAt），主维度字段保持兼容
- [x] 1.2 抽出「来源 → 主维度取值」映射表（Cursor=月额度 / Codex=5h / Antigravity=默认模型），阈值复用 <10/<20/≥20
- [x] 1.3 调整 UI 渲染范式为「主水球 + 次级条列表」，使三来源共用同一渲染

## 2. Codex Provider（codex-quota-provider）

- [x] 2.1 实现 `codex` 可执行探测与 `~/.codex/auth.json` 存在性检查，区分「未安装」与「未登录」引导态
- [x] 2.2 实现 `codex app-server` 短命子进程封装：JSON-RPC `initialize` 握手 + 握手后延迟
- [x] 2.3 调 `account/rateLimits/read`，解析 primary(5h)/secondary(7d) 的 usedPercent / resetsAt 与 planType；完成后结束子进程
- [x] 2.4 归一化为 `QuotaSnapshot`：主维度 5h（remaining=100-usedPercent），7d 进 `secondaryWindows`，计划名取 planType
- [x] 2.5 超时/异常处理：避免阻塞，失败转引导态；命令与方法名集中常量化

## 3. Antigravity Provider（antigravity-quota-provider）

- [x] 3.1 实现本地 Language Server 探测：定位进程、从参数提取端口与 CSRF token，调本地 API
- [x] 3.2 实现云模式回退：读取本地 refreshToken/projectId → `POST oauth2.googleapis.com/token` 换 access token
- [x] 3.3 调 `POST cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`（body `{"project":...}`），解析 `models.*.quotaInfo`（remainingFraction/resetTime/isExhausted）与 `defaultAgentModelId`
- [x] 3.4 归一化为 `QuotaSnapshot`：主维度取默认模型（remaining=fraction*100），其余模型进 `secondaryWindows`
- [x] 3.5 本地连不上且无有效云端凭证 → 未登录引导态；接口/字段集中常量化
- [x] 3.6 加入轻量缓存（如 5 分钟）避免频繁拉取

## 4. 三来源 Tab 集成（multi-source-tabs）

- [x] 4.1 顶部 Tab 扩为 Cursor / Codex / Antigravity 三栏，切换驱动对应 Provider
- [x] 4.2 渲染次级维度：Codex 显示 7d 窗口条，Antigravity 显示多模型分组
- [x] 4.3 来源可用性自适应：单来源失效只在其 Tab 显示引导/错误，不影响其它来源刷新
- [x] 4.4 首屏默认选中一个可用来源 Tab（按选定策略），持久化上次选中来源
- [x] 4.5 三来源文案接入既有中英文本地化

## 5. 串联与校验

- [x] 5.1 各来源接入定时刷新与手动刷新，仅优先刷新当前可见 Tab
- [x] 5.2 对照每条 spec 场景验证：Codex 双窗口取色、Antigravity 多模型取色、单来源失效隔离、未安装/未登录引导态、默认 Tab 落到可用来源
- [~] 5.3 实拉校验：**Antigravity 已在已登录环境实拉验证通过**——经本地 `language_server` 的 `GetAvailableModels`（内部代理 `FetchAvailableModels`）取得真实模型额度，已据实测修正端口发现（`lsof -a`）、CSRF 头（`x-codeium-csrf-token`）、字段名（`displayName`/`quotaInfo.remainingFraction`/`resetTime`），UI 正常渲染；**Codex 仍待**在已安装并登录 Codex CLI 的环境实拉 `account/rateLimits/read` 校验字段
- [x] 5.4 更新 README：新增来源的前置条件（安装/登录）、逆向接口免责声明
