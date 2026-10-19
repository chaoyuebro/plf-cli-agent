# plf-cli 编译与单组回测命令

本 Skill 只使用以下命令：

```text
plf-cli version [--out <new-output.json>]
plf-cli help [--out <new-output.json>]
plf-cli status [--root <install-root>] [--pid <pid>] [--out <new-output.json>]
plf-cli doctor [--root <install-root>] [--pid <pid>] [--out <new-output.json>]
plf-cli instrument-list [--root <install-root>] [--pid <pid>] [--out <new-output.json>]
plf-cli history --contract <contract> --period <规范分钟周期|1d|1w|1mo>
    --start <yyyymmdd> --end <yyyymmdd>
    [--timeout <1..600>] [--root <install-root>] [--pid <pid>]
plf-cli compile --source <source.fml> --name <internal-name>
    --display-name <display-name>
    [--source-encoding utf8|cp936]
    [--editor ejia|mylang]
    [--replace-existing]
    [--root <install-root>]
    [--pid <pid>]
    [--out <new-output.json>]
plf-cli run --source <source.fml> --name <internal-name>
    --display-name <display-name>
    --contract <contract> --period <规范分钟周期|1d|1w|1mo>
    --start <yyyymmdd> --end <yyyymmdd>
    [--params Name=Value,...]
    [--fee-mode fixed|ratio]
    [--open-fee <non-negative-number>]
    [--close-fee <non-negative-number>]
    [--slippage-ticks <non-negative-number>]
    [--source-encoding utf8|cp936]
    [--editor ejia|mylang]
    [--replace-existing]
    [--root <install-root>]
    [--pid <pid>]
    [--timeout <1..600>]
    [--out <new-output.json>]
```

禁止调用 `optimize`、`--grid`，也禁止直接编排 `backtest-submit`、`job-wait` 等底层任务命令。
本 Skill 的回测入口只有 `run`，且每次只传一个 `--params` 对象。清理例外：`run` 已取得终态报告，或 `history` 已取得完整数据，但
`data.cleanup.data.deleted != true` 时，可对响应中同一个已知终态 `job_id` 补调用一次 `job-delete`。
`history` 的 ID 位于 `data.job_id`；服务端返回 `JOB_NOT_FOUND` 表示该作业已不存在，无须重试。
不得提交新任务或自行列举、清理其他任务；权限拒绝时按账号权限拒绝规则停止业务调用。

## 历史 K 线取数

用户要求历史 K 线数据时只调用 `history`，默认不传 `--out`，直接读取标准输出 JSON。
同一次调用内捕获并解析完整响应，不先写响应文件；不生成或编译公式，不调用 `run`、
`history-submit`、`backtest-submit` 或 `job-wait` 来拼装替代流程。
只有用户明确要求保存 JSON 文件时才额外传 `--out <新文件.json>`。

1. 读取 `version`，确认 CLI 顶层 `data.history_data_implemented == true`；再读取 `status`，
   确认服务端 `data.status.history_data_implemented == true`、`data_adapter_ready == true`，且
   `supported_periods` 包含请求的规范周期。缺少能力字段表示版本不支持，应更新 CLI/EJClient。
   `status` 退出 31 或 `ready == false` 可能只是公式引擎未就绪，不阻止数据能力已就绪的取数。
   不用 `doctor.ready_for_backtest` 作为历史取数门禁。
2. 使用既有标的解析流程取得合约 key，明确周期及起止交易日期；持续携带已确认的 `$RootArgs`、
   同一个 `$ClientPid`；默认省略 `--out`。超时默认 300 秒，显式值范围 1～600 秒。
3. CLI 自动提交纯取数作业、等待 `data_ready`、每页读取最多 5000 根并汇总完整 JSON。
   取数、等待和分页共享超时预算；终态清理不计入。最终输出不受单次 IPC 32 MB 限制。
4. 按 UTF-8 捕获标准输出，在同一次调用内解析为内存对象；stderr 单独保留，不用 `2>&1` 混入 JSON。
   确认 `schema == "plf-cli/1"`、`command == "history"`、`success == true`、
   `exit_code == 0`，并确认 `data.bar_count == data.bars.length`。分页失败不会返回部分成功的 bars。
   无数据仍为 `NO_HISTORY_DATA`，不得替换为空数组成功，也不为了补数据自动改周期或扩大区间。
5. 成功结果的 `data.cleanup` 为本次作业删除回执。清理失败保留 `data.job_id`、
   `cleanup_failed/cleanup_error`；数据已完整取回时不因清理失败重新取数。
   失败响应保留原始错误和已知作业 ID，权限拒绝时立即停止，不换客户端或反复重提。

默认调用示例（直接使用内存中的 `$HistoryResult.data.bars`）：

```powershell
$HistoryArguments = @(
  'history', '--contract', $Contract, '--period', $Period,
  '--start', [string]$StartTradeDate, '--end', [string]$EndTradeDate
) + $RootArgs + @('--pid', [string]$ClientPid)
$HistoryPreviousEncoding = [Console]::OutputEncoding
try {
  [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
  $HistoryRaw = & $Cli @HistoryArguments
} finally {
  [Console]::OutputEncoding = $HistoryPreviousEncoding
}
$HistoryJson = $HistoryRaw -join [Environment]::NewLine
if ([string]::IsNullOrWhiteSpace($HistoryJson)) {
  throw 'history returned no JSON on stdout; do not resubmit or add --out automatically.'
}
$HistoryResult = ConvertFrom-Json -InputObject $HistoryJson -ErrorAction Stop
```

调用和解析放在同一次工具调用中；需要展示时从内存对象提取所需数据或摘要，避免把完整大数组
打印到工具输出后再依赖可能被截断的回显解析。stdout 为空、截断或无法解析时报告响应读取失败，
保留已经取得的作业 ID，不自动补 `--out`、重定向文件或重复提交同一取数请求。

响应沿用 `plf-cli/1`，`data` 直接包含以下字段（不是 `data.response.data`）：

| 字段 | 类型与含义 |
| --- | --- |
| `contract` / `period` | 合约 key、规范周期；小时别名规范化为分钟 |
| `start_trade_date` / `end_trade_date` | 请求起止交易日期，包含两端 |
| `bar_count` / `bars` | 最终根数、按时间严格递增的完整 K 线数组 |
| `mutable_right_edge` | 本次区间可能包含仍在变化的最新尾部 |
| `bars[].time` / `end_time` | 原始 Unix 秒，不额外加减时区偏移 |
| `bars[].trade_date` | 数据源交易日期；夜盘按该字段归属 |
| `bars[].open/high/low/close` | 源价格数字，不套用报告展示的小数两位规则改写数据 |
| `bars[].volume` / `position` | 十进制字符串，完整保存有符号 64 位整数；不得经 double 转换后再保存 |

`position` 沿用数据源语义：期货为持仓量，股票为成交额。周/月沿用下节的区间内日线合成规则，
保留首尾不完整周期；`calendar_source/calendar_range_policy/calendar_boundary_policy` 会随结果回显。

默认只在内存中使用历史响应，不创建由 Skill 管理的历史响应文件或缓存。CLI 内部分页汇总仍会
使用调用结束后自动删除的临时文件。用户明确要求保存数据时保留其指定的正式 JSON 文件，
不当作中间文件删除。取数本身不生成回测报告，也不授权额外回测或绘图。

## 周期规则

- 中文“日线/周线/月线”分别规范化为 `1d/1w/1mo`；`1m` 是一分钟，月线不能写成 `1M`。
  周线按周一开始的自然周、月线按自然月合成，不等同于 `7d/30d`，暂不开放多周、多月、季度、年线。
- 周/月使用已成功取回的区间内实际日线统一合成，不在每个下载分页内各自合成。
  首尾不足整周/月的部分保留，不向区间外补取数据；`calendar_range_policy` 为
  `aggregate_only_requested_trade_dates`，`calendar_boundary_policy` 为
  `include_partial_first_and_last_bucket`。分析时说明边界可能不完整，不冒充完整周/月结果。
  时间标签沿用现有口径：周一、月首工作日；标签可能早于请求起日，但输入数据不会早于起日或晚于截止日。
  `calendar_source` 为 `1d`；持仓量期货取末值、股票按现有合成口径累计。
  仅当 `supported_periods` 包含 `1w/1mo` 才运行；`period_rules.calendar_aggregation_enabled` 描述服务端日线合成能力。

