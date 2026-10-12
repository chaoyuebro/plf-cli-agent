# 策略案例库（真实可用源码）

本文件收录盘立方宽语言的**真实策略案例**，全部来自官方策略范例集（`60个策略规范版.txt`）
与官方宽语言案例（`盘立方宽语言案例5/6.txt`）。用途：Agent 生成新公式时**优先从中挑选结构
最接近的骨架改造**，而不是从零手写。

配套文件：
- 语法与函数签名 → `formula-functions.md`
- K 线形态类指标案例 → `examples-indicators.md`

## 选用方法

1. 先在下面的"案例索引"里按**类别**找到最接近的目标。
2. 打开对应的"骨架"，照抄结构（`Params` / `GlobalVars` / `Vars` / `Begin ... End`）。
3. 只改信号条件与参数，**不要改动结构骨架**——这是最容易被编译器接受的部分。
4. 需要未在本文件出现的函数时，先回 `formula-functions.md` 核对签名。

## 案例索引

| # | 简称 | 类别 | 核心逻辑 | 关键函数 |
| --- | --- | --- | --- | --- |
| 1 | `TrendBreakout_MM` | 趋势突破 + 资金管理 + 跨周期 | 日线均线定方向，短周期突破开仓，按单笔最大亏损计算手数，跟踪止损 | `HisData` `iMA` `HighestFC` `IntPart` `MarketPosition` |
| 2 | `RangeBreakout` | 区间紧凑突破 | 低波动横盘后突破区间上沿 | `HighestFC` `PlotText` `PlotDot` `SetStopPoint` |
| 3 | 阶梯突破 | 多条件确认突破 | 连续两根突破 + 收盘两连涨 | `&&` `BoolSeries` `ColorBar` |
| 4 | 昨日区间突破 | 单条件突破（二选一阈值） | 突破昨日最高 或 昨收+昨日振幅 | `If-Else` `PlotNumeric` |
| 5 | `Donchian_Breakout_Signal` | 通道突破 + 趋势过滤 | 唐奇安通道突破 + EMA 过滤 | `Highest` `EMA` |
| 6 | `MA_Squeeze_Break_V3` | 均线粘合突破 | 均线持续粘合后价格突破束缚 | `MA` `Abs` |
| 7 | `K_Hammer` / `K_DarkCloud` / `K_Fractal` | 反转形态 | 锤子线 / 乌云盖顶 / 顶底分型 | `Abs` `Max` `Min` |
| 8 | `OpenThreeLineStrategy` | 开盘三线 | 以开盘价为基准的三线突破 | `Open` `TickPrice` |
| 9 | 跨周期画线 | 跨周期取数 | 分钟图上画昨日高低点横线 | `HisData` `PlotHorzLine` `UnPlotHorzLine` |

---

## 1. `TrendBreakout_MM` — 趋势突破资金管理策略（推荐作为端到端样板）

**为什么是样板**：这是唯一一个同时覆盖"跨周期取数 + 序列变量 + 双向下单 + 跟踪止损 +
按风险计算仓位"的官方案例，结构完整、注释清晰，是生成复杂策略时的最佳出发点。

**适用场景**：需要方向过滤 + 突破入场 + 资金管理的双向策略。

**结构要点**

- 跨周期数据放在 `GlobalVars` 的 `NumericArray`（日线三价）。
- 序列变量放 `GlobalVars`：`NumericSeries DailyMA / ShortHigh / ShortLow / LongHigh / LongLow / StopLossPrice / EntryPriceCustom`。
- 信号用 `BoolSeries` 放 `Vars`，开仓前先算信号、再算手数、最后统一执行。
- 顺序上**先算 `PositionSize`、后执行下单**，避免在 `If` 里嵌套资金计算。
- 用 `MarketPosition` 判断持仓方向：`0` 空仓 / `1` 多头 / `-1` 空头。
- 用 `and` 连接多条件（与 `&&` 等价）。

**精简骨架**

