# GitHub 入门（写给本仓库的主人）

这份教程贴着本仓库的真实情况写：你已经有一个能用的插件仓库，本文讲清它怎么上到 GitHub、以后怎么更新、README 怎么写、以及要避开哪些坑。命令都可以直接复制到终端（Git Bash / PowerShell / CMD 均可）跑。

---

## 1. 先建立三个概念

| 概念 | 一句话解释 | 在本仓库对应的东西 |
|---|---|---|
| **仓库（repository）** | 一个项目文件夹 + 它的全部历史 | 整个 `PianoAutoSustain` 文件夹 |
| **提交（commit）** | 一次存档点，记录「改了什么、为什么」 | 已经有 19 个，如 `U2: 三页换肤…` |
| **远程（remote）** | 这个仓库在 GitHub 上的镜像地址 | `https://github.com/你的用户名/piano-auto-sustain` |

日常关系：**本地仓库是你的工作间，GitHub 是云端备份 + 分享橱窗**。改动永远先在本地提交（commit），再推送（push）上云。

---

## 2. 上传自己的仓库（本次发布发生了什么）

第一次把本地仓库放上 GitHub，一共就三件事：

1. **在 GitHub 上建一个空仓库**（网页点 New repository，起名、选 Public、**不要**勾选任何初始化文件）——本次由 `gh repo create` 代办；
2. **告诉本地仓库远程地址在哪**：`git remote add origin https://github.com/你/piano-auto-sustain.git`；
3. **推送**：`git push -u origin main`——把本地 `main` 分支的全部 19 个提交推上去，`-u` 的意思是「以后这个分支默认推到这个远程」，之后每次只用 `git push`。

首次推送时 Windows 会弹一个浏览器窗口让你登录 GitHub 授权一次（Git Credential Manager 或 gh 凭据代劳），之后再也不用。

---

## 3. 平时怎么更新代码（三步流程）

改了任何文件之后（比如调了插件参数的默认值）：

```bash
git add .                        # 1. 把改动放进「待提交区」（. = 全部）
git commit -m "写清楚这次改了什么"  # 2. 存档点
git push                         # 3. 推上 GitHub
```

就这三步，没有任何更多仪式。两个习惯建议：

- **commit 信息写「为什么」**：`修换踏间隙默认值` 远好于 `修改文件`——半年后你会感谢自己；
- **小步多commit**：一个功能一个 commit，别攒一周一起推。

**更省事的办法**：直接在对话里跟我说「把 XXX 改了然后推上去」，我来执行这三步并写好提交信息。

---

## 4. README.md 怎么写

README.md 是仓库首页，用 **Markdown** 语法写的纯文本。GitHub 打开仓库时自动渲染它。速查：

```markdown
# 一级标题            ## 二级标题          ### 三级标题
**加粗**              *斜体*               `行内代码`
- 无序列表项          1. 有序列表项
[链接文字](https://…)                   ← 超链接
![图片说明](docs/img/ui-perf.png)        ← 图片（相对仓库路径）
| 列1 | 列2 |                          ← 表格（下一行写 |---|---|）
> 引用文字
```

本仓库的 [README.md](../README.md) 逐段就是活教材：开头一句话定位 → 截图 → 特性列表 → 安装 → 参数表格 → 链接到 docs/。写新 README 的套路就是：**一句话说清这是什么 → 一张图 → 三到五个卖点 → 怎么装 → 遇到问题去哪**。

改完 README 想预览效果：VS Code 里 `Ctrl+Shift+V`，或直接推上 GitHub 看渲染。

---

## 5. 让别人直接下载插件：发一个 Release

仓库页右侧 **Releases → Create a new release**：

1. 「Choose a tag」输入 `v1.1`（版本号），选 New tag；
2. 标题写 `v1.1 象牙琴房版`，描述写这版改了什么；
3. 把 `src/PianoAutoSustain.jsfx` 拖进附件框；
4. Publish release。

之后任何人打开 Releases 页就能一键下载 jsfx，不用懂 git。以后每次大更新都打一个 tag + Release，这就是「版本」。

---

## 6. 后续注意事项（避坑清单）

1. **网页端和本地不要同时改同一个文件**——两边都改了再推会产生「冲突」需要手动合并。养成习惯：改动只在一处发生（本地改完推，或网页改完 `git pull` 拉回本地）。
2. **公开仓库 = 所有人可见**。不要往里放密码、token、私人路径里的敏感信息；已经推上去的东西即使删除也可能被缓存过——公开前想一下。
3. **commit 别用 `--force` 强推**，除非你 100% 知道自己在干什么（会覆盖远程历史）。
4. **换电脑/重装系统**：装好 git → `git clone https://github.com/你/piano-auto-sustain.git`，全部历史都在；插件继续可用。
5. **想撤销本地未推送的改动**：`git restore 文件名`（单个文件）或先 `git stash`（暂存起来）。
6. **token/凭据安全**：gh 登录的凭据存在本机凭据管理器里，不要截图分享 `gh auth token` 的输出。

---

## 7. 常用命令速查

```bash
git status                    # 我改了什么？（最常用，迷路先跑它）
git add .                     # 暂存全部改动
git commit -m "说明"          # 存档
git push                      # 推上 GitHub
git pull                      # 把 GitHub 上的更新拉回本地
git log --oneline             # 查看提交历史
git restore 文件名             # 撤销某文件未提交的改动
gh repo view --web            # 浏览器打开本仓库
gh release create v1.1 文件    # 发版（或走网页）
```

---

## 8. 本仓库的更新分工建议

- **跟 ZCode 说**：功能改动、参数调整、修 bug——我改代码、跑检查、commit、push 一条龙；
- **你自己练手**：README 措辞、文档错别字、加截图（截图放 `docs/img/`，README 里 `![](docs/img/xxx.png)` 引用）——正好用来熟悉三步流程。