- 保留 `1m`、`3m`、`1d`；支持 `5m～1440m` 中 5 的整数倍，例如 `10m`、`20m`、`45m`、`90m`、`120m`。
- CLI 和 IPC 接受整数小时 `1h～24h`，统一规范化成分钟：`1h → 60m`、`2h → 120m`、`3h → 180m`。
  Agent 把中文“10分钟”“2小时”转换成 `10m`、`120m` 后提交。任务、缓存和报告采用同一个规范周期。
- `24h` 是 `1440m`，不是 `1d`。分钟线沿用客户端的周期合成和小时划分设置，不承诺跨交易日拼成固定根数；日线单独取日线数据。
- 拒绝 `2m`、`7m`、`1.5h`、`25h`、`1445m`、负数、零、前导零、空格和大写单位；不得偷偷替换用户周期。
- 执行前用规范分钟值（或 `1d/1w/1mo`）检查 `status.data.status.supported_periods`；列表包含当前客户端实际支持的全部规范周期。
  不在列表内就停止并说明当前客户端尚不支持，不得只因 CLI 能解析就提交。
- 新客户端的 `status.data.status.period_rules` 包含 `minute_step: 5`、`max_minutes: 1440`、
  `minute_multiples_enabled`、`hour_alias_minutes: 60`、`canonical_unit: "m"`。
  `minute_multiples_enabled` 取自数据模块独立能力位；旧数据模块不声明时不能假定支持新增周期。
  旧客户端没有 `period_rules` 时仍以 `supported_periods` 为准；Agent 始终提交规范分钟写法，因此 `1h` 在旧客户端可按已声明的 `60m` 使用。
- 数据量和超时限制保持不变；周期合法不保证任意区间都有足够历史数据。

## 安装目录与身份校验

默认目录不可用时，必须询问用户实际安装目录并等待回答，禁止自行搜索或猜测。安装目录只能来自用户明确给出的路径、接受的默认路径或此前经用户确认后保存的本副本配置；Agent 的“已确认”声明与用户回复“已经启动”不能替代目录确认。文档中的 `D:\Release` 仅是示例，不得据此选择安装目录。

`--root` 是盘立方安装目录，所有命令都支持；本 Skill 的每次调用都要带上它，
取值来自 `paths.ps1` 的 `$RootArgs`（即 `@('--root', $Root)`），
必须在子命令之后插入；使用 `--out` 时放在它之前，且与 `--root` 的值分成两个独立数组元素：

```powershell
$CliArguments = @('compile', '--source', $Source) + $RootArgs + @('--out', $Output)
```

CLI 用 `--root` 校验 IPC 命名管道的归属方就是该安装目录的 EJClient。实测行为：

```text
--root 正确且该目录的 EJClient 在运行   → exit 0，data.install_root == $Root
--root 指向不存在的目录                 → exit 70，SERVER_IDENTITY_FAILED
--root 指向另一个存在的安装目录         → exit 70，SERVER_IDENTITY_FAILED
不传 --root                             → 默认按 plf-cli.exe 自身所在目录推断
```

`SERVER_IDENTITY_FAILED` 的含义是“管道归属方不是预期的 EJClient 安装”，不是公式错误：
此时先核对 `$Root`（是否已由用户确认、是否等于用户安装盘立方的那个目录），
按 [首次加载确认安装目录](root-config.md) 处理——若客户端其实在别处，请用户直接给出路径后
`set` 覆盖配置，**不代为查找**；不要改公式继续重试。

成功的 `status` / `compile` 响应都带 `data.install_root`，它是本次校验通过的安装目录，
必须与 `$Root` 一致。

## Windows 命令执行约束

- 本机 Bash 缺少 `ls`、`dirname` 等 coreutils，调用会退出 127；本 Skill 全程使用 PowerShell，不降级到 Bash。
- `history` 默认直接捕获 UTF-8 标准输出并在同一次调用内解析，不传 `--out`，详见历史 K 线取数。
  其他命令每次传一个尚不存在的 `--out` JSON 路径，该文件是其响应的权威来源；标准输出仅作辅助。
- 可执行文件和参数必须分离。中文显示名先放入变量，再作为参数数组中的一个完整元素传递：

运行前，先用文件编辑能力创建 UTF-8 编码的 `$DisplayNameFile`，内容例如
`布林带策略(BollingerBand)`；不要在无 BOM 的 PowerShell 5.1 脚本里直接写这段中文。

```powershell
# Create DisplayNameFile as UTF-8 before running this ASCII-only script.
$DisplayName = [IO.File]::ReadAllText(
  $DisplayNameFile, [Text.Encoding]::UTF8
).Trim()
$Arguments = @(
  'compile',
  '--source', $Source,
  '--name', $Name,
  '--display-name', $DisplayName,
  '--source-encoding', 'utf8',
  '--editor', 'ejia',
  '--pid', [string]$ClientPid
) + $RootArgs + @('--out', $Output)
& $Cli @Arguments
try {
  $Result = Get-Content -Raw -Encoding UTF8 $Output | ConvertFrom-Json
} finally {
  foreach ($Path in @($Output, $DisplayNameFile)) {
    if ([IO.File]::Exists($Path)) {
      [IO.File]::Delete($Path)
    }
  }
}
```

- 对使用 `--out` 的命令，本机执行器可能吞掉 PowerShell 子进程标准输出；调用后读取本次响应文件。
  `history` 按专节在进程内直接捕获、解析 stdout，不把执行器回显当作数据源，也不自动落盘重试。
- PowerShell 5.1 读取响应 JSON 文件时必须显式使用 `Get-Content -Raw -Encoding UTF8`。省略 `-Encoding UTF8` 可能只让中文 `data.display_name` 显示成乱码；JSON 文件本身仍可能完全正确，不能据此误判为 CLI 写错显示名或重新注册公式。
- 不得在 `& $Cli @Arguments` 后添加 `| Out-Null`、重定向到管道或其他 PowerShell 管道操作。本机实测带管道时 `$LASTEXITCODE` 会错误地变成 70，而 JSON `exit_code` 仍为真实的 0。
- JSON 内的 `success`、`exit_code` 和结构化字段是唯一判定依据；不得使用 `$LASTEXITCODE`，也不得只凭执行器显示的退出码作成功判断。
- 不得把含中文公式名的整条命令拼成一个 shell 字符串，避免管道、引号、代码页或 shell 转义改变 `--display-name`。
- JSON 读取、解析并保存为内存对象后，立即用 `[System.IO.File]::Delete()` 删除对应中间文件；显示名辅助文件、探测脚本及 `_plf_*`/`_probe*` 文件也在使用后直接删除。错误结果同样清理，不保留到下一轮。本机 `Remove-Item` 会被 safe-delete 包装器拦截并抛出 `trash-failed / Some operations were aborted`，不得再用它清理；`Remove-Item -LiteralPath @($a,$b)` 这类多路径数组写法更会**静默失效**（加了 `-ErrorAction SilentlyContinue` 也不报错），把 `--out` JSON 残留在临时目录。收尾统一做法：`Get-ChildItem -LiteralPath $env:TEMP -Filter '_plf*' -File` 枚举后对每个路径调用 `[IO.File]::Delete()`，并再枚举一次确认剩余为 0。删除前必须确认目标就是本轮创建的明确文件路径。

## 编译调用

使用上一节的 PowerShell 参数数组形式调用；每轮只替换 `$Output`，
`$Name` 与 `$DisplayName` 保持不变。

只要 `status` 返回唯一有效的 `data.selected_pid`，首次 `status` 就可不传 `--pid`，不受当前 EJClient 进程总数影响；取得该值后，`doctor` 和每次 `compile` 都固定传该 PID。

`--out` 必须是尚不存在的 `.json` 路径。`status`、`doctor` 和每轮 `compile` 都创建新的输出文件，不能覆盖或误读上一轮结果。
解析完成后删除该 JSON；不得删除工作 `.fml`、已注册 `.fml` 或 DLL。

## 单组参数回测调用

`--contract` 使用 QuoteDataCenter 的原生三段式 key：`交易所 品种 合约号`。分隔符是单个
ASCII 空格，整个 key 必须作为参数数组中的一个元素，例如：

