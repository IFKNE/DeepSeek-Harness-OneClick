# DeepSeek Harness 一键安装包 · 使用说明

## 当前推荐使用方式

1. 解压整个安装包，双击 `1-一键安装.bat`。
2. 安装完成后，使用桌面或开始菜单中的 `DeepSeek Harness` 图标启动。
3. API Key 仍然通过 `2-配置APIKey.bat` 配置。

安装器现在会部署原生启动器、官方图标和当前用户的每日更新检查。默认不启用登录自启；启动器会复用已有的 DSH 服务，避免重复连接。

## 更新、修复与诊断

- `6-检查更新.bat`：手动检查更新，安装前会询问，不会静默替换版本。
- `7-修复安装.bat`：重新部署启动器、快捷方式和每日检查任务，不删除聊天记录。
- `8-生成诊断报告.bat`：生成脱敏报告，API Key、Bearer Token 和网页 token 会被隐藏。
- 卸载默认保留 `%USERPROFILE%\\DeepSeek Harness` 中的聊天记录；删除数据需要经过二次确认。

每日更新检查只读取版本元数据；无网络或没有新版本时保持安静，需要安装时仍由用户确认。

> DeepSeek Harness（`dsh`）是 DeepSeek 官方的 AI 编程代理运行时，自带 Web 界面、无头模式和终端模式。本安装包面向**全新的 Windows 10/11 电脑**，全程几乎零手动操作，API Key 由你自己配置。

---

## 一、包里有什么

