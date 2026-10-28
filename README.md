# DeepSeek Harness One-Click Installer

面向 Windows 10/11 的 DeepSeek Harness 安装与启动工具。项目把 DSH 的 Node.js 运行时、用户数据目录和原生 EXE 启动器组合成一个可解压、可安装、可修复的仓库。

普通用户只需要运行 `1-一键安装.bat`；开发者可以直接检查 PowerShell 脚本、C# 启动器和测试。

## 项目提供什么

- 当前用户范围内安装，不要求把文件写入 `Program Files`。
- 自动检测 Node.js，并在需要时安装 Node.js LTS。
- 安装或更新 `@deepseek-ai/dsh`。
- 原生 `DeepSeek Harness.exe` 启动器，负责复用 DSH 服务、读取授权地址和打开应用窗口。
- 桌面和开始菜单快捷方式，使用官方 DeepSeek Harness 图标。
- 每日版本元数据检查；发现安装包更新后由用户确认，不静默替换文件。
- 修复、诊断和数据安全卸载脚本。

## 快速开始

### 从 GitHub 下载使用

1. 在 GitHub Releases 下载 ZIP；没有 Release 时使用仓库的 **Code -> Download ZIP**。
2. 解压整个目录，不要只复制某一个 `.bat` 文件。
3. 双击 `1-一键安装.bat`。
4. 安装完成后运行 `2-配置APIKey.bat`。
5. 使用桌面或开始菜单中的 `DeepSeek Harness` 图标启动。

安装器默认使用当前用户的 `%USERPROFILE%\DeepSeek Harness` 作为 `DSH_HOME`。如果用户已经设置过用户级 `DSH_HOME`，安装器会沿用原目录，因此不会因为切换启动方式而丢失旧会话。

### 已经安装过原版 DSH

直接运行 `1-一键安装.bat` 会部署 EXE 启动模式，同时保留已有的 `settings.yaml`、`.credentials.yaml`、`profiles`、`sessions` 和 `storages`。安装器不会主动删除聊天记录。

如果旧数据在自定义目录且没有设置 `DSH_HOME`，使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -HomeOverride "D:\你的旧DSH数据目录"
```

## 仓库结构

```text
1-一键安装.bat             新用户安装入口
2-配置APIKey.bat           API Key 配置入口
3-启动Web界面.bat          启动原生 EXE
4-卸载.bat                 安全卸载入口
5-后台启动.vbs             旧用户兼容入口
6-检查更新.bat             手动检查安装包更新
7-修复安装.bat             修复启动器、快捷方式和更新任务
8-生成诊断报告.bat         生成脱敏诊断报告

scripts/
  install.ps1              安装、迁移和快捷方式部署
  launch.ps1               调用已安装的原生启动器
  update.ps1               GitHub Release 更新检查
  register-update-task.ps1 注册当前用户的每日检查任务
  repair.ps1               不删除用户数据的修复流程
  diagnostics.ps1          生成脱敏诊断信息
  uninstall.ps1            删除程序但默认保留数据
  lib/InstallerCommon.psm1 路径、校验、健康检查和脱敏公共函数

template/                   新用户默认配置
launcher/
  bin/DeepSeek Harness.exe  可分发的原生启动器
  assets/DeepSeekHarness.ico 官方图标
  src/                      C# 启动器源码
  tests/                    启动器测试源码
  build.ps1                 本地编译和测试脚本

