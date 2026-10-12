# Ejia 公式完整函数列表

这是 Agent 编写 Ejia 公式时直接使用的函数清单，包含函数名、返回类型、参数、默认值和用途说明。先在本文件中确认签名，再生成公式；没有列出的函数不得凭空使用。

## 使用规则

- 默认只使用“K线数据、策略交易、策略状态、金融统计、数学、时间、字符串和数组”函数。
- “账户函数”会触达实盘账户，普通生成与编译演示禁止使用。
- 即时行情函数通常依赖运行期行情，本阶段只验证编译，不使用它们。
- 公式参数放在 `Params`，序列变量放在 `Vars`，主体写在 `Begin ... End`。
- 如果编译器返回的签名诊断与本清单冲突，以编译器诊断为准，并更新本 Skill 的清单。

## 下单与风控函数（官方签名）

签名以官方函数库（`【函数】盘立方宽语言函数库.txt`）为准。**官方文档中下单量参数名为
`Numeric volume`**，不是 `Integer Lot`；写成整数实参（如 `Buy(1, Open)`）同样可行。

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `Buy` | `Bool Buy(Numeric volume, Numeric Price, String symbol="")` | 多头建仓。`Volume` 为建仓数量；`Price` 为 0 表示市价单；`symbol` 默认当前合约。若已有卖仓，会同时发平卖仓 + 开买仓两条指令（成交顺序不保证） |
| `Sell` | `Bool Sell(Numeric volume, Numeric Price, String symbol="")` | 多头平仓。**`Volume` 为 0 表示完全平仓**，否则只平 volume 的买仓；无买仓时不执行任何操作 |
| `SellShort` | `Bool SellShort(Numeric volume, Numeric Price, String symbol="")` | 空头建仓。已有买仓时会同时发平买仓 + 开卖仓两条指令 |
| `BuyToCover` | `Bool BuyToCover(Numeric volume, Numeric Price, String symbol="")` | 空头平仓，签名同 `Sell` |

示例（官方）：

```text
SellShort(50, 10.2);                            // 以 10.2 的价格卖出 50 张合约
SellShort(10, Close);                           // 以当前 Bar 收盘价卖出 10 张，立即发委托
SellShort(20, Q_BidPrice("TA205"), "TA205");    // 以 TA205 的申买价卖出 20 手
```

### 止损 / 止盈 / 浮动止损

| 函数 | 签名 | 参数说明 |
| --- | --- | --- |
| `SetStopPoint` | `Numeric SetStopPoint(Numeric StopPoint, Integer nPriceType=0, Integer nAddTick=0, String Name="")` | `StopPoint` 止损点数，当前价相对**最近一次开仓价**亏损达到/跌破该值即止损 |
| `SetWinPoint` | `Numeric SetWinPoint(Numeric WinPoint, Integer nPriceType=0, Integer nAddTick=0, String Name="")` | `WinPoint` 止盈点数，盈利达到/超过该值即止盈 |
| `SetFloatStopPoint` | `Bool SetFloatStopPoint(Numeric StartPoint, Numeric StopPoint, Integer nPriceType=0, Integer nAddTick=0, String Name="")` | `StartPoint` 启动点数（盈利超过它才开启监控）；`StopPoint` 回撤止损点数 |

三个函数的 `nPriceType` 取值一致：**0 最新价（默认）/ 1 对盘价 / 2 挂单价 / 3 市价 / 4 停板价**；
`nAddTick`（超价点数）**仅在 `nPriceType` 为 0/1/2 时有效**。

官方示例中的点数语义（注意要乘以最小变动价位）：

```text
SetStopPoint(10);   // 郑棉多头：开仓价 15000，价格 ≤ 15000-5*10=14950 时止损平仓
SetWinPoint(10);    // 郑棉多头：开仓价 15000，价格 ≥ 15000+5*10=15050 时止盈平仓
SetFloatStopPoint(20, 10);  // 开仓 15000，突破 15100 后启动；涨到 15300 时止损线升至 15250
```

## 绘图函数（官方签名）

### 指标线

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `PlotNumeric` | `Numeric PlotNumeric(String Name, Numeric Number, Integer Color=-1, Integer BarsBack=0)` | 绘制指标线；`Name` 不区分大小写；`Color=-1` 使用属性设置框的颜色 |
| `PlotStickLine` | `Numeric PlotStickLine(String Name, Numeric Number, Numeric Number2, Integer Color=-1, Integer BarsBack=0)` | 竖线段，从 `Number` 到 `Number2`。如 `PlotStickLine("Line", High, Low);` |
| `PartLine` | `Bool PartLine(Integer nIdx, Numeric fPrice, Integer nIdx2, Numeric fPrice2, Integer Color=-1, Integer nWidth=1)` | 斜线段，起点 `(nIdx, fPrice)`、终点 `(nIdx2, fPrice2)`；`nWidth` 为像素粗细。如 `PartLine(0, Close, 3, High[3], Red);` |
| `PlotVertLine` | `Bool PlotVertLine(Integer BarsBack=0)` | 竖线；如 `PlotVertLine(CurrentBar%5);` 每隔 5 根画一根 |
| `UnPlot` | `Bool UnPlot(String Name, Integer BarsBack=0)` | 取消 `PlotNumeric` 所画的线 |
| `SetShapeStyle` | `Bool SetShapeStyle(String name, Integer width, Integer lineType=0, Bool bVisible=True)` | 设置指标线样式；`lineType` 0 实线 / 1 虚线A / 2 虚线B / 3 虚线C |

### 标注

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `ColorBar` | `Bool ColorBar(Integer Color, Integer BarsBack=0)` | **变色 K 线**，把满足条件的那根 K 线整体染色，如 `ColorBar(Yellow);` |
| `PlotText` | `Bool PlotText(Numeric value, String text, Integer BarsBack=0, Integer Color=-1)` | 在价格 `value` 处绘制字符串 |
| `PlotIcon` | `Bool PlotIcon(Numeric fPrice, Integer nIcon=0, Integer BarsBack=0)` | 在价格 `fPrice` 处绘制系统图标 |
| `PlotDot` | `Bool PlotDot(String name, Numeric fPrice, Integer nType, Integer Color=-1, Integer BarsBack=0)` | 绘制点，`nType` 0–14 共 15 种（箭头、圆点、三角等） |
| `PlotBar` | `Bool PlotBar(String Name, Numeric Number1, Numeric Number2, Bool bEmpty=True, Integer clr=-1, Integer BarsBack=0)` | 绘制柱状图，`bEmpty` 控制空心。如 `PlotBar("Vol", Vol, 0, False, Red);` |
| `FillRange` | `Integer FillRange(String name, Numeric price1, Numeric price2, Integer color, Integer barsBack=0)` | 填充两价之间的区域背景，常用于均线多空带 |

`PlotIcon` 的 `nIcon` 取值（0–15）：0 正常表情 / 1 笑脸 / 2 哭脸 / 3 上箭头 / 4 下箭头 /
5 上箭头2 / 6 下箭头2 / 7 喇叭 / 8 加锁 / 9 解锁 / 10 货币+ / 11 货币- / 12 加号 /
13 减号 / 14 叹号 / 15 叉号。

信号可视化三件套的典型组合（可直接复用）：

```text
If (BreakoutSignal)
{
    PlotText(Low - 2*TickPrice, "突破", 0, Green);  // 文字标注在低点下方
    PlotIcon(Close, 3, 0);                          // 在收盘价处画上箭头
    ColorBar(Yellow);                               // 该根 K 线整体标黄
}
```

### 警告

`Bool Alert(String Info, Integer FontSize=3, Integer Color=0, Bool bBeep=True)` —
弹出提示窗口，`FontSize` 取 1–5，`bBeep` 控制是否响铃。
如 `Alert("Hello", 5, Red);`。**编译演示中慎用**，会在运行时弹窗。

## 常用属性与合约函数

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `BigPointValue` | `Numeric BigPointValue(String symbol="")` | 一个点的价值。A 股为 1；恒指期货为 50 港币；**未登录交易服务器时返回 0**。资金管理公式必须处理该情况 |
| `ContractUnit` | `Integer ContractUnit(String symbol="")` | 每张合约的单位数量；未登录返回 0 |
| `TickPrice` | `Numeric TickPrice(String symbol="")` | 最小变动价位，常用于构造 "低点下方 N 个跳动" 这类标注位置 |
| `SymbolName` | `String SymbolName(String symbol="")` | 合约名称 |
| `SymbolStatus` | `Integer SymbolStatus(String symbol="")` | 交易状态：1 正常 / 2 挂起 / 3 删除；未登录返回 0 |
| `ExchangeStatus` | `Integer ExchangeStatus(String ExchangeName)` | 交易所状态：-1 无效 / 0 正初始化 / 1 准备就绪 / 2 集合竞价 / 3 竞价撮合 / 4 连续交易 / 5 交易暂停 / 6 交易闭市 |
| `ExchangeTime` | `Numeric ExchangeTime(String ExchangeName)` | 交易所时间；未启动交易时返回本机系统时间 |
| `ExchangeName` | `String ExchangeName(String symbol="")` | 合约所属交易所代码 |
| `SeatMargin` | `Numeric SeatMargin(String symbol="")` | 保证金率（0–1 小数） |

