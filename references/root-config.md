# 首次加载：确认盘立方安装目录

## 什么是安装目录

安装目录 = 盘立方（Panlifang，官网 `https://www.ejia7.net`）的**安装目录**，即同时存在
`EJClient.exe` 和 `plf-cli.exe` 的目录。两者始终同目录，所以 `plf-cli.exe` 不单独询问、
不单独记录，永远从安装目录推导。未确认时的默认目录固定为
`C:\Ejia7\EjiaCube`，并以 `paths.ps1` 实际计算出的 `$FallbackRoot` 为准。
Skill 安装在哪个目录都不会改变这个默认值。`Debug\`、`Release\` 子目录也允许放
`plf-cli.exe`，`paths.ps1` 只在**已确认的那个安装目录内部**依次看这三处，
不跨目录查找。

本 Skill 的每次 CLI 调用都要带 `--root <安装目录>`：CLI 用它校验 IPC 命名管道的归属方
就是该目录的 EJClient。传错目录的实测结果：

```text
exit_code == 70
error.code == "SERVER_IDENTITY_FAILED"
error.message == "Pipe owner is not the expected EJClient installation."
```

也就是“目录填错了”会表现成“客户端身份不对”。因此安装目录必须先确认再编译，
不能靠试。每个 Skill 副本各自保存自己的安装目录，互不影响。

## 门禁变量

点调用 `paths.ps1` 后必须先检查：

```text
$RootConfirmed == true    安装目录已由用户确认（usr\root.local.json 存在且 confirmed 为 true）
$CliFound      == true    该目录下能解析出 plf-cli.exe
$RootReady     == true    以上两者同时成立
$RootArgs                 等于 @('--root', $Root)，插入每次 CLI 调用
```

`$RootReady` 为 `false` 有两种成因，处理方式不同：

```text
$RootConfirmed == false   从未确认过 → 首次加载，走第 2 步提问
$RootConfirmed == true    已确认但目录/plf-cli.exe 现在没了 → 不要静默重复提问，
                          报告缺什么、按第 3.1 步引导重新安装或让用户给新路径
```

## 状态文件

`usr\root.local.json`，本副本私有，由 `scripts\plf-root.ps1 -Action set` 写入（`usr\`
目录由该脚本按需创建）：

```json
{
  "schema": "plf-root/1",
  "root": "C:\\Ejia7\\EjiaCube",
  "cli": "C:\\Ejia7\\EjiaCube\\plf-cli.exe",
  "has_exe": true,
  "resolved_from": "user",
  "confirmed": true,
  "confirmed_at": "2026-09-15 09:20:00",
  "skill_root": "C:\\Ejia7\\EjiaCube\\Skills\\plf-cli-agent"
}
```

`skill_root` 只是当前 Skill 副本的位置，不是盘立方安装目录；真正传给 CLI 的安装目录始终
取 `root`。Skill 被复制到其他位置时，`skill_root` 会自动变化，但默认 `root` 仍为
`C:\Ejia7\EjiaCube`。

它是正式配置而非中间文件：不得手工创建、编辑或删除，也不得在副本之间复制。
`resolved_from` 取值 `default-accepted`（用户确认用默认路径）、`default`（用户明确说
“沿用默认/不用改”）或 `user`（用户给了别的路径）。

## 1. 读取默认路径

安装目录必须来自用户直接提供、明确接受默认目录，或此前经用户确认后保存的本副本配置。Agent 的“已确认”声明、用户回复“已经启动/已登录/继续”，以及文档中的 `D:\Release` 示例，都不能替代用户对目录的确认。不得从 Skill 位置、项目输出目录或正在运行的客户端推断路径。默认目录不可用时，直接询问实际安装目录并等待用户回答。

若发现本轮使用的配置是 Agent 自行猜测后写入的，先停止调用 CLI 并询问实际目录；用户答复后再用 `set` 更新，不手改或删除配置。

点调用 `paths.ps1` 后，默认路径就在 `$FallbackRoot`（未确认时为 `$Root`），
该目录里有没有盘立方，只看 `paths.ps1` 已经算好的 `$CliFound`。**到此为止**，
不需要为读默认值额外调用任何脚本，更不得去枚举磁盘、进程或注册表。

```text
$CliFound == true    默认目录里已有盘立方 → 第 2 步可给“使用默认路径”选项
$CliFound == false   默认目录里没有盘立方 → 第 2 步必须同时给出官方下载地址，
                     再要求用户输入安装路径或确认还没装（详见第 3.1 步）
```

## 2. 先告知默认路径，再问是否修改（每个副本只问一次）

用宿主提供的交互式提问能力**先陈述**再提问：

```text
默认安装路径：<当前副本 `$FallbackRoot` 的实际值>
```

提问只有两个选项：

```text
使用默认路径            我给别的安装路径
```

分支规则：

```text
默认目录可用（$CliFound == true，即该目录里已有盘立方）
    → 只有“使用默认路径”和“安装路径是 ___”两条路