```text
//------------------------------------------------------------------------
// 简称: TrendBreakout_MM
// 名称: 趋势突破资金管理策略
// 类别: 交易指令
// 类型: 用户应用
//------------------------------------------------------------------------
Params
    Integer DayMAPeriod(10);          // 日线均线周期
    Integer ShortPeriod(50);          // 短周期
    Integer LongPeriod(100);          // 长周期
    Integer TradeEnable(1);           // 交易开关：1-启用，0-禁用
    Integer SoundAlert(1);            // 语音提醒：1-开启，0-关闭
    Numeric MaxLossPerTrade(1000);    // 单笔最大亏损金额

GlobalVars
    NumericArray DailyCloseArray;
    NumericArray DailyHighArray;
    NumericArray DailyLowArray;
    NumericSeries DailyMA;
    NumericSeries ShortHigh;
    NumericSeries ShortLow;
    NumericSeries LongHigh;
    NumericSeries LongLow;
    NumericSeries StopLossPrice;
    NumericSeries EntryPriceCustom;

Vars
    BoolSeries LongCondition(False);
    BoolSeries ShortCondition(False);
    Numeric PositionSize;
    Numeric RiskPerShare;

Begin
    // 1) 跨周期日线数据 + 日线均线
    DailyCloseArray = HisData(Enum_Data_Close, Enum_Period_Day, 1);
    DailyHighArray  = HisData(Enum_Data_High,  Enum_Period_Day, 1);
    DailyLowArray   = HisData(Enum_Data_Low,   Enum_Period_Day, 1);
    DailyMA = iMA(DailyCloseArray, DayMAPeriod);
    PlotNumeric("DailyMA", DailyMA, Blue);

    // 2) 短/长周期高低点（用 [1] 避开当前未完成 K 线）
    ShortHigh = HighestFC(High[1], ShortPeriod);
    ShortLow  = LowestFC(Low[1],  ShortPeriod);
    LongHigh  = HighestFC(High[1], LongPeriod);
    LongLow   = LowestFC(Low[1],  LongPeriod);

    // 3) 信号
    LongCondition  = (Close[1] > Open[1]) and (Close[1] > ShortHigh[1]) and (ShortLow[1] > LongLow[1]);
    ShortCondition = (Close[1] < Open[1]) and (Close[1] < ShortLow[1])  and (ShortHigh[1] < LongHigh[1]);

    // 4) 资金管理：按单笔最大亏损算手数
    If (LongCondition)
    {
        RiskPerShare = Open - ShortLow[1];
        PositionSize = IntPart(MaxLossPerTrade / (RiskPerShare * BigPointValue * ContractUnit));
        PositionSize = Max(PositionSize, 1);              // 最少 1 手
    }
    Else If (ShortCondition)
    {
        RiskPerShare = ShortHigh[1] - Open;
        PositionSize = IntPart(MaxLossPerTrade / (RiskPerShare * BigPointValue * ContractUnit));
        PositionSize = Max(PositionSize, 1);
    }

    // 5) 执行
    If (TradeEnable == 1)
    {
        If (MarketPosition == 0)
        {
            If (LongCondition and Open > DailyMA)
            {
                Buy(PositionSize, Open);
                StopLossPrice = ShortLow[1];
                EntryPriceCustom = Open;
                If (SoundAlert == 1)
                    Alert(SymbolName + "多单开仓");
            }
            Else If (ShortCondition and Open < DailyMA)
            {
                SellShort(PositionSize, Open);
                StopLossPrice = ShortHigh[1];
                EntryPriceCustom = Open;
                If (SoundAlert == 1)
                    Alert(SymbolName + "空单开仓");
            }
        }

        If (MarketPosition == 1)              // 多头：跟踪止损
        {
            StopLossPrice = Max(StopLossPrice, ShortLow[1]);
            PartLine("ShortStop", 0, ShortLow, 1, ShortLow[1], Red, 2);
            If (Low <= StopLossPrice)
            {
                Sell(0, Max(StopLossPrice, Low));   // 0 = 全部平仓
                If (SoundAlert == 1)
                    Alert(SymbolName + "多单止损平仓");
            }
        }
        Else If (MarketPosition == -1)        // 空头：跟踪止损
        {
            StopLossPrice = Min(StopLossPrice, ShortHigh[1]);
            PartLine("ShortStop", 0, ShortHigh, 1, ShortHigh[1], Green, 2);
            If (High >= StopLossPrice)
            {
                BuyToCover(0, Min(StopLossPrice, High));
                If (SoundAlert == 1)
                    Alert(SymbolName + "空单止损平仓");
            }
        }
    }
End
```

