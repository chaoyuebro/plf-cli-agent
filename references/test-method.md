# 纯 CLI 生成—报错—修复—再生成测试

目标是验证同一个公式名和同一个工作源码经历：

```text
生成错误源码 → 编译失败 → 结构化错误回报 → 修改源码 → 再编译 → 注册成功
```

不调用 PowerShell 测试脚本，不调用任何策略运行或行情命令。

## 1. 派生路径

```powershell
# SKILL.md has already loaded Skill\paths.ps1.
# $Root, $Cli, $SkillRoot, $RootArgs and $WorkDir must not be redefined here.
# First-run root setup must already be finished: $RootReady must be true.
$Name = 'AgentCompileLoop_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$ChineseName = [string]([char]0x516C) + [char]0x5F0F + [char]0x7F16 +
    [char]0x8BD1 + [char]0x95ED + [char]0x73AF + [char]0x6F14 + [char]0x793A
$DisplayName = $ChineseName + '(' + $Name + ')'
$Source = "$WorkDir\$Name.fml"

function Invoke-PlfToFile {
    param(
        [string[]]$CliArguments,
        [string]$JsonPath
    )
    try {
        & $Cli @CliArguments
        if (-not (Test-Path -LiteralPath $JsonPath)) {
            throw "plf-cli did not create --out JSON: $JsonPath"
        }
    } catch {
        if ([IO.File]::Exists($JsonPath)) {
            [IO.File]::Delete($JsonPath)
        }
        throw
    }
}
```

Agent 可创建 `$WorkDir`，但不得扫描其内容。派生的 CLI 或 Skill 路径不存在时停止。

## 2. 连接与编译门禁

为每次调用创建不同的 JSON 路径并直接调用：

```powershell
$VersionOut = Join-Path $env:TEMP ("plf-version-" + [guid]::NewGuid().ToString('N') + '.json')
$StatusOut = Join-Path $env:TEMP ("plf-status-" + [guid]::NewGuid().ToString('N') + '.json')
$DoctorOut = Join-Path $env:TEMP ("plf-doctor-" + [guid]::NewGuid().ToString('N') + '.json')
Invoke-PlfToFile -CliArguments (@('version') + $RootArgs + @('--out', $VersionOut)) -JsonPath $VersionOut
Invoke-PlfToFile -CliArguments (@('status') + $RootArgs + @('--out', $StatusOut)) -JsonPath $StatusOut
Invoke-PlfToFile -CliArguments (@('doctor') + $RootArgs + @('--out', $DoctorOut)) -JsonPath $DoctorOut
try {
    $VersionResult = Get-Content -Raw -Encoding UTF8 $VersionOut | ConvertFrom-Json
    $StatusResult = Get-Content -Raw -Encoding UTF8 $StatusOut | ConvertFrom-Json
    $DoctorResult = Get-Content -Raw -Encoding UTF8 $DoctorOut | ConvertFrom-Json
} finally {
    foreach ($Path in @($VersionOut, $StatusOut, $DoctorOut)) {
        if ([IO.File]::Exists($Path)) {
            [IO.File]::Delete($Path)
        }
    }
}
```

标准输出为空时仍继续读取 JSON，不读取 `$LASTEXITCODE`，不改用 Bash。取得
`$ClientPid = $StatusResult.data.selected_pid`，只要求：

```text
管道连接成功
StatusResult.data.install_root == $Root
selected_pid == status.server_pid
doctor.data.ready_for_compile == true
```

`doctor` 因其他能力返回 11 或 31，不得阻止本测试；始终解析其 JSON 中独立的 `ready_for_compile`。

## 3. 第一轮：生成可确定失败的源码

把 Skill 的 `assets/invalid-formula.md` 内容写入 `$Source`，保存为 UTF-8，然后执行：