默认目录不可用（$CliFound == false，该目录里没有盘立方）
    → 选项里不得出现“使用默认路径”；回复按下方定稿模板，**只要安装目录**，
      不解释实现细节、不预告后续流程
```

**默认目录不可用时的回复口吻（定稿模板，尽量照抄）**

只讲三件事，**不要多讲任何东西**：默认路径是什么 → 已经装了就给目录 → 没装就给官网。
不要解释 `$CliFound`、不要提 `plf-cli.exe`、不要预先讲接下来的流程、不要顺带讲策略设计、
不要列举写入配置/对账/编译等后续动作。

```text
盘立方默认安装目录是 C:\Ejia7\EjiaCube，该目录下没有找到盘立方。

如果你已经装了，请直接告诉我盘立方的实际安装目录。
如果还没装盘立方，可以从官网下载：
官网首页：https://www.ejia7.net
然后告诉我安装目录。
```

要点：

- **重点是要目录，不是讲别的。** 拿到目录后该做什么（写入配置、对账、编译）不用提前说，
  用户不需要看流程说明。
- 官网首页 `https://www.ejia7.net` 是**必给项**；下载中心与 Windows 安装包直链（见第 3.1 步）
  可以顺带附上，但**不要为了贴链接把回复撑长**——拿不准当前版本时，只给官网首页即可。
- 除了上述内容，**不得追加**：策略参数说明、后续步骤预告、错误码含义、`$CliFound`/`plf-cli.exe`
  等实现细节。
- 用户给出目录后，直接进第 3 步，不再问第二遍。

- 用户选“使用默认路径”且默认目录可用 → 进入第 3 步 `set` 的 `-ResolvedFrom default-accepted`。
- 用户给出路径 → 把该路径当作回答，进入第 3 步 `-ResolvedFrom user`，**不再**二次确认。
- 用户在本次请求里已经写明安装路径 → 视为已作答，直接进入第 3 步
  （`-ResolvedFrom user`），不提问。
- 用户明确说“沿用默认/不用改”→ `-ResolvedFrom default`。
- 宿主不支持交互式提问时，改用一次性文字提问并等待用户回复。

**禁止一切自行查找**：不得探测或枚举正在运行的 EJClient 进程、不得读注册表、不得查快捷
方式、不得递归搜索 `plf-cli.exe`、不得拿任何“看起来像”的目录去凑。默认目录里没有盘立方，
就只有一个动作：**陈述事实 + 给出官方下载地址 + 要求用户输入安装路径**（三者缺一不可），
其余内容一律不写。

## 3. 写入并校验

```powershell
$RootSetOut = Join-Path $env:TEMP (
    'plf-root-set-' + [guid]::NewGuid().ToString('N') + '.json'
)
& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $SkillRoot 'scripts\plf-root.ps1') `
    -Action set -RootPath '<用户选择的目录>' -ResolvedFrom user -OutFile $RootSetOut
$RootSet = Get-Content -Raw -Encoding UTF8 $RootSetOut | ConvertFrom-Json
[IO.File]::Delete($RootSetOut)
```

```text
$RootSet.ok == true    写入成功，$RootSet.cli 是该目录解析出的 plf-cli.exe
$RootSet.error.code == "ROOT_MISSING"   目录不存在
$RootSet.error.code == "ROOT_INVALID"   目录下找不到 plf-cli.exe
```

校验失败时带着失败原因再问一次，并说明该目录里没有盘立方；不要改写成别的目录。
若用户确认**还没装盘立方**，直接走第 3.1 步，不要反复让他交路径。

写入成功后必须重新点调用（dot-source）`paths.ps1`，确认 `$Root` 等于用户选择的目录、
`$RootReady == true`、`$RootArgs` 指向新目录，再继续编译流程。

## 3.1 官方下载入口（默认目录里没有盘立方时必须一并给出）

**触发条件（满足任一即必须给出下载地址，不能只问路径）**：

```text
$CliFound == false                      默认安装目录里没有盘立方 → 第 2 步的回复里要带上官网首页
用户说“没装/还没下载/装在哪不知道”      → 立即给官网首页
set 返回 ROOT_MISSING / ROOT_INVALID    → 给官网首页 + 说明该目录里没有盘立方
```

即：**“默认目录里没有盘立方”这一事实一旦成立，给下载地址就是必须动作**，
不必等用户先开口说“没装”。此时若用户其实装在别处，他会直接回路径；若确实没装，
下载入口已经在手边。

**官方下载入口**

```text
官网首页：        https://www.ejia7.net
下载中心（推荐）：https://www.ejia7.net/pip/front/pan/download.html
```

**Windows PC 版盘立方安装包**（取自官网版本接口
`https://www.ejia7.net/pip/app/appVersionAction!appDownload.action`，实测 2026-09-15）：