**可复用的关键模式**

| 模式 | 写法 |
| --- | --- |
| 取日线数据 | `HisData(Enum_Data_Close, Enum_Period_Day, 1)` |
| 日线均线 | `iMA(DailyCloseArray, DayMAPeriod)`（数组必须用 `iMA`） |
| 避开未来函数 | 用 `High[1]` / `Close[1]` 参与计算 |
| 手数计算 | `IntPart(最大亏损 / (风险点数 * BigPointValue * ContractUnit))` 再 `Max(...,1)` |
| 全部平仓 | `Sell(0, price)` / `BuyToCover(0, price)`（数量 0 = 清仓） |
| 跟踪止损 | `StopLossPrice = Max(StopLossPrice, 新的支撑位);` |

---

## 2. `RangeBreakout` — 区间紧凑突破识别系统

**适用场景**：低波动横盘后的首次突破；波动率越小信号越可靠。

**核心逻辑**：先用 `HighestFC`/`LowestFC` 求前 N 根（不含当前）的区间上下沿，
再要求"区间波动率 < 阈值"且"当前收盘突破上沿"，两条件同时成立才算突破。

**骨架**

```text
//------------------------------------------------------------------------
// 简称: RangeBreakout
// 名称: 区间紧凑突破识别系统
// 类别: 技术指标
//------------------------------------------------------------------------
Params
    Integer RangePeriod(20);          // 区间观察周期
    Numeric RangeThreshold(0.05);     // 区间波动阈值(5%)
    Integer AlertSwitch(1);           // 提醒开关

GlobalVars
    Integer lastBar(0);               // 控制单根 K 线只提醒一次

Vars
    NumericSeries RangeHigh;
    NumericSeries RangeLow;
    Numeric RangeWidth;
    Numeric RangeRatio;
    BoolSeries BreakoutSignal;

Begin
    RangeHigh  = HighestFC(High[1], RangePeriod);
    RangeLow   = LowestFC(Low[1],  RangePeriod);
    RangeWidth = RangeHigh - RangeLow;
    RangeRatio = RangeWidth / RangeLow;

    BreakoutSignal = (RangeRatio < RangeThreshold) && (Close > RangeHigh);

    If (BreakoutSignal)
    {
        PlotText(High, "区间突破", 0, Red);
        PlotDot("BreakoutSignal", Low, 1, Red);
        PlotNumeric("区间上沿", RangeHigh, RGB(255,215,0));
        PlotNumeric("区间下沿", RangeLow,  RGB(255,215,0));

        Buy(1, Open);
        SetStopPoint(20, 1, 1);   // 20 跳止损，对盘价
        SetWinPoint(40, 1, 1);    // 40 跳止盈，对盘价

        If (AlertSwitch == 1)
        {
            Alert("区间紧凑突破信号出现");
        }
    }
End
```

**要点**：`GlobalVars` 里 `lastBar` 是"每根 K 线只触发一次"的常用哨兵变量；
`SetStopPoint` / `SetWinPoint` 的 `nPriceType` 用 `1`（对盘价）时 `nAddTick` 才有效。

---

## 3. 阶梯突破 — 多条件确认突破

**适用场景**：需要"连续确认"来过滤假突破。核心是"连续两根 K 线突破 + 收盘价两连涨"。

**骨架（信号部分）**