```powershell
'--contract', 'ZCE AP IDX'
'--contract', 'ZCE AP MI'
'--contract', 'DCE LG 2611'
```

第三段含义固定如下：用户指定“主连”时使用 `MI`；用户指定“指数”时使用 `IDX`；
指定具体月份时使用 QDC 合约号。比如“苹果主连”是 `ZCE AP MI`，“苹果指数”是
`ZCE AP IDX`。

不支持 `ZCE|AP|IDX`、`ZCE.AP.IDX`、`ZCE_AP_IDX`、`APIDX` 等自行拼接形式。
中文名称先通过
`scripts/contract-catalog.ps1 -Action Resolve -Query <名称> -OutFile <全新临时 JSON>` 解析。
该脚本每天首次使用 `instrument-list` 刷新品种/股票最小目录；期货指数和主连可自动生成标准
三段 key。郑商所月份可输入三位或四位，四位删除首位；其他交易所使用四位年月。
用户没给月份时不得猜测或批量盲试。
`status.logged_in` 当前可能固定为 `null`，不能把它当作未登录或合约表为空的证据。

`run` 每次代表一次完整回测。`--params` 的逗号分隔字段属于**同一组参数**，例如：

```powershell
$RunArguments = @(
  'run',
  '--source', $Source,
  '--name', $Name,
  '--display-name', $DisplayName,
  '--source-encoding', 'utf8',
  '--editor', 'ejia',
  '--replace-existing',
  '--contract', $Contract,
  '--period', $Period,
  '--start', $StartTradeDate,
  '--end', $EndTradeDate,
  '--params', 'M=10,N=20,StopPoint=30',
  '--timeout', '600',
  '--pid', [string]$ClientPid
) + $RootArgs + @('--out', $Output)
& $Cli @RunArguments
```

### 实际 K 线取数

`--start` / `--end` 使用 `yyyymmdd`。保持用户给出的合约、周期和日期范围，按实际返回且位于
指定范围内的 K 线回测。新客户端返回 `data_range_policy=actual_bars`；CLI 取数规划与结果判定
不读取交易日历，也不返回 `calendar_diagnostics` 或日历辅助提示。

- 日线直接使用实际日线；分钟/小时沿用 QDC 的基础分钟取数和周期合成规则，小时规范化为分钟。
- 窗口按自然日期、时段密度和根数上限划分，直接请求窗口截止日期，不要求下一交易日锚点。
- 不要求区间起止当天或日历所列日期有 K 线。空窗口可以继续；整个范围无 K 线时返回 `NO_HISTORY_DATA`。
- 下载失败、超时、取消、回调元数据错误和无效/乱序 K 线仍失败。分钟/小时因根数限制未取到左侧时，
  保留有界扩容及拆窗；`DATA_RANGE_INCOMPLETE` 不再表示逐日交易日历校验失败。
- `calendar_source` / `calendar_range_policy` / `calendar_boundary_policy` 是周/月自然周期合成信息，
  不表示交易日历检查，也不能用来要求用户补齐休市日 K 线。

请求截止日为今天时，`mutable_right_edge=true` 表示当前尾部可能变化，该任务不写入或复用
进程内不可变行情快照。这个字段不证明已经取到数据，仍需依据终态和真实报告判断成功。
不得因为尾部仍在变化、周末或节假日而自动回退用户给出的日期。

取数失败的解释必须有证据：纯取数命令不涉及公式，但仍走同一取数通道，不能单凭区间失败推断
真实日线断档。`bar_count=0` 是最终输入数量，失败时数据可能已清理；最后一次回调的首尾时间
也只描述该次回调，不能据此宣称整个范围一根未取到或某日期之后全无数据。

旧客户端若仍返回 `TRADE_CALENDAR_NOT_READY` 或因日历校验返回 `DATA_RANGE_INCOMPLETE`，
如实报告该客户端的取数/日历故障，不宣称新逻辑已在旧版本生效。没有实际数据内容证据时，
不得认定本地历史没下载全或断档；不要把重新下载、缩区间或换合约当作已经证实的修复。
变更区间/合约仍需用户明确授权；输入和外部状态未变化时不重复提交同一回测。

上述命令只运行 `(M=10,N=20,StopPoint=30)` 这一组，不得把各字段拆成取值列表，不得生成
笛卡尔积。下一组参数只能在读取本轮 `data.response.data.backtest.report` 后由 Agent 给出，再单独调用一次 `run`。

`--params` 中的每个名称都必须已经存在于当前公式 `Params` 声明并编译进当前 DLL。
若响应为退出码 34 + `FORMULA_PARAMETER_INVALID`：

1. 不用相同参数重试；
2. 不把它计为一轮有效回测；
3. 不得为使该参数生效而擅自新增参数、修改交易逻辑或重新定义策略；
4. 只能改用已存在的参数继续，或先向用户提出源码变更；用户确认后结束旧批次、重新编译并
   从新基准轮开始。

同一批顺序回测的可比性条件是公式源码和 DLL 逻辑保持不变。入场条件、出场条件、参数声明
或默认计算逻辑只要发生变化，就必须建立新的批次；修改前后的结果不得放在同一“最优参数”
排名中。回测中通过 `--params MidExit=0` 得到的最优结果也不会自动把源码里的默认值从 1
改成 0；只有用户明确要求固化最优参数时才修改源码默认值、重新编译，并以不传 `--params`
的回测确认默认结果可复现。**若优化期间改动过默认值，优化结束后必须改回原值并重新编译**，
把公式还原到用户拿到时的状态。

### 轮次授权边界

`run` 的轮次数由用户决定，不由 Agent 按结果好坏决定：

- **用户没要求优化时**：只跑基准轮一次。生成公式 → 编译注册 → 跑一次回测 → 展示结果，
  任务即结束。首轮亏损、胜率低、回撤大、样本偏少都**不构成**继续调参的理由；
  要改参数必须先说明理由并取得用户同意。
- **用户要求优化 N 轮时**：总运行数恰好是 `N + 1`（基准轮 + N 轮调参），
  或用户另行指定的口径。跑满即停，**不得追加“验证轮”“收敛轮”**。
- **任何情况下都不得**把未经用户要求的调参轮次当作「顺手做了」而一并提交。

用户明确要求任务级费率或滑点时，在同一个 `$RunArguments` 数组中追加：

```powershell
'--fee-mode', 'ratio',
'--open-fee', '0.0001',
'--close-fee', '0.0001',
'--slippage-ticks', '1'
```

`fixed` 是每手固定金额，`ratio` 是 0—1 的小数比例。只设置滑点时可以省略
`--fee-mode`；只要传了 `--open-fee` 或 `--close-fee`，就必须同时传 `--fee-mode`。
未传的费率侧继续使用 QuoteDataCenter 合约默认值，覆盖只在当前回测任务内生效。

成功回测至少验证：

```text
exit_code == 0
success == true
data.phase == "completed"
data.execution_binding.verified_in_engine == true
data.response.data.state == "completed"
data.response.data.backtest.engine_return == 1
data.response.data.backtest.report 存在
```

### 任务清理与重启判定

`run` 的 `--timeout` 是提交和等待回测终态共享的预算，从提交开始计时，包含取数、排队和实际回测；
编译、终态后的删除任务不计入这项预算。`history` / `run` / `history-submit` / `backtest-submit` / `job-wait`
接受 1～600 秒，CLI 默认仍为 300 秒；本 Skill 的回测命令显式使用 `--timeout 600`，用户指定更短时使用用户值。
超过 600 秒的参数会被拒绝。上限增加需要同时更新 `plf-cli.exe` 与 `EJClient.exe`，不改变 QDC 的底层下载等待限制。
**2026-10-08 本机实测：`--timeout 600` 已被接受**（`run` 返回 `exit_code=0`、`success=true`）；
若某台机器仍拒绝 600，说明该机的 CLI/EJClient 版本偏旧，按上一段的排查手法确认 `error.code`
后再提示升级，不要据旧经验对外宣称"上限是 300 秒"。
报告完成后，即使删除任务失败，`run` 仍返回 `success == true`，并设置 `data.cleanup_failed == true`
及 `data.cleanup_error`。必须另查 `data.cleanup.data.deleted`：

