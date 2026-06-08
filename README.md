# AI Quota Widget（多来源额度面板）

一个常驻 macOS 桌面的透明「液态玻璃」悬浮小组件，在一个窗口内实时显示 **Cursor / Codex / Antigravity** 三个来源的剩余额度，不打断开发工作流。

## 功能

- **透明液态玻璃悬浮窗**：基于 `NSPanel` + `NSVisualEffectView`，半透明、可透出桌面背景，精致且不打扰视线。
- **哆啦A梦卡通角色主题**：不仅有经典水箱圆形，还支持纯 SwiftUI 矢量路径绘制的**哆啦A梦全身形象主题**。水波水位会严格在角色全身轮廓内起伏，且文字配有半透明高对比度黑胶囊背板以防止文字遮挡。
- **三来源切换 Tab**：顶部 Cursor / Codex / Antigravity，切换即驱动对应 Provider；单来源失效（未安装/未登录/接口失效）只在其 Tab 显示引导态，不影响其它来源；启动默认落到一个可用来源。
- **三色 LED 状态灯**：剩余 `< 10%` 红、`< 20%` 黄、`≥ 20%` 绿。各来源主维度：Cursor=月额度、Codex=5h 窗口、Antigravity=默认模型。
- **水球水位动画**：圆形水球水位对应主维度剩余百分比，球心显示剩余用量；正弦晃动动画可在设置中开关。
- **双击折叠与展开**：小组件可以折叠为极简的悬浮球（支持 Tooltip 气泡提示当前激活的 AI 工具和计费/模型状态），**双击悬浮球即可平滑还原为大面板**，鼠标移开 0.8s 自动收回。
- **Cursor 计费模式直切**：支持解析 Cursor 新版 Usage-based（美元额度）计费。在主面板直接点击余额（如 `$167.78 left`）即可弹出菜单，在 **API 模式** 与 **Auto 模式** 之间直接无缝直切。
- **自定义 Codex 路径**：支持指定自定义 Codex 可执行路径（支持填入 `.app` 包路径如 `/Applications/Codex.app`，程序会自动寻路其内部二进制可执行文件），完美解决客户端安装在非标准目录导致无法加载的问题。
- **Antigravity 套餐展示**：接入本地 Connect 接口的 `/GetUserStatus`，自动高优解析并展示用户的套餐计划名称（如 `Google AI Pro`）。
- **心跳时长 GA4 统计**：后台自动使用 Google Analytics 4 (GA4) Measurement Protocol 进行匿名使用时长统计（事件 `app_heartbeat`），提供完全无感的零本地数据库统计服务。
- **窗口行为**：自由拖拽到任意位置、置顶/取消置顶切换、记忆窗口位置；不出现在 Dock 与 Cmd+Tab（Accessory 应用）。
- **设置与本地化**：中英文一键即时切换、可配置刷新间隔、手动刷新按钮、水球晃动开关；偏好持久化到 `UserDefaults`，重启恢复。

## 凭证来源（完全本地、不弹 Keychain、不依赖浏览器）

组件以只读方式（`mode=ro&immutable=1`）打开本地 Cursor 数据库：

```
~/Library/Application Support/Cursor/User/globalStorage/state.vscdb
```

读取 `ItemTable` 中的 `cursorAuth/accessToken`、`refreshToken`、`cachedEmail`、`stripeMembershipType`。令牌**仅驻内存**，过期或 401 时用 `refreshToken` 向 `oauth/token` 自动续期并重试一次；`shouldLogout=true` 时进入「需重新登录」态。组件自身不写入任何包含令牌的文件，错误信息对令牌明文与文件路径做脱敏。

## 各来源前置条件

| 来源 | 前置条件 | 未就绪时表现 |
| --- | --- | --- |
| **Cursor** | 已登录 Cursor 桌面端 | 未登录引导态 |
| **Codex** | 安装 Codex CLI（`codex` 在 PATH）且已登录（`~/.codex/auth.json` 有效） | 「未安装 Codex CLI」/「请先在 Codex 中登录」引导态 |
| **Antigravity** | Antigravity IDE 正在运行（本地 Language Server 可连）**或**本地存在有效 OAuth 凭证（云模式） | 「请先在 Antigravity 中登录」引导态 |

- **Codex**：组件按需 spawn `codex app-server` 短命子进程，由其自带的 `~/.codex/auth.json` 认证，无需 cookie/API key；读取完成立即结束子进程，整体带超时，绝不阻塞。
- **Antigravity**（本地模式已实地验证）：定位 IDE 内置 Codeium 系 `language_server` 进程，从其参数取 `--csrf_token`，用 `lsof -a -p <pid> -iTCP -sTCP:LISTEN` 取动态监听端口（参数里 `--https_server_port 0` 不含真实端口），再以 Connect 协议调本地 `https://127.0.0.1:<port>/exa.language_server_pb.LanguageServerService/GetAvailableModels`（自签名 TLS，仅信任 127.0.0.1；CSRF 头为 `x-codeium-csrf-token`）。该方法内部已认证并缓存代理云端 `FetchAvailableModels`，**不需要我们管理任何 OAuth**。解析 `response.models.<id>`：`displayName`（友好名）、`quotaInfo.remainingFraction`(0~1)、`resetTime`、`isExhausted`，主维度取 `defaultAgentModelId`。
  > 云模式（`refreshToken` → `oauth2.googleapis.com/token` → `fetchAvailableModels`）作为回退保留，但 Antigravity 使用其专属 OAuth client（非 Gemini CLI 公共 client），其 `client_id/secret` 尚待确认；IDE 运行时本地模式已足够，云模式当前默认不启用。
  > Codex `account/rateLimits/read` 的精确字段仍待在已安装并登录 Codex CLI 的环境实拉确认。相关常量集中在 `Constants.swift`。

