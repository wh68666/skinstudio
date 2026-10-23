# SkinStudio

一个 Windows 托盘软件，统一管理 **ZCode、MonkeyCode、Codex、OpenCode、WorkBuddy 桌面端**的皮肤。
由原 ZCode Skin 项目合并扩展，主题库共用，每个应用的当前主题、程序位置和调试端口分别保存。

项目仓库：[wh68666/skinstudio](https://github.com/wh68666/skinstudio)。

## 使用

1. 下载单文件 `SkinStudio-v2.8.3.exe`，无需解压、安装或另配脚本，直接双击即可。
2. 双击 EXE，在窗口上方选择应用。
3. 选主题，点击“应用所选”；支持拖入 ZIP、导入 ZIP、在线图库下载安装。
4. “程序 / 端口”可手动选择桌面端 EXE 和独立端口；“恢复官方外观”只恢复所选应用。
5. 最小化后留在托盘。托盘也可以切换应用、主题和打开主窗口。

首次换肤需要重启所选应用以启用 CDP，恢复官方外观也会重启。**操作前先保存工作**。
已经由本工具带 CDP 启动的应用可直接切换主题。退出管理器后，当前页面皮肤仍在；
页面刷新或新窗口的自动补注需要管理器保持运行。正常退出应用再从原快捷方式打开，会恢复原生外观。

需要 Windows PowerShell 5.1（系统自带）和对应的官方桌面应用。
发行 EXE 已嵌入所需脚本、界面资源和内置主题，可以单独复制、移动或重命名运行。
源码入口是 `src/SkinStudio.app.ps1`，开发运行使用 `scripts/dev.ps1`，旧脚本入口保留在 `scripts/ZCodeSkin.app.ps1`。

## 单文件与用户数据（2.7.1）

- 程序依赖内嵌在 EXE 中，运行时自动准备到 `%LOCALAPPDATA%\SkinStudio\runtime\`，无需用户管理这些文件；缓存按内容隔离，并在启动时校验和修复。
- 配置、主题、导入记录、缩略图和日志保存在 `%LOCALAPPDATA%\SkinStudio\data\`。主窗口左下角“数据目录”可直接打开，替换或移动 EXE 不影响这些数据。
- 从旧版升级时，先把新 EXE 放到原目录运行一次；用户数据目录尚为空时，自动复制原目录中的配置、主题、导入及验收记录。旧文件保留，已删除的内置主题不会被重新添加。
- 需要自定义数据位置时可使用 `SkinStudio.exe -DataDirectory "D:\My SkinStudio Data"`。源码和命令行工具默认与 EXE 共用 Windows 用户数据，也支持通过 `-DataDirectory` 隔离。

## SkinStudio 自身界面皮肤（2.7.0）

窗口顶部的“SkinStudio 界面”提供云白、暮夜、鸢尾、松林四款内置皮肤，以及“跟随系统”。选择后立即生效，自动保存，下次启动恢复；跟随系统会响应 Windows 应用浅/深色设置变化。

主题覆盖主界面、卡片、搜索框、下拉菜单、按钮、外观调节、程序设置和兼容性验收窗口，深色皮肤也使用对应的窗口标题栏。该选择只改变管理器外观，五款目标软件的主题、收藏及微调数据保持各自独立。

## 工作页面兼容性验收（2.6.0）

- 新增“兼容性验收”入口，固定检查长对话、代码块、输入框、分栏、上下文、菜单及设置，分别记录浅/深色共 14 项。
- 应用卡片显示版本与验收情况。应用或适配更新后旧记录不会算作当前版本通过，并提示重新验收；首次检测到的版本显示尚未验收。
- 检查当前页面、查看本机截图、填写备注后人工确认通过或记录问题。自动观察不会代替人工验收，缺失场景保持待验收。
- 已补 MonkeyCode 实机证据 12/14 项，独立上下文面板仍待验收；修复浅色代码块注释对比不足，排除宠物悬浮窗注入。
- 新增 56 项合成工作页面回归；其他应用当前版本的实机覆盖范围、操作步骤和限制见 [COMPATIBILITY.md](docs/COMPATIBILITY.md)。

## 换肤状态与故障处理（2.5.0）

- 顶部四张应用卡片显示“未安装、未运行、已连接、需要重启”；点击卡片切换应用。状态在后台定期检测，悬停可查看程序位置、端口及重启原因。“未安装”表示暂未探测到有效桌面程序，可手动指定位置。
- 换肤按实际执行显示“启动应用 → 等待连接 → 应用皮肤 → 验证效果”，并显示已用时间。已连接的应用跳过启动和重启；等待兼容页面最长 40 秒。
- 成功前独立读取每个目标页面的主题标记、有效样式表与壁纸，并验证图片可以解码；部分页面失败也会提示验证未通过。这里验证的是样式与图片生效情况，复杂布局仍可能需要目视检查。
- 失败直接显示所在阶段、原因和错误详情，包括程序无效、启动失败、端口占用、连接超时、脚本错误及验证失败。“重试”复用同一应用、主题及当时的微调参数，并使用当前的程序位置和端口；切换主题选择不会改变重试目标。
- “查看日志”打开本机 `logs/app.log`，其中记录各执行阶段和完整错误。图库加载消息不会覆盖换肤失败提示。
- 恢复官方外观显示相应的重启、等待启动与验证启动阶段；因官方方式不会启用调试连接，此时验证的是应用进程重新运行。

## 缩略图主题库（2.4.0）

- 本地与远程主题均使用自适应卡片，展示壁纸、浅/深色标记、版本及当前应用的使用状态。未标注模式的主题不会凭图片猜测深浅色。
- 输入名称、主题 ID 或远程作者搜索，支持大小写不敏感的多关键词匹配；“×”清空搜索，“仅收藏”筛选星标主题。
- 点击卡片右上角星标收藏 / 取消收藏。收藏按主题 ID 在本地与远程列表、五个应用之间共用，保存在本机设置中；不会修改图库网站的收藏。
- 单击卡片选择，双击本地卡片应用默认皮肤，双击远程卡片下载。点击收藏不会触发应用或下载；原有导入、删除、微调操作继续沿用。
- 本地壁纸后台解码为小尺寸缩略图；远程预览来自图库官方预览接口，后台加载并缓存到 `assets/thumbnails/`。加载失败会显示占位卡片，不阻塞搜索和本地换肤。
- 远程搜索 / 收藏筛选会在后台补全目录，加载期间先显示已取得的结果；预览只为当前批次匹配项加载，“加载更多”继续展示，避免一次下载整个主题库的图片。
- 外观微调默认折叠，展开后继续编辑。搜索、收藏筛选保留所选主题及尚未保存的微调草稿。

## 外观微调（2.3.0）

选择本地主题后，展开“外观微调”：

- 面板不透明度 0–100%，数值越小越能看清壁纸；背景模糊 0–20 px，0 表示清晰原图。
- 壁纸位置可跟随主题或选居中、四边、四角；输入框、菜单和固定标题栏保留各自的阅读底色。
- “清晰壁纸 / 柔和玻璃 / 阅读优先”只填充编辑器参数，调整滑块本身也不会改变已应用的主题。
- **应用并保存微调**：保存所选应用、所选主题的参数，并应用它；失败时保留之前成功应用的外观，保存值可重试。
- **应用已保存微调**：一键复用这个应用、这个主题的保存值，不会误用编辑器尚未保存的改动。
- **应用所选**和**恢复主题默认**始终使用原先的默认效果，不删除已保存的微调。

每个应用、每个主题分别保存一组微调。关闭管理器或重启后仍可复用；自动补注和开关浅/深色同步、可读性时保留当前已应用的微调。
有调试连接时即时应用；首次启用换肤仍可能需要重启所选应用，滑块操作不会触发重启。
当前设置版本为 4，自动迁移旧配置并保留已保存的微调。升级后请使用新版软件管理设置，旧版会拒绝覆盖这些新设置。

## 五种应用如何适配

| 应用 | 技术 | 默认端口 | 换肤方式 |
|---|---|---|---|
| ZCode | Electron / Tailwind v4 | 9223 | 启动参数打开 CDP，壁纸绘制到 `#root`，覆盖表面变量 |
| MonkeyCode | Tauri / WebView2 | 9224 | 仅给子进程设置 WebView2 调试参数，复用官方壁纸层和 daisyUI 变量 |
| Codex | Electron | 9335 | 探测桌面安装，CDP 注入壁纸，映射背景、面板、文字、强调色变量 |
| OpenCode | Electron 桌面版 2.x | 9336 | 共用主题壁纸，适配 v2 UI 和原生色板变量，玻璃面板及原生浅/深色同步 |
| WorkBuddy | Electron 桌面版（本机验证 5.8.3） | 9337 | 子进程专用调试端口，独立聊天/分栏样式及原生浅深色同步 |

2.8.0 新增 WorkBuddy：选择顶部 WorkBuddy 卡片，选择主题并应用即可。支持现有主题、恢复官方外观、可读性增强、外观微调及按主题保存微调。首次换肤需要重启目标应用，请先保存工作。默认读取运行进程、安装注册表和常用安装目录；也可在“程序 / 端口”指定 WorkBuddy.exe。仅支持带 resources/app.asar 的 Electron 桌面版。

WorkBuddy 需要通过子进程环境变量 WORKBUDDY_REMOTE_DEBUGGING_PORT 启用调试连接，默认使用 9337；不会写入系统环境变量。已有 WorkBuddy 进程因权限不同而不可访问时会提示原因，请让 SkinStudio 与 WorkBuddy 使用相同权限。主窗口和真实设置窗口分别识别，图片预览等窗口不注入。WorkBuddy 配置和微调与其余四款应用隔离。

2.2.0 新增 OpenCode：左上角选择 OpenCode 后即可应用现有主题，设置和端口独立保存。
默认探测 `%LOCALAPPDATA%\Programs\@opencodedesktop\OpenCode.exe` 及运行中的桌面程序，
也可以在“程序 / 端口”手动选择。仅支持带 `resources/app.asar` 的 Electron 桌面版，
终端 CLI 和旧 Tauri 桌面版不适用。本机 OpenCode 2.1.2 的独立测试实例已验证浅/深色壁纸、输入框和菜单；未重启用户原来的会话。
菜单使用不透明底色，按钮保留原生状态；主内容使用半透明玻璃，避免给每个按钮增加底框。
原生 `opencode-color-scheme` 偏好用于持久保存浅/深色，保留原有 `opencode-theme-id` 色板选择。

2.2.1 修正 OpenCode 会话分栏：左右阅读面板各绘制一层玻璃，消除上下文 / 审查面板内部底色反复叠加形成的白块；
固定标题栏保留遮挡滚动文字的底色，输入框、浮层、代码和网页内容继续使用各自的表面。
已在运行中的真实会话页检查上下文分栏，更新样式无需重启该会话。

2.2.2 去掉 OpenCode 聊天和侧边内容面板的背景模糊，直接显示清晰壁纸；保留单层半透明阅读底色、固定标题栏遮挡和输入框表面。

Codex 桌面程序通常是 `OpenAI.Codex_.../app/ChatGPT.exe`；`codex.exe` 是 CLI，不能用作桌面端。
自动探测包括运行进程、Microsoft Store 安装注册、常见目录和卸载注册表项。
Store 更新导致路径变化时会重新探测。若当前版本不接受调试参数或 Windows 拒绝直接启动，
界面会报告错误；不会修改 WindowsApps 权限或安装文件。

本机开发时确认的桌面程序为 OpenAI.Codex 26.1016.6573.0 的 `ChatGPT.exe`。
2.1.1 优化 ZCode 的玻璃层次：去掉壁纸染色和全窗口重复底层，内容区与侧栏分别绘制半透明面板，项目工具栏与输入框合为一张玻璃卡片，淡化首页装饰标识；保留原生按钮状态、菜单可读性及浅/深色同步。

2.1.0 默认在应用皮肤时自动匹配浅/深色外观：读取 `theme.json` 的 `appearance: light|dark`，
没有明确标记时保留当前模式。主窗口可以按应用关闭“随皮肤自动切换浅色 / 深色外观”。
关闭只停止之后的同步，不会把应用恢复到此前的模式；恢复官方皮肤也保留当前原生外观设置。

ZCode 使用应用原生主题 store，Codex 使用原生 `appearanceTheme` 设置，已在本机验证持久保存。
MonkeyCode 优先寻找原生主题 setter，并沿用现有 `mc.theme` 的存储格式；没有可识别的持久化入口时，
仅同步当前渲染页面外观。MonkeyCode 本机现已补做部分工作页面的实机验收，具体版本与待验收项见 [COMPATIBILITY.md](docs/COMPATIBILITY.md)。
切换皮肤和重载页面会执行同步；用户手动改变原生模式后，不会在后台持续强制改回。

2.1.0 同时修复 ZCode 浅色主题文字泄漏到原生深色菜单的问题：作者 CSS 限定在匹配模式内生效，
并为 ZCode 增加轻柔可读性开关，修正菜单、弹窗、次要文字和图标的对比度，不增加独立按钮底框。

2.0.1 已在正在运行的 Codex 上通过 CDP 应用并检查实际渲染截图，无需重启当前会话。
聊天主面板按 50% 不透明度处理，输入框保留 88% 底色；浅色主题不会覆盖深色模式的原生文字色。
同时覆盖独立 Chromium 上的真实 CDP 通信、三种注入脚本的壁纸渲染、配置/导入逻辑，
并增加超过 2 MiB 的壁纸回归检查。ZCode、MonkeyCode 尚未完成全部页面逐项视觉验收。
Codex 适配是第一版：目前提供壁纸与基础颜色，复杂主题中依赖 Dream Skin 自身 DOM 标记的
布局效果、自定义 `codex-extra.css` 不会直接照搬。

2.0.1 还修复了后台检查期间点击换肤被忽略、在线图库加载阻塞本地换肤的问题。
2.0.2 清除输入区外层的白色整块背景及其上方渐变，保留输入框本身的阅读底色。
2.0.4 将 Codex 可读性开关调整为轻柔玻璃效果（默认开启）：导航与工具栏共用半透明底层，
按钮默认保持透明，不加粗边框或独立底框；仅在悬停和选中时轻微高亮，图标增加柔和阴影。
主面板在浅色模式下为 56%、深色模式下为 64% 不透明度，减少对壁纸的遮挡。
关闭开关恢复原来的透明效果。
2.0.5 移除菜单栏与页面之间原生预留的 8px 标题栏间距，避免透明皮肤露出横向缝隙。
偏好按应用保存，切换主题时继续沿用；禁用按钮和发送按钮保留原来的状态与语义色。
更新适配器后，即使主题 ID 和版本不变，运行时修订标记也会触发重新注入；桌宠浮层不会加载主窗口壁纸。

Codex 官方也支持基础外观、颜色和字体设置，参见
[官方外观设置](https://learn.chatgpt.com/docs/reference/settings#appearance)。
壁纸不修改安装文件。开启自动外观同步时，只更新原生浅/深色模式，不覆盖自定义配色或字体。

## 主题共用与迁移

- 启动读取旧 ZCode `config.json`，把旧路径、当前主题、端口迁移为 `apps.zcode`。
  首次保存时写入版本 4 配置，MonkeyCode、Codex、OpenCode、WorkBuddy 独立配置，不会误用旧端口。
- 现有 ZCode 主题目录原位保留。
- 原 MonkeyCode 主题可把整个 `themes/<id>` 目录复制到本软件的 `themes/`，或压缩该目录后导入。
  重名主题请先自行保留备份。管理器没有自动查找、修改另一份软件的用户目录。
- 新导入的 Dream Skin ZIP 保留原始色板，按所选应用转换；旧主题缺少色板时从已有 CSS 变量读取。
- 支持原生主题包的 `background` 字段和 Dream Skin 包的 `image` 字段。
- 删除主题会清除五个应用中引用该主题的记录；已注入页面会保留到恢复或重启。
- 导入限制：ZIP 不超过 32 MiB、32 项、解压内容不超过 64 MiB；有 manifest 时逐文件校验 SHA-256。

```text
themes/<id>/
  theme.json       id、name、version、appearance、colors、position 等
  theme.css        ZCode 或 MonkeyCode 原生样式 / 导入生成的调色板
  background.jpg   也支持 jpeg / png / webp
  codex-extra.css  保留的源主题 CSS，不直接注入
```

旧软件和 SkinStudio 不应同时给同一应用持续换肤，否则两个注入器可能轮流覆盖。
共享主题不表示所有应用 DOM 相同：只迁移可映射的颜色、壁纸和定位，各自的专用选择器分开处理。

## 脚本使用

```powershell
# 不指定 Application 时仍默认 ZCode，兼容旧命令
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-start.ps1 -Application zcode -Theme aurora -Force
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-start.ps1 -Application monkeycode -Theme aurora -Force
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-start.ps1 -Application codex -Theme aurora -Force
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-start.ps1 -Application opencode -Theme aurora -Force

# 恢复指定应用
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-clear.ps1 -Application codex

# 共用主题导入；imports/ 中的 ZIP 也会在脚本启动时自动导入
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/skin-import.ps1 -Zip C:\path\theme.zip
```

## 项目结构

源码在 `src/`，命令在 `scripts/`，打包模板在 `packaging/`，内置资源在 `resources/`，文档在 `docs/`。生成文件进入 `build/` 和 `dist/`，旧本地数据保留在 `data/legacy/`，均不提交。

详细目录和路径约定见 [PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)。

## 开发与构建

```powershell
# 开发运行
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1

# 回归验证：临时配置/主题、独立无界面 Edge，不重启用户应用
powershell -NoProfile -ExecutionPolicy Bypass -File tests/verify.ps1

# 界面与三语言自检，不联网、不导入到用户主题库、不写用户配置
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 -SelfTest

# 生成 EXE 与包含内置主题的便携发布包，需要 ps2exe
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1
```

源码界面自检输出在 `build/selftest-data/logs/selftest.txt`，预览在同目录的 `selftest-ui.png`。
`config.json`、`themes/`、`imports/`、`logs/` 都是本地用户数据；发行 EXE 内只带内置 Aurora，未包含本机配置或下载的皮肤。升级仅需替换 EXE，用户数据独立保留。

核心源码集中在 `src/`：`SkinStudio.app.ps1`（统一界面、托盘、图库、多应用监控）、
`skin-lib.ps1`（CDP、ZIP、ZCode 样式）、`skin-platforms.ps1`（五应用适配、路径探测、配置迁移）、
`skin-opencode.ps1`（OpenCode 桌面壁纸和玻璃样式）、
`skin-workbuddy.ps1`（WorkBuddy 桌面聊天及设置窗口适配）、
`skin-operation.ps1`（执行阶段、应用状态和独立效果验证）、`skin-status-ui.ps1`（状态卡片、进度、错误与重试）、
`skin-visuals.ps1`（微调配置、预设及五应用样式）、`skin-visual-ui.ps1`（微调编辑器）、
`skin-theme-browser.ps1` / `theme-cards.xaml`（卡片、搜索、收藏）、`skin-thumbnails.ps1`（预览解码与缓存）、
`skin-appearance.js`（原生外观同步与兼容回退）。

## 实现与参考

不修改官方二进制、app.asar、签名或系统级环境变量。调试端口只允许本机回环监听，
注入前校验监听者属于所选程序，并过滤应用页面，跳过内嵌网页和远程 WebSocket。
本机其他进程仍可能访问无鉴权 CDP；恢复外观或正常重启应用后关闭调试端口。

参考：[MonkeyCode Skin](https://github.com/wh68666/monkeyscode-skin)、
[Codex Dream Skin](https://github.com/Fei-Away/Codex-Dream-Skin)、
[Codex Dynamic Skin](https://github.com/CCDawn/Codex-Dynamic-Skin)。
来源说明见 [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md)。