- 为 `true`：任务生命周期完整，继续分析报告。
- 不为 `true`，但响应中有已知终态 `job_id`：保存已经读取的报告，只对该 ID 补调用一次
  `plf-cli job-delete --job <id>`；禁止重跑相同参数。
- 补删失败：保留原始清理错误码并停止自动处理。不得用新回测、反复删除或重启来掩盖失败。

`status.data.status.job_counts.completed` 和 `job_table_size` 是保留的终态数量，不是 IPC 卡死证据。
任务表容量为 `job_table_capacity`，服务端达到容量时会优先淘汰最旧终态。满足以下条件时必须判定
服务健康，不得请求用户重启：

```text
status.success == true
status.data.status.ready == true
status.data.status.engine_coordinator_ready == true
status.data.status.engine_shutting_down == false
status.data.status.job_counts.active == 0
status.data.status.job_counts.queued == 0
status.data.status.pending_queue_depth == 0
```

只有具有直接证据时才可请求重启，并在回复中只说一次具体异常：`ready == false`、
`engine_shutting_down == true`、同一 EJClient PID 在外部状态未变化时连续两次 IPC 超时，或同一任务
超过自身 `--timeout` 且 `job-cancel` 和 `job-delete` 都失败。标准输出为空、零成交、完成任务数量非零、
`logged_in == null` 都不是重启条件。

### IPC 终态报告异常

`exit_code == 70` 且 `error.code == "INVALID_IPC_RESPONSE"` 只说明 CLI 已读取到的终态响应未通过
有界 UTF-8、严格 JSON 或 `plf-ipc/1` 信封校验。CLI 随后写入 `--out` 的约 2—3 KB 错误对象是
本地重新包装的错误信封，不是 EJClient 原始响应，不能用其大小推断“报告超过 IPC 上限”。一笔成交也
可能因统计值出现 `NaN`/`Infinity` 而使严格 JSON 解析失败，因此禁止采用以下规避动作：

- 调整 ATR、止损止盈或其他策略参数来减少成交；
- 改成零成交窗口、更换 `IDX`/`MI`/月份合约或关闭报告字段；
- 在输入和客户端状态未变化时重复提交同一回测；
- 因任务已经完成就直接要求用户重启 EJClient。

遇到该错误时只调用一次 `status`。若 IPC 本身可达且服务状态健康，删除本轮临时错误 JSON，明确报告
“回测计算可能已经完成，但终态报告协议/序列化失败”，然后停止本轮参数优化；该轮没有可用于分析的
真实报告。只有 `status` 同时满足上节的真实重启条件时，才请求重启。

新运行时会在最终序列化前清洗遗漏的非有限浮点数。成功响应出现
`data.response.data.numeric_fields_sanitized > 0` 时，报告仍是真实终态，但对应的异常数值已经被替换为
0。记录该数量并完成任务清理，不把该轮用于参数排名，也不继续自动调参；字段不存在或为 0 时正常分析。

零成交时保持用户指定的合约、周期和日期不变，先分析信号和参数。`IDX` 可能不适合实盘下单，
但这不等于不能用于模拟回测。把 `IDX` 改成 `MI` 或月份合约属于新的数据口径，只能在用户确认后
作为独立对照轮运行，不能悄悄回退或覆盖原回测结论。

传了任务成本时还要验证 `data.response.data.cost_source` 与
`data.response.data.cost_overrides`；下一个未传成本的任务必须恢复 `qdc_default`。

报告分析使用 `report.profit`、`report.statistics`、`report.trade_pairs`、
`report.equity_curve`、`report.year_month` 和 `report.trade_parse`。每轮解析后立即删除对应
`--out` JSON；需要留档时使用正式报告导出文件，不保留临时响应文件。

### 报告字段名对照（防误取，2026-09-23 实测踩过）

报告顶层键固定为：
`close_at_end, cost_source, equity_curve, equity_curve_meta, headless_report_available,
headless_report_schema, monthly, open_positions, profit, statistics, trade_pairs, trade_parse,
year_month, yearly`。

- **`trade_parse` 没有 `total` / `win` / `lose` / `win_rate`**：它只有 `all_*`、`win_*`、`lose_*`
  三组前缀字段（`all_trade_lots`、`all_avg_profit`、`all_avg_hold_period`、
  `win_trade_lots`、`win_avg_profit`、`win_avg_hold_period`、`win_avg_float_pnl`、
  `win_max_consecutive_pnl`、`win_max_trade_pnl`，`lose_*` 同构）。
  取不存在的字段 PowerShell **不报错**，只会静默得到空值 —— 打印出来就是一行 `trades=` 空白，
  别以为是回测没出成交。**笔数与胜率的权威位置是 `statistics.kind_total`**：
  `trade_lots` / `win_lots` / `lose_lots` / `win_rate` / `win_lose_ratio`（＝均盈÷均亏）/
  `avg_win` / `avg_lose` / `avg_win_period` / `avg_lose_period` / `max_consecutive_lose` /
  `max_consecutive_win` / `max_win` / `max_lose` / `total_win` / `total_lose` / `total_cost` /
  `net_profit` / `max_used_fund`；分方向看 `statistics.kind_long.*` 与 `statistics.kind_short.*`（同构）。
- `profit` 侧常用：`start_fund` / `last_assets` / `total_profit` / `profit`（比率看 `statistics.profit_ratio`）、
  `total_win` / `total_lose` / `cost` / `all_times` / `win_times` / `lose_times` /
  `max_assets` / `min_assets` / `max_retracement`（＝最大回撤，含浮盈口径）/ `liquidated_profit`
  （＝不含手续费净额，`liquidated_profit - cost == total_profit`，可自检）/ `hold_profit`。
- `statistics` 侧常用：`max_drawdown`、`max_drawdown_prior_high_ratio`、`sharpe_ratio`、
  `annual_profit_ratio`、`profit_ratio`、`hold_time` / `hold_time_ratio`、`net_profit_drawdown_ratio`、
  `max_premium_prior_low_ratio`、`monthly_avg_profit`、`max_empty_days`、`total_hold_period`、
  `total_trade_time`；**`annual_return` 不存在**（曾误取为空），年化看 `annual_profit_ratio`。
- **`year_month` 实测返回空对象**（唯一属性名为空串，值为空白），月度/年度数据改看 `monthly` 与 `yearly`。
- 一次 `run` 只够解析一轮：**在同一脚本里把所有需要的字段一次性抽完**，不要为补取字段重跑回测。

### 资金曲线字段

资金曲线只使用完整终态中的以下路径：

```text
data.response.data.backtest.report.headless_report_available
data.response.data.backtest.report.headless_report_error
data.response.data.backtest.report.equity_curve
data.response.data.backtest.report.equity_curve_meta
```

当 `headless_report_available == true` 时，`equity_curve[]` 每个点包含：

```text
time, bar_id, dynamic_equity, static_equity, available,
long_margin, short_margin, cost, total_return
```

- `static_equity` 是静态权益，最接近 DlgBP 的“初始资金 + 已实现盈亏 - 手续费”口径，作为默认资金曲线和分析的主要序列。
- `dynamic_equity` 包含持仓浮动盈亏，只在用户明确要求动态权益、浮动盈亏或两种口径对比时作为辅助序列。
- **`statistics.max_drawdown` 走的是「含持仓浮盈」口径，不是 `static_equity` 口径，两者不可混写。**
  实测（TurtleTrend / ZCE AP IDX / 1d，2026-09-22）：报告给 `max_drawdown = -41700`
  （`max_drawdown_prior_high_ratio = -0.03836`，反推前高约 1,087,000），
  而按 `static_equity` 平台值逐段算出的最大回撤只有 **23,228.75**（峰值 1,068,478.75 → 谷底 1,045,250，-2.17%）。
  `static_equity` 序列里根本不存在 4.17 万的峰谷落差，所以报告值是含浮盈算出来的。
  **画 `static_equity` 曲线时，不要把报告的 `max_drawdown` 直接标成这条曲线的回撤**；
  要么并列标注两个口径并写清来源，要么按 `static_equity` 平台值自己重算（平台值是阶梯函数的全部极值，
  逐段跑峰谷即精确值，不需要插值）。
- 交叉验证技巧：`trade_parse.lose_max_consecutive_pnl` 与按 `static_equity` 算出的连亏段峰谷落差应当吻合
  （同上例，x=589 处落差 23,148.75 == 报告 -23148.75），可用它反证自己的回撤算法没写错。
