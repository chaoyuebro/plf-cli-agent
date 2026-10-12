---
name: plf-cli-agent
description: Resolve Chinese stock or futures names to current Panlifang contract keys, generate or modify Ejia formula source, compile and repair it through plf-cli, optionally run sequential single-parameter backtests, or manage a registered formula's background executor when both CLI and EJClient advertise executor v1. Never use batch grid optimization or search project and installation directories.
---

# 盘立方公式生成与编译调试

完成两个顺序闭环：

```text
生成公式 → plf-cli compile → 错误回报 → 修改同一源码 → 再次 compile → 注册成功

单组参数 → plf-cli run → 完整回测报告 → Agent 分析 → 下一组参数 → 再次 run
```

另有按需启用的独立闭环：已注册公式 + 明确的合约/周期 → `executor-add` → 按用户要求
`executor-start` / `executor-status` / `executor-stop` / `executor-remove`。它是 EJClient 内的后台策略计算，
**不是** `run` 回测，也不产生可替代完整回测报告的结果。只在用户明确要求后台执行、管理或查询时进入，
先按[后台执行器](references/executor.md)完成双端能力检查；不支持时停止，不把 `run` 当作替代。

只有用户要求回测或调参时才进入第二个闭环。每次回测只允许一个明确的参数对象；禁止调用
`optimize`、`--grid`，禁止一次生成参数组合笛卡尔积。

## 授权边界（不可自行放宽）

用户的原始请求就是授权范围的**上限**，只能少做，不能多做。这三条在任何情况下都不得违反：

1. **没要求就不优化。** 用户只说「写一个策略并回测」（或「生成 + 编译 + 跑一次」）时，
   任务到**基准轮结束即完成**：生成公式 → 编译注册 → 跑一次回测 → 展示结果。不得因为
   首次结果不理想、亏损、胜率低、回撤大或「样本偏少」就自行追加第二轮参数调整。
   一轮回测的好坏不是继续调参的理由；**只有用户明确说「优化」「调参」「多跑几组」才可以进入
   多轮迭代**。用户没提优化时，允许的分析范围仅限：如实报告本轮指标、指出亏损/回撤等客观
   事实、说明本轮的局限。**指出问题可以，动手改参数不行。** 需要变更参数或交易逻辑时，
   先说清拟改动内容与理由，等用户同意后再执行。

2. **说几轮就几轮，一轮不多。** 用户说「优化 N 轮」时，总运行数必须恰好是 `N + 1`
   （基准轮 + N 轮调参）或用户另行指定的口径，**不得多跑一轮来「验证」或「收敛」**。
   用户说「优化 2 轮」，第 3 轮调参就是越权。达到用户指定的轮数后立即停止，
   即使还能想到更优的参数组合也不得继续提交。

3. **默认参数不因回测结果改变。** 用户没有明确说「固化」「设为默认值」「把最优参数写进公式」时，
   回测结束后公式源码 `Params` 里的默认值必须保持用户拿到时的原样。
   逐轮调参只允许通过 `--params` 传入临时覆盖，**不得把某轮的最优参数回写进源码默认值**，
   也不得为此重新编译。若在优化过程中已改动过默认值，优化结束后**必须改回原值并重新编译**，
   让公式恢复到用户原本会拿到的那一版。只有用户明确要求固化时才修改默认值。

违反以上任一条都属于越权操作。已经发生越权时，先如实说明实际改动，再询问是还原还是保留，
不要自行决定。

## 输出形式