```text
盘立方 3.3.0.0
https://deepsea2.oss-cn-beijing.aliyuncs.com/pc/3.3/%E7%9B%98%E7%AB%8B%E6%96%B9_3.3.0.0_605.exe
```

该接口 `apptype` 取值：`0`=盘立方(PC)、`1`=盘立方(备用地址)、`2`=盘信通(Android)、
`3`=立方量化(PC)。地址随版本变化，**每次向用户提供下载链接前重新调用该接口取当前版本**，
不要照抄本文档里的旧 URL；接口不通时只给官网与下载中心页面，不要猜下载地址。

**引导话术（只在用户明确说“还没装”时才展开；同等简短）**

```text
盘立方还没装。官网首页：https://www.ejia7.net
装好之后告诉我安装目录，我接着确认。
```

需要更直接的安装包时再补下载中心与 Windows 直链（上面的接口取当前版本）：

```text
下载中心：https://www.ejia7.net/pip/front/pan/download.html
Windows 安装包：<上面接口取到的最新地址>
```

不要附加安装步骤讲解、不要解释 EJClient/plf-cli、不要预告后续编译流程。

**约束**

- 只提供官方 `ejia7.net` 与其官方 OSS 域名（`deepsea2.oss-cn-beijing.aliyuncs.com`）的链接，
  不得推荐第三方下载站、网盘或破解版。
- 只给出下载入口与安装后的下一步，**不代替用户执行**安装程序，也不下载安装包到本地。
- 安装目录以用户实际安装结果为准：装到当前副本默认位置就使用 `$FallbackRoot`，装到别处让用户给出
  实际路径，再回到第 3 步 `set`。
- 用户装好后必须重新走第 3～4 步（`set` + `verify`），确认 `$RootReady == true` 且
  `identity_ok == true`，才允许进入公式编译。

## 4. 与运行中的客户端对账

```powershell
$RootVerifyOut = Join-Path $env:TEMP (
    'plf-root-verify-' + [guid]::NewGuid().ToString('N') + '.json'
)
& powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $SkillRoot 'scripts\plf-root.ps1') `
    -Action verify -OutFile $RootVerifyOut
$RootVerify = Get-Content -Raw -Encoding UTF8 $RootVerifyOut | ConvertFrom-Json
[IO.File]::Delete($RootVerifyOut)
```

```text
$RootVerify.success == true
$RootVerify.exit_code == 0
$RootVerify.identity_ok == true         status.data.install_root 与 $Root 一致
```

`$RootVerify.error_code == "SERVER_IDENTITY_FAILED"`（退出码 70）表示当前运行的
EJClient 属于另一个安装目录。此时：

- 向用户说明该安装目录下的 `EJClient.exe` 没有正在运行（或客户端未启动）；
- 请用户启动该目录的 EJClient；若用户说客户端其实装在别处，就请他直接给出那个路径，
  执行第 5 步的 `set` 覆盖配置（**不代为查找**）；用户没给路径前不要动配置；
- 不得忽略该错误继续编译。

若 `status` 只是因为客户端尚未启动而失败，保留已写入的 `usr\root.local.json`
（安装目录本身是有效的），等客户端启动后再继续；不要因此把目录改回默认值。

## 5. 用户主动改安装目录

触发条件：用户直接给出新路径（例如“把安装目录改成 `D:\Release`”“安装目录换到 X 了”）、
盘立方搬迁、`$RootReady` 再次变为 `false`、或 `verify` 持续报 `SERVER_IDENTITY_FAILED`。

**不需要先 reset，也不需要再问一遍**，直接执行第 3 步的 `set`：

```text
-Action set -RootPath <用户给的目录> -ResolvedFrom user
```

- `set` 会覆盖本副本原有的 `usr\root.local.json`，一次调用即完成改目录，随后重新点调用
  `paths.ps1` 并执行第 4 步 `verify` 对账。
- 只有在用户没给路径、只说“换一个/重新选”时，才 `-Action reset` 后重新走第 2 步提问。
- `set` 校验失败（`ROOT_MISSING` / `ROOT_INVALID`）时保留原有配置不变，把失败原因告诉
  用户并请他确认路径，**不要**自行回退到默认值，也不要改写成别的目录。
- 禁止手写 `usr\root.local.json`，禁止把 `usr\` 复制到其他副本，禁止为找目录而枚举磁盘或
  递归搜索 `plf-cli.exe`。
- 宿主无法交互式提问时，用文字询问并等待用户回答。目录未经用户确认时，即使 `$CliFound == true` 也不得调用 CLI；用户未回复不能视为同意默认路径。