- `available`、多空保证金和 `cost` 用于解释权益变化与资金占用。
- `equity_curve_meta` 的 `source_record_count` 是源记录数，`point_count` 是实际返回点数，
  `stride` 是抽样步长，`sampled` 表示是否抽样；抽样曲线仍保留最后一点。

**提取手法（本机踩过两次，务必照做）**：`equity_curve` 是**对象数组（`System.Object[]`）**，
不是单个对象。在 PowerShell 里对它直接取 `$eq.PSObject.Properties` 只会得到数组自身的
`Count/Length/Rank/SyncRoot/...` 元数据，**拿不到元素字段**；必须先 `$eq[0].PSObject.Properties`
看元素字段名。一次解析响应后应当**把所有需要的字段一次性抽成独立数组**再落盘，例如：

```powershell
$eq = $rep.equity_curve                 # Object[]，$eq[0] 才是第一个点
$se = foreach ($e in $eq) { [double]$e.static_equity }
$tm = foreach ($e in $eq) { [double]$e.time }
```

不要为了“取另一个字段”再读一次响应 JSON。另外本机 executor 会吞掉子进程 stderr，
`.ps1` 报错时只看到一个 `exit code 1` 而没有任何信息；捕获错误的唯一办法是
`powershell -NoProfile -ExecutionPolicy Bypass -File x.ps1 2>&1 | Out-File y.txt -Encoding utf8`，
脚本内部再套 `try { } catch { $_.Exception.Message + $_.InvocationInfo.PositionMessage }`。

### 资金曲线绘图

用户要求“资金曲线”时，交付物必须包含真实折线图，而不是资金点清单、CSV 截图或只有文字的
走势描述。一次解析终态 JSON 后，直接使用内存中的 `equity_curve` 绘制：

- 保留 `equity_curve` 的返回顺序，不按真实时间间隔分配横向宽度；横坐标使用从 0 开始的记录
  顺序号，各点等距。`time` 只用于抽样刻度和悬停提示，转换为 Asia/Shanghai（北京时间）；
  跨度较长时按成交记录所在年月分组标注，较短时显示日期或时分。重复或仅相差一秒的时间点也
  必须保持独立等距位置，避免同一根 K 线内的资金变化被挤成垂直线。
- 纵坐标是资金金额，默认范围覆盖 `static_equity` 和初始资金的最小值、最大值，并在上下各留
  约 10% 边距。用户要求同时展示动态权益时，再把 `dynamic_equity` 纳入范围。不得为了视觉
  夸张截断数据或改变数值关系。
- 默认只用红色主线绘制 `static_equity`，图例写“资金曲线（已实现权益）”。只有用户明确要求
  动态权益、浮动盈亏或两种口径对比时，才增加较淡的 `dynamic_equity` 辅助线并明确标注，不能
  把动态权益冒充 DlgBP 资金曲线。
- 绘制初始资金水平参考线，并在曲线开头加入初始资金起点（仅当报告存在可靠的初始资金字段；
  不得从首个权益点或最终净利润反推）。主线使用形状保持的平滑连续插值：经过原始资金点、相邻
  等值区间保持水平、不得超过相邻点及全局原始高低值。**禁止使用阶梯线。** 平滑方法固定为
  下一条的「控制点降采样 + 单调样条」，**不存在降级为普通连续折线的退路**；不要为了“更平滑”
  修改、移动或虚构资金点。
- **阶梯数据无法靠 `tension` 平滑，必须降采样为控制点再做单调样条插值**。`static_equity` 是
  「长平台 + 瞬时跳变」的阶梯序列，典型回测中真实变化点极少（实测 616 点中仅 21 处变化、
  22 个平台段，单段长 1–185 根，段间跳变只占 1 根 K 线）。此时：
  - `tension` 只作用于相邻两点连线。平台内相邻点等值（斜率 0），平滑后仍是直线；跳变处只有
    1 根 K 线的过渡空间，平滑被压缩到不可见。**因此不论 `tension` 取 0.2/0.4/0.5，画出来
    都还是直角台阶。**
  - `cubicInterpolationMode: 'monotone'` 是单调保形插值，**本身不产生弯曲**，且会覆盖
    `tension` 的效果。
  - **正确做法**：① 扫描曲线，把连续等值的点归为平台段，记录 `(start, end, value)`；
    ② 取每段**中点**作为控制点 `((start+end)/2, value)`，并补首尾点
    `(0, first_value)`、`(n-1, last_value)`；③ 对控制点做 Fritsch–Carlson 单调立方样条
    （保证不越过原始高低点）；④ 对 `i = 0..n-1` 逐点求值后喂给图表库，最终渲染
    `tension: 0`（插值已由控制点完成）。控制点间距大，样条才有空间产生可见弯曲。
  - 反复微调 `tension` 无效时，先停下检查参数是否适用于当前数据结构，不要继续试数值。
- 内联展示的图表（对话内直接渲染的 widget）**必须把曲线数据完全内联**在脚本内，
  不得引用同目录外部 `.js` 数据文件——相对路径加载会静默失败，导致图区空白、只剩文字框架。
- **独立 HTML 文件也必须把数据内联。** 早期版本允许 HTML 引用同目录 `equity_data.js`，
  本机实测不可靠且极易出错：数据文件当时只写了一部分（`n=991` 但 `static` 数组被截断），
  页面加载后 `EQUITY.ticks` 为 `undefined`，**横轴刻度全部空白、只剩一根红线和纵轴**。
  一律用 `[IO.File]::WriteAllText()` 把完整 `var EQUITY = {...};` 拼进 HTML，
  写完必须回读校验：文件字节数 > 15 KB、包含 `var EQUITY = {"n"`、无 U+FFFD。
- **横轴刻度必须覆盖整个时间跨度，但也不能太密。** 用 `autoSkip: false` + `maxRotation: 0`，
  并在 `ticks.callback` 里按索引查表返回 `YYYY/MM`，其余返回空串：
  `var idx = Number(this.getLabelForValue(v)); return LB_SHOW[idx] ? tickMap[idx] : '';`
  不要用 `maxTicksLimit` 配“最近邻匹配”的近似算法——索引对不齐时会整批吞掉刻度。
- **【最高优先级 · 血泪教训】`EQUITY.ticks` 里的月份标签必须带引号。**
  JSON 拼接时如果写成 `"ticks":[0,2023/01,17,2023/02,...]`，**在 JS 里 `2023/01` 是除法表达式
  （2023÷1=2023），不是字符串**，整个数组退化成数字数组。
  后果：任何 `typeof lbl !== 'string'` 或 `^\d{4}/\d{2}$` 校验会把**全部 45 个标签拒掉**，
  `LB_TOTAL` 变成 0，于是 `LB_SHOWN`/`LB_PICK` 全空 → **横轴一个刻度都没有**（叶生报过这个 bug）。
  正确写法：`"ticks":[0,"2023/01",17,"2023/02",...]`，即**每个标签都用引号包起来**。
  自检：写完后正则 `"ticks":\[([^\]]*)\]` 取出内容，确认每个偶数位都是纯数字、奇数位都是带引号字符串。
  另可在解析处加一道兜底 `lbl = String(lbl);` 再校验，防止历史上已生成的数据文件带病。