```text
Params
    Integer BreakoutPeriod(20);

Vars
    NumericSeries High_N;
    BoolSeries BreakSignael;
    Bool ContinueRiseSignal;
    Bool LadderBreakSignal;

Begin
    High_N = Highest(High[1], BreakoutPeriod);       // 只取已完成 K 线，无未来函数

    BreakSignal        = High > High_N;
    ContinueRiseSignal = Close > Close[1] && Close[1] > Close[2];

    LadderBreakSignal  = BreakSignal && BreakSignal[1] && ContinueRiseSignal;

    If (LadderBreakSignal)
    {
        ColorBar(Yellow);            // 触发信号的 K 线整体标黄
        Buy(1, Open);
        SetStopPoint(20, 1, 1);
    }
End
```

**要点**：`BreakSignal[1]` 要求信号变量声明为 `BoolSeries`（只有序列类型才能 `[n]` 回溯）；
`&&` 可连续串联。

---

## 4. 昨日区间突破 — 单条件突破 + 阈值二选一

**适用场景**：日内策略以昨日区间为参考；用 `Params` 开关切换两种阈值口径。

**骨架**

```text
Params
    Bool UseAmplitude(true);     // true=用昨收+振幅，false=用昨日最高价

Vars
    Numeric Yesterday_High;
    Numeric Yesterday_Low;
    Numeric Yesterday_Close;
    Numeric Yesterday_Amplitude;
    Numeric BreakoutLevel;
    Bool YesterdayBreakSignal;

Begin
    Yesterday_High      = High[1];
    Yesterday_Low       = Low[1];
    Yesterday_Close     = Close[1];
    Yesterday_Amplitude = Yesterday_High - Yesterday_Low;

    If (UseAmplitude)
    {
        BreakoutLevel = Yesterday_Close + Yesterday_Amplitude;
    }
    Else
    {
        BreakoutLevel = Yesterday_High;
    }

    YesterdayBreakSignal = Close > BreakoutLevel;

    If (YesterdayBreakSignal)
    {
        PlotText(Low - 2*TickPrice, "昨日区间突破", 0, RGB(0,150,255));
        PlotIcon(Close, 1, 1);
        Buy(1, Open);
        SetStopPoint(20, 1, 1);
        SetWinPoint(40, 1, 1);
    }

    PlotNumeric("突破阈值", BreakoutLevel, RGB(150,0,150));
End
```

**要点**：`Bool` 参数可以直接当 `If` 条件用，不必写 `== true`；
`PlotText` 的位置用 `Low - 2*TickPrice` 把标注压到 K 线下方。

---

## 5. `Donchian_Breakout_Signal` — 唐奇安通道突破 + EMA 趋势过滤

**适用场景**：经典海龟式突破，加一条 EMA 做方向过滤。

**骨架（信号部分）**

```text
Params
    Integer ChannelPeriod(20);
    Integer EMAPeriod(60);

Vars
    NumericSeries UpperBand;
    NumericSeries LowerBand;
    NumericSeries TrendEMA;
    Bool LongSignal;
    Bool ShortSignal;

Begin
    UpperBand = REF(Highest(High, ChannelPeriod), 1);   // 必须 REF 到前一根
    LowerBand = REF(Lowest(Low, ChannelPeriod), 1);
    TrendEMA  = EMA(Close, EMAPeriod);

    LongSignal  = Close > UpperBand && Close > TrendEMA;
    ShortSignal = Close < LowerBand && Close < TrendEMA;

    If (LongSignal)
    {
        PlotText(Low - 2*TickPrice, "向上突破", 0, Red);
        PlotIcon(Close, 3, 0);          // 上箭头
        Buy(1, Open);
    }
    Else If (ShortSignal)
    {
        PlotText(High + 2*TickPrice, "向下突破", 0, Green);
        PlotIcon(Close, 4, 0);          // 下箭头
        SellShort(1, Open);
    }

    PlotNumeric("上轨", UpperBand, RGB(255,215,0));
    PlotNumeric("下轨", LowerBand, RGB(255,215,0));
End
```