`ExchangeStatus` / `ExchangeTime` 的 `ExchangeName` 取 `"ZCE"` 郑州 / `"DCE"` 大连 /
`"SHFE"` 上海 / `"CFFEX"` 中金。

## 数组函数（官方签名）

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `ArrAdd` | `NumericArray ArrAdd(NumericArray arr, Numeric num)` | 把 `num` 追加到末端并返回 `arr` |
| `ArrInsert` | `NumericArray ArrInsert(NumericArray arr, Integer pos, Numeric num)` | 插入到 `pos` 位置之前 |
| `ArrRemove` | `NumericArray ArrRemove(NumericArray arr, Integer pos, Integer count=1)` | 从 `pos` 起删 `count` 个，后面元素前移 |
| `ArrSub` | `NumericArray ArrSub(NumericArray arr, Integer pos, Integer count)` | 取子数组；`pos+count` 不得越界 |
| `ArrLength` | `Integer ArrLength(NumericArray arr)` | 数组长度，**跨周期取数后必查是否为 0** |
| `ArrSort` | `NumericArray ArrSort(NumericArray arr, Bool bUp=True)` | `True` 升序、`False` 降序 |
| `ArrRevers` | `NumericArray ArrRevers(NumericArray arr)` | 反转数组 |
| `ArrSetSize` | `NumericArray ArrSetSize(NumericArray arr, Integer size, Numeric value=0)` | 设定长度，新增元素初值为 `InvalidNumeric` |
| `ArrFind` | `Integer ArrFind(NumericArray arr, Numeric num, Integer start=0, Integer mode=0)` | 返回首个满足条件的下标；`mode` 0 等于 / 1 大于等于 / 2 小于等于；找不到返回 -1 |
| `ArrClear` | `NumericArray ArrClear(NumericArray arr)` | 清空数组 |
| `ArrPrint` | `Integer ArrPrint(NumericArray arr, Integer pect=6)` | 输出到调试窗口，最多显示前 100 个元素 |
| `ToArray` | `NumericArray ToArray(NumericSeries src)` | 把序列变量复制成数组 |
| `iMA` | `Numeric iMA(NumericArray Arr, Numeric Length=10, Numeric Pos=0)` | 数组均值 |
| `iHHV` | `Numeric iHHV(NumericArray Arr, Numeric Length=10, Numeric Pos=0)` | 数组最高值 |
| `iLLV` | `Numeric iLLV(NumericArray Arr, Numeric Length=10, Numeric Pos=0)` | 数组最低值 |
| `iEMA` | `Numeric iEMA(NumericArray Arr, Numeric Length=10, Numeric Pos=0)` | 数组指数平均 |
| `iSMA` | `Numeric iSMA(NumericArray Arr, Integer N=10, Numeric M=1, Integer Pos=0)` | 数组加权平均；`M` 为权重且不得大于 `N` |
| `iRSI` | `Numeric iRSI(NumericArray Arr, Integer N=12, Integer Pos=0)` | 数组 RSI |
| `iMACD` | `Numeric iMACD(NumericArray Arr, NumericRef iDIF, NumericRef iDEA, Integer prdShort=12, Integer prdLong=26, Integer M=9, Integer Pos=0)` | 数组 MACD；`iDIF`/`iDEA` 为**引用参数**，用于回传 DIFF / DEA |
| `iStandardDev` | `Numeric iStandardDev(NumericArray Arr, Numeric Length, Numeric DataType)` | 数组标准差；`DataType` 1 总体 / 2 样本 |
| `iVariancePS` | `Numeric iVariancePS(NumericArray Arr, Numeric Length=10, Numeric DataType=1)` | 数组估算方差 |

- `Pos` 是"从第几个元素开始"，`Pos+Length` 必须小于数组长度。
- 官方示例的语义（数组 `{1,2,3,4,5,6}`）：`iMA(arr,3,0)` = (1+2+3)/3，`iMA(arr,2,1)` = (2+3)/2，
  `iHHV(arr,4,2)` = MAX(3,4,5,6)，`iLLV(arr,4,2)` = MIN(3,4,5,6)。
- **`iMACD` 的引用参数写法**（其余 `i*` 函数返回标量）：

```text
Vars
    Numeric fDiff;
    Numeric fDea;
Begin
    Numeric fMACD = iMACD(arr, fDiff, fDea, 12, 26, 5, 1);
End
```

## 其他常用函数

| 函数 | 签名 | 说明 |
| --- | --- | --- |
| `IIF` | `Numeric IIF(Bool Conditon, Numeric TrueValue, Numeric FalseValue)` | 三元表达式，可参与算术运算（多因子打分用法见下文实测） |
| `IIFString` | `String IIFString(Bool Conditon, String TrueValue, String FalseValue)` | 字符串版三元表达式 |
| `Text` | `String Text(Numeric num)` | 把数字转成字符串，配合字符串拼接 `+` 使用 |
| `Print` | `Numeric Print(String word)` / `Numeric Print(Numeric word, Integer Prec=6)` | 输出到调试窗口，`Prec` 为小数位数 |
| `Commentary` | `Numeric Commentary(String text)` | 输出一行字符串，返回字符串长度 |
| `InvalidNumeric` | `Numeric InvalidNumeric()` | 无效数字，本系统定义为 0 |
| `InvalidString` | `String InvalidString()` | 无效字符串，本系统定义为 `""` |
| `ValueWhen` | `Numeric ValueWhen(Bool Condition, Numeric Data)` | 返回最后一次满足条件时的值 |
| `StarTrade` / `StopTrade` | 见官方函数库「策略交易函数」 | 启动 / 停止策略交易 |

### 颜色函数

`Rgb(Integer r, Integer g, Integer b)` 自定义颜色（参数 0–255），以及命名颜色函数：
`Black()` `Blue()` `Cyan()` `DarkBrown()` `DefaultColor()`（默认红）`Green()` `Magenta()`
`Red()` `White()` `Yellow()` `ColorUp()`（系统上涨色）`ColorDown()`（系统下跌色）。

**注意**：颜色函数写作带括号的调用形式（`Red()`），官方范例中也常直接写 `Red`，两种写法均可见；
以本机编译器实测为准。

## 完整列表

```text
Params
    Integer FastLength(5);
    Integer SlowLength(20);
    Numeric StdDevK(2);
GlobalVars
Vars
    NumericSeries FastMA;
    NumericSeries SlowMA;
Begin
    FastMA = MA(Close, FastLength);
    SlowMA = MA(Close, SlowLength);
End
```

`Params` 不只支持整数参数。需要小数语义的参数使用 `Numeric`；本机编译器已确认
`Numeric StdDevK(2);` 可以通过编译，其类型仍是 `Numeric`，不能因为默认值写成整数
字面量就改成 `Integer`。

## 模型结构

官方语法规范定义的骨架，四个区域各只能出现一次，顺序固定：

```text
// 简称:   趋势突破
// 名称:   TrendBreakout
// 类别:   策略
// 类型:   趋势
Params      // 参数定义（数值型；必须给默认值；不能定义序列变量）
    Integer BreakoutPeriod(20);
GlobalVars  // 全局变量定义（跨周期保持，直到公式停止运行）
    Bool G_Ready;
Vars        // 局部变量定义（每个计算周期重置）
    NumericSeries High_N;
    Numeric BreakoutLevel;
Begin       // 策略执行区，语句自上而下、自左至右执行
    ...
End
```

各区域硬性规则（来自官方语法规范）：

| 区域 | 规则 |
| --- | --- |
| `Params` | 只能有一个；必须在变量定义之前；**参数类型只能是数值型，不能用序列变量**；必须指定默认值；**不可以用 `=` 赋值**；一次只能定义一个参数；函数名不能作参数名 |
| `GlobalVars` | 只能有一个；在 `Params` 之后、主程序之前；变量从公式被加载起一直存在，直到公式被停止运行；一行只能定义一个；函数名不能作变量名 |
| `Vars` | 只能有一个；在 `Params` 之后、主程序之前；类型可为数值型/字符串型/数组型；**可不指定默认值，数值型默认 0、字符串型默认空串**；可在主程序中用 `=` 赋值；一行只能定义一个；函数名不能作变量名 |
| `Begin ... End` | 各只能有一个；语句自上而下、自左至右计算 |