- **【必做】生成 HTML/图表后必须真机渲染验证，不能只靠读代码判断。**
  本项目连错**四轮**（全空 → 全密 → 重叠 → 又全空）都是因为「看代码觉得对」就交付。
  **本 skill 已内置脚本 `scripts/verify_render.js`，直接跑它，不要另写。**
  ```powershell
  Set-Location 'C:\Users\Mayn\.workbuddy\binaries\node\workspace'
  $env:NODE_PATH='C:\Users\Mayn\.workbuddy\binaries\node\workspace\node_modules'
  & 'C:\Users\Mayn\.workbuddy\binaries\node\versions\22.22.2-3\node.exe' `
    '<本skill>\scripts\verify_render.js' '<图表HTML>' '<截图.png>' [canvasId] `
    2>&1 | Out-File -FilePath '<结果>.txt' -Encoding utf8
  ```
  脚本内部用 Playwright 挂本机已装的 Chrome 跑 headless，直接问 Chart.js 它**实际渲染**了哪些刻度：
  ```js
  // 挂本机 Chrome，免下载 Chromium（npx playwright install chromium 极慢，实测 4 分钟未完成）
  const browser = await chromium.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe'
  });
  // 关键：遍历 scales.x.ticks，调用户 callback 拿真实文案，非空才算数
  const cb = c.options.scales.x.ticks.callback;
  for (const t of c.scales.x.ticks) {
    const txt = cb.call({ getLabelForValue: x => c.scales.x.getLabelForValue(x) }, t.value);
    if (txt !== '' && txt != null) rendered.push(txt);
  }
  // 相邻标签索引差 → 真实像素间距，取最小值即重叠判据
  const span = xRight - xLeft, realSpan = lastIdx - firstIdx;
  minGap = min(相邻索引差 / realSpan * span);
  ```
  脚本输出 `verdict`（`PASS`/`FAIL`/`WARN`）、`rendered[]`、`minGap`、`logs`、`hasYTitle`。
  判据：`renderedCount > 0` 且 `minGap` **大于 40px**（小于则视觉上会碰）。
  `logs` 含页面 `console.log` 与 `PAGEERROR`，截图用于存档复核。
  实测通过：`months=45 chartW=1144 shown=16 minGap=47.4 verdict=PASS`。
  首次使用需 `npm i playwright`（**仅装库，不下载浏览器**），详见 SKILL.md「图表真机渲染验证」。
- **横轴密度必须「按容量算」，不能「按日历拍」。**（叶生纠正过三次：先全空、再全密、再重叠）
  正确顺序是三步：**① 先统计总月数 → ② 算能放下几个标签 → ③ 在这个数量上均匀取**。
  **禁止**写死「每 3 个月一个」（`月份 % 3 === 0`）这类按日历抽的做法——跨度一变密度就不合适，
  而且遇到短期跨度会抽出 3 个刻度、遇到长期跨度抽出一堆重叠。
  ```js
  // ① 统计跨度内总月数
  var LB_IDX = [], LB_LAB = [];
  for (i=0;i<EQUITY.ticks.length;i+=2){
    var lbi = EQUITY.ticks[i], lbl = String(EQUITY.ticks[i+1]);
    if (!/^\d{4}\/\d{2}$/.test(lbl)) continue;
    LB_IDX.push(lbi); LB_LAB.push(lbl);
  }
  var LB_TOTAL = LB_IDX.length;                       // 本例 = 45 个月
  // ② 能放下几个「YYYY/MM」标签（11px 字体含间隙实测每个约 58px）；容器宽度必须能取到
  var PK_W = 58;
  function measureW(){
    var el = document.querySelector('.wrap') || document.querySelector('canvas');
    var w = el ? el.clientWidth : 0;
    if (!w) { w = window.innerWidth || 900; }         // 布局未完成时的兜底
    return Math.max(320, w - 70);                     // 减去 y 轴宽度
  }
  var CH_W = measureW();
  var LB_SHOWN = Math.max(2, Math.floor(CH_W / PK_W * 0.85));
  if (LB_SHOWN > LB_TOTAL) LB_SHOWN = LB_TOTAL;
  // ③ 均匀取 LB_SHOWN 个。必须用 floor(x+0.5)，不能用 round()：
  //    round() 永远取不到最后一个索引，会再补一个 → 首尾标签重复重叠（踩过）。
  var LB_PICK = [];
  for (i=0;i<LB_SHOWN;i++){
    var pi = Math.floor(i * (LB_TOTAL - 1) / (LB_SHOWN - 1) + 0.5);
    if (pi > LB_TOTAL - 1) pi = LB_TOTAL - 1;
    if (LB_PICK.indexOf(pi) < 0) LB_PICK.push(pi);
  }
  for (i=0;i<LB_PICK.length;i++){ LB_SHOW[LB_IDX[LB_PICK[i]]] = true; }
  ```
  **另外三个必须配齐的点**：
  ① **容器宽度不能早读**。图表创建前 `.wrap.clientWidth` 常为 0，会让 `LB_SHOWN` 塌成 2。
     把抽取逻辑封成 `computePicks()`，在 `onResize`、`requestAnimationFrame`、
     `window.resize` 三处都调一次并 `chart.update('none')`。
  ② **y 轴标题和刻度会重叠**：`y.title.display: true` 配 6 位数刻度（如 `1,020,911`）时标题会压住刻度。
     直接 `y.title: { display: false }`，单位写进 `sub` 副标题或横轴标题里。
     同时给 `y.ticks.padding: 8`。
  ③ 刻度标签字号用 11px（10px 偏小、12px 易挤），`x.ticks.padding: 8`。
  调试时在 `console.log` 打印 `months / chartW / shown / ~stepMonths / labels` 五个值核对。
- **横轴范围用数据自身长度对齐**：`offset: true` 且 `labels` 为 `0..n-1`，
  这样首尾点贴边、每月刻度都落在真实位置上。
- **推荐做法（2026-09-22 实测通过，兼具「零手抄」与「零乱码」）**：① 用 Write 工具直接把 HTML 写到目标路径，
  正文里留两个占位符，例如 `var RAW = [__RAW_DATA__];`、`var TICKS = [__TICKS_DATA__];`，库位置留 `//__CHARTJS_LIB__`；
  ② 用 PowerShell `[IO.File]::ReadAllText($html, UTF8)` 读入，配合 `.Replace()` 做**字面替换**
  （`String.Replace` 不是正则，不必转义 `$`），再用 `[IO.File]::WriteAllText($html, $h, UTF8-noBOM)` 写回。
  这样 714 个资金点不必手工誊抄（誊抄必错），中文也从不经过 PS 字符串字面量，不会出现 `璧勯噾`。
  ③ Chart.js 也可用同一手法内联（`Invoke-WebRequest` 下载 `chart.umd.js` 到临时目录 → 替换 `//__CHARTJS_LIB__`），
  成品 HTML 约 220 KB 且**完全不依赖外网**，离线双击即可打开。
  ④ 替换后**必须回读校验**：元素个数、首尾值、`__*__` 占位符残留数、U+FFFD 数。
  ⚠️ 校验正则要容忍空格：源码写的是 `var RAW = [`，若用 `var RAW=\[` 去匹配会**全部匹配不到**、
  统计出 `1` 个元素而误判失败（与「数据为空时判据退化成假通过」同源）。
- 生成独立 HTML 的脚本若含中文，`.ps1` 必须存成 **UTF-8 with BOM**：
  PowerShell 5.1 读无 BOM 脚本按 ANSI 解析，here-string 里的中文会整体变成乱码
  （`资金` → `璧勯噾`），并且乱码里的单引号会截断 JS 字符串。更稳的做法是在脚本里
  用码点拼装中文（`[char]0x8D44 + [char]0x91D1`），或先写占位符、再用码点替换。
  写完必须回读确认无 `[\uFFFD]` 且 `<h1>` 等标签完好。
- 资金曲线不绘制数据点标记：关闭 `marker`、圆点、方点、节点描边和逐点数值标签，只保留连续
  线条。交互式图表可以保留不可见的悬停命中区域和 tooltip，但静止画面不得出现点阵。
- 标题、图例、网格和坐标含义必须清楚。横轴标题使用“资金记录顺序（刻度为北京时间）”，不要
  标成连续时间轴。
- 使用返回的全部曲线点；若 `equity_curve_meta.sampled == true`，在图注中写明源记录数、返回点数
  和步长。少于两个有效点时不伪造折线，明确说明数据不足。