tests/                      PowerShell 测试和打包冒烟测试
installer-manifest.json     安装器和启动器版本清单
docs/                       设计文档
```

`launcher/bin/LauncherCoreTests.exe` 等测试输出属于本地构建产物，不是用户运行所需的文件，已由 `.gitignore` 排除。

## 启动器工作方式

原生启动器执行以下流程：

1. 使用当前用户的 `DSH_HOME`。
2. 检查本机 3080 端口；已有健康的 DSH 服务时直接复用。
3. 没有服务时，在隐藏窗口启动 `dsh web --no-open`。
4. 从本地启动日志读取带 token 的地址。
5. 用 Microsoft Edge 应用模式打开本地 Web 界面。
6. 使用单实例锁，避免重复启动多个后端。

启动器不会读取或修改聊天正文，也不会把 API Key 写入仓库。

## 更新机制

### DSH 运行时更新

再次运行 `1-一键安装.bat` 时，安装器会比较当前 DSH 版本和 npm 上的版本。版本相同就跳过重复安装；版本不同才执行 npm 更新。

### 安装包更新

`6-检查更新.bat` 检查 GitHub Releases：

- 没有网络时保留现有安装并退出。
- 没有新版本时不修改文件。
- 发现新版本时先询问用户。
- 下载的 Release 资产会在有 SHA-256 摘要时校验。
- 安装器不会在后台无确认地替换 DSH 或用户配置。

安装时会注册一个当前用户的每日检查任务。任务只执行元数据检查；真正安装更新仍需要用户运行新版安装包或手动确认。

## 开发和本地验证

### 环境

- Windows 10/11
- Windows PowerShell 5.1
- Node.js 18 或更高版本（运行 DSH 时需要）
- .NET Framework 自带的 `csc.exe`（编译原生启动器）

### 编译和测试原生启动器

```powershell
Set-Location .\launcher
.\build.ps1
```

该脚本会编译 `DeepSeek Harness.exe` 和 `LauncherCoreTests.exe`，然后运行启动器单元测试。

### 运行仓库测试

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\InstallerCommon.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Update.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Maintenance.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\PackageSmoke.ps1
```

安装脚本支持 DryRun，测试时不会安装 Node.js、DSH 或创建快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 `
  -DryRun -WhatIfLauncher -NoScheduledTask -NoNodeInstall -NoDshInstall
```

## 用户数据和安全边界

默认数据目录：

```text
%USERPROFILE%\DeepSeek Harness
```

其中包含：

- `settings.yaml`：用户设置。
- `.credentials.yaml`：API Key，不能公开。
- `sessions\`：会话记录。
- `storages\`：工作区和会话投影数据。
- `profiles\`：DSH profile 和插件配置。
- `launcher\logs\`：启动日志。

仓库的 `.gitignore` 会排除凭据、会话、压缩会话、日志、诊断报告、备份和本地 DSH 数据。提交前仍应执行：

```powershell
git status --short --ignored
```

不要把真实的 `.credentials.yaml`、整个 `DeepSeek Harness` 数据目录或任何 API Key 提交到 GitHub。

## 维护入口

| 入口 | 用途 |
| --- | --- |
| `1-一键安装.bat` | 安装或迁移到 EXE 启动模式 |
| `2-配置APIKey.bat` | 配置本地 DeepSeek API Key |
| `3-启动Web界面.bat` | 启动已安装的原生应用 |
| `4-卸载.bat` | 删除程序、快捷方式和更新任务，默认保留数据 |
| `6-检查更新.bat` | 手动检查 GitHub Release |
| `7-修复安装.bat` | 恢复启动器、快捷方式和更新任务 |
| `8-生成诊断报告.bat` | 生成脱敏诊断报告 |

`5-后台启动.vbs` 仅用于兼容原来的后台启动习惯；新安装推荐使用 EXE 快捷方式。

## 常见问题

### 安装过程很慢

首次安装需要下载 Node.js 或 npm 依赖。网络不稳定时重新运行安装器并选择国内 npm 镜像。已经是当前版本时，安装器会跳过重复 npm 安装。

### 浏览器提示 `dsh web authentication required`

关闭旧的 Web 窗口，重新使用桌面上的 `DeepSeek Harness` 图标启动。启动器会自动打开带 token 的地址。

### 找不到旧会话

检查用户级 `DSH_HOME` 是否仍指向旧数据目录。必要时使用 `-HomeOverride` 指定旧路径，不要删除原来的 `sessions` 文件夹。

### Node.js 安装失败

跳过 `winget` 并使用安装包下载兜底：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -NoWinget
```

## 贡献

提交修改前请：

1. 保留用户数据和凭据边界，不把本地 DSH 数据复制到仓库。
2. 为安装、更新、修复行为补充可重复测试。
3. 运行 `launcher\build.ps1` 和 `tests\` 下的 PowerShell 测试。
4. 用清晰的提交信息说明修改了哪个入口或组件。

如果报告问题，请附上 `8-生成诊断报告.bat` 生成的脱敏报告，不要直接上传 `.credentials.yaml`、会话文件或完整日志。