`Params` 不只支持整数参数。需要小数语义的参数使用 `Numeric`；本机编译器已确认
`Numeric StdDevK(2);` 可以通过编译，其类型仍是 `Numeric`，不能因为默认值写成整数
字面量就改成 `Integer`。

## 控制流

官方语法规范（`【语法】盘立方语法规范.txt`）已明确下列控制流写法，可直接使用。
公式最外层使用一次 `Begin ... End`；**分支与循环体一律用花括号 `{ ... }` 包裹**，
不存在 `Then`、`Then Begin`、`Do`/`EndDo` 之类的写法。

### If / If-Else / If-Else If

```text
If (Condition)
{
    公式语句;
}
```

```text
If (Condition1)
{
    公式语句1;
}
Else If (Condition2)
{
    公式语句2;
}
Else
{
    公式语句3;
}
```

- `If` 体中的语句必须用 `{}` 括起来。
- 嵌套结构中 `Else` 与其**前面最近的、还未配对的 `If`** 配对。
- 单条件成立、否则分支这种两分写法，用 `If (C) { } Else { }` 即可，不必硬套 `Else If`。

### For 循环

`For` 用于次数确定的循环。**循环变量必须是在此前已经定义过的数值型变量**（放到 `Vars`）。

```text
For i = 1 To 结束值        // 从小到大，步长恒为 1，初始值必须 <= 结束值
{
    公式语句;
}

For j = 结束值 DownTo 0    // 从大到小，步长恒为 -1，初始值必须 >= 结束值
{
    公式语句;
}
```

注意：循环数组时，下标不要超过元素总数量。

### While 循环

适用于次数未知的循环；条件为真时重复执行，为假时退出。

```text
While (Condition)
{
    公式语句;
}
```

### Break / Continue / Return

```text
While (True)
{
    公式语句1;
    If (Condition)
    Break;          // 结束整个循环，执行循环之后的代码
}

While (Condition1)
{
    公式语句1;
    If (Condition2)
    Continue;       // 结束本次循环，直接进入下一次条件判断
    公式语句2;
}

While (True)
{
    公式语句1;
    If (Condition)
    Return          // 从当前位置返回，Return 之后的代码不再执行
    公式语句2;
}
```

`Break` / `Continue` 在 `If` 体内作为单条语句使用，可不加花括号。

## 运算符

官方运算符总表（示例取自官方语法规范，均为 `IIF` 内的布尔表达式）：

| 运算符 | 含义 | 官方示例 |
| --- | --- | --- |
| `+` `-` `*` `/` | 加、减、乘、除 | `Num = High + Close;` |
| `&&` | 逻辑与（并且） | `IIF(High > Close && Close > Low, 1, 0)` |
| `\|\|` | 逻辑或（或者） | `IIF(High > Close \|\| Close > Low, 1, 0)` |
| `>` | 大于 | `IIF(High > Close, 1, 0)` |
| `<` | 小于 | `IIF(Low < Close, 1, 0)` |
| `>=` | 大于等于 | `IIF(High >= Close, 1, 0)` |
| `<=` | 小于等于 | `IIF(High <= Close, 1, 0)` |
| `!=` | 不等于 | `IIF(High != Close, 1, 0)` |
| `==` | 等于（比较） | `IIF(High == Close, 1, 0)` |
| `=` | 赋值（不是比较） | `Num = IIF(High == Close, 1, 0);` |

要点：

- **`=` 只用于赋值，`==` 才用于相等比较**，两者不可混用。
- 比较符写成连写形式：`>=`、`<=`、`!=`。官方文档正文中偶见 `> =` 的排版空隙，
  但实际书写应为连写；本机编译器对连写形式已验证可用。
- 逻辑与/或除 `&&` / `||` 外，官方策略范例中也大量出现 `And` / `and` 写法
  （如 `If(A And B)`、`if(a and b)`），两种写法并存，以本机编译器实测为准。

## 数据类型

官方数据类型共 12 种：

| 类型 | 含义 | 常见使用位置 |
| --- | --- | --- |
| `Numeric` | 数值型 | `Params` / `Vars` |
| `Integer` | 整型 | `Params` / `Vars` |
| `NumericSeries` | 数值序列（可 `[n]` 回溯） | `Vars` / `GlobalVars` |
| `NumericRef` | 数值引用 | 函数形参 |
| `String` | 字符串 | `Params` / `Vars` |
| `StringSeries` | 字符串序列 | `Vars` / `GlobalVars` |
| `StringRef` | 字符串引用 | 函数形参 |
| `Bool` | 布尔型 | `Vars` / `GlobalVars` |
| `BoolSeries` | 布尔型序列 | `Vars` / `GlobalVars` |
| `BoolRef` | 布尔型引用 | 函数形参 |
| `NumericArray` | 数组型 | `Vars`（如 `HisData` 返回值） |
| `NumericArrayRef` | 数组型引用 | 函数形参 |

`Params` 只能用数值型（`Numeric` / `Integer`）；序列类型（`NumericSeries`、
`BoolSeries`、`StringSeries`）与数组型只能出现在 `Vars` / `GlobalVars`。

## 变量的作用范围

### 局部变量（`Vars`）

- 定义在 `Vars` 区域，**每次计算都重新取值**：不赋值就直接取初始值（数值 0 / 空串）。
- 用 K 线数据回测时，"当次计算" = 某一根 K 线的计算过程，赋值只在那一根 K 线内生效；
  逐笔回测与盘中运行时，"当次计算" = 某一笔数据的计算过程。
- 代码运行结束即自动销毁。

```text
Vars
    Numeric yang;
    Numeric yin;
Begin
    IF (Open < Close)
    {
        yang = 1;
    }
    IF (Open > Close)
    {
        yin = 1;
    }
End
```

### 全局变量（`GlobalVars`）

- 一直保存上次修改的值，**直到该公式被停止运行**。
- 与 `Vars` 的区别：`Vars` 每个周期重新赋值、运行结束即销毁；`GlobalVars` 跨周期保留。
- 官方限制：`GlobalVars` 只能定义在策略/指标里，**不能定义在函数中**。
- 适合"只初始化一次"的标志位，例如：

```text
GlobalVars
    Bool G_Inited;
Vars
    Numeric RefHigh;
Begin
    If (!G_Inited)
    {
        RefHigh = High;
        G_Inited = true;
    }
End
```

### 序列变量（`NumericSeries`）

序列变量是宽语言与 C++ 之类通用语言最显著的差别，专为金融统计（如移动平均）而设计。

- 拥有**数据回溯**能力，用中括号访问历史：`High` 是本周期最高价，`High[1]` 是上一根 K 线最高价。
- 长度自动变化，**始终与图中 K 线数量一致**：新生成一根 K 线，序列长度自动 +1，新增元素初值等于上一周期的值。
- 使用规则（尤其写在函数中时，否则多个序列变量存取会串位）：
  - 尽可能保证每一周期都执行到序列变量相关语句；
  - **尽量不要在 `If` / `Else` 语句内部使用序列函数**；
  - 可以在循环中使用序列函数，但必须保证**每个周期中序列函数的调用次数完全相同**。

官方 EMA 示例（序列变量 + 回溯 + 首根 K 线保护）：

```text
Params
    Numeric Price(10);
    Numeric Length(10);
Vars
    Numeric sFcactor;
    NumericSeries EMAValue;
Begin
    sFcactor = 2 / (Length + 1);
    If (CurrentBar == 0)
    {
        EMAValue = Price;
    }
    Else
    {
        EMAValue = sFcactor * (Price - EMAValue[1]) + EMAValue[1];
    }
    Return EMAValue;
End
```

### 行内声明

变量可以在使用处直接声明并赋初值，无需先写进 `Vars`：

```text
Numeric MA1 = iMA(Close15M);        // 行内声明 Numeric
Numeric MA2 = iMA(OpenDay, 20, 1);  // 带全部参数的行内声明
```

### C 风格 For

除 `For i = a To b` 外，官方指标样例中也使用 C 风格计数循环：

```text
For (int i = 2; i <= 4; i++)
{
    ...
}
```

## 跨周期行情：HisData

`HisData` 用于获取**跨周期、跨合约**的历史数据，是数组而不是序列变量。

- 返回值：`NumericArray`，**数据按时间由近到远排列**（`[0]` 是最近的一根）。
- 与序列变量的本质区别：**序列变量依赖图表，数组完全脱离图表**。
- 语法：
  `NumericArray HisData(Enum type, Enum period, Integer interval, String Symbol="", Integer maxLength=100)`
- 参数：
  - `Type` 历史数据种类；`Period` 周期类型；`interval` 周期数（5 分钟线填 5，50 秒线填 50）；
  - `Symbol` 合约代码，留空表示当前合约；`maxLength` 返回数组的最大长度。

**历史数据种类（`Type`）**