```powershell
$Out1 = Join-Path $env:TEMP ("plf-compile-1-" + [guid]::NewGuid().ToString('N') + '.json')
$Arguments1 = @(
  'compile', '--source', $Source, '--name', $Name,
  '--display-name', $DisplayName,
  '--source-encoding', 'utf8', '--editor', 'ejia',
  '--pid', [string]$ClientPid
) + $RootArgs + @('--out', $Out1)

Invoke-PlfToFile -CliArguments $Arguments1 -JsonPath $Out1
try {
    $Result1 = Get-Content -Raw -Encoding UTF8 $Out1 | ConvertFrom-Json
} finally {
    if ([IO.File]::Exists($Out1)) {
        [IO.File]::Delete($Out1)
    }
}
```

必须验证：

```text
$Result1.exit_code == 20
$Result1.success == false
$Result1.error.code == "COMPILE_FAILED"
$Result1.data.editor_result.errors 至少一项
$Result1.data.strategy_registered 不为 true
```

Agent 在 commentary 中输出首批 `phase/row/col/msg`，然后继续当前任务，不能在这里结束。

## 4. 第二轮：修改同一源码并再次编译

使用 Skill 的 `assets/agent-demo.md` 内容替换同一个 `$Source`，并在写入前完成：

```text
FORMULA_SHORT_NAME → $Name（ASCII 英文简称）
FORMULA_DISPLAY_NAME → $DisplayName，即中文名称(英文简称)
```

例如 `$Name=AgentCompileLoop_20260911_150000` 时，`$DisplayName` 为
`公式编译闭环演示(AgentCompileLoop_20260911_150000)`。保持两者不变，创建新的输出路径：

```powershell
$Out2 = Join-Path $env:TEMP ("plf-compile-2-" + [guid]::NewGuid().ToString('N') + '.json')
$Arguments2 = @(
  'compile', '--source', $Source, '--name', $Name,
  '--display-name', $DisplayName,
  '--source-encoding', 'utf8', '--editor', 'ejia',
  '--pid', [string]$ClientPid
) + $RootArgs + @('--out', $Out2)

Invoke-PlfToFile -CliArguments $Arguments2 -JsonPath $Out2
try {
    $Result2 = Get-Content -Raw -Encoding UTF8 $Out2 | ConvertFrom-Json
} finally {
    if ([IO.File]::Exists($Out2)) {
        [IO.File]::Delete($Out2)
    }
}
```

必须验证：

```text
$Result2.exit_code == 0
$Result2.success == true
$Result2.data.editor_result.ok == true
$Result2.data.editor_result.stage == "finalize"
$Result2.data.requested_name == $Name
$Result2.data.editor_result.name == $Result2.data.name
$Result2.data.display_name 为最终显示名称
$Result2.data.name_auto_renamed 为布尔值
$Result2.data.editor_result.sha256 匹配 ^[0-9a-fA-F]{64}$
$Result2.data.install_root == $Root
$Result2.data.strategy_registered == true
$Result2.data.disk_registered == true
$Result2.data.runtime_registered == true
$Result2.data.editor_restart_required == false
$Result2.data.strategy_source 非空
```

还必须读取发布源码并确认 `// 简称:` 与 `// 名称:` 均已填写，且简称等于
`$Result2.data.name`，名称等于 `$Result2.data.display_name`，不含 `FORMULA_SHORT_NAME`、`FORMULA_DISPLAY_NAME`、
`FORMULA_CHINESE_NAME` 或 `%s`。

## 5. 最终回复

全部核验仍须在内部执行，但成功后的最终回复只简洁确认公式已经生成、编译并热加载到
当前 EJClient，无需重启客户端。不要输出题为“编译结果核验（全部通过）”的章节，
不要逐项打印核验字段，也不要列出工作源码、发布源码、DLL、SHA256 等交付物明细。

只有失败且无法继续时，才返回用户采取下一步所必需的错误摘要。

不得报告行情、盈亏、交易记录或其他运行结果，因为本测试只验证公式生成和编译反馈循环。