**要点**：`Highest(High, N)` **含当前 Bar**，直接用 `Close` 无法突破自己，必须 `REF(...,1)`；
`PlotIcon` 的上/下箭头是 `3` / `4`。

---

## 6. 均线粘合突破（`MA_Squeeze_Break_V3` 类）

**适用场景**：均线长时间粘合（蓄力）后价格突破束缚。

**骨架（信号部分）**

```text
Params
    Integer ShortMA(10);
    Integer MidMA(20);
    Integer LongMA(60);
    Numeric SqueezeRatio(0.01);      // 粘合阈值 1%

Vars
    NumericSeries MA1;
    NumericSeries MA2;
    NumericSeries MA3;
    Numeric MAMax;
    Numeric MAMin;
    Bool Squeeze;
    Bool BreakOut;

Begin
    MA1 = MA(Close, ShortMA);
    MA2 = MA(Close, MidMA);
    MA3 = MA(Close, LongMA);

    MAMax = Max(MA1, Max(MA2, MA3));
    MAMin = Min(MA1, Min(MA2, MA3));
    Squeeze = (MAMax - MAMin) / MAMin < SqueezeRatio;   // 三线粘合

    BreakOut = Squeeze[1] && Close > MAMax[1];          // 前一根粘合 + 本根向上突破

    If (BreakOut)
    {
        ColorBar(Red);
        Buy(1, Open);
        SetStopPoint(20, 1, 1);
    }

    PlotNumeric("MA1", MA1, Red);
    PlotNumeric("MA2", MA2, Green);
    PlotNumeric("MA3", MA3, Blue);
End
```

**要点**：`Max` / `Min` 只接受两个参数，多值比较要嵌套；`Squeeze` 声明为 `BoolSeries`
才能用 `Squeeze[1]`。

---

## 7. 反转形态类（锤子线 / 乌云盖顶 / 顶底分型）

**适用场景**：单根或两根 K 线的形态识别，通常只做信号标注（不自动下单），
是**最适合编译演示**的一类——不触达交易接口。

**锤子线（看涨）骨架**

```text
Params
    Numeric BodyRatio(0.3);      // 实体/全幅 上限
    Numeric ShadowRatio(2.0);    // 下影/实体 下限

Vars
    Numeric Body;
    Numeric FullRange;
    Numeric LowerShadow;
    Numeric UpperShadow;
    Bool Hammer;

Begin
    Body        = Abs(Close - Open);
    FullRange   = High - Low;
    LowerShadow = Min(Open, Close) - Low;
    UpperShadow = High - Max(Open, Close);

    Hammer = (Body / FullRange < BodyRatio)          // 实体很小
          && (LowerShadow > Body * ShadowRatio)      // 下影很长
          && (UpperShadow < Body)                    // 上影很短
          && (Close > Open);                         // 收阳更可靠

    If (Hammer)
    {
        PlotText(Low - 2*TickPrice, "锤子线", 0, Red);
        PlotIcon(Low, 3, 0);
    }
End
```

**乌云盖顶（看跌）骨架**

```text
Vars
    Bool DarkCloud;

Begin
    // 前一根阳线 + 本根高开低走、收盘跌破前一根实体中点
    DarkCloud = (Close[1] > Open[1])
             && (Open > Close[1])
             && (Close < (Close[1] + Open[1]) / 2)
             && (Close < Open);

    If (DarkCloud)
    {
        PlotText(High + 2*TickPrice, "乌云盖顶", 0, Green);
        PlotIcon(High, 4, 0);
    }
End
```

**顶底分型（支撑压力位）思路**：用 `High[1] > High[2] && High[1] > High` 判定顶分型、
`Low[1] < Low[2] && Low[1] < Low` 判定底分型，再把分型点记进序列变量当支撑压力位。

---

## 8. `OpenThreeLineStrategy` — 开盘三线

**适用场景**：日内以**当日开盘价**为基准构造三条参考线（开 +/- k 个 Tick），价格穿越即触发。