`Enum_Data_Close` 收盘价 / `Enum_Data_Open` 开盘价 / `Enum_Data_High` 最高价 /
`Enum_Data_Low` 最低价 / `Enum_Data_Median` 中间价 (高+低)/2 /
`Enum_Data_Typical` 标准价 (高+低+收)/3 / `Enum_Data_Weighted` 加权收盘价 (高+低+开+收)/4 /
`Enum_Data_Vol` 成交量 / `Enum_Data_Opi` 持仓量 / `Enum_Data_Time` K线时间

**周期类型（`Period`）**

`Enum_Period_Default` 当前图表周期 / `Enum_Period_Tick` 分笔 / `Enum_Period_Dyna` 分时 /
`Enum_Period_Second` 秒线 / `Enum_Period_Min` 分钟 / `Enum_Period_Hour` 小时 /
`Enum_Period_Day` 日线 / `Enum_Period_Week` 周线 / `Enum_Period_Month` 月线 /
`Enum_Period_Year` 年线

**数组必须用 `i*` 系列函数计算，不能当作序列变量传给 `Average` / `Highest` / `Lowest`。**

| 常用数组函数 | 用途 |
| --- | --- |
| `ArrAdd` | 在元素尾部追加一个元素 |
| `ArrInsert` | 插入一个元素到数组中 |
| `ArrRemove` | 从数组中移除某个元素 |
| `ArrLength` | 获得数组中元素的个数 |
| `ArrRevers` | 反转数组 |
| `iMA` | 求数组的平均值 |
| `iHHV` | 求数组的最高值 |
| `iLLV` | 求数组的最低值 |
| `iEMA` | 求数组的指数平均 |
| `iMACD` | 求数组的指数平滑异同平均 |
| `iSMA` | 求数组的权重平均值 |
| `iRSI` | 求数组的相对强弱指数 |

官方跨周期示例（注意 `ArrLength` 空数组保护）：

```text
Params
    String Kind("CF205");
Vars
    NumericArray Close15M;
    NumericArray OpenDay;
Begin
    Close15M = HisData(Enum_Data_Close, Enum_Period_Min, 15, Kind);
    OpenDay  = HisData(Enum_Data_Open,  Enum_Period_Day, Kind);

    If (ArrLength(Close15M) == 0)
    {
        Print("暂未获取到15分钟数据");
    }
    Else
    {
        Numeric MA1 = iMA(Close15M);
        Print(Kind + "的15分钟线当前MA值为：" + Text(MA1));
    }
End
```

`iMA(数组, N, offset)` 可带周期与偏移：`iMA(OpenDay, 20, 1)` 表示"日线前一周期、20 周期的均值"。

## 本机编译器补充实测

以下事实来自真实编译（退出码 0），作为官方规范的落地佐证：

- 条件必须写在圆括号中：`If (条件)`；多语句分支使用 `{ ... }`。
- 赋值使用 `=`；相等比较使用 `==`，不能把赋值符号当成比较符号。
- `And` 两侧可自由组合函数与比较，例如
  `If (CurrentContracts() == 0 And CrossUnder(Close, LoBand))`。
- `>` 与 `<` 均可用（BollingerBand 策略）；`>=` / `<=` 由官方规范给出。
- `PlotNumeric` 的线名可用中文（如 `"上轨"`），源码以 UTF-8 保存并传
  `--source-encoding utf8` 时编译正常；CLI 回报的 `data.editor_source_encoding`
  为 `cp936` 属正常转换，不是错误。
- `Buy(LotSize, Close)` 可直接把 `Integer` 参数当作 `Integer Lot` 实参使用。
- 信号可视化三件套可同时使用：`PlotText(位置, 文本, 对齐, 颜色)`、
  `PlotIcon(位置, 图标编号, 方向)`、`ColorBar(颜色)`。
- 一行 200 字符以上的长表达式可编译，不需要人为折行。

**优先级**：官方规范 > 本机编译实测 > 其他语言习惯。前两者冲突时以本机编译器
诊断为准，并回头更新本文件。**任何未被官方规范或本机编译证实的写法都不得凭空推断。**

### 多分支双向策略实测（BollingerBand 双向版，退出码 0，2026-09-11）

以下写法在同一次真实编译中全部通过，可直接复用：

- 一个 `Begin ... End` 内可并列多个 `If (条件) { ... }` 分支，每个分支两条语句（下单 + `Commentary`）无问题。
- `CurrentBuyContracts() > 0`、`CurrentSellContracts() > 0` 可用，用于区分多/空持仓，避免用
  `CurrentContracts() > 0` 时多空互相干扰。
- `SellShort(LotSize, Close)` 与 `BuyToCover(LotSize, Close)` 可用，签名同 `Buy`/`Sell`。
- 同一个公式内可连续多条 `PlotNumeric`（中文线名如 `"上轨"`/`"中轨"`/`"下轨"`）配 `Red()`/`Yellow()`/`Green()`。
- `Numeric` 参数（`Numeric StdDevK(2);`）与 `Integer` 参数混用正常；`StandardDev(Close, Length, 1)` 与 `MA(Close, Length)` 搭配计算布林带无误。
- 成功响应里 `data.template_metadata_filled` 可能为 `false`（源码头部已手写），但
  `strategy_registered`/`disk_registered`/`runtime_registered` 均为 `true`、`editor_restart_required` 为 `false`，即为成功。

### 多因子评分双向策略实测（MultiFactorTrend，退出码 0，2026-09-14）

以下写法在同一次真实编译中全部通过，可直接复用：

- `IIF(Bool 条件, Numeric 真值, Numeric 假值)` 可用，并且能在**一条表达式里多次相加**，用来
  给多个因子打分，例如
  `LongScore = IIF(FastMA > SlowMA, 1, 0) + IIF(Close > TrendMA, 1, 0) + IIF(RsiVal > RsiLow, 1, 0);`。
- `REF(Highest(High, N), 1)`、`REF(Lowest(Low, N), 1)` 可用，用作唐奇安通道的突破触发值：
  `Highest(High, N)` 含当前 Bar，必须 `REF` 到前一根才可能被 `Close` 突破。
- `AvgTrueRange(N)`、`RSI(Close, N)`、`MA(Vol, N)` 可用；配合 7 条 `PlotNumeric` 无问题。
- `LoBand > Close` 与 `Close < LoBand` 已在同一个指标中真实编译通过；二者都是严格比较，
  分别表示“左值大于右值”和“左值小于右值”，交换两侧后条件等价，相等时均为假。
- 并列 6 个 `If (A And B) { ... }` 分支正常编译，其中 `A` 用
  `CurrentContracts() == 0`/`CurrentBuyContracts() > 0`/`CurrentSellContracts() > 0` 做持仓判定、
  `B` 用 `CrossOver`/`CrossUnder`/数值比较做信号判定。
- 单行 200 字符以上的长表达式可编译，不需要人为折行。

### 海龟通道突破双向策略实测（TurtleSystem，退出码 0，2026-09-22）

以下写法在同一次真实编译中全部通过，可直接复用：

- **零参状态函数可以裸名当变量用，不必加空括号**：`BigPointValue`、`ContractUnit`、
  `Available`、`TickPrice`、`MarketPosition`、`CurrentEntries`、`LastEntryPrice` 混在算术表达式与
  `If` 条件里编译通过，例如 `RiskPerUnit = StopATR * ATRVal * BigPointValue * ContractUnit;`
  与 `UnitSize = IntPart(Available * RiskPercent / 100 / RiskPerUnit);`。
- `REF(Highest(High, N), 1)` / `REF(Lowest(Low, N), 1)` 可在同一公式里同时做入场通道（N=20）
  与离场通道（N=10），4 条通道线互不干扰。
- `AvgTrueRange(N)` 返回标量，可直接赋给 `NumericSeries` 并参与乘除。
- 一个公式内可并列「空仓开仓 / 多头加仓+止损+离场 / 空头加仓+止损+离场」三组
  `If ... Else If` 分支，分支内含 `Buy(UnitSize, Close)`、`Sell(0, Min(StopPrice, Low))`、
  `BuyToCover(0, Max(StopPrice, High))` 与 `PlotText` / `PlotIcon`。
- `CurrentEntries < MaxUnits && High >= LastEntryPrice + k*ATRVal` 可作为金字塔加仓条件；
  已有持仓时重复 `Buy` / `SellShort` 会继续追加建仓次数。
- 头寸规模用 `IntPart(权益 * 风险% / (止损倍数 * N * BigPointValue * ContractUnit))`
  + `Max(UnitSize, 1)`，`BigPointValue`/`ContractUnit` 返回 0 时自动降级为 1 手，不会除零报错。

## 完整列表