- 除非用户明确要求图片或可视化，否则不得调用绘图、配图、图像生成、画布或可视化工具，也不得额外制作流程图、架构图或演示示意图。
- 用户要求“资金曲线”“权益曲线”或“画出回测曲线”时，读取并严格执行
  [CLI 命令参考的资金曲线绘图](references/cli-commands.md#资金曲线绘图)：使用真实 `equity_curve`、
  默认绘制 `static_equity`、采用不越界的 Fritsch–Carlson 平滑，并在交付前运行
  `scripts/verify_render.js` 真机验证。图表实现细节不在入口重复维护。
- **图表/报告交付给用户的固定形式是「正文里的 md 锚文本链接」**：调 `present_files` 后取返回值里的
  `previewed` 字段（那就是客户端给预览用的 http 地址），正文写成
  `[白糖指数资金曲线](<previewed url>)`，再附一行本地路径作离线保底。
  **锚文本 = `<品种><合约>资金曲线`，一律写全**：品种用中文名（与用户原话一致，
  如 `白糖` / `铸造铝合金`），合约用盘立方口径的合约标识（`指数` / `主连` / 具体月份如 `2501`），
  末尾固定拼 `资金曲线`。
  例：`白糖指数资金曲线`、`铸造铝合金指数资金曲线`、`螺纹钢主连资金曲线`。
  **不对锚文本做任何长度判断、截短、缩写或改写**：不许删品种名、不许把品种换成行业简称、
  **不许在规则或回复里出现“字数／几个字／长度上限”这类口径**。锚文本多长只由品种名和合约名决定，
  不由任何规则约束。叶生 2026-09-23 连续两次否掉这套说法：
  「肯定不能这样啊，为什么要限制字数？就是 品种+合约+资金曲线」、
  「8 个字 为什么还是 8 个字啊，不是说不限制字数了吗？」。
  **锚文本里只放名称，不塞周期、策略名、回测区间**（这三项写进图内标题与副标题）。
  **链接卡片的宽度有限，锚文本会被卡片裁切显示**（2026-09-23 实测 `[白糖指数资金曲线]`
  渲染出来只显示到 `白糖`，叶生回「没给对」）。⇒ **完整名称必须再用普通文本写一遍**，
  普通文本会正常折行、不受链接卡片宽度限制。锚文本一律写全，卡内被裁属渲染行为、
  与文本内容无关，**不要据此改动锚文本**，并让它**独占一个段落、前后留空行**。
  不得只给文件名、裸路径或裸地址；
  不要用文件卡片代替链接，也不要为了“能点”自己起 `http.server`。完整口径见
  [CLI 命令参考的资金曲线绘图](references/cli-commands.md#资金曲线绘图)。
- **交付正文只写两行**：① `<品种><合约>资金曲线已生成。`——完整名称写在这句**普通文本**里，
  这样即使链接卡片把锚文本裁短，用户也一定看得到完整名字；② 那行锚文本链接（独占一段）。
  不要口径说明、参数复现、数字表格、下一步建议、临时地址失效提醒；采样与回撤口径等细节
  写进图内或报告内，等用户追问再说（2026-09-23 叶生：「这两句话就行，其他的解释不要」）。
- `.fml` 工作源码和注册产物仍须实际生成，CLI 结果仍须完整核验，但最终回复不打印“编译结果核验（全部通过）”清单，也不列工作源码路径、发布路径、DLL 路径、SHA256 等交付物明细。
- 默认不得在最终回复中附加、链接、渲染或以文件卡片展示 `.fml` 源码。只有用户明确要求
  “查看源码”“打开文件”或“下载公式”时才显示对应文件；创建和编译公式本身不构成展示授权。
- 成功时默认只简洁说明公式已经生成、编译并加载到 EJClient；失败时只报告继续处理所必需的错误摘要。
- 最终回复发送前去除重复段落、重复步骤和重复的用户操作请求；同一条“请重启/请登录/请确认”不得在一条回复中出现两次。
- **需要用户配合时必须说重点，不说流程**：只写“要用户做什么/给什么”，不解释内部变量与实现细节（如 `$CliFound`、`plf-cli.exe`、`--root`、错误码），不预告后续步骤（写入配置、对账、编译、注册），不顺手展开策略参数或源码设计。用户没问的一律不写。
- 公式源码中按策略需求调用 `PlotNumeric` 等绘图函数属于公式功能，不属于额外示意图，不受本条限制。

## 必须实际执行

- 用户说“使用本 Skill 生成、编译、测试或调试公式”时，必须创建或修改 `.fml` 文件并实际调用 `plf-cli compile`；不能只展示代码、命令或操作说明。
- 用户要求回测、分析报告或继续调参时，必须实际调用 `plf-cli run`；每轮只提交一组 `--params`，读取本轮完整报告后才能决定下一组。
- 用户仅要求查询或管理**已注册公式**的后台执行器时，按[后台执行器](references/executor.md)操作；不因管理请求自动改源码、重新编译或提交回测。新增公式则先完成编译注册，再按明确授权添加执行器。
- 只有用户明确要求“解释、查看方案或不要执行”时才只回答文字。
- “不自行编译 C++ 工程”只禁止 MSBuild/Visual Studio 构建 `EJClient.sln`；不禁止公式编译。`plf-cli compile` 是本 Skill 的核心动作，用户要求本闭环即授权执行。

## 安装目录与首次加载

**先问目录，禁止自行寻找。** 未有用户明确提供或接受的安装目录时，只检查默认目录；默认目录不可用就立即询问实际安装目录并等待回答。不得从 Skill 所在位置、项目的 `Release` 目录、运行进程、历史演示路径或候选目录推断安装位置。`D:\Release` 等文档示例不代表本次用户的安装目录。

只有用户直接给出的目录、明确接受的默认目录，或由此前用户确认后保存的本副本配置可以使用。Agent 自己说“安装目录已确认”不构成确认；用户只回复“已经启动”“已登录”“继续”也不等于确认 Agent 先前自行猜出的目录。若本轮发现配置来自自行猜测，停止使用该配置并询问用户实际目录；拿到回答后再用 `set` 更新。

每次执行本 Skill，第一步必须读取并用 PowerShell 点调用（dot-source）执行
[路径配置](paths.ps1)，确保派生变量保留在当前会话。`$Root`（盘立方安装目录）的取值顺序是：
本副本私有的 `usr\root.local.json`（由首次加载流程
写入）→ `paths.ps1` 里的 `$FallbackRoot` 默认值。默认安装目录固定为
`C:\Ejia7\EjiaCube`，不随 Skill 自身所在目录变化。`$SkillRoot` 直接取配置文件所在的
`$PSScriptRoot`；`$Cli`、`$WorkDir`、函数表、命令表和模板路径全部自动推导。
Skill 自身移动无需改路径；禁止在其他文件重复填写绝对路径。

**目录约定：共享只读文件在 Skill 根目录，本副本私有的内容一律放 `usr\`。**

```text
<Skill 根目录>
├── SKILL.md              共享，全部副本逐字节一致
├── paths.ps1             共享（各副本 $FallbackRoot 除外）
├── agents\  assets\  references\  scripts\    共享
└── usr\                  本副本私有，禁止跨副本复制
    ├── _user_meta.json   平台导入时写入的安装元数据
    ├── root.local.json   已确认的盘立方安装目录
    ├── work-formulas\    本副本生成过的公式
    └── work-reports\     用户明确要求保留的资金曲线与正式报告
```

`usr\` 由 `scripts\plf-root.ps1` 按需创建，不需要手工建目录。`paths.ps1` 必须留在根目录：
它是点调用入口，`scripts\plf-root.ps1` 按固定相对路径引用它。

点调用后必须检查门禁：

```text
$RootConfirmed == true
$CliFound == true
$RootReady == true
```

`$RootReady` 不为 `true` 即为**首次加载**（或安装目录已失效）：必须先按
[首次加载确认安装目录](references/root-config.md) **先告诉用户默认路径是什么，再问是否需要
修改**；用户要改就给实际安装路径，不要就沿用默认值。默认目录里有没有盘立方只看
`paths.ps1` 已算好的 `$CliFound`：若为 `false`，**不得自行查找**——不探测运行中的进程、
不读注册表、不查快捷方式、不递归搜盘，也不得说“我去确认/我来找”。这一轮回复**只讲三件事、
越短越好**：① 固定写“盘立方默认安装目录是 `C:\Ejia7\EjiaCube`，该目录下没有找到盘立方。”，
不得在用户提示中提及 `paths.ps1`、`$FallbackRoot` 或其他内部实现；
② 已经装了 → 请用户直接给实际安装目录；③ 还没装 → 给官网首页 `https://www.ejia7.net`
并让用户装好后告知目录。**重点是要到安装目录**：不要解释 `$CliFound`/`plf-cli.exe`、
不要预告后续流程（写入配置、对账、编译）、不要顺带讲策略参数或源码设计。确认后必须用
`scripts\plf-root.ps1 -Action set` 写入本副本的 `usr\root.local.json`，再重新点调用
`paths.ps1` 并确认 `$RootReady == true`，然后才允许调用 CLI。这也是本 Skill 每个副本
唯一的询问时机：只问一次、只问安装目录，`plf-cli.exe` 与 `EJClient.exe` 恒同目录、
不单独询问。禁止在目录未确认时编译，禁止把候选目录列表当成选项让用户挑，禁止为找目录
而扫描、递归枚举磁盘或自行猜测。

**默认目录里没有盘立方时**（`$CliFound == false`）、或用户给出的目录里没有盘立方、
或用户表示还没装：给官网首页 `https://www.ejia7.net` 并让用户装好后告知安装目录。
只在用户明确说“还没装”时，才补下载中心
`https://www.ejia7.net/pip/front/pan/download.html` 与 Windows 安装包直链（从官网版本接口
`https://www.ejia7.net/pip/app/appVersionAction!appDownload.action` 现取）。
回复保持简短，只围绕“要安装目录”。只给官方链接、不代替用户安装，
也不要把“没装盘立方”当成公式错误处理。

确认后，`status`、`doctor`、每轮 `compile`、每轮 `run` 和受支持的 `executor-*` 命令都必须在子命令之后插入 `$RootArgs`
（即 `--root <安装目录>`），让 CLI 校验管道归属方就是该目录的 EJClient；`--root`
传错会返回退出码 70 和 `SERVER_IDENTITY_FAILED`，不得当作公式错误处理。

用户主动给出新路径（例如“把根目录改成 `D:\Release`”）、盘立方搬迁、或 `$RootReady` 再次
变为 `false` 时：用户已给路径就直接 `scripts\plf-root.ps1 -Action set -RootPath <该路径>`
覆盖本副本的 `usr\root.local.json`，不要再问一遍、不要先 reset；只有用户没给路径、只说“换一个”
时才 `-Action reset` 后重走提问流程。改完必须重新点调用 `paths.ps1` 并重新对账。
任何时候都不得手改状态文件。

本 Skill 在多个位置各有一份副本，供不同工具与不同环境的会话使用。`SKILL.md`、
`references/`、`assets/`、`agents/`、`scripts/` 的内容必须逐字节一致；每个副本的私有状态
全部隔离在各自的 `usr\` 目录里，同步副本时禁止覆盖或搬运任何副本的
`paths.ps1` `$FallbackRoot` 与 `usr\`。

**本机已知的 `plf-cli-agent` 副本（共 4 份，改动必须全部同步）：**

```text
用户级（Skill 真正的发现路径）
  C:\Users\Mayn\.workbuddy\skills\plf-cli-agent

项目主副本
  D:\BaiduSyncdisk\MFC\pcclient\.codex\skills\plf-cli-agent

项目 Release 副本
  D:\BaiduSyncdisk\MFC\pcclient\Release\Skills\plf-cli-agent

独立发布测试副本
  D:\Release\Skills\plf-cli-agent
```

副本清单可能变化。只同步自己想到的那一两份是最常见的失误：**修改任何共享文件后，
必须用目录扫描重新确认副本全集，再逐份同步并做全量哈希复验**，不得凭记忆假定副本数量。
每份副本有各自的 `usr\`（`work-formulas\` 内容互不相同），同步时只覆盖上列共享文件，
`paths.ps1` 与 `usr\` 一律保持原样。

**平台重装 / Skill 迁移会重建 Skill 根目录，`usr\` 私有内容不保证保留。**
2026-09-23 实测：用户级 Skill 由 `plf-cli-agent-demo` 迁移重建为 `plf-cli-agent`，
原 `usr\work-formulas\TurtleSystem.fml` 与整个 `usr\work-reports\` 全部丢失，
`usr\root.local.json` 也一并消失（需重新确认安装目录）。`modify_backup` 里的同名副本是 0 字节，不能当备份用。
因此：**用户明确要求保留的资金曲线 / 正式报告，除按约定写入 `usr\work-reports\` 外，
必须同时另存一份到工作区或用户指定目录**（例如 `<工作区>\reports\`），
最终回复给用户的是工作区那一份；`usr\` 里的只作为本副本的工作副本。

资金曲线算法**只在本 Skill 内定义**，不依赖任何外部配套 Skill。`SKILL.md`
「输出形式」的资金曲线条目与 `references/cli-commands.md#资金曲线绘图` 必须保持同一口径；
两处说法不一致时先修文档、不要各按各的猜。修改任一处后必须把改动同步到本 Skill 的所有副本。

派生路径不存在时报告 `paths.ps1` 计算出的具体路径，不得扫描其他目录寻找替代文件。

## 文件访问边界

- 禁止对工作区或 EJClient 安装目录执行全文搜索、递归枚举或示例发现。
- 禁止读取安装目录的 `formula/`、项目 `include/`、编辑器/FormulaEngine 源码、历史 `.fml` 或配置文件来补充语法。
- 公式语法和函数唯一依据是 [Skill 内置语法与完整函数表](references/formula-functions.md)；
  真实源码骨架取 [策略案例库](references/examples-strategies.md) 与
  [指标案例库](references/examples-indicators.md)，这两个案例库同属 Skill 内置内容。
- 只允许读取本 Skill（包括别名种子表）、用户明确点名或附加的单个 `.fml`、当前工作公式，
  以及 CLI 返回的 JSON。标的解析不得读取安装目录中的 `all_contract.dat`、`hot_contract_list.dat`。
- 只允许写入 `usr\work-formulas\<英文简称>.fml`、用户明确要求的 `usr\work-reports\` 图表/报告、`usr\instrument-catalog.json`、`usr\root.local.json`（只能通过 `scripts\plf-root.ps1` 写入）和本次临时 JSON；不得直接编辑 CLI 发布到 EJClient 安装目录的文件。`usr\_user_meta.json` 由平台维护，任何情况下都不得读取、创建、修改或删除。
- 每次使用完毕后立即删除本轮产生的所有中间文件，包括 `--out` JSON、`scripts\plf-root.ps1 -OutFile` 产生的 JSON、显示名辅助文本、探测脚本及 `_plf_*`/`_probe*` 文件；成功与失败路径都不能遗留。本机 `Remove-Item` 会被 safe-delete 包装器拦截并抛出 `trash-failed / Some operations were aborted`，多路径数组写法还会静默失效，因此清理已确认属于本轮的文件必须使用 `[System.IO.File]::Delete()` 逐个删除并复验剩余为 0。工作公式、CLI 发布的公式源码、DLL、`usr\` 内的正式产物（`_user_meta.json`、`root.local.json`、`instrument-catalog.json`）和 Skill 正式说明文件是正式产物，不属于中间文件，不得删除。

## 前置条件与编译门禁

- 用户必须预先启动 `EJClient.exe`，且该客户端所在目录必须等于已确认的安装目录 `$Root`。本地公式编译不要求 QDC 连接或完整回测能力，但编译后的运行时注册及其他业务 IPC 要求当前账号具有有效的 CLI 功能授权。
- 全程使用 PowerShell 参数数组调用固定 CLI，不使用 Bash。每次 `status`、`doctor`、`instrument-list`、`compile`、`run` 和受支持的 `executor-*` 调用都必须在子命令之后插入 `$RootArgs`（`--root <安装目录>`），并为每次调用指定全新的 `--out` JSON 路径；CLI 调用后不得附加 `| Out-Null` 或其他管道。本机管道会使 `$LASTEXITCODE` 出现错误值，因此成败只按 UTF-8 读取后的 JSON `success`、`exit_code` 和结构化字段判断，不记录或交叉校验 `$LASTEXITCODE`。标准输出为空时不能据此判定成功或失败。中文 `--display-name` 必须存入变量后作为独立数组元素传递，禁止拼接整条命令字符串。`doctor` 的 JSON `exit_code` 为 11 或 31 时仍须读取 `data.ready_for_compile`，不能因完整运行能力未就绪而停止编译；执行回测前则必须确认 `data.ready_for_backtest == true`。后台执行器另按[后台执行器](references/executor.md)核验能力和运行条件，不用回测就绪字段替代。
- **把「调 CLI」和「解析响应」拆成两次调用**：不要把 `run`/`compile` 之后的 JSON 解析写进同一条内联
  PowerShell 命令。2026-09-23 实测：超长的内联脚本会整段失败（退出码 1、且无任何标准输出），
  失败后也看不出 CLI 究竟有没有执行，容易误判成“需要重新提交”。正确顺序：① 一条命令只做点调用 +
  调 CLI，把 `--out` JSON 留在临时目录；② 另写一个独立 `.ps1`（放 `%TEMP%`，执行后删除）解析该 JSON、
  落盘摘要与权益数组；③ 删除 JSON 与解析脚本。
- `status` 返回 `IPC_UNREACHABLE`（退出码 30）时先看客户端是不是**刚启动**：EJClient 启动后建立 IPC
  管道需要几十秒，稍等重试一次 `status` 即可，不要据此判定客户端未运行或管道故障。
  （2026-09-23 实测：进程 14:32:45 启动，首次 `status` 报 `IPC_UNREACHABLE`，重试即 `success=True`。）
  「客户端在不在跑」可用 `Get-Process -Name EJClient` 只读诊断（这不属于“自行查找安装目录”），
  但**安装目录本身仍只能来自 `usr\root.local.json` 或 `$FallbackRoot`**。
- **PowerShell 变量名陷阱：`$pid` 是只读自动变量**（当前进程 ID），不能赋值。2026-09-23 实测：
  `$pid = $status.data.selected_pid` 会抛「无法覆盖变量 PID，因为该变量为只读变量或常量」；该异常发生在
  上游 `try` 块里、被 `catch` 吞掉后 `--pid` 取值落空，CLI 便拿**当前 PowerShell 进程**当身份去连管道，
  返回 `PIPE_IDENTITY_FAILED`（退出码 70）——**看起来像客户端不匹配，实际是脚本自己把 PID 弄丢了**。
  ⇒ 承接 `selected_pid` 一律用 `$ClientPid` 这类自定义变量名，并在 `run` 前把实际使用的 PID 写进摘要自检。
- **回测相关命令的 `--timeout` 上限是 600 秒**：`run`/`history-submit`/`backtest-submit`/`job-wait`
  接受 1～600 秒，CLI 不传参数时仍默认 300 秒。本 Skill 的 `run` 显式传 `--timeout 600`，
  用户明确指定更短时使用用户值。取数、排队和回测共享预算，编译及终态清理不计入。
  后台执行器的等待规则不变：默认 60 秒，上限 300 秒，见 [后台执行器](references/executor.md)。
  超过 600 秒返回 `INVALID_TIMEOUT`（退出码 10）；旧版程序拒绝 600 时应核对并更新 CLI 和 EJClient，
  不能宣称已应用新上限。
  **本机已于 2026-10-08 实测确认 600 可用**：`run` 带 `--timeout 600` 返回 `exit_code=0`、
  `success=true`，`plf-cli help` 的 usage 亦声明 `[--timeout 1..600]`。此前一段时间 600 被拒
  是本机 CLI/EJClient 版本偏旧所致，用户升级后已消除——**再遇到 600 被拒不要写死"上限 300"，
  先按上面手法抓 `error.code` 确认，并提示核对版本**。
  **关键：参数校验类错误只在 stdout 打印一行 JSON，不写 `--out` 文件**——所以脚本里出现
  `cli_done=False`（`--out` 不存在）时，**先怀疑命令行参数校验失败，而不是客户端/管道故障**。
  定位手法：把该次 CLI 调用改成 `$cap = & $Cli @A 2>&1`（重定向、不加管道符）再落盘查看 stdout，
  一次就能看到 `error.code`，不要仅凭输出文件缺失判断管道故障。
- 日志与作业类命令不止 `status`/`doctor`/`compile`/`run`：`help` 还列出
  `instrument-list`、`history-submit`（纯取数，排查「有数据但取不到」最快）、`backtest-submit`、
  `job-status`/`job-wait`/`job-cancel`/`job-delete`、`report-export --input <report.json>
  --output <x.csv|x.html|x.json> [--section summary|equity|trades]`、`executor-*`。
  **注意 `--period` 的取值范围是 `1m|3m|1d|1w|1mo|Nm(N=5..1440,step=5)|Nh(N=1..24)`。**
  CLI 没有删除公式的子命令，因此**不要用裸 `compile` 做诊断**：名称被占用时会静默生成 `xxx_2`
  并同时注册到磁盘与运行时，给用户的公式列表留下垃圾。诊断一律用 `--replace-existing` 或只跑 `run`。
- 继续编译只要求：管道成功连接到一个明确的 EJClient、身份校验成功、`doctor.data.ready_for_compile == true`。
- 本机同时运行多个 EJClient 是常态，不能仅因发现多个进程就停止。只要 `status` 响应仍给出唯一、有效的 `data.selected_pid`，客户端身份就视为明确，直接用该 PID 继续；只有 `status` 无法选出唯一 PID、返回歧义错误或后续身份校验不一致时，才停止并让用户指定 PID。后续所有命令固定携带同一个 `--pid`。

## 生成源码

1. 完整读取 [公式语法与函数表](references/formula-functions.md)，只使用其中已确认的语法、函数及签名。
2. 用户给出策略规则时，先查[策略案例库](references/examples-strategies.md)与
   [指标案例库](references/examples-indicators.md)，挑结构最接近的真实源码作骨架改造；
   两个案例库里没有覆盖的结构再自行按函数表编写。写入 `usr\work-formulas\<英文简称>.fml`。
   用户明确给出旧公式时，修改该公式的工作副本，不修改 EJClient 安装副本。
3. 用户只要求演示但没有给出策略规则时，优先取案例库中的**无副作用指标**（只画线、不下单、
   不弹窗，见指标案例库第 1、2、4、5、6 类），复制 Skill 的成功模板到工作目录并生成唯一名称
   `AgentFormula_yyyyMMdd_HHmmss`。
4. 工作源码保存为 UTF-8，调用 CLI 时使用 `--source-encoding utf8`。只有用户明确给出的源文件确认为 CP936 时才传 `cp936`。
5. 新建公式时同时确定两个名称：
   - 内部简称：1–64 位 ASCII 字母、数字或下划线，不能以数字开头，例如 `TrendBreakout`；它必须与文件名和 CLI `--name` 完全一致。
   - 显示名称：固定写成 `中文名称(英文简称)`，例如 `趋势突破(TrendBreakout)`，并通过 CLI `--display-name` 传递。英文半角括号 `()` 和中文全角括号 `（）` 均受接口支持，本 Skill 默认使用英文半角括号。
   - CLI 会在编译前检查公式注册表、源码和 DLL。简称重名时自动选择 `_2`、`_3` 等第一个可用名称，并同步更新显示名称括号内的英文简称；禁止把自动改名误判为失败。
   - 每轮响应后以 `data.name` 和 `data.display_name` 作为最终身份。若 `data.name_auto_renamed == true`，立即把当前工作源码的文件名和头部名称同步为最终身份，后续修复轮次固定使用该最终名称。
   - 只有用户明确要求修改已存在的旧公式时才传 `--replace-existing`；新建公式和普通演示禁止传该参数。
6. 每个 Ejia 公式必须填写头部名称信息，不能保留模板占位符：

```text
// 简称:TrendBreakout
// 名称:趋势突破(TrendBreakout)
```

   - `简称` 使用简短 ASCII 英文名，并与 `.fml` 文件名、CLI `--name` 和内部公式名完全一致。
   - `名称` 与 CLI `--display-name` 完全一致，默认采用 `中文名称(英文简称)`。
   - EJClient 最终显示该 `--display-name`，不能再次自动附加英文简称。
   - 自动演示公式也必须先把成功模板里的 `FORMULA_SHORT_NAME` 和 `FORMULA_DISPLAY_NAME` 替换掉，再调用 CLI。

## 账号功能权限

- 业务 IPC 使用当前 EJClient 账号的独立 CLI 权限；`status`、`doctor` 的可达或就绪结果不能证明账号有权限，不增加独立权限查询。
- 优先读取响应 `error.code`。遇到 `PERMISSION_DENIED`（标的目录脚本为 `code=PERMISSION_DENIED`）立即停止业务调用，不修改公式、不重试、不换 PID/安装目录、不请求重启来规避权限。
- 权限拒绝通常退出 32；`run` 的内部等待阶段也可能退出 34。不要仅按退出码判断为版本问题、普通等待错误或策略错误。
- 生成公式后运行时注册因权限被拒时，最终回复只写：“<用户所需策略名称>公式已写好，但运行时注册被拒：当前账号没有 CLI 使用权限，请开通权限后重新登录盘立方。”例如“双均线策略公式已写好，但运行时注册被拒：当前账号没有 CLI 使用权限，请开通权限后重新登录盘立方。”不得追加本地编译通过、磁盘已注册、源码路径、简称、显示名、策略细节、旧文件状态或权限恢复后的步骤预告。其他调用被拒时只写“当前账号没有 CLI 使用权限，请开通权限后重新登录盘立方。”只有授权恢复并刷新账号权限、用户要求继续后才恢复任务。
- 编译注册被拒时可能已生成磁盘产物，不能宣称公式已加载；等待阶段被拒也不能宣称已受理任务已经停止。具体判断见[CLI 权限拒绝处理](references/cli-commands.md#账号权限拒绝)。

## 编译、回报和继续生成

调用形式见 [CLI 命令表](references/cli-commands.md)。每次使用新的 `--out` JSON 路径。

### 编译成功

必须同时验证：

```text
exit_code == 0
success == true
data.strategy_registered == true
data.disk_registered == true
data.runtime_registered == true
data.editor_restart_required == false
data.editor_result.ok == true
data.editor_result.stage == "finalize"
data.editor_result.name == data.name
data.name_auto_renamed 为布尔值
data.editor_result.sha256 为 64 位十六进制
data.strategy_source 非空
```

成功后结束循环。上述字段只用于内部判定，不逐项展示；最终仅简洁说明公式已热加载到
当前 EJClient 的“加载指标”列表且无需重启客户端，不输出核验表或交付物清单。

### 可修复的公式错误

当退出码为 20 且 `error.code == "COMPILE_FAILED"`：

1. 立即在 commentary 中回报本轮错误摘要，包括 `phase/row/col/msg`；这是中间进度，不结束任务。
2. 读取 `data.editor_result.errors[]` 和必要的 `cl_out`，定位当前工作源码。
3. 只根据明确诊断和 Skill 函数表修改同一个 `.fml`。
4. 使用同一个公式名、一个新的输出 JSON 路径再次执行 `plf-cli compile`。
5. 最多自动修复 5 轮。

不得因为第一轮编译失败就停在文字说明，也不得新建一串不同名称的公式躲避错误。

### 不可继续的错误

以下情况立即停止并报告，不修改公式掩盖环境问题：

- 管道不可达、客户端身份改变，或 CLI 返回 `SERVER_IDENTITY_FAILED`（退出码 70，通常意味着 `--root` 指向的目录里没有正在运行的 EJClient）。
- `ready_for_compile != true`。
- `STRATEGY_REGISTRY_BUSY`、安装文件缺失、输出协议无效或输出目录不可写。
- 连续 5 轮仍为 `COMPILE_FAILED`。

## 单组参数回测与逐轮调整

**先看授权**：用户没说要优化时，本节的「逐轮调整」部分整体不适用——跑完基准轮就结束，
回到「授权边界」第 1 条。只有用户明确说了优化/调参才按下面迭代。

仅在用户明确给出或确认以下四项后执行：合约、周期、开始日期、结束日期。执行前读取
[CLI 命令表](references/cli-commands.md) 的单组 `run` 约定，并确认 `doctor.data.ready_for_backtest == true`。
周期支持 `1m`、`3m`、`1d`、`1w`、`1mo`，以及 `5m～1440m` 中 5 的整数倍；整数小时
`1h～24h` 是分钟别名，例如 `2h → 120m`。中文“10分钟”“2小时”先转换成对应的
规范分钟值，再传给 CLI。`24h → 1440m`，不得当成 `1d`；日线仍走独立数据源。
“日线/周线/月线”分别使用 `1d/1w/1mo`；`1m` 永远是一分钟，不是月线。
周月线按自然周/月合成，不换算成 `7d/30d`；只合成指定区间内的日线，首尾可能是
不完整周期，分析时必须说明。周/月不受分钟上限限制，但暂不支持 `2w/2mo` 等倍数。
执行前必须确认**规范化后的周期**存在于 `status.data.status.supported_periods`。
新客户端另提供 `period_rules` 描述步长、上限和扩展能力，但不能替代实际周期列表检查；
旧客户端没有该字段时仍只允许列表中已声明的周期。`2m`、`7m`、小数小时和超过上限
的周期不支持，不得擅自四舍五入、更换周期或在不支持时继续提交。完整规则见
[CLI 命令表的周期规则](references/cli-commands.md#周期规则)。

每天第一次使用本 Skill 且任务涉及回测合约时，先调用
`scripts\contract-catalog.ps1 -Action Ensure`。脚本通过 `plf-cli instrument-list` 拉取当前
EJClient 的最小标的表，并按本地日期和已确认安装目录缓存到 `usr\instrument-catalog.json`；
同一天、同一安装目录不得重复刷新。接口细节见[标的目录](references/instrument-catalog.md)。

用户提供中文名称时，调用
`scripts\contract-catalog.ps1 -Action Resolve -Query <名称> -OutFile <全新临时 JSON>`，
从该文件读取结果后立即删除：
- 期货表只保存 HYXX 品种名和两段基础 key；“指数”追加 `IDX`，“主连/主力/连续”追加 `MI`。
- 中文期货品种名后接月份时生成月份合约。郑商所 `ZCE` 同时接受三位和四位输入：
  `苹果611` → `ZCE AP 611`，`苹果2610` → `ZCE AP 610`；其他交易所使用四位年月，
  例如 `塑料2611` → `DCE L 2611`。
- 股票表直接保存中文名和 QDC 完整 `ContractID`；股票 `--contract` 只接受该完整值，
  例如 `SSE SHA 600519`。不得替换或降级为 `600519.SH` 等行情显示代码，也不得尝试旧格式兼容。
- 只有 `status == resolved` 才能把返回的 `key` 传给 `--contract`。
- `need_contract` 表示只识别到期货品种，必须询问用户具体要指数、主连还是月份合约；
  `ambiguous` 必须展示候选并让用户选择；`not_found` 必须报告未找到。不得自行补第三段。

期货最终仍使用 QuoteDataCenter 三段式 key：`交易所 品种 合约号`，三段之间使用单个
ASCII 空格，例如 `ZCE AP IDX`、`ZCE AP MI`、`ZCE AP 610`、`DCE LG 2611`。不得改写成
`ZCE|AP|IDX`、`ZCE.AP.IDX`、`ZCE_AP_IDX`、`APIDX` 或 `AP2601`。月份合约不在最小品种表中；
只允许使用用户明确给出的月份；郑商所可为三位或四位，其他交易所为四位。不能自行猜测月份。
`status.logged_in == null` 是未实现的状态字段，不能据此断言 QDC 合约表未加载；遇到
`CONTRACT_NOT_FOUND` 时先核对三段式空格格式。

口语简称、别名或英文缩写（例如「pta」「螺纹」）仍使用同一个
`contract-catalog.ps1 -Action Resolve`。例如“螺纹”先在别名表中关联到品种，再要求当天目录中
存在唯一的 `SHFE RB` 行；此时只确认了品种，脚本返回 `need_contract`，Agent 必须继续询问用户
要“螺纹指数”“螺纹主连”还是具体月份。目录中没有唯一对应行时不生成结果。
完整规则和验证用例见[标的解析](references/contract-resolution.md)。

1. 基准轮只调用一次 `plf-cli run`。没有用户参数时不传 `--params`，使用公式默认参数；有参数时把这一组写成单个 `Name=Value,...`。
   保持用户给出的合约、周期和起止日期，不因周末、节假日或取数失败自行缩区间、换合约。
   取数以区间内实际 K 线为准，不使用交易日历作强制检查或辅助提示；窗口按自然日期与数据量规划。
   周/月线由区间内实际日线合成。下载失败、超时、数据无效及根数截断保护仍保留。
   新客户端通过 `data_range_policy=actual_bars` 标明此口径；完整说明及旧版本错误处理见
   [CLI 命令表的实际 K 线取数](references/cli-commands.md#实际-k-线取数)。
   `mutable_right_edge == true` 表示请求触及当前尾部，最后一根 K 线可以仍在变化，且不复用不可变快照；
   是否取数成功仍依据任务终态，不能仅凭此字段判定成功或失败。
2. 每轮必须等待 `run` 返回完整终态，读取 `data.response.data.backtest.report` 后再分析；不得在上一轮未结束时提交下一轮。报告中 `headless_report_available == true` 时，资金曲线固定读取 `report.equity_curve`，采样信息读取 `report.equity_curve_meta`；为 `false` 时记录 `headless_report_error`，不得根据成交对、净利润或首尾权益伪造资金曲线。
3. 每轮响应 JSON **只允许读取和解析一次**。解析后立即在当前任务上下文中保存一条紧凑的轮次记录：轮次、实际参数、净利润、最大回撤、交易次数、胜率、盈亏比、权益曲线评价和停止原因候选；随后删除该轮 `--out` JSON。禁止为了“提取关键指标”“提取统计指标”或撰写总结而再次读取同一个 JSON，也禁止另建 `_rr.txt` 等会被覆盖的单轮摘要文件作为历史数据源。
4. 分析至少使用净利润、最大回撤、交易次数、胜率、盈亏比和权益曲线。默认资金曲线以 `static_equity` 为主要序列，用于评价已实现资金变化；`dynamic_equity`、可用资金、保证金和成本用于解释持仓期间浮动盈亏与资金占用，不得把两种口径混写成同一条曲线的结论。结合 `equity_curve_meta.sampled/stride/source_record_count` 判断曲线是否经过抽样。评价至少关注总体方向、峰谷回撤、长时间停滞和尾段稳定性，不得只比较首尾两个点。先检查交易数是否足够，再比较收益，不能只按净利润选择参数。若曲线不可用，明确把该轮标记为“资金曲线不可用”，仍可分析其他真实报告字段，但不得给出曲线形态结论。
5. Agent 每次只能根据已保存的轮次记录给出**下一组**参数和修改理由，然后再次调用一次 `run --params`。一组可同时包含多个字段，例如 `M=10,N=20,StopPoint=30`；这些字段共同构成一次回测，不得展开为多组组合。
6. 禁止调用 `optimize`、`--grid`、并行提交或自行生成笛卡尔积。CLI 对 `optimize` 返回 `OPTIMIZE_NOT_EXPOSED`。
7. 用户未指定轮数时最多迭代 3 轮；用户指定时**恰好等于用户说的轮数**，不得多跑一轮，
   也不得超过 5 轮。这里的“迭代”不含基准轮，例如用户说“基准轮 + 3 轮调参”或“优化 3 轮”，
   总运行数必须恰好是 4 份不同参数的实际结果——跑满即停，不追加“验证轮”“收敛轮”。
   连续两轮核心指标没有改善、报告无交易、参数已到合法边界或无法从报告提出有依据的新参数时提前停止。
   用户没有要求优化时，不进入本迭代，也不得用本条的“3 轮”上限把未经授权的调参正当化。
8. 每个参数对象只能提交一次；已完成轮次不得因标准输出为空、需要补充统计字段或总结尚未完成而重新运行。遇到环境、合约、取数或协议错误时，在输入和外部状态未变化前不得用相同参数重试。已有 `job_id` 时只等待该任务，禁止重复提交。
9. 若准备执行的命令与上一条命令在子命令、参数和输入状态上完全相同，必须先停止并检查已保存的轮次记录；没有可证明的新状态时不得调用工具。相同错误连续出现两次时停止自动尝试，向用户报告当前阻塞条件。
10. 最终比较直接使用当前任务上下文中的全部轮次记录，一次性给出结论；不得回头重读各轮响应文件。只推荐已实际回测过的参数，不得把尚未运行的建议写成“最优参数”。
11. 后续轮次继续使用同一个工作 `.fml` 和最终公式简称，并传 `--replace-existing`，避免自动生成 `_2`、`_3` 公式。任务结束时复验本轮所有 `--out` JSON 和辅助摘要均已删除，不删除工作公式和注册产物。
12. 回测报告完成时，`run` 即使删除任务失败也返回成功，并在 `data.cleanup_failed` 和 `data.cleanup_error` 标出清理警告。必须另查 `data.cleanup.data.deleted`；若清理失败，保留真实报告，不得重跑同一参数，也不得直接要求重启。仅可针对响应中同一个已知终态 `job_id` 补调用一次 `job-delete`。补删仍失败时报告原始错误码并停止后续自动回测，不得创建新任务掩盖残留。
13. `status` 中存在已完成任务不代表 IPC 卡住。`ready == true`、`engine_coordinator_ready == true`、`active == 0`、`queued == 0`、`pending_queue_depth == 0` 时必须视为健康，即使 `completed` 或 `job_table_size` 大于 0 也不得要求重启。只有实际出现 `ready == false`、`engine_shutting_down == true`、同一 PID 连续两次 IPC 超时，或任务超过自身超时且取消和删除均失败时，才可依据具体状态请求用户重启。详细判定见 [CLI 命令表](references/cli-commands.md#任务清理与重启判定)。
14. 零成交只表示当前合约、区间、周期、参数和策略逻辑没有产生交易，不能据此断言 `IDX` 不可回测，也不得自动把用户指定的 `IDX` 换成 `MI` 或月份合约。更换合约只能作为另一个明确标注的对照实验，并须先获得用户确认。
15. `exit_code == 70` 且 `error.code == "INVALID_IPC_RESPONSE"` 表示终态响应不符合 IPC/JSON 协议，不是策略结果。CLI 写出的错误 JSON 是重新包装后的错误信封，其文件大小不是 EJClient 原始响应体大小；不得据此断言报告超限，不得调整 ATR、减少成交、关闭报告段、修改公式或更换合约来规避。外部状态未变化时禁止重复提交同一回测；只允许补查一次 `status`，随后按[CLI 命令参考](references/cli-commands.md#ipc-终态报告异常)停止并报告协议故障。
16. 成功响应若包含 `data.response.data.numeric_fields_sanitized > 0`，表示 EJClient 为保证 JSON 合法而把非有限浮点数替换成了 0。保留并读取该轮真实报告，但不得使用可能受影响的 0 值做参数排名、宣称改进或继续自动调参；报告清洗数量并停止本轮优化，等待运行时计算源头修复。字段不存在或为 0 才按普通成功报告处理。

### 参数优化与源码变更边界

- `--params` 只能使用当前公式源码 `Params` 中已经声明、且已编译进当前 DLL 的参数名。开始基准轮前先从当前工作源码和 CLI 回显确认可用参数集合；后续轮次不得发明 `BandMax`、`MidExit` 等未声明参数。
- 返回退出码 34 且 `error.code == "FORMULA_PARAMETER_INVALID"` 时，这是参数对象无效，不是策略效果不佳，也不是可通过重复运行解决的瞬时错误。立即停止本次提交，指出无效参数；不得擅自修改源码、增加参数或改变交易规则来让该参数通过。
- 单组参数逐轮优化期间，公式源码、DLL 逻辑、入场/出场条件和参数声明必须保持不变。每轮只改变 `--params` 的值，保证所有轮次属于同一个可比较实验。
- 如果分析发现确实需要新增参数或修改交易逻辑，先结束当前优化批次并向用户说明拟修改内容及其影响。只有用户明确同意源码变更后才能修改并重新编译；编译成功后从新的基准轮重新开始，修改前后的结果分属两个版本，不得放进同一参数排名或声称直接提升。
- “本轮最优参数”不等于“源码默认参数”。**默认参数不得因任何一轮回测结果而被改动**：
  优化期间只通过 `--params` 传临时覆盖，不碰源码 `Params` 默认值，也不为此重新编译。
  最终回复关于改参边界**只保留一句「公式源码默认值一个没动」**，不展开复验明细（不列
  `TrendPeriod(60)` 之类的原值清单）、也不主动列复现所需的参数覆盖；用户点名问复现参数时再给。
  用户明确要求固化时，才修改默认值、重新编译并执行一轮不传 `--params` 的基准验证。
- 若在优化过程中因任何原因改动过默认值（例如中途误把某轮参数写回源码），优化结束后**必须改回原默认值并重新编译**，
  使公式恢复到用户拿到时的状态，然后在回复中说明已还原。禁止把「优化完的默认值」当作遗留结果留在源码里。
- 用户只要求生成 + 回测（没要求优化）时，公式源码从编译到交付全程只写用户的原始策略规则，
  `Params` 默认值不因回测结果调整。回测里可以指出亏损、回撤、交易数不足等客观问题，
  但不据此改参数；要改就先征求用户同意。

### 任务级费率与滑点

- 用户没有明确指定时，不传费率或滑点选项，让 QuoteDataCenter 使用合约默认费率。
- 只有用户明确要求自定义成本时才传 `--fee-mode`、`--open-fee`、`--close-fee` 或 `--slippage-ticks`。
- `fixed` 表示每手货币金额；`ratio` 使用小数比例，例如 `0.0001` 表示万分之一；滑点单位是最小变动价位 tick。
- 只覆盖开仓或平仓一侧时，未指定的一侧继续使用合约默认费率。只设滑点时不需要 `--fee-mode`。
- 传入成本选项前确认 `status.data.status.task_cost_overrides_implemented == true`。必须从终态回显的 `cost_source/cost_overrides` 判定是否生效，不得只根据利润差猜测。

对用户的阶段回报保持简洁：直接说明关键指标变化和下一轮调整理由，不单独报告基准轮完成状态，也不强调未传参数；只有参数覆盖实际影响分析时才提本轮参数。用户要求完整报告时再输出或导出完整报告。
用户要求资金曲线时，先用当前内存中的 `equity_curve` 按 DlgBP 口径生成以记录顺序为横轴、资金为纵轴的实际曲线图并展示，时间只作刻度标签，不能只输出点列表或文字总结。用户另外要求资金曲线数据或 CSV 时，在删除本轮临时响应 JSON 前调用
`plf-cli report-export --input <本轮响应.json> --output <新文件.csv> --section equity`
导出正式 CSV。该子命令不连接 EJClient，**不得附加 `--out`、`--root` 或 `--pid`**；当前实现中
`--output` 已占用输出路径槽，再传 `--out` 会被判为重复参数，而错误标准输出在本机可能不可见。
导出路径必须尚不存在；标准输出为空时检查目标 CSV 是否创建、非空且包含表头和数据行，不能据此
宣称 `report-export` 未实现。CSV 是数据附件，不能替代资金曲线图；未要求 CSV 时不调用 `report-export`。

## 后台策略执行器

用户要求在 EJClient 中持续计算策略、查看或管理后台任务时，完整读取
[后台执行器命令与安全边界](references/executor.md)。添加前确认最终注册公式简称、已解析的盘立方合约 key
和受支持周期；`--params` 只传用户明确给出的单个参数对象。`executor-add` 默认仅添加，
用户要求立即启动时才加 `--start`；已存在任务不得为求“干净”而自动停止或删除。

只查询用 `executor-list` / `executor-status`。`executor-start`、`executor-stop`、`executor-remove`
均属改变运行状态的操作，必须与用户明确授权及目标 `executor_id` 一一对应。写操作遇到超时、
响应丢失或 `result_unknown`，保留 `operation_id`，先用 `executor-request-status` 对账；
不能盲目重试同一写操作。

## 测试

执行确定性演示时读取 [纯 CLI 编译循环测试](references/test-method.md)。测试必须表现出“第一次失败有结构化错误，随后修改同一源码并成功注册”，不调用任何测试脚本。