| 文件 | 作用 |
|------|------|
| `1-一键安装.bat` | 检测/安装 Node.js → npm 安装 dsh → 设置数据目录 → 部署原生启动器与快捷方式 |
| `2-配置APIKey.bat` | 把你的 DeepSeek API Key 写入配置文件（输入时不可见） |
| `3-启动Web界面.bat` | 启动原生 DeepSeek Harness 应用（自动复用 DSH 服务） |
| `5-后台启动.vbs` | **一键后台静默启动** Web 界面：双击即启动（**不自动开浏览器**），启动后把**带令牌的访问地址复制到剪贴板**并提示（也可在 `%DSH_HOME%\web-url.txt` 里找）；可拖到任意地方用 |
| `4-卸载.bat` | 干净卸载（可选保留数据） |
| `scripts\*.ps1` | 上面的入口实际调用的脚本（可手动运行） |
| `template\` | 默认配置模板（settings.yaml / credentials 示例） |
| `使用说明.md` | 就是本文件 |

---

## 二、三步搞定（全新电脑）

1. **双击 `1-一键安装.bat`**
   - 电脑没有 Node.js 时会自动安装 LTS 版（可能弹一次 UAC，点"是"）：先试 `winget`，**若 winget 不可用或失败（例如报 `0x8A15005E` 证书错误），会自动改用国内镜像/官网的 MSI 安装包兜底**，不用你手动处理；想跳过 winget 可运行 `scripts\install.ps1 -NoWinget`。
   - 脚本**始终安装最新版**（`@latest`），会显示当前已装版本与 npm 最新版。
   - 询问"是否使用国内镜像源"时，回车即可（默认国内 npmmirror，快）。
   - 默认不配置登录自启；需要使用时直接双击桌面或开始菜单中的 `DeepSeek Harness` 图标。
2. **双击 `2-配置APIKey.bat`**，**一键粘贴**你的 DeepSeek API Key（免手打）：
   - 先到 https://platform.deepseek.com →「API Keys」→ 创建，用 **Ctrl+C** 复制 Key（`sk-` 开头）。
   - 脚本会自动从**剪贴板读取** Key，按回车确认即可；剪贴板没有时也会引导你复制后一键读取。
   - 保存后**立即生效**（配置文件是热加载的，不用重启）。
3. **双击桌面或开始菜单中的 `DeepSeek Harness` 图标**，应用会自动打开 Web 界面。
   - 它会等 dsh 打印出带 `?token=` 的地址后再打开浏览器（那是一次性授权钥匙），所以不会出现 `dsh web authentication required`。首次打开会引导初始化，选择工作目录（workspace）后即可对话。

> **想看后台静默运行？** 双击 `5-后台启动.vbs` 即可在**后台启动** Web 界面（无控制台窗口），启动后**只提示访问地址、不自动开浏览器**（提示里的地址是带 `?token=` 的完整地址，并且**已复制到剪贴板**，直接粘贴到浏览器就行）；若已在运行则只提示。这个 `.vbs` 可以**拖到桌面/任意文件夹**，双击照样能用。

> 安装脚本不会写入 API Key——Key 完全由你掌控，只存在本机 `DeepSeek Harness\.credentials.yaml` 里。

---

## 三、数据都在哪

所有数据都在一个文件夹（也就是 `DSH_HOME`），默认：

```
C:\Users\你的用户名\DeepSeek Harness\
├── settings.yaml          # 设置（模型、主题等，热加载）
├── .credentials.yaml      # 你的 API Key
├── storages\              # 工作区 + 会话数据
├── sessions\              # 会话记录（jsonl.zstd 压缩）
├── web-url.txt            # dsh web 最近一次启动的输出，里面有带令牌的访问地址
└── profiles\              # web 等 profile 配置（首次启动自动生成，别手动乱改）
```

- **备份** = 直接复制这个文件夹。
- 环境变量 `DSH_HOME` 指向它；删掉的话 dsh 会退回默认的 `~\.dsh`，所以别删。

---

## 四、常见问题

| 现象 | 处理 |
|------|------|
| 打不开 http://127.0.0.1:3080 | 确认窗口里 dsh 在运行；端口被占用时用 `dsh web --port 8080` 换端口 |
| 浏览器提示 `dsh web authentication required` | dsh web 的浏览器访问要"令牌 + Cookie"：直接用裸地址 `http://127.0.0.1:3080` 打开、而这个浏览器还没授权时就会这样。**新版脚本会自动用带 `?token=` 的地址打开**；手动进的话，用 `%DSH_HOME%\web-url.txt` 里带 `?token=` 的那一行地址打开一次即可（之后 30 天不用再管）。注意 `127.0.0.1` 和 `localhost` 算两个不同的站点，Cookie 不通用 |
| 提示没有 API Key | 运行 `2-配置APIKey.bat`，或检查 `.credentials.yaml` 里的 `DEEPSEEK_API_KEY` |
| `dsh` 命令找不到 | 重新运行 `1-一键安装.bat` |
| 改了设置没生效 | settings 是热加载的，但个别情况需重启 `dsh web` |
| 安装很慢/失败 | 重跑安装脚本，选国内镜像源；或先手动确认能访问 https://registry.npmmirror.com |
| 装 Node.js 时报 `0x8A15005E`（证书不匹配） | 这是 winget 自身源连不上/证书校验失败，**重跑一次安装脚本即可**（新版会自动改用 MSI 兜底）；仍不行就手动到 https://nodejs.org/zh-cn 或 https://npmmirror.com/mirrors/node/ 装好 LTS，再重跑脚本 |
| 想彻底不用 winget | `powershell -ExecutionPolicy Bypass -File scripts\install.ps1 -NoWinget` |
| 取消开机自启 | 按 `Win + R` 输入 `shell:startup` 回车，删掉 `dsh-web-autostart.vbs` |

---

## 五、手动命令速查（PowerShell / CMD）

```powershell
dsh web                                  # 启动 Web 界面
dsh web --port 8080                      # 换端口
dsh --profile headless "你的任务描述"      # 无头模式：跑一次任务并输出结果
dsh --profile tui                        # 终端界面（需先装 tui profile）
dsh --dump-config                        # 查看合成后的配置
dsh --version                            # 查看版本
```

## 六、升级

安装脚本每次运行都执行 `npm install -g @deepseek-ai/dsh@latest`，所以**重复运行 `1-一键安装.bat` 即可升级到最新版**（会自动对比并提示当前版本 vs npm 最新版）。

也可以手动升级：

```powershell
npm install -g @deepseek-ai/dsh@latest
```

当前是开发者预览版（0.1.x），官方明确说明可能有破坏性变更；升级后遇到问题重新配置即可。

## 七、卸载

双击 `4-卸载.bat`：删除开机自启 → 删除 `DSH_HOME` 环境变量 → （询问）删除数据目录 → （询问）卸载全局包。

---

*数据全部保存在本机，不依赖云端；API Key 仅用于调用 DeepSeek 官方 API。*
