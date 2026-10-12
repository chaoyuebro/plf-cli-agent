# 后台策略执行器（executor v1）

本页只用于用户明确要求在 EJClient 中添加、启动、查询、停止或移除后台策略计算时。
它不是 `plf-cli run` 回测；不要自动提交回测、优化参数或开启交易。

## 先确认双端能力

按 SKILL.md 的安装目录、`--root`、`--pid` 和全新 `--out` 规则先定位同一 EJClient。
只读调用 `plf-cli version`、`plf-cli help` 和 `plf-cli status`，分别核验：

1. CLI 的 `help.data.implemented` 包含 `executor-v1`（或 `usage` 明确列出所需 `executor-*` 命令），且 `version.data.executor_implemented == true`、`executor_api_version == 1`。
2. `status.data.status.executor_implemented == true`、`executor_api_version == 1`，并有当前客户端身份。后续所有命令固定同一 `--root` 和 `--pid`。

任一端不满足就报告“不支持后台执行器”，停止该流程；**不能**用 `run`、GUI 模拟或旧命令代替。
截至 2026-09-24，本仓库源码的 CLI 为 `0.20.0-executor`，但 `Release/plf-cli.exe` 实际仍为
`0.19.0-instrument-list`，其 `help` 没有执行器命令。仅更新本 Skill 不会使旧发布二进制获得能力；
每次以实际安装目录内的运行版本和服务端状态为准。不要为了启用功能自行编译 C++ 工程。

## 输入与身份

- 已注册公式使用其最终**内部简称**（编译响应的 `data.name`），不是中文显示名称。只管理已有公式时不重新编译；新公式必须先确认编译响应的 `runtime_registered == true`。
- 合约按[标的解析](contract-resolution.md)取得当前盘立方规范 key，不能猜月份；周期按[CLI 周期规则](cli-commands.md#周期规则)规范化并核对 `status.data.status.supported_periods`。添加前让用户明确公式、合约、周期；冲突或歧义时先询问。
- `--params` 是单个 `Name=Value,...` 数值对象，只覆盖已注册公式声明的可用参数；未要求覆盖就省略。不因已有任务参数不同而自动替换或删除。
- `executor_id` 是当前执行器会话中的任务身份，`operation_id` 是一次写操作的回执身份；两者不能互换。会话变化后旧 `executor_id` 失效，先重新 `executor-list`，不要沿用旧 ID 改写任务。

## 命令

以下展示子命令及业务参数。实际调用每次都在子命令后带同一个 `--root <安装目录>`、
`--pid <选定客户端 PID>`、全新 `--out <尚不存在的.json>`；PowerShell 使用参数数组，不拼接整条命令。

```text
executor-add --formula <内部简称> --contract <规范 key> --period <周期>
  [--params Name=Value,...] [--start] [--wait] [--timeout 60]
executor-list
executor-status --id <executor_id>
executor-start --id <executor_id> [--wait] [--timeout 60]
executor-stop --id <executor_id>
executor-remove --id <executor_id>
executor-request-status --request <operation_id>
```

- `executor-add` 默认只添加并保存配置；只有用户要求立即运行时才带 `--start`。
  `--wait` 仅对带 `--start` 的 `add` 或 `start` 有效。`--timeout` 必须伴随 `--wait`，
  范围 1–300 秒，默认 60 秒。
- `executor-list` 用于发现当前任务；`executor-status` 用于查看指定任务快照。
  读取 `task.state`、`desired_running`、`runGeneration`、`last_error`、`cleanup_pending`、
  `trading_enabled`。`--wait` 成功只表示**同一运行代次**进入 `running`，不是计算完成或回测完成。
- 添加遇到同公式/合约/周期的既有任务时，服务端可能复用它；检查返回的 `created`、
  `persisted`、`applied`、`started`、`task`，不要把“成功”一律表述为新建。
- `executor-stop` 后检查清理状态；`executor-remove` 仅允许已停止、无待清理的任务。
  用户只要求停止时不要顺手移除；用户只要求移除运行中的任务时，先说明必须停止并获得相应授权。
  CLI 管理不得开启交易，遇到 `EXECUTOR_TRADING_CONFLICT` 不要绕过保护。

## 账号权限

遇到 `error.code == "PERMISSION_DENIED"`，按[CLI 权限拒绝处理](cli-commands.md#账号权限拒绝)停止。
能力检查成功不等于账号已获授权；不要继续查询回执、停止或删除任务来规避门禁。
保留已知 `executor_id`、`operation_id`，不宣称之前受理的操作被撤销；授权恢复且用户要求继续时先查状态。

## 写操作回执与失败恢复

`add/start/stop/remove` 都先经过 `prepare`，再按 `operation_id` 执行；输出 JSON 的
`data.operation_id`、`server_instance_id`、`action`、`arguments`、`phase` 是对账依据。
写操作成功也要核对目标、阶段、代次和实际 `task` 快照。不能只看标准输出或退出码。

若超时、IPC 中断、返回 `result_unknown == true`，或结果尚在 `queued/executing`，
先保留 `operation_id`，用 `executor-request-status --request <operation_id>` 查询同一操作，
必要时再查 `executor-status` / `executor-list`。**在确认未生效之前不得重复提交写命令**。
`EXECUTOR_WAIT_TIMEOUT` 只说明等待期限到了，不会自动停止或删除任务，也不能直接重试添加/启动。
`EXECUTOR_GENERATION_REPLACED`、`EXECUTOR_STOPPED`、`EXECUTOR_SESSION_EXPIRED` 和
`EXECUTOR_REQUEST_EXPIRED` 均须按当前会话和任务快照重新核对，不把旧回执当作新运行结果。
`EXECUTOR_DATA_NOT_READY` / `EXECUTOR_MAINTENANCE_UNAVAILABLE` 是运行条件问题，不是公式编译错误；
不要通过重编译、换合约或无限重试掩盖。

每次读取本轮 `--out` JSON 后按 SKILL.md 的临时文件规则清理；不得删除任务配置、已注册公式或
用户未授权清理的后台任务。