- 生成确定性的本地图表（PNG、SVG 或可打开的 HTML），保存到用户指定路径；用户未指定时放到
  本 Skill 的 `usr\work-reports\`，使用不会覆盖旧文件的唯一名称，**并同时另存一份到工作区
  `<工作区>\reports\`**（平台迁移会重建 Skill 根目录并清掉 `usr\`，见 SKILL.md）。最终答复给
  用户的是工作区那一份，并按下面「交付形式」给可点击的锚文本链接。不得调用 AI 生图，也不得用
  Mermaid/流程图代替数据图。
- **交付形式固定为「正文里的 md 锚文本链接」，不是文件卡片。** 步骤：① 调 `present_files`；
  ② 从它的返回值里取 `previewed` 字段 —— 那就是客户端给预览用的 http 地址
  `http://127.0.0.1:<port>/static-html/<hash>/<url编码文件名>`（实测 `HEAD` 返回 200、
  `Content-Type: text/html`），只有这种 http 地址才会被聊天窗口渲染成可点链接；
  ③ 正文两行交付：**第一行用普通文本**写 `<品种><合约>资金曲线已生成。`（完整名称必须出现在
  普通文本里，理由见下）；**第二行**给 `[白糖指数资金曲线](<previewed url>)`，独占一个段落。
  本地路径默认不列，仅用户追问离线副本时再给。
  硬约束：锚文本 = `<品种><合约>资金曲线`，**一律写全**。品种用中文名（与用户原话一致，
  如 `白糖` / `铸造铝合金`），合约用盘立方口径的合约标识（`指数` / `主连` / 具体月份如 `2501`），
  末尾固定拼 `资金曲线`。例：`白糖指数资金曲线`、`铸造铝合金指数资金曲线`、`螺纹钢主连资金曲线`。
  **不对锚文本做任何长度判断、截短、缩写或改写**：不许删品种名、不许把品种换成行业简称
  （`铸造铝合金` → `铝合金` 这类），**也不许在规则或交付文本里出现“字数／几个字／长度上限”这类口径**。
  锚文本多长只由品种名与合约名决定，不由任何规则约束。叶生 2026-09-23 连续两次否掉这套说法：
  「肯定不能这样啊，为什么要限制字数？就是 品种+合约+资金曲线」、
  「8 个字 为什么还是 8 个字啊，不是说不限制字数了吗？」。
  **锚文本里只放名称，不塞周期、策略名、回测区间**（三者写进图内标题与副标题）。
  **链接卡片宽度有限，锚文本会被卡片裁切显示**（2026-09-23 实测 `[白糖指数资金曲线]` 渲染出来
  只显示到 `白糖`，叶生回「没给对」）。⇒ 所以完整名称必须**再用普通文本写一遍**
  （普通文本正常折行，不受卡片宽度限制）；锚文本一律写全，卡内被裁属渲染行为、与内容无关，
  **不要据此改动锚文本**。
  交付格式固定两行：`<品种><合约>资金曲线已生成。` + 独占一段的锚文本链接。
  **不得只给文件名、裸路径或裸地址**；
  `file:///` 与裸路径在该聊天窗口不渲染为链接，只会原样显示成文本；**不得用文件卡片替代链接**
  （用户会判定"这不还是文件"），**也不要为了"能点"自己起 `python -m http.server`**（用户明确不要服务）。
  该地址绑在当前客户端进程上（端口与 hash 会变），关掉客户端即失效；**交付正文不写这条提醒**
  （SKILL.md「交付正文只写两行」），只在用户追问地址长期有效性时再说明，或改给工作区那份本地路径。
  在 PowerShell 里拼含中文的 URL 时用 `[Uri]::EscapeDataString($fileName)` 现场拼，
  **不要直接粘 `%XX` 字面量**（沙箱会误判成 cmd 的 `%VAR%` 语法并拦掉整条命令）。
- 图表之外可以附简短曲线解读，但文字说明和逐点数据都不能代替图表本身。

一次 `ConvertFrom-Json` 后从同一内存对象提取曲线及其他指标，不得为分析曲线再次读取响应
JSON。`headless_report_available == false` 时记录 `headless_report_error.code/message`，不得从
成交对、净利润或首尾资金反推并冒充 GUI 口径资金曲线。

用户明确要求资金曲线数据或 CSV 时，在删除本轮临时响应前执行：

```powershell
$ExportArgs = @(
    'report-export',
    '--input', $RunResultJson,
    '--output', $EquityCsv,
    '--section', 'equity'
)
& $Cli @ExportArgs
```

约束如下：

- `$RunResultJson` 必须是仍然存在的完整 `run` 终态 JSON，扩展名为 `.json`，大小小于 64 MiB；
  其中必须存在 `data.response.data.backtest.report`。
- `$EquityCsv` 使用全新、可写且尚不存在的 `.csv` 路径。导出器使用 `CREATE_NEW`，不会覆盖旧文件。
- `--section equity` 只对 CSV 生效；CSV 还支持 `summary` 和 `trades`。`.html` 输出完整报告，
  `.json` 输出输入 JSON。
- `report-export` 是纯本地后处理，不连接 EJClient，禁止传 `--root`、`--pid`。
- **禁止同时传 `--output` 和 `--out`。** 当前实现让两者共用输出路径状态；`--output` 是正式
  产物路径，再传 `--out` 会触发重复参数错误。此子命令也没有单独的响应 JSON 路径。
- 本机标准输出可能被执行器吞掉。标准输出为空不代表未实现；调用后以 `$EquityCsv` 已创建、
  文件非空、UTF-8 CSV 表头为
  `time,bar_id,static_equity,dynamic_equity,available,total_return,cost,long_margin,short_margin`
  且至少有一行数据作为成功判定。
- 没有生成文件时先检查是否误传 `--out`、输入 JSON 是否仍存在、目标路径是否已存在以及
  `equity_curve` 是否存在；不得在未检查这些条件时声称本机 CLI 没有实现 `report-export`。

导出成功后再删除临时响应 JSON；正式 CSV 是用户要求的数据附件，不属于中间文件，但不能替代
上面的资金曲线图。用户没有要求 CSV 时不调用 `report-export`，直接使用内存中的曲线绘图和分析。

### 多轮顺序回测的读取状态机

每轮严格按以下顺序执行，完成一步后不回退：

```text
提交一组参数 → 等待终态 → 读取本轮 JSON 一次 → 提取紧凑轮次记录
→ 删除本轮 JSON → 与已有轮次记录比较 → 决定停止或提交下一组
```

紧凑轮次记录至少包含：轮次、实际参数、净利润、最大回撤、交易次数、胜率、盈亏比、
权益曲线评价。它保存在当前任务上下文中，供最终比较使用；不得通过反复读取原始响应来重建。

- 不创建 `_rr.txt`、`summary-current.txt` 等会被下一轮覆盖的摘要文件作为历史轮次来源。
- 不得把同一个响应分别以“解析报告”“提取关键指标”“提取统计指标”等名义读取多次；一次
  `ConvertFrom-Json` 后从同一内存对象提取全部所需字段。
- 不得用当前轮摘要冒充第一轮或其他历史轮。第 N 轮的参数和指标必须来自第 N 次实际回测的
  内存记录。
- 用户要求“基准轮 + N 轮调参”时，总运行数应为 `N + 1`；不能把基准轮计入调参轮数。
- 已有 `job_id` 时只执行等待，不再次提交；同一参数对象完成后不重复运行。
- 相同命令在没有新输入或外部状态变化时不得连续调用；相同错误出现两次即停止自动重试。
- 标准输出为空时只读取本次 `--out` JSON，不重新执行命令。

## 通用响应

```text
schema
success
exit_code
stage
duration_ms
error.code
error.message
data
```

只使用 JSON 的 `success`、`exit_code` 和对应结构化字段判断调用结果。

## 账号权限拒绝

当前账号需要独立的 `plf_gn_cli` 功能授权才能调用业务 IPC。`status` 是诊断豁免请求，
其成功及 `doctor` 的文件/能力就绪结果都不能证明权限已开通。无需为此增加单独预检。

解析 JSON 时优先检查 `error.code == "PERMISSION_DENIED"`，服务端返回 `retryable=false`。
下表描述权限拒绝时的 CLI JSON `exit_code`，不用于替代错误码判断：

| 路径 | exit_code |
| --- | --- |
| `compile` 运行时注册 | 32 |
| `history`、`run` 提交阶段、`history-submit`、`backtest-submit` | 32 |
| 通用 `job-status` / `job-wait` / `job-cancel` / `job-delete` | 32 |
| `executor-*` | 32 |
| `run` 内部等待阶段的 `job.status` | 34 |

权限拒绝时立即停止业务调用；不能修公式、调参数、换安装目录、换 PID、反复发请求或请求重启来规避。
生成公式后运行时注册被拒时，对用户只回复“<用户所需策略名称>公式已写好，但运行时注册被拒：当前账号没有 CLI 使用权限，请开通权限后重新登录盘立方。”不附加本地编译或磁盘注册状态、文件路径、公式身份、策略细节、旧文件状态、后续编译注册预告。其他调用被拒时只提示“当前账号没有 CLI 使用权限，请开通权限后重新登录盘立方。”下面的产物与任务状态说明只用于内部判断。恢复授权、刷新账号权限且用户要求继续后，
有已知任务或操作回执 ID 时先核对已有状态，避免重复提交。

