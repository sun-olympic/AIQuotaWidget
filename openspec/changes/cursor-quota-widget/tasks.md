## 1. 工程搭建

- [x] 1.1 创建 macOS SwiftUI App 工程（最低系统版本、Bundle ID、关闭沙盒以允许读取 `state.vscdb`）
- [x] 1.2 配置为 Agent/Accessory 应用（`LSUIElement`），不出现在 Dock 与 Cmd+Tab
- [x] 1.3 引入 SQLite 访问能力（系统 `libsqlite3` 或轻量封装），添加 README 与依赖说明

## 2. 凭证与令牌（quota-data-provider）

- [x] 2.1 实现 `CredentialStore`：以只读 `mode=ro&immutable=1` 打开 `state.vscdb`，读取 `cursorAuth/accessToken`、`refreshToken`、`cachedEmail`、`stripeMembershipType`
- [x] 2.2 凭证缺失时返回「未登录」状态，给出提示而非崩溃
- [x] 2.3 实现 `TokenRefresher`：调用 `POST .../oauth/token`（refresh_token，固定 client_id），更新内存令牌
- [x] 2.4 处理 `shouldLogout=true` → 进入「需重新登录」态并停止自动刷新
- [x] 2.5 确保令牌不落盘、错误信息脱敏（不含令牌明文与文件路径）

## 3. 额度数据层（quota-data-provider）

- [x] 3.1 定义 `QuotaSnapshot`（remainingPercent / primaryText / secondaryText / resetAt / planName / mode）与 `QuotaProvider` 协议
- [x] 3.2 实现 `CursorUsageBasedProvider`：`POST GetCurrentPeriodUsage` + `GetPlanInfo`，美分÷100、毫秒时间戳解析，归一化为快照
- [x] 3.3 实现 `CursorLegacyProvider`：`GET /auth/usage`，按 `(max-num)/max` 算剩余%、`startOfMonth+1周期` 算重置
- [x] 3.4 实现计费模型自动探测：先调 usage-based，有有效 `planUsage` 走新模型，否则回退 legacy
- [x] 3.5 令牌过期/401 自动刷新并重试一次的统一请求封装
- [x] 3.6 将接口 URL、client_id、字段名集中为常量，便于逆向接口变更时快速修补
- [x] 3.7 预留 `CodexProvider` 接口占位（二期实现）

## 4. 悬浮窗口与层级（widget-window-behavior）

- [x] 4.1 用 `NSPanel`（无边框、nonactivating、不抢焦点）承载 SwiftUI 内容
- [x] 4.2 集成 `NSVisualEffectView` 实现透明液态玻璃背景
- [x] 4.3 实现自定义拖拽区域，支持窗口自由移动到屏幕任意位置
- [x] 4.4 实现置顶/取消置顶切换（窗口 level 在 floating 与 normal 间切换）
- [x] 4.5 小尺寸 + 半透明呈现，保证不遮挡开发；记忆窗口位置

## 5. 核心 UI（floating-widget-ui）

- [x] 5.1 搭建整体布局，参照需求附图（顶部标题/状态、右上操作按钮区、左侧水球、右侧信息块）
- [x] 5.2 实现三色 LED 状态灯组件（<10% 红 / <20% 黄 / ≥20% 绿）+ 状态文字
- [x] 5.3 用 `Canvas` + `TimelineView` 实现水球：水位对应剩余%，球心显示「P% Left」
- [x] 5.4 实现水面正弦晃动动画，受设置开关控制（关闭则静态水位）
- [x] 5.5 渲染额度信息块：主额度文本、重置倒计时、计划名称（PRO/Ultra）
- [x] 5.6 实现顶部 Cursor/Codex 切换 Tab；Codex 显示「即将支持」占位
- [x] 5.7 数据失败/未登录态的 UI 呈现（提示而非空白或过期数据）
- [x] 5.8 usage-based 下 on-demand（spendLimitUsage）作为独立小条展示，不并入主水位

## 6. 设置与本地化（widget-settings）

- [x] 6.1 实现中英文本地化资源，语言切换即时刷新全部文案
- [x] 6.2 实现可配置刷新间隔 + 定时器；修改后立即生效
- [x] 6.3 实现手动刷新按钮（立即请求并重置定时器）
- [x] 6.4 实现水球晃动开关
- [x] 6.5 用 `UserDefaults` 持久化语言/刷新间隔/晃动开关/置顶状态/窗口位置，并在启动时恢复

## 7. 串联与校验

- [x] 7.1 串联数据层与 UI：定时刷新 → 探测 → 取数 → 归一化 → 更新水球/LED/信息块
- [ ] 7.2 对照每个 spec 场景手动验证（绿/黄/红、晃动开关、置顶、中英切换、间隔变更、未登录态、计费模型回退）— 待工具链修复后运行 App 验证
- [ ] 7.3 验证整窗液态玻璃质感与附图一致、不遮挡开发 — 待工具链修复后运行 App 验证
- [x] 7.4 编写 README：构建运行步骤、权限说明、逆向接口免责声明
