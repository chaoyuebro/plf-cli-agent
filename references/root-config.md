# 首次加载：自动发现盘立方安装目录

## 目录与授权口径

用户已授权首次加载时搜索电脑。没有用户明确给出的目录、也没有本副本有效配置时，先自动发现；
找到后按下方两句模板显示当前目录和直接输入新目录的修改方式；未找到则说明未找到并请用户手动输入，不先询问是否接受默认路径。

盘立方目录以实际存在的 `EJClient.exe` 为证据。使用 CLI 还要求该目录或其 `Debug/Release`
子目录有 `plf-cli.exe`；不能只因存在一个 CLI、Skill 或历史示例就认定安装位置。
目录发现只读取进程路径、安装注册项、目录名和程序存在性，不读取策略、账号或用户文档，
不启动程序、不下载安装包、不修改客户文件。

## 1. 判断是否需要发现

先读取并点调用 `paths.ps1`。用户在当前请求里给出目录时直接验证该目录；
`$RootReady == true` 且客户端程序仍存在时复用本副本配置，不每轮扫描电脑。
没有有效配置，或保存位置已经失效且用户没有给新目录时，执行第2步。
`$FallbackRoot` 只是发现候选之一，默认位置为空不等于整台电脑没安装。

`usr/root.local.json` 是本副本私有正式状态，由 `plf-root.ps1 -Action set` 写入；
不得手改、跨副本覆盖或从其他副本搬运。`usr/_user_meta.json` 不得读取或修改。
`confirmed: true` 表示用户输入或本流程自动发现并校验后可使用的目录，不再限定必须人工确认。
`resolved_from` 自动发现使用 `auto-discovered`，用户直接提供或选择使用 `user`；旧值继续兼容。

## 2. 执行只读发现

```powershell
$RootDiscoverOut = Join-Path $env:TEMP ('plf-root-discover-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $SkillRoot 'scripts\plf-root.ps1') -Action discover -OutFile $RootDiscoverOut
  $RootDiscovery = Get-Content -Raw -Encoding UTF8 $RootDiscoverOut | ConvertFrom-Json
} finally {
  if ([IO.File]::Exists($RootDiscoverOut)) { [IO.File]::Delete($RootDiscoverOut) }
}
```

发现顺序：运行中的 EJClient 路径 → 常见安装位置及注册表安装记录 → 未找到时搜索本地固定磁盘。
磁盘搜索跳过无法访问的目录、系统保护目录和重解析点，不遍历网络或可移动磁盘，默认最多120秒。
脚本的 `SearchRoots` 参数仅用于明确限定范围及隔离测试；正常首次加载不传，避免只搜默认位置。

读取结果：

| 字段 | 含义 |
| --- | --- |
| `found` / `candidates` | 是否发现客户端目录，以及实际找到的全部候选 |
| `candidates[].root/cli` | 安装目录、可解析的CLI；cli为空表示该安装缺少CLI |
| `candidates[].running/source` | 当前是否运行、发现来源 |
| `selected_root` | 唯一可用目录，或多份可用中唯一正在运行的目录 |
| `requires_selection` | 多份可用且无法唯一选定，需要用户选择 |
| `timed_out` / `unreadable_directory_count` | 搜索范围可能不完整，不代表没有安装 |

### 找到目录

目录确认成功（首次加载、用户修改目录、或连接检查成功）后，正文只显示以下两句：

> 当前盘立方安装目录：`<实际目录>`。
>
> 如需更改安装目录，请直接在对话框输入新的目录。

不加“盘立方已连上”标题，不展示“已保存，以后直接复用”、进程/PID、QDC连接情况、
回测引擎就绪情况或各功能均可用清单。目录、身份和能力检查仍内部执行；
仅当用户明确要求诊断详情时才按需展示。普通成功确认不使用选项弹窗重复询问是否接受目录。
用户直接在对话框输入新目录后，按第3步校验并保存，再使用相同两句模板确认。

- `selected_root` 非空：直接按第3步保存并验证，不再问“要不要用这个目录”。
- 多份可用且无法唯一确定：列出实际找到的目录，请用户选择；不根据历史示例或 Skill 位置猜。
- 找到客户端但缺少 CLI：仍打印找到的目录，说明该版本缺少 CLI，请更新盘立方；不说未找到，
  不保存不可用目录继续业务调用。

### 未找到目录

> 未找到盘立方安装目录，请手动输入安装目录。

等待用户输入即可，不宣称“电脑没安装”，不反复启动全盘扫描。用户提供目录后直接校验，
无需二次确认。仅在用户明确说还没安装时提供[盘立方官网](https://www.ejia7.net)。

## 3. 保存并重新加载

将 `selected_root` 或用户给出的有效目录放入 `$SelectedRoot`。自动发现时使用
`$RootResolution = 'auto-discovered'`，用户输入或选择时使用 `'user'`。

```powershell
$RootSetOut = Join-Path $env:TEMP ('plf-root-set-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $SkillRoot 'scripts\plf-root.ps1') -Action set `
    -RootPath $SelectedRoot -ResolvedFrom $RootResolution -OutFile $RootSetOut
  $RootSet = Get-Content -Raw -Encoding UTF8 $RootSetOut | ConvertFrom-Json
} finally {
  if ([IO.File]::Exists($RootSetOut)) { [IO.File]::Delete($RootSetOut) }
}
```

`ok == true` 后重新点调用 `paths.ps1`，确认 `$Root` 与选定目录一致、`$RootReady == true`，
后续每次 CLI 调用固定携带 `$RootArgs`。`ROOT_MISSING/ROOT_INVALID` 时报告该目录的校验结果，
请用户重新输入，不擅自改成另一个候选或重新扫描。

## 4. 核对运行中的客户端

找到目录不等于已启动客户端。业务前使用 `status` 或既有 `plf-root.ps1 -Action verify`
核对 `data.install_root` 与 `$Root`，固定使用同一 `$ClientPid`。
目录正确但程序未启动时只请用户启动该目录的盘立方，不更换路径试错。

```powershell
$RootVerifyOut = Join-Path $env:TEMP ('plf-root-verify-' + [guid]::NewGuid().ToString('N') + '.json')
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File `
    (Join-Path $SkillRoot 'scripts\plf-root.ps1') -Action verify -OutFile $RootVerifyOut
  $RootVerify = Get-Content -Raw -Encoding UTF8 $RootVerifyOut | ConvertFrom-Json
} finally {
  if ([IO.File]::Exists($RootVerifyOut)) { [IO.File]::Delete($RootVerifyOut) }
}
```

`identity_ok == true` 才能把响应视为该安装目录的客户端。接口不可达、身份不符或缺少组件时
按对应错误处理，不因权限不足去搜索其他客户端。

## 权限不足时的固定提示

> 当前账号没有盘立方智策权限，请前往[盘立方会员](https://www.ejia7.net/ngpip/web/client-web/member/pc/index.html#/package)或联系你的客服获取权限。

使用可点击的超链接，不只打印裸网址。立即停止业务调用，不换目录、PID或其他接口绕过；
公式已写好但注册被拒时，只在这句话前加真实的“公式已写好，但运行时注册被拒”状态。
授权恢复且用户要求继续后，再刷新状态并继续。