**骨架（信号部分）**

```text
Params
    Integer LineTicks(3);        // 每条线距开盘价的 Tick 数

Vars
    Numeric RefOpen;
    Numeric UpLine;
    Numeric DownLine;
    Bool CrossUp;
    Bool CrossDown;

Begin
    RefOpen  = Open;
    UpLine   = RefOpen + LineTicks * TickPrice;
    DownLine = RefOpen - LineTicks * TickPrice;

    CrossUp   = Close > UpLine   && Close[1] <= UpLine;
    CrossDown = Close < DownLine && Close[1] >= DownLine;

    If (CrossUp)
    {
        PlotText(High, "上穿一线", 0, Red);
        Buy(1, Open);
    }
    Else If (CrossDown)
    {
        PlotText(Low, "下穿一线", 0, Green);
        SellShort(1, Open);
    }

    PlotNumeric("开盘线",  RefOpen,  White);
    PlotNumeric("上线",    UpLine,   RGB(255,0,0));
    PlotNumeric("下线",    DownLine, RGB(0,255,0));
End
```

**要点**：`TickPrice` 是把"跳数"换算成价格的关键；上穿判定要 `Close > Line && Close[1] <= Line`。

---

## 9. 跨周期画线 — 在分钟图上标昨日高低点

**适用场景**：小周期图表上叠加日线关键位；是最短的跨周期可用例子。

**骨架**

```text
Vars
    NumericArray YesterdayHigh;
    NumericArray YesterdayLow;
    Numeric YesterdayHighValue;
    Numeric YesterdayLowValue;

Begin
    UnPlotHorzLine(2);                                       // 先清掉上次画的线
    YesterdayHigh = HisData(Enum_Data_High, Enum_Period_Day, 1);
    YesterdayLow  = HisData(Enum_Data_Low,  Enum_Period_Day, 1);

    YesterdayHighValue = YesterdayHigh[1];                   // 数组按时间由近到远
    YesterdayLowValue  = YesterdayLow[1];

    PlotHorzLine(YesterdayHighValue, RGB(255,0,0), 1);
    PlotHorzLine(YesterdayLowValue,  RGB(0,0,255), 1);
End
```

**要点（来自官方案例 6 的注意事项）**

1. `HisData` 返回 `NumericArray`，**不是** `NumericSeries`。
2. 数组必须用 `iMA` / `iHHV` / `iLLV`，**不能用** `Average` / `Highest` / `Lowest`。
3. 日线：`HisData(Enum_Data_*, Enum_Period_Day, 1)`；5 分钟：`Enum_Period_Min, 5`；
   1 小时：`Enum_Period_Hour, 1`。
4. `PlotHorzLine(价格, 颜色, 线宽)` 配 `UnPlotHorzLine(个数)` 清理，避免重画叠加。

---

## 通用编写约定

- **文件头注释块**：`// 简称:` / `// 名称:` / `// 类别:` / `// 类型:`，官方规范要求。
- **避开未来函数**：参与判定的价格一律用 `[1]`，或用 `HighestFC` / `LowestFC`；
  `Highest` / `Lowest` 含当前 Bar，必须 `REF(...,1)` 后再比较。
- **信号变量回溯**：需要 `[n]` 就必须声明成 `NumericSeries` / `BoolSeries`；普通
  `Numeric` / `Bool` 不能回溯。
- **局部变量每次重置**：`Vars` 里的计数变量在每个计算周期都会回到初始值，
  不要指望它跨周期累加——要跨周期就用 `GlobalVars`。
- **资金管理**：`BigPointValue` / `ContractUnit` 未登录交易服务器时返回 0，
  直接相除会得到无效值，公式里要能容忍（如配合 `Max(..., 1)`）。
- **编译演示优先级**：只画线与标注、不下单的指标（第 7、9 类）最稳；
  一旦出现 `Buy` / `Alert`，编译通过也可能在运行期弹窗或下单，演示时优先选无副作用版本。