`compile` 在本地编译和磁盘注册后才请求运行时注册。因此权限拒绝时可能已有
`disk_registered=true`、`runtime_registered=false`；保留工作源码和已有产物，不宣称已加载，
也不要为了“清理失败”自行删除安装目录产物或生成 `_2` 等新公式。

`run` 内部等待被拒时，现有 CLI 会自行尝试一次 `job.cancel`；若授权仍未恢复，它也会被拒。
这不代表已受理任务已停止，Agent 不追加取消/删除重试，也不提交第二个回测。
若报告已返回、随后清理被拒，保留真实报告，并停止自动补删及下一轮回测。

`contract-catalog.ps1` 在刷新 `instrument-list` 时以 `code=PERMISSION_DENIED`、
`retryable=false` 保留该错误；不能将它误判为“没有该标的”或自行换合约。

## 编译失败字段

```text
error.code == "COMPILE_FAILED"
data.editor_result.ok == false
data.editor_result.errors[].phase
data.editor_result.errors[].row
data.editor_result.errors[].col
data.editor_result.errors[].msg
data.editor_result.cl_out
```

CLI 退出码 20 表示公式生成、解析、编译或链接失败。Agent 必须使用结构化 `errors[]` 修复工作源码并继续，而不是只把 `cl_out` 原样交给用户。

## 编译成功字段

```text
data.source_encoding
data.editor_source_encoding
data.source_staged
data.template_metadata_filled
data.editor_exit_code
data.install_root
data.editor_result.ok
data.editor_result.stage
data.editor_result.name
data.requested_name
data.requested_display_name
data.name
data.display_name
data.name_auto_renamed
data.replace_existing
data.editor_result.sha256
data.strategy_registered
data.disk_registered
data.runtime_registered
data.strategy_source
data.editor_restart_required
```

成功注册必须同时满足退出码 0、`strategy_registered=true`、
`disk_registered=true`、`runtime_registered=true`、
`editor_restart_required=false`，并取得 64 位 DLL SHA256。磁盘注册成功但运行时注册失败时，
CLI 必须返回非零退出码；Agent 应报告环境/刷新错误，不能把它误报为完整成功。

`--name` 是不含括号的 ASCII 内部简称；`--display-name` 是界面名称，默认采用
`中文名称(英文简称)`。接口同时接受英文半角括号 `()` 和中文全角括号 `（）`。

默认编译会检查 `sysfml.dat`、`fmlGroup.xml`、发布源码和 DLL。请求简称已存在时，
CLI 自动选择 `_2`、`_3` 等第一个可用后缀，并同步改写显示名称中的英文简称。
Agent 必须以响应中的 `data.name`、`data.display_name` 为最终身份；
`data.name_auto_renamed == true` 是正常成功路径。只有用户明确要求修改旧公式时才传
`--replace-existing`，该模式保留原简称及原分组。

## 已实测的踩坑与规避（PowerShell 5.1 + 本机 CLI 0.14.0）

1. **执行器脚本必须保持纯 ASCII。** PowerShell 5.1 读取**不带 BOM** 的 `.ps1` 时按系统
   ANSI 代码页解析（本机 `[Text.Encoding]::Default` 为 `gb2312`），脚本里的中文串会被解成
   乱码并原样传给 CLI，CLI 随即返回退出码 10、`error.code == "INVALID_ARGUMENT"`、
   `message == "Invalid formula name, display name or editor (ejia/mylang)."`。
   —— 这个报错**不代表公式名或显示名格式有问题**，先核对“传给进程的字符串”再动公式。
   本机实测的两种可靠做法：
   - 把中文显示名放在独立的 UTF-8 文本文件里，用
     `[IO.File]::ReadAllText($path, [Text.Encoding]::UTF8).Trim()` 读出；
   - 或在纯 ASCII 脚本里用码点拼装，例如
     `$cn = [string]([char]0x5E03) + [char]0x6797 + [char]0x5E26 + [char]0x7B56 + [char]0x7565`
     （即“布林带策略”），再 `$cn + '(BollingerBand)'`。
   自检方式：读字节确认脚本无 >127 的字节，或输出该字符串的码点（应当是 `5E03 6797 ...`）。
2. **`--opt=value` 等号形式不被支持**：`--display-name=xxx` 会直接得到退出码 10；必须把
   `--display-name` 与值作为参数数组里两个独立元素传递。
3. **不要用 `$Pid`、`$Args`、`$Input` 等 PowerShell 只读自动变量**：赋值会抛出
   “无法覆盖变量 PID，因为该变量为只读变量或常量”，探测脚本会整体中断。客户端 PID 一律叫
   `$ClientPid`。
4. **纯 ASCII + 已有中文名的情况下，`--pid` 不是必须的**：`status` 返回唯一
   `data.selected_pid` 时，不带 `--pid` 的 `compile` 同样成功，且响应里回填了同一个
   `data.selected_pid`，可据此确认客户端身份。带 `--pid` 的调用在本机也验证通过。
5. **`data.template_metadata_filled` 可以为 `false`**：它表示 CLI 无需替源码补填头部占位符
   （源码头部已手写完整），与注册成功无关，不得据此判定失败。
6. **不要把整份响应原样落盘后按行读取。** 响应 JSON 是**单行超长文本**（`compile` 成功响应
   约 3 KB 以上），按行读取的工具会在 2000 字符处截断，`data.strategy_source` 等排在末尾的
   字段直接看不到，容易被误判成“无法核验”。正确做法：`ConvertFrom-Json` 后只把需要的字段
   抽成几行简短文本再读，例如
   `$j.data.strategy_source.Length`、`$j.data.editor_result.sha256.Length`。
7. **`--out` 必须是每轮全新的路径，且必须确认上一轮的 JSON 已真的删除。** 清理静默失效时，
   残留的旧 JSON 会被下一轮当成当前结果读取（`success`、`exit_code` 往往长得一样，很难发现）；
   每轮调用前先确认目标路径不存在，收尾按上一条复验剩余为 0。调用协议本身的失败判定顺序是：
   先看 `--out` JSON 是否存在并可解析，再看 `success`、`exit_code` 和结构化字段；标准输出为空、
   执行器不显示输出、`$LASTEXITCODE` 异常都不构成失败证据。
8. **`--root` 必须等于用户安装盘立方的那个目录，且填安装目录本身而不是它的
   `Skills\` 子目录。** 本机实测：`--root D:\Release` 时 `status`/`compile` 都正常，响应回填
   `data.install_root == "D:\Release"`；`--root D:\BaiduSyncdisk\MFC\pcclient\Release`
   （另一个确实存在的安装目录）或 `--root D:\NoSuchDir` 都返回退出码 70 +
   `SERVER_IDENTITY_FAILED`。该报错与公式源码无关，先核对安装目录再动公式；
   首次加载必须先告知用户默认路径并询问是否修改（见
   [首次加载确认安装目录](root-config.md)），不允许自行探测运行中的进程、枚举磁盘或用
   反复试错的方式猜目录。
9. **`--root` 正确但该目录的 EJClient 没在运行**，也会返回 `SERVER_IDENTITY_FAILED`。
   先请用户启动客户端；若该目录里没有盘立方（比如还没装），那是“未安装”而不是
   “身份错误”，按 [首次加载确认安装目录](root-config.md) 第 3.1 步**给出官方下载地址**
   （不只是问路径），不要反复改 `--root` 试错，也不要自行去找盘立方装在哪。
10. **执行器不回显标准输出时，把结果落盘再读，不要指望命令回显。** 调用
    `scripts\contract-catalog.ps1 -Action Resolve -Query <中文名> -OutFile <全新临时 JSON>`，
    从 `OutFile` 读取结构化结果后立即删除；不得用管道捕获脚本输出，也不得绕过脚本自行解析缓存。
    **回显为空不是失败证据**，判定只看落盘 JSON 与文件内容。
    同理，需要看 `status`/`doctor`/`run` 的字段时，一律从各自的 `--out` JSON 里
    用 `ConvertFrom-Json` 抽字段后写成短文本再读。