## 构建与运行

### 方式一：完整 Xcode（推荐）

```bash
# 用 Xcode 打开 Package.swift，或：
swift build
swift run
```

### 方式二：仅 Command Line Tools

```bash
./build.sh
open .build/app/AIQuotaWidget.app
```

> ⚠️ **Gatekeeper 未签名拦截提示**：
> 如果您在打开应用时遭遇系统提示“应用已损坏，应移至废纸篓”或“无法验证开发者”，这是由于 macOS 针对未签名应用的 Gatekeeper 安全限制拦截所致。请使用以下两种方式之一绕过拦截：
> 
> * **图形化授信（推荐）**：在访达（Finder）中，**按住 `Control` 键并右键点击 `AIQuotaWidget.app`**，选择 **打开 (Open)**，在弹出的系统对话框中点击 **打开 (Open)** 按钮即可，后续再次双击即可正常使用。
> * **终端命令（命令行）**：打开终端运行以下命令清除隔离属性：
> 
>   ```bash
>   xattr -cr /Applications/AIQuotaWidget.app
>   ```

> ⚠️ **已知环境前置**：部分 macOS「命令行工具（Command Line Tools）」安装存在重复模块映射 bug
> （`/Library/Developer/CommandLineTools/usr/include/swift/` 下同时存在 `module.modulemap`
> 与 `bridging.modulemap`，二者都定义 `SwiftBridging`，导致编译任何 `import Foundation` 的代码报
> `redefinition of module 'SwiftBridging'`）。如遇此错误，删除其中一个重复文件即可修复（影响整机所有命令行 Swift 构建）：
>
> ```bash
> sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
> ```
>
> 或安装/切换到完整 Xcode：`sudo xcode-select -s /Applications/Xcode.app`。

## 运行单元测试

纯逻辑（额度归一化、LED 阈值、重置时间、脱敏）已覆盖单元测试：

```bash
swift test
```

## 权限说明

- 仅**只读**当前用户自己的 `state.vscdb` 与 `~/.codex/auth.json`（仅探测存在性），无需「完全磁盘访问权限」。
- Codex 通过 spawn 本机 `codex` 子进程取数；Antigravity 优先本机回环（localhost），云模式才访问 Google 端点。
- 不联网上报任何第三方；仅向各来源自身端点（`api2.cursor.sh` / 本机 Codex 子进程 / Antigravity 本地或 Google 端点）发起额度/令牌请求。

## 架构

```
Sources/AIQuotaWidget/
├── App/            程序入口、Accessory 策略、AppDelegate
├── Window/         FloatingPanel(NSPanel)、VisualEffectView、窗口控制器（拖拽/置顶/位置记忆）
├── Data/           凭证读取、令牌刷新、统一请求封装、Provider（Cursor legacy/usage-based/自动探测、Codex app-server、Antigravity 本地/云）、归一化（Cursor/Codex/Antigravity）、服务编排（三来源独立状态）
├── Settings/       AppSettings（UserDefaults 持久化）
├── Localization/   中英文案表（运行时即时切换）
└── UI/             ContentView、WaterBallView、LEDView、InfoBlockView、TabBarView、SettingsView
```

数据层以 `QuotaProvider` 协议 + 统一 `QuotaSnapshot` 隔离计费/产品差异，UI 只消费快照。

## 免责声明（逆向接口）

本组件使用的以下接口/通道均为**逆向获取的非官方/实验性接口**，可能随对应产品版本变更而失效，仅供个人额度查看：

- **Cursor**：`GET https://api2.cursor.sh/auth/usage`（legacy）、`POST .../GetCurrentPeriodUsage` 与 `GetPlanInfo`（usage-based）、`POST .../oauth/token`（令牌刷新）。
- **Codex**：本机子进程 `codex app-server` 的 JSON-RPC `initialize` + `account/rateLimits/read`（`app-server` 官方标注 experimental）。
- **Antigravity**：本地 Language Server 端点；云模式 `POST https://oauth2.googleapis.com/token`（固定 Google client）+ `POST https://cloudcode-pa.googleapis.com/v1internal:fetchAvailableModels`（`v1internal` 为内部端点）。云模式凭证仅本机使用、不外传；优先走本地模式以减少对云端逆向的依赖。

所有接口 URL、`client_id`、命令与方法名、字段名集中在 `Sources/AIQuotaWidget/Data/Constants.swift`，便于接口变更时快速修补。任一来源失效仅影响其自身 Tab，不拖垮其它来源。