```text
#K线数据-sys
Integer BarStatus()  //当前Bar的状态
Integer CurrentBar()   //当前Bar的索引值
NumericSeries Date()     //当前Bar的日期,简写D
NumericSeries Time()     //当前Bar的时间,简写T
NumericSeries TradeDate()	//当前Bar的交易日
Bool HistoryDataExist()  //历史数据是否存在
NumericSeries Close(String symbol="")  //收盘价,简写C
NumericSeries High(String symbol="")  //最高价,简写H
NumericSeries Low(String symbol="")  //最低价,简写L
NumericSeries Open(String symbol="")  //开盘价,简写O
NumericSeries OpenInt(String symbol="") //持仓量
NumericSeries Vol(String symbol="") //成交量,简写V

NumericArray HisData(Enum type, Enum period,Integer interval,   String Symbol="", Integer maxLength=100)     //获得各种历史数据
#数据函数简写-hide
Numeric C()  //收盘价
Numeric H()  //最高价
Numeric L()  //最低价
Numeric O()  //开盘价
Numeric V() //成交量
Numeric D()    //当前Bar的日期
Numeric T()     //当前Bar的时间
#即时行情-sys
Numeric Q_AskPrice(String symbol="",String symbol2="", int level=1) //最新卖价(组合行情仅最后一根K线有效)
Numeric Q_AskVol(String symbol="",String symbol2="", int level=1) //最新申卖量(组合行情仅最后一根K线有效)
Numeric Q_BidPrice(String symbol="",String symbol2="", int level=1)   //最新买盘价格(组合行情仅最后一根K线有效)
Numeric Q_BidVol(String symbol="",String symbol2="", int level=1) //最新申买量(组合行情仅最后一根K线有效)
Numeric Q_Close(String symbol="",String symbol2="")   //最新价或收盘价(组合行情仅最后一根K线有效)
Numeric Q_AvgPrice(String symbol="")	//实时结算价
Numeric Q_High(String symbol="") //当日最高价
Numeric Q_Low(String symbol="") //当日最低价
Numeric Q_LowerLimit(String symbol="")   //当日跌停板价
Numeric Q_Open(String symbol="") //当日开盘价
Numeric Q_OpenInt(String symbol="")   //持仓量
Numeric Q_PreClose(string symbol="") //昨收盘
Numeric Q_PreOpenInt(String symbol="")   //昨日持仓量
Numeric Q_PreSettlePrice(String symbol="") //昨日结算价
Numeric Q_PriceChgRatio(String symbol="")   //当日涨跌幅
Numeric Q_PriceChg(String symbol="") //当日涨跌
Numeric Q_TotalVol(String symbol="") //当日成交量
Numeric Q_TurnOver(String symbol="") //成交金额(股票)
Numeric Q_UpperLimit(String symbol="") //当日涨停板价
#策略交易-sys
Bool Buy(Integer Lot=0,Numeric Price=0,String symbol="")   //产生一个多头建仓操作
Bool BuyToCover(Integer Lot=0,Numeric Price=0,String symbol="")		 //产生一个空头平仓操作
Bool Sell(Integer Lot=0,Numeric Price=0,String symbol="")		//产生一个多头平仓操作
Bool SellShort(Integer Lot=0,Numeric Price=0,String symbol="")		//产生一个空头建仓操作
Numeric SetStopPoint(Numeric StopPoint, Integer nPriceType=0, Integer nAddTick=0, String Name="")		//设置止损
Numeric SetWinPoint(Numeric WinPoint, Integer nPriceType=0, Integer nAddTick=0, String Name="")		//设置止赢
Bool SetFloatStopPoint(Numeric StartPoint, Numeric StopPoint,Integer nPriceType=0, Integer nAddTick=0, String Name="")   //设置浮动止损
#策略状态-sys
Numeric AvgEntryPrice(String symbol="")    //获得当前持仓的平均建仓价格
Integer BarsSinceEntry(String symbol="")        //获得当前持仓的第一个建仓位置到当前位置的Bar计数
Integer BarsSinceExit(String symbol="")         //获得最近平仓位置到当前位置的Bar计数
Integer BarsSinceLastEntry(String symbol="")    //获得当前持仓的最后一个建仓位置到当前位置的Bar计数
Numeric ContractProfit(String symbol="")       //获得当前持仓的每手浮动盈亏
Integer CurrentContracts(String symbol="")     //获得当前持仓的持仓合约数
Integer CurrentBuyContracts(String symbol = "")		//获得当前持仓的多仓合约数
Integer CurrentSellContracts(String symbol = "")	//获得当前持仓的多仓合约数
Integer CurrentEntries(String symbol="")       //获得当前持仓的建仓次数
Integer EntryDate(String symbol="")            //获得当前持仓的第一个建仓位置的日期
Numeric EntryPrice(String symbol="")           //获得当前持仓的第一个建仓价格
Integer EntryTime(String symbol="")            //获得当前持仓的第一个建仓位置的时间
Integer  ExitDate(String symbol="")            //获得最近平仓位置Bar日期
Integer  ExitPrice(String symbol="")           //获得最近平仓位置的平仓价格
Integer  ExitTime(String symbol="")            //获得最近平仓位置Bar时间
Integer  LastEntryDate(String symbol="")      //获得当前持仓的最后一个建仓位置的日期
Numeric  LastEntryPrice(String symbol="")     //获得当前持仓的最后一个建仓价格
Integer  LastEntryTime(String symbol="")      //获得当前持仓的最后一个建仓位置的时间
Integer  MarketPosition(String symbol="")     //获得当前持仓状态
Numeric  MaxPositionLoss(String symbol="")    //获得当前持仓的最大浮动亏损数
Numeric  MaxPositionProfit(String symbol="")  //获得当前持仓的最大浮动盈利数
Numeric PositionProfit(String symbol="")       //获得当前持仓的浮动盈亏。
Numeric HighestSinceLastEntry(String symbol="")	//最近一次开仓到现在的最高价
Numeric LowestSinceLastEntry(String symbol="")		//最近一次开仓到现在的最低价
#策略性能-sys
Numeric Available()	  //获得策略当前的可用虚拟资金
Numeric FloatProfit()    //获得策略当前浮动盈亏
Numeric GrossLoss()    //获得累计的总亏损。
Numeric GrossProfit()  //获得累计的总盈利。
Numeric Margin()		  //获得策略当前占用的持仓保证金
Numeric NetProfit()	  //获得策略当前平仓盈亏
Integer NumEventTrades()  //获得保本交易的总手数。
Integer NumLoseTrades()  //获得亏损交易的总手数。
Integer NumWinTrades()  //获得盈利交易的总手数。
Integer NumAllTimes()		//获得开仓次数
Integer NumWinTimes()     //获得盈利次数
Integer NumLoseTimes()    //获得亏损次数
Integer NumEventTimes()	//获得保本次数
Numeric PercentProfit()  //获得盈利的成功率
Numeric TradeCost()      //获得交易产生的手续费
Integer TotalTrades()  //获得交易的总开仓手数。
#账户函数-sys
String A_AccountID()  //返回当前交易账户ID
Bool A_IsConnected() //判断是否连接交易服务器并登录成功
Bool IsTradeAllowed()  //是否允许交易
Integer A_SendOrder(Enum BuyOrSell,Enum EntryOrExit,Numeric Lot,Numeric Price, String symbol="")  //针对当前账户发送委托单
Bool A_DeleteOrder(Integer orderNo)  //发送撤单指令
Integer A_FirstOrderNo(String symbol1="")    //返回当前账户第一个单子
Integer A_NextOrderNo(Integer OrderNo,String symbol="")  //返回当前账户下一个单子
Integer A_LastOrderNo(String symbol="")  //返回当前账户最近一个单子
Integer A_FirstQueueOrderNo(String symbol="")    //返回当前账户第一个排队单子
Integer A_NextQueueOrderNo(Integer OrderNo,String symbol="")  //返回当前账户下一个排队单子
Integer A_LastQueueOrderNo(String symbol="")  //返回当前账户最近一个排队单子
Enum A_OrderStatus(Integer OrderNo) //查询订单状态
String A_OrderContractNo(Integer OrderNo)  //订单合约号
Enum A_OrderBuyOrSell(Integer OrderNo)	//订单买卖类型
Enum A_OrderEntryOrExit(Integer OrderNo) //订单开平类型
Numeric A_OrderPrice(Integer OrderNo)	 //订单委托价格
Integer A_OrderLot(Integer OrderNo) //订单委托数量
Integer A_OrderFilledLot(Integer OrderNo) //订单成交量
String A_OrderAccount(Integer OrderNo) //订单的账号		
Numeric A_OrderFilledPrice(Integer OrderNo) //订单成交价格
Numeric A_OrderTime(Integer OrderNo)  //订单下单时间
Integer A_TodayBuyPosition(String Symbol="")  //当前账户当日开买仓量
Integer A_TodaySellPosition(String Symbol="") //当前账户当日开卖仓量
Integer A_BuyPosition(String Symbol="")  //当前账户买仓总量
Integer A_SellPosition(String Symbol="") //当前账户卖仓总量
Integer A_BuyPositionCanCover(String Symbol="")	//当前账户买仓可平数量
Integer A_SellPositionCanCover(String Symbol="")	//当前账户空仓可平数量
Numeric A_BuyAvgPrice(String Symbol="")   //当前账户买仓均价
Numeric A_SellAvgPrice(String Symbol="")  //当前账户卖仓均价
Integer A_TotalPosition(String Symbol="") //当前账户总持仓量
Numeric A_TotalAvgPrice(String Symbol="")   //当前账户总持仓均价
Numeric A_Available()	//当前账户的可用资金
Numeric A_Margin()  	//当前账户的持仓保证金
Numeric A_Cost()         //当前账户的手续费
Numeric A_Assets()        //当前账户的权益
Numeric A_HoldProfit()	  //当前账户的持仓盈亏
Numeric A_CoverProfit()	  //当前账户的平仓盈亏
Bool DeleteAllOrders(String name="") //批量撤单函数
StringArray A_GetAllPositionSymbol()		//获得当前账户所有持仓合约
#商品属性-sys
Enum BarType() //当前图表的周期类型
Integer BarInterval() //当前图表的周期数值
String SetOrderFlag(String name)   //设置当前公式所下定单的标识
Numeric BigPointValue(String symbol="") //返回一个点的价值
Integer ContractUnit(String symbol="") //每张合约的单位数量
String ExchangeName(String symbol="") //商品的交易所名称
Integer MinMove(String symbol="") //商品的价格最小变动量
Numeric PriceScale(String symbol="") //商品的计价精度
Numeric TickPrice(String symbol="") //商品的最小变动价位
String PeriodName() //当前图表的周期名称
String Symbol() //当前图表商品的代码
String SymbolName(String symbol="") //根据商品代码获得商品的名称
Numeric SeatMargin(String symbol="") //席位保证金比例

#金融统计-sys
Numeric AdaptiveMovAvg(NumericSeries Price=1,Numeric EffRatioLength=10,Numeric FastAvgLength=2,Numeric SlowAvgLength=30) //求卡夫曼自适应移动平均
Numeric Average(NumericSeries Price,Numeric Length=10) //求平均
Numeric AverageD(Numeric DataType=1,Numeric Length=10) //求N天以来的价格平均值
Numeric AverageFC(NumericSeries Price,Numeric Length=10) //快速计算平均值
Numeric AvgDeviation(NumericSeries Price=1,Numeric Length=10) //求平均背离
Numeric AvgPrice() //求平均价格
Numeric AvgTrueRange(Numeric Length=10) //求平均真实范围
Numeric BarsSinceToday() //当天的第一个数据到当前的Bar数
Numeric BarsLast(Bool Condition)  //返回最后一次满足条件时距离当前的Bar数
Numeric CloseD(Numeric daysAgo=2) //求N天前的收盘价
Numeric CoefficientR(NumericSeries Price1=1,NumericSeries Price2=1,Numeric Length=10) //求皮尔森相关系数
Numeric CountIf(BoolSeries TestCondition=False,Numeric Length=10) //获取最近N周期条件满足的计数
Numeric Correlation(NumericSeries Price1=1,NumericSeries Price2=1,Numeric Length=10) //求相关系数
Numeric Covar(NumericSeries Price1=1,NumericSeries Price2=1,Numeric Length=10) //求协方差
Bool CrossOver(NumericSeries Price1=1,NumericSeries Price2=1) //求是否上穿
Bool CrossUnder(NumericSeries Price1=1,NumericSeries Price2=1) //求是否下破
Numeric Cum(NumericSeries Price=1) //求累计值
Numeric DEMA(NumericSeries Price=0,Numeric Length=10) //求双指数移动平均
Numeric Detrend(NumericSeries Price=1,Numeric Length=10) //求趋势平滑
Numeric Extremes(NumericSeries Price,Numeric Length,Bool bMax,NumericRef ExtremeBar) //求极值
Numeric HighD(Numeric daysAgo=2) //求N天前的最高价
Numeric Highest(NumericSeries Price=0,Numeric Length=5) //求最高
Numeric HighestBar(NumericSeries Price=0,Numeric Length=5) //求最高值出现的Bar
Numeric HighestFC(NumericSeries Price=1,Numeric Length=10) //快速计算最高
Numeric KDJ(Numeric N,NumericRef RSV,NumericRef KValue,NumericRef DValue,NumericRef JValue) //求N周期KDJ
Bool LinearReg(NumericSeries Price,Numeric Length,Numeric TgtBar,NumericRef LRSlope,NumericRef LRAngle,NumericRef LRIntercept,NumericRef LRValue) //求线性回归
Numeric LowD(Numeric daysAgo=2) //求N天前的最低价
Numeric Lowest(NumericSeries Price=0,Numeric Length=5) //求最低
Numeric LowestBar(NumericSeries Price=0,Numeric Length=5) //求最低只出现的Bar
Numeric LowestFC(NumericSeries Price=1,Numeric Length=10) //快速计算最低
Numeric MA(NumericSeries Price,Numeric Length=10) //求平均，等价于Average
Numeric NthCon(Bool Con=False,Numeric N=1) //第N个满足条件的Bar距当前的Bar数目
Numeric NthExtremes(NumericSeries Price,Numeric Length,Numeric N,Bool bMax,NumericRef NthExtremeBar) //求N极值
Numeric NthHigher(NumericSeries Price=1,Numeric Length=10,Numeric N=3) //求第N高
Numeric NthHigherBar(NumericSeries Price=1,Numeric Length=10,Numeric N=3) //求第N高出现的Bar
Numeric NthLower(NumericSeries Price=1,Numeric Length=10,Numeric N=3) //求第N低
Numeric NthLowerBar(NumericSeries Price=1,Numeric Length=10,Numeric N=3) //求第N低出现的Bar
Numeric OpenD(Numeric daysAgo=2) //求N天前的开盘价
Numeric OpenIntD(Numeric daysAgo=2) //求N天前的持仓量
Bool ParabolicSAR(Numeric AfStep,Numeric AfLimit,NumericRef oParClose,NumericRef oParOpen,NumericRef oPosition,NumericRef oTransition) //求抛物线转向
Numeric PercentChange(NumericSeries Price=1,Numeric Length=10) //求涨跌幅
Numeric PercentR(Numeric Length=10) //求威廉指标
Bool Pivot(NumericSeries Price,Numeric Length,Numeric LeftStrength,Numeric RightStrength,Numeric Instance,Numeric HiLo,NumericRef PivotPrice,NumericRef PivotBar) //求转折
Numeric RateOfChange(NumericSeries Price=1,Numeric Length=10) //求变动率
Numeric REF(NumericSeries Price,Integer N) //求前N周期的值
Numeric SAverage(Numeric Price_series=1, Numeric Length=10) //平滑移动平均
Numeric SMA(NumericSeries Price,Numeric Length=10,Numeric Weight=1) //求移动平均
Numeric StandardDev(NumericSeries Price=1,Numeric Length=10,Numeric DataType=1) //求标准差
Numeric Summation(NumericSeries Price,Numeric Length=10) //求和
Numeric SummationFC(NumericSeries Price,Numeric Length=10) //快速求和
Numeric SwingHigh(Numeric Instance=1,NumericSeries Price=1,Numeric Strength=1,Numeric Length=10) //求波峰点
Numeric SwingLow(Numeric Instance=1,NumericSeries Price=1,Numeric Strength=1,Numeric Length=10) //求波谷点
Numeric TodayAvgPrice() //计算当日均价
Numeric TrueHigh() //求真实高点
Numeric TrueLow() //求真实低点
Numeric TrueRange() //求真实范围
Numeric VariancePS(NumericSeries Price=1,Numeric Length=10,Numeric DataType=1) //求估计方差
Numeric VolD(Numeric daysAgo=2) //求N天前的成交量
Numeric WAverage(NumericSeries Price,Numeric Length=10) //求权重平均
Numeric XAverage(NumericSeries Price=10,Numeric Length=10) //求指数平均
Numeric MACD(NumericSeries Price,NumericRef DIFF,NumericRef DEA,Integer prdShort=12,Integer prdLong=26,Integer Length=9) //求指数平滑异同平均
Numeric EMA(NumericSeries Price=10,Integer Length=10) //求指数平均
Numeric RSI(NumericSeries Price=10,Integer N=12) //返回相对强弱指标值
Integer GetZigZagPoints(NumericArrayRef arrPointIdx,NumericArrayRef arrPointPrie,NumericArrayRef arrPointType,Integer step=5)//取得折线顶点低点数据

#绘图函数-sys
Bool ColorBar(Integer Color,Integer BarsBack=0) //变色K线,设置K线颜色
Bool PartLine(String Name,Integer nIdx,Numeric fPrice,Integer nIdx2, Numeric fPrice2,Integer Color=-1,Integer nWidth=1)  //绘制一个斜线段
Integer PlotColorLine(String name,Numeric price,Integer clr,Integer width=1,Integer barsBack=0) //绘制彩色指标线
Numeric PlotNumeric(String Name,Numeric Number,Integer Color=-1,Integer BarsBack=0) //绘制指标线
Numeric PlotStickLine(String Name,Numeric Number,Numeric Origin,Integer Color=-1, Integer BarsBack=0)		//绘制竖线段
Bool PlotVertLine(Integer BarsBack=0) //绘制一条竖线
Bool PlotText(Numeric Value,String text,Integer BarsBack=0,Integer Color=-1) //绘制一个字符串
Bool PlotIcon(Numeric Price,Integer Icon=0,Integer BarsBack=0,Integer Color=-1) //绘制一个系统图标
Bool PlotDot(String Name,Numeric Price,Integer Type,Integer Color=-1,Integer BarsBack=0)  //绘制一个点
Bool PlotBar(String Name, Numeric Number1,Numeric Origin,Bool bEmpty=True,Integer clr=-1,Integer BarsBack=0)	 //绘制一个柱子
Bool SetOwnAxis(String name)	//设置一个指标线为自由坐标
Bool SetShapeStyle(String name, Integer width, Integer lineType=0,Bool bVisible=True) //设置画线宽度,样式,是否显示等属性
Bool UnPlot(String Name,Integer BarsBack=0)  //取消PlotNumeirc所绘制的线
Bool UnPlotText(Integer BarsBack=0) //取消PlotText绘制的字符串
Bool UnPlotIcon(Integer BarsBack=0) //取消绘制的图标
Bool UnPlotDot(String Name, Integer BarsBack=0) //取消绘制的点
Bool UnPlotPartLine(String Name,Integer nIdx) //取消绘制的斜线段
Bool UnPlotVertLine(Integer BarsBack=0) //取消绘制的竖线
Integer ReName(String oldName,String newName)	//重命名指标线名称
Integer SetPect(String name,Integer pect) //设置指标线小数点位数
Integer PlotHorzLine(Numeric price,Integer color,Integer BarsBack=0)	//画横线
Integer UnPlotHorzLine(Integer BarsBack=0)				//取消画横线
Integer FillRange(String name,Numeric price1,Numeric price2,Integer color,Integer barsBack=0) //填充区域
#颜色函数-sys
Integer ColorUp()		//上涨色
Integer ColorDown()		//下跌色
Integer ColorBk()      //背景色
Integer DefaultColor()   //默认颜色
Integer Rgb(Integer R,Integer G,Integer B) //自定义rgb颜色
Integer Black() //黑色
Integer Blue()  //蓝色
Integer Cyan()  //青色
Integer DarkBrown()  //茶色
Integer DarkCyan()    //深青色
Integer DarkGray()    //深灰色
Integer DarkGreen()   //深绿色
Integer DarkMagenta()  //深洋红色
Integer DarkRed()      //深红色
Integer Green()   //绿色
Integer LightGray()   //浅灰色
Integer Magenta()    //洋红色
Integer Red()      //红色
Integer White()    //白色
Integer Yellow()  //黄色
#数学函数-sys
Numeric Abs(Numeric num)  //返回参数的绝对值
Numeric Acos(Numeric num) //返回数字的反余弦值
Numeric Asin(Numeric num) //返回参数的反正弦值
Numeric Atan(Numeric num) //返回参数的反正切值
Numeric Atan2(Numeric X,Numeric Y) //返回给定的X及Y坐标值的反正切值
Integer Combin(Integer num,Integer num2) //计算从给定数目的对象集合中提取若干对象的组合数
Numeric Cos(Numeric num) //返回给定角度的余弦值
Numeric Cosh(Numeric num) //返回参数的双曲余弦值
Numeric Ctan(Numeric num) //返回给定角度的余切值
Integer Ceil(Numeric num) //返回不小于num的最小整数
Numeric Exp(Numeric num) //返回e的n次幂
Numeric Fact(Numeric num) //返回数的阶乘
Integer Floor(Numeric num) //返回不大于num的最大整数
Numeric FracPart(Numeric num) //返回一个数的小数部分
Integer IntPart(Numeric num) //返回一个数的整数部分
Numeric Ln(Numeric num) //返回一个数的自然对数
Numeric Log(Numeric Number,Numeric Base) //按所指定的底数，返回一个数的对数
Integer Mod(Integer Number,Integer Divisor) //返回两数相除的余数
Numeric Max(Numeric Value1,Numeric Value2) //求最大值
Numeric Min(Numeric Value1,Numeric Value2) //求最小值
Numeric Neg(Numeric num) //返回参数的负绝对值
Numeric Pi() //返回数字3.1415926535898
Numeric Power(Numeric num,Numeric powerNum) //返回给定数字的乘幂
Integer Rand(Integer Bottom,Integer Top) //返回位于两个指定数之间的一个随机整数
Numeric Round(Numeric Number,Integer Num_digits) //返回某个数字按指定位数舍入后的数字
Integer Sign(Numeric num) //返回数字的符号
Numeric Sin(Numeric num) //返回给定角度的正弦值
Numeric Sinh(Numeric num) //返回某一数字的双曲正弦值
Numeric Sqr(Numeric num) //返回参数的平方
Numeric Sqrt(Numeric num) //返回正平方根
Numeric Tan(Numeric num) //返回给定角度的正切值
Numeric Tanh(Numeric num) //返回某一数字的双曲正切值
#时间函数-sys
Numeric CurrentTime()  //返回当前时间
Numeric CurrentDate()  //返回当前日期
Numeric DateAdd(Numeric date,Integer Number) //返回增加指定天数后的日期
Integer DateDiff(Numeric date1,Numeric date2) //返回两个日期之间的日期间隔
String DateTimeToString(Numeric dtDateTime) //将日期时间值转化为字符串类型
String DateToString(Integer nDate) //将日期值转化为字符串类型
NumericSeries Day() //获得当前Bar的日信息
Integer DayFromDateTime(Numeric x) //获取输入日期时间的日信息
Integer Friday() //获得星期五的值
Numeric GetTickCount()	//获得客户端自开机以来经历的毫秒数
NumericSeries Hour()   //获得当前Bar的小时信息
Integer HourFromDateTime(Numeric x) //获取输入日期时间的小时信息
Integer MakeDate(Integer nYear,Integer nMonth,Integer nDay) //将参数生成日期值
Numeric MakeDateTime(Integer nDate,Numeric fTime) //将参数生成日期时间值
Numeric MakeTime(Integer nHour,Integer nMinute,Integer nSecond) //将参数生成时间值
NumericSeries Minute() //获得当前Bar的分钟信息
Integer MinuteFromDateTime(Numeric x) //获取输入日期时间的分钟信息
Integer Monday() //获得星期一的值
NumericSeries Month() //获得当前Bar的月信息
Integer MonthFromDateTime(Numeric x) //获取输入日期时间的月信息
Integer Saturday() //获得星期六的值
NumericSeries Second() //获得当前Bar的秒信息
Integer SecondFromDateTime(Numeric x) //获取输入日期时间的秒信息
Integer StringToDate(String str) //将字符串YYYY-MM-DD转化为日期
Numeric StringToDateTime(String str) //将字符串YYYY-MM-DD HH:MM:SS转化为日期时间
Numeric StringToTime(String str) //将字符串HH:MM:SS转化为时间
Integer Sunday() //获得星期日的值
Numeric SystemDateTime() //获取当前日期时间
Integer Thursday() //获取星期四的值
Integer TimeDiff(Numeric Time1,Numeric Time2)   //返回两个日期之间的间隔秒数
Numeric TimeAdd(Numeric Time1, Integer addV) //返回增加指定秒数后的日期
String TimeToString(Numeric fTime) //将时间值转化为字符串类型
Integer Tuesday() //获取星期二的值
Integer Wednesday() //获取星期三的值
Integer Weekday()  //获得当前Bar的周信息
Integer WeekdayFromDateTime(Numeric x) //获取输入日期时间的周信息
NumericSeries Year() //获得当前Bar的年信息
Integer YearFromDateTime(Numeric x) //获取输入日期时间的年信息
#字符串函数-sys
Bool Exact(String String1,String String2) //判断两字符串是否完全相等，区分大小写
String Left(String str,Integer lCount) //返回前lCount长度的字符串
Integer Len(String str) //返回字符串的长度
String Lower(String str) //转化为小写
String Mid(String str,Integer lFirst,Integer lCount=0) //返回从lFirst开始共lCount个字符组成的字符串
String Right(String str,Integer lCount) //返回字符串右端指定长度的字符串
String Text(Integer value)  //将数字转化为字符串
String Text(Numeric value,Integer Prec=6)  //将数字转化为字符串
String Trim(String str) //去除字符串两端的空格
String Upper(String str)  //转为大写
Numeric Value(String str)   //将字符串转化为数字
Numeric FindSubString(String main, String sub)   //查找字符串

#数组函数重载-hide
NumericArray ArrInsert(NumericArray arr,Integer pos,NumericArray val) //在数组指定位置插入数据
StringArray ArrInsert(StringArray arr,Integer pos,String val) //在数组指定位置插入数据
StringArray ArrInsert(StringArray arr,Integer pos,StringArray arr2) //在数组指定位置插入数据
StringArray ArrAdd(StringArray arr,String str)  //添加数据到数组末端
StringArray ArrRemove(StringArray arr,const Integer pos,const Integer count=1) //从数组中移除元素
StringArray ArrSort(StringArray arr, Bool bUp=True) //将数组排序
Integer ArrPrint(StringArray arr, Integer Prec=6) //将数组输出到调试窗口
StringArray ArrSub(StringArray arr,Integer pos,Integer count) //取得数组的子集
Integer ArrLength(StringArray arr) //获得数组的长度
StringArray ArrClear(StringArray arr) //清空数组
Integer ArrFind(StringArray arr,String num,Integer start=0,Integer mode=0) //查找数组,返回第一个满足条件的索引值 
StringArray ToArray(StringSeries src) //将序列变量复制到数组
StringArray ArrRevers(StringArray arr) //将数组反转
StringArray ArrSetSize(StringArray arr,Integer size,String str="") //设置数组的大小，以str填充

#数组函数-sys
NumericArray ArrAdd(NumericArray arr,Numeric num)  //添加数据到数组末端
NumericArray ArrInsert(NumericArray arr,Integer pos,Numeric val) //在数组指定位置插入数据
NumericArray ArrRemove(NumericArray arr,const Integer pos,const Integer count=1) //从数组中移除元素
NumericArray ArrSort(NumericArray arr, Bool bUp=True) //将数组排序
Integer ArrPrint(NumericArray arr, Integer Prec=6) //将数组输出到调试窗口
NumericArray ArrSub(NumericArray arr,Integer pos,Integer count) //取得数组的子集
Integer ArrLength(NumericArray arr) //获得数组的长度
NumericArray ArrClear(NumericArray arr) //清空数组
Integer ArrFind(NumericArray arr,Numeric num,Integer start=0,Integer mode=0) //查找数组,返回第一个满足条件的索引值 
NumericArray ToArray(NumericSeries src) //将序列变量复制到数组
NumericArray ArrRevers(NumericArray arr) //将数组反转
NumericArray ArrSetSize(NumericArray arr,Integer size,Numeric value=0) //设置数组的大小，以value填充
Numeric iMA(NumericArray Arr,Numeric Length=10,Numeric Pos=0) //求平均
Numeric iHHV(NumericArray arr,Numeric length=10,Numeric pos=0) //求最高
Numeric iKDJ(Numeric N,NumericArray arrClose,NumericArray arrHigh,NumericArray arrLow,NumericRef KValue,NumericRef DValue,NumericRef JValue,Numeric Pos=0) //求数组的KDJ
Numeric iLLV(NumericArray arr,Numeric length=10,Numeric pos=0) //求最低
Numeric iEMA(NumericArray arr,Numeric length=10,Numeric pos=0) //求指数平均
Numeric iMACD(NumericArray Arr,NumericRef iDIF,NumericRef iDEA,Integer prdShort=12,Integer prdLong=26,Integer M=9,Integer Pos=0) //求指数平滑异同平均
Numeric iSMA(NumericArray Arr,Integer N=10,Numeric M=1,Integer Pos=0) //求数组的权重平均值
Numeric iRSI(NumericArray Arr,Integer N=12,Integer Pos=0) //求数组的相对强弱指数
Numeric iVariancePS(NumericArray& Arr, const Numeric& Length = 10, const Numeric& DataType = 1)  //求数组估计方差
Numeric iStandardDev(NumericArray& Arr, const Numeric& Length = 10, const Numeric& DataType = 1) //求数组标准差
#枚举函数-sys
Enum Enum_Period_Default()	//周期类型_当前图表周期
Enum Enum_Period_Tick()		//周期类型_分笔
Enum Enum_Period_Dyna()		//周期类型_分时
Enum Enum_Period_Second()	//周期类型_秒线
Enum Enum_Period_Min()		//周期类型_分钟
Enum Enum_Period_Hour()		//周期类型_小时
Enum Enum_Period_Day()		//周期类型_日线
Enum Enum_Period_Week()		//周期类型_周线
Enum Enum_Period_Month()	//周期类型_月线
Enum Enum_Period_Year()		//周期类型_年线
Enum Enum_Period_DayX()		//周期类型_多日
Enum Enum_Data_Close()		//历史数据种类_收盘价
Enum Enum_Data_Open()		//历史数据种类_开盘价
Enum Enum_Data_High()		//历史数据种类_最高价
Enum Enum_Data_Low()		//历史数据种类_最低价
Enum Enum_Data_Vol()		//历史数据种类_成交量
Enum Enum_Data_Opi()		//历史数据种类_持仓量
Enum Enum_Data_Time()		//历史数据种类_日期时间
Enum Enum_Entry()  //开仓
Enum Enum_Exit()   //平仓
Enum Enum_ExitToday()  //平今
Enum Enum_Buy() //买入
Enum Enum_Sell() //卖出
Enum Enum Enum_Sended() //已发送
Enum Enum_Queued()  //已排队
Enum Enum_PartFilled()  //部分成交
Enum Enum_Filled()  //完全成交
Enum Enum_Canceled()  //已撤单
Enum Enum_PartCanceled()  //已撤余单
Enum Enum_Fail()  //指令失败
#期权函数-sys
Numeric O_Volatility(Integer nWindow=60) //历史波动率(可选参数N为窗口周期,默认60)
Numeric O_ImpliedVolatility() //隐含波动率
String O_OptionTarget() //期权标的合约key
String O_ReverseContract() //反手合约key
#其他函数-sys
Bool Alert(String info,Integer size=3, Integer Color=0, Bool bBeep=True) //弹出警告
Numeric Commentary(String txt) //向调试窗口输出一行字符串
Bool Filter(Bool Con,Numeric N) //条件过滤
String GetMacAddr()		//返回网卡Mac地址
Numeric Print(String word)   //向调试窗口输出一个字符串
Numeric Print(Nuemric num,Integer prec=6) //向调试窗口输出一个数值
Numeric Print(Integer num) //向调试窗口输出一个整数
String InvalidString() //返回无效字符串的值""
Integer InvalidInteger() //返回无效整数
Numeric InvalidNumeric() //返回无效数字
Numeric ValueWhen(Bool Condition,Numeric Data) //返回最后一次满足条件的值
Bool IsTradeAllowed() //返回是否允许自动交易
Bool FileAppend(String strPath,String strText) //向文件追加一行文字
Bool FileDelete(String strPath) //删除文件
Numeric IIF(Bool Conditon,Numeric TrueValue,Numeric FalseValue) //根据逻辑真假值返回不同的数值
String IIFString(Bool Conditon,String TrueValue,String FalseValue) //根据逻辑真假值返回不同的字符串
Bool SetGlobalVar(Integer nIndex,Numeric fVal) //设置一个全局变量
Integer Sleep(int n) //线程暂停n毫秒
Bool Sound(Integer idx)  //播放一个声音     
Numeric GetGlobalVar(Integer nIndex) //读取一个全局变量的值
String GetProfileString(String strSection,String strKey) //读取公式信息文件指定块中的键名对应的字符串
String GetProfileString2File(String strPath,String strSection,String strKey) //读取公式信息文件指定块中的键名对应的字符串
Bool SetProfileString(String strSection,String strKey,String strValue) //把给定的键名及其值写入到公式信息文件的相应块中
Bool SetProfileString2File(String strPath,String strSection,String strKey,String strValue) //把给定的键名及其值写入到公式信息文件的相应块中
String AppPath()	//获得主程序目录
Integer SetFmlVipLevel(String strLevel) //设置策略用户等级
Integer SetFmlPassword(String passWord) //设置策略访问密码
Integer SetFmlUserGroupID(String groupId) //设置策略访问用户组
Integer SetFmlExpiredDate(String yyyymmdd) //设置策略过期日期
Integer GetPlatformVersion()		//获得策略平台版本号
Bool IsAuthCheckEnable()		//返回策略平台是否支持策略授权
Integer SelectStock()		//产生选股信号
Bool SetFmlNotify(String info)//设置策略预警信息
```
