# 项目目录

EXE 是发行产物。PowerShell、JavaScript 和 XAML 仍是需要维护、测试及提交到 Git 的源文件；打包时按清单嵌入 EXE。

```text
skinstudio/
├── README.md
├── src/                  程序入口、应用适配、界面、注入脚本和运行资源
├── scripts/              开发运行、CLI、构建、验证及发布命令
├── packaging/            单文件启动器模板及资源映射清单
├── resources/
│   ├── icons/            编译用图标
│   └── themes/aurora/    随程序提供的内置主题，纳入版本控制
├── docs/                 兼容性报告、发行说明、来源说明及本文档
├── tests/                回归、数据迁移、工作页面和独立 EXE 检查
├── build/                编译结果、测试输出和临时文件，不提交
├── dist/                 当前发行 EXE 及历史产物，不提交
└── data/legacy/          旧工作目录数据的本地归档，不提交
```

## 常用入口

从仓库根目录执行：

```powershell
# 开发运行，使用与已发布软件相同的 Windows 用户数据目录
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1

# 独立的开发数据，避免影响正在使用的设置
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/dev.ps1 -DataDirectory "D:\My Test Data"

# 编译 -> build/SkinStudio.exe
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1

# 生成单文件发行程序 -> dist/SkinStudio-v<版本>.exe
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build-release.ps1

# 回归 + 源码界面自检 + 单文件发行包自检（先构建）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify.ps1 -IncludePackage
```

`scripts/publish-release.ps1` 只在源代码提交并上传之后使用，会检查远程主分支、标签及安装包校验值。

## 路径约定

- `src` 保持运行资源集中，内部相对引用不依赖调用者的工作目录。
- `packaging/package-files.ps1` 显式映射“源码路径 → EXE 内部路径”，发行程序不依赖仓库目录结构，也不把整个工作目录打包。
- 编译中间文件在 `build/intermediate/`，源码界面自检结果在 `build/selftest-data/logs/`。
- 实际用户配置和主题仍在 `%LOCALAPPDATA%\SkinStudio\data\`，源码运行和 CLI 默认与 EXE 共用；可以通过 `-DataDirectory` 隔离。
- 原根目录的配置、下载主题、缩略图和日志已保留在 `data/legacy/`，历史研究和测试文件在 `build/legacy-research/`。这些不是运行依赖。
- 已发布的历史安装包在 `dist/`，旧版 EXE 保留在 `build/legacy/`。用户删除的主题不会因为整理目录而重新加入用户主题库。

2.7.2 发布整理后的项目结构，安装包只提供独立 EXE；历史 GitHub Release 保留，不覆盖旧版本附件。
