# 标的解析

本 Skill 只有一个标的解析入口：

```powershell
scripts\contract-catalog.ps1 -Action Resolve -Query <用户输入> -OutFile <全新临时 JSON>
```

从 `OutFile` 读取 UTF-8 JSON 后立即删除。不要依赖标准输出，也不要用管道捕获结果；
`OutFile` 必须尚不存在。

脚本每天首次使用时通过 `plf-cli instrument-list` 刷新
`usr\instrument-catalog.json`。目录中的期货两段基础 key、股票完整 `ContractID`
是唯一权威来源；`references\contracts.seed.json` 只提供期货别名，不直接产生 key。

## 解析规则

| 输入 | 结果 |
| --- | --- |
| `贵州茅台` | `SSE SHA 600519` |
| `SSE SHA 600519` | 原样返回完整股票 `ContractID` |
| `600519.SH` | `not_found`，不兼容股票显示代码 |
| `苹果指数` | `ZCE AP IDX` |
| `苹果主连` / `苹果主力` / `苹果连续` | `ZCE AP MI` |
| `苹果2610` | `ZCE AP 610` |
| `苹果611` | `ZCE AP 611` |
| `塑料2611` | `DCE L 2611` |
| `ZCE AP` | `need_contract`，询问指数、主连或具体月份 |
| `ZCE AP IDX` / `ZCE AP MI` | 返回完整三段式 key |
| `ZCE AP 2610` | 归一化为 `ZCE AP 610` |

自然语言月份必须由用户明确给出。郑商所 `ZCE` 接受三位或四位，四位输入删除首位；
其他交易所使用四位年月。已经是完整三段式 key 时规则相同。
不得从当前日期、主力月份或候选列表猜测月份。

## 状态处理

- `resolved`：唯一可运行 key，才能传给 `--contract`。
- `need_contract`：只识别到期货品种；询问用户要指数、主连还是月份合约，不得代选。
- `ambiguous`：展示 `candidates` 让用户选择。
- `not_found`：报告未找到，不试造 key。
- `error`：报告目录刷新或安装目录错误。

只有两段的期货基础 key 永远不能返回 `resolved`。别名表只帮助定位当天目录中的品种行：
例如“螺纹”定位到 `SHFE RB` 后返回 `need_contract`，由用户继续指定指数、主连或月份；
目录没有唯一对应行时返回未找到。

## 数据和维护

- `usr\instrument-catalog.json`：各副本私有，每个本地日期和安装目录刷新一次。
- `references\contracts.seed.json`：共享的期货别名和类型词，随 Skill 同步。
- 不读取 `all_contract.dat`、`hot_contract_list.dat`，也不维护额外学习缓存。
- 修改解析逻辑后至少验证：股票中文名、完整股票 key、股票旧显示代码、期货两段 key、
  指数、主连、ZCE 三位/四位月份、非 ZCE 四位月份、完整三段式和未知名称。
