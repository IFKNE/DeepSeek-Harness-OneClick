# DeepSeek Harness 一键安装包 · 使用说明

> DeepSeek Harness（`dsh`）是 DeepSeek 官方的 AI 编程代理运行时，自带 Web 界面、无头模式和终端模式。本安装包面向**全新的 Windows 10/11 电脑**，全程几乎零手动操作，API Key 由你自己配置。

---

## 一、包里有什么

| 文件 | 作用 |
|------|------|
| `1-一键安装.bat` | 检测/安装 Node.js → npm 安装 dsh → 设置数据目录 → （可选）开机自启 |
| `2-配置APIKey.bat` | 把你的 DeepSeek API Key 写入配置文件（输入时不可见） |
| `3-启动Web界面.bat` | 启动 Web 界面并自动打开浏览器 |
| `4-卸载.bat` | 干净卸载（可选保留数据） |
| `scripts\*.ps1` | 上面的入口实际调用的脚本（可手动运行） |
| `template\` | 默认配置模板（settings.yaml / credentials 示例） |
| `使用说明.md` | 就是本文件 |

---

## 二、三步搞定（全新电脑）

1. **双击 `1-一键安装.bat`**
   - 电脑没有 Node.js 时会自动安装 LTS 版（可能弹一次 UAC，点"是"）。
   - 询问"是否使用国内镜像源"时，回车即可（默认国内 npmmirror，快）。
   - 询问"是否配置开机自启"时，回车即可（默认开启）。
2. **双击 `2-配置APIKey.bat`**，粘贴你的 DeepSeek API Key。
   - 没有 Key？去 https://platform.deepseek.com →「API Keys」→ 创建，格式是 `sk-` 开头的一串。
   - 保存后**立即生效**（配置文件是热加载的，不用重启）。
3. **双击 `3-启动Web界面.bat`**，浏览器自动打开 **http://127.0.0.1:3080**。
   - 首次打开会引导初始化，选择工作目录（workspace）后即可对话。

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
└── profiles\              # web 等 profile 配置（首次启动自动生成，别手动乱改）
```

- **备份** = 直接复制这个文件夹。
- 环境变量 `DSH_HOME` 指向它；删掉的话 dsh 会退回默认的 `~\.dsh`，所以别删。

---

## 四、常见问题

| 现象 | 处理 |
|------|------|
| 打不开 http://127.0.0.1:3080 | 确认窗口里 dsh 在运行；端口被占用时用 `dsh web --port 8080` 换端口 |
| 提示没有 API Key | 运行 `2-配置APIKey.bat`，或检查 `.credentials.yaml` 里的 `DEEPSEEK_API_KEY` |
| `dsh` 命令找不到 | 重新运行 `1-一键安装.bat` |
| 改了设置没生效 | settings 是热加载的，但个别情况需重启 `dsh web` |
| 安装很慢/失败 | 重跑安装脚本，选国内镜像源；或先手动确认能访问 https://registry.npmmirror.com |
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

```powershell
npm install -g @deepseek-ai/dsh@latest
```

当前是开发者预览版（0.1.x），官方明确说明可能有破坏性变更；升级后遇到问题重新配置即可。

## 七、卸载

双击 `4-卸载.bat`：删除开机自启 → 删除 `DSH_HOME` 环境变量 → （询问）删除数据目录 → （询问）卸载全局包。

---

*数据全部保存在本机，不依赖云端；API Key 仅用于调用 DeepSeek 官方 API。*
