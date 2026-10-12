# 指标案例库（K 线形态与绘制类）

本文件收录盘立方宽语言的**真实指标源码**，来自官方指标样例集（`盘立方指标样例.txt`、
`盘立方指标2026.txt`、`盘立方指标案例.txt`）。

**为什么优先用这类指标做演示**：它们只做 `PlotText` / `PlotIcon` / `PlotNumeric` 绘制，
**不含 `Buy` / `Sell` / `Alert` 等副作用调用**，编译通过后即使运行也不会下单或弹窗，
是最安全的可运行验证材料。

配套文件：
- 语法与函数签名 → `formula-functions.md`
- 策略类（含下单与资金管理）案例 → `examples-strategies.md`

## 这套指标的公共写法

官方指标样例高度模板化，几乎全部遵循同一套写法，掌握后可以快速改造：

```text
指标名
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    ...
End
===============================================================================
```

- 段落之间用 `================` 分隔（样例集的格式，**不是语法要求**）。
- 指标**普遍在 `Begin` 里用行内声明**（`Numeric avg=...;`、`Bool up=True;`），
  而不是先把变量写进 `Vars`。
- **一律用 `[1]` 判定已经走完的 K 线**，在当前 K 线（`[0]`）上绘制标注。
- 大量使用 `AverageFC`（含当前 Bar 的均值，功能等价于 `Average`）做自适应阈值。
- 当前 K 线标注位置约定：看涨标在 `H[1]`（前一根最高价）、看跌标在 `L[1]`（前一根最低价），
  `PlotText` 的第三个参数 `1` 表示向上一根 K 线偏移。

> 注意：官方样例里 `AverageFC` 与 `Average` 混用（如 `AverageFC(Abs(C[1]-O[1]),200)` 与
> `Average(Close,20)` 同时出现），二者在样例中都被接受。函数库中 `Average` 接受序列变量；
> **数组**必须用 `iMA`。

## 案例索引

| # | 指标名 | 类别 | 核心逻辑 | 关键点 |
| --- | --- | --- | --- | --- |
| 1 | 长阳 / 长阴 | 单根实体 | 实体 > 3 倍近 200 根平均实体 | `AverageFC(Abs(C[1]-O[1]),200)` |
| 2 | 五连阳 / 五连阴 | 连续形态 | 连续 5 根同向 | `For` 计数 |
| 3 | 一阳破三阴 / 一阴破三阳 | 反转形态 | 前 3 根反向 + 本根反向放量突破 | C 风格 `For` + `Break` |
| 4 | 3K 反转 | 三根组合 | 中间影线超长 + 反向突破 | 影线长度对比均值 |
| 5 | 口吞宝剑 | 三根组合 | 长影线 + 反向吞没 | 与 3K 反转同构 |
| 6 | K线突破均线 | 均线突破 | 前一根上穿均线 | `Close[2]` / `Close[1]` 双条件 |
| 7 | 回踩均线 | 均线支撑 | 先上穿，再连续 6 根不破均线 | 嵌套 `For` + `ballup` 标记 |
| 8 | 金叉死叉 | 均线交叉 | `CrossOver` / `CrossUnder` | `BoolSeries` 才能 `[n]` |
| 9 | 均线方向改变 | 趋势拐点 | 连续 32 根单调上行 | `Return` 提前退出 + 降序遍历 |
| 10 | `StandardKLine` | 自适应基准 | 前 N 根波动最大 M 根算基准 | `Array_SetSize` + 插入排序 |

---

## 1. 长阳 / 长阴

**适用场景**：识别单根大实体 K 线，最简短的入门指标（全文仅 6 行逻辑）。

**核心逻辑**：用近 200 根 K 线的**平均实体绝对值**做自适应阈值，实体超过 3 倍即为长阳/长阴。

**完整源码**

```text
长阳
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Numeric avg=AverageFC(Abs(C[1]-O[1]),200);
    If(C[1]-O[1]>3*avg)
    {
        PlotText(H[1],"长阳",1);
    }
    If(O[1]-C[1]>3*avg)
    {
        PlotText(L[1],"长阴",1);
    }
End
```

**要点**：`Abs(C[1]-O[1])` 是实体绝对值（不分阴阳），`C[1]-O[1] > 0` 判阳、
`O[1]-C[1] > 0` 判阴；`PlotText(H[1], "长阳", 1)` 的第三个参数 `1` 是偏移一根 K 线。

---

## 2. 五连阳 / 五连阴

**适用场景**：识别连续同向 K 线，`For` 计数循环的入门范例。

**核心逻辑**：遍历前 1–5 根，统计阳线数与阴线数，各自等于 5 即触发。

**完整源码**

```text
五连阳
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Integer up=0;
    Integer dn=0;
    For(Integer i=1;i<=5;i++)
    {
        If(C[i]>O[i])
        {
            up++;
        }
        If(O[i]>C[i])
        {
            dn++;
        }
    }
    If(up==5)
    {
        PlotText(H[1],"五连阳",1);
    }
    If(dn==5)
    {
        PlotText(L[1],"五连阴",1);
    }
End
```

**要点**：`up++`（自增）、`up==5`（比较用 `==`）；`For(Integer i=1;i<=5;i++)` 是
C 风格计数循环，**循环变量在使用处行内声明**。

---

## 3. 一阳破三阴 / 一阴破三阳

**适用场景**：经典反转形态——前三根反向，第四根一根阳线全部收复。

**核心逻辑**：先用 `For` 检查前 2–4 根**是否全是阴线**（遇到阳线立刻 `up=False; Break;`），
同时记录这三根的最高价 `lhp`；再要求当前根收盘突破 `lhp` 且最低价低于前两根之一。

**完整源码**

```text
一阳破三阴
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Bool up=True;
    Numeric lhp=0;
    For(int i=2;i<=4;i++)
    {
        lhp=Max(lhp,H[i]);
        If(C[i]>O[i])
        {
            up=False;
            Break;
        }
    }
    If(up&&C[1]>lhp&&L[1]<H[2])
    {
        PlotText(H[1],"一阳破三阴",1);
    }
    Bool dn=True;
    Numeric llp=L[2];
    For(int j=2;j<=4;j++)
    {
        llp=Min(llp,L[j]);
        If(C[j]<O[j])
        {
            dn=False;
            Break;
        }
    }
    If(dn&&L[1]<llp&&H[1]>L[2])
    {
        PlotText(L[1],"一阴破三阳",1);
    }
End
```

**要点**：`Break` 在 `If` 体内作为单条语句使用，**不加花括号**；
`Bool up=True;` 与 `Bool dn=True;` 是中段行内声明，不必提到 `Vars`；
`&&` 串联三个条件。

---

## 4. 3K 反转

**适用场景**：三根 K 线组合的影线反转形态。

**核心逻辑**：中间的 `[2]` 那根 K 线要有一根**远超平均振幅**的长影线，
且当前根 `[1]` 收盘反向突破、`[2]` 同时创出比 `[3]` 更极端的极值。

**完整源码**

```text
3K反转
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Numeric AvgHL=AverageFC(H[1]-L[1],200);
    Numeric linefrom=Min(O[2],C[2]);
    Numeric linelength=linefrom-L[2];
    If(linelength>AvgHL&&C[1]>H[2]&&L[2]<L[3])
    {
        PlotText(H[1],"3K反转（阳）",1);
    }
    linefrom=Max(O[2],C[2]);
    linelength=H[2]-linefrom;
    If(linelength>AvgHL&&C[1]<L[2]&&H[2]>H[3])
    {
        PlotText(L[1],"3K反转（阴）",1);
    }
End
```

**要点**：`linefrom` / `linelength` 是**复用同一个变量**先算下影再算上影；
`Min(O[2],C[2]) - L[2]` 即"实体下沿到最低价"的下影长度。

---

## 5. 口吞宝剑

**适用场景**：与 3K 反转同构的另一组合——长影线 + 反向吞没。

**核心逻辑**：区别在于末根条件变成"开盘价也越过了 `[2]` 的极值"（真正吞没）。

**完整源码**

```text
口吞宝剑
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Numeric AvgHL=AverageFC(H[1]-L[1],200);
    Numeric linefrom=Max(O[2],C[2]);
    Numeric linelength=H[2]-linefrom;
    If(linelength>AvgHL&&C[1]>H[2]&&O[1]<H[2])
    {
        PlotText(H[1],"口吞宝剑（阳）",1);
    }
    linefrom=Min(O[2],C[2]);
    linelength=linefrom-L[2];
    If(linelength>AvgHL&&C[1]<L[2]&&O[1]>L[2])
    {
        PlotText(L[1],"口吞宝剑（阴）",1);
    }
End
```

**对比 3K 反转**：3K 反转要求 `L[2] < L[3]`（创更低）；
口吞宝剑要求 `O[1] < H[2]`（开盘即低于上影顶，形成吞没）。

---

## 6. K线突破均线

**适用场景**：均线突破类信号的最短范例，含 `PlotNumeric` 画线。

**完整源码**

```text
K线突破均线
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
Begin
    //策略执行区
    Numeric MA20=Average(Close,20);
    PlotNumeric("MA",MA20);
    If(Close[2]<=MA20&&Close[1]>MA20)
    {
        PlotText(H[1],"UP",1);
    }
End
```

**要点**：`MA20` 是**行内 `Numeric`**，每根 K 线重算；`Close[2] <= MA20 && Close[1] > MA20`
即"前一根上穿"；`PlotNumeric("MA", MA20)` 只传两个参数，颜色用默认。

---

## 7. 回踩均线

**适用场景**：均线支撑确认——先突破、再回踩不破。

**核心逻辑**：要求前一根收盘站上均线（`C[1] > MA20[1]`）且更早一根低点触及过均线，
然后往前检查 3–8 根**是否始终没跌破**均线（`L[i] < MA20[i]` 一出现就否掉）。

**完整源码**

```text
回踩均线
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
    NumericSeries MA20;
Begin
    //策略执行区
    MA20=Average(C,20);
    PlotNumeric("MA",MA20);
    If(C[1]>MA20[1]&&L[2]<=MA20[2])
    {
        Bool ballup=True;
        For(int i=3;i<=8;i++)
        {  If(L[i]<MA20[i])
           {
            ballup=False;
            Break;
           }
        }
        If(ballup)
        {
            PlotIcon(H[1],3,1);
        }
    }
End
```

**要点**：`MA20` 因为要用 `MA20[1]` / `MA20[2]` 回溯，**必须声明为 `NumericSeries`** 且放到
`Vars`（行内 `Numeric` 无法 `[n]`）；`PlotIcon(H[1], 3, 1)` 的 `3` 是上箭头；
`Bool ballup` 在 `If` 块内行内声明。

---

## 8. 金叉死叉

**适用场景**：双均线交叉信号，`BoolSeries` 的典型用法。

**完整源码**

```text
金叉死叉
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
    NumericSeries MA1;
    NumericSeries MA2;
    BoolSeries upcross;
    BoolSeries dncross;
Begin
    //策略执行区
    MA1=Average(C,10);
    MA2=Average(C,30);
    PlotNumeric("MA1",MA1);
    PlotNumeric("MA2",MA2);
    upcross=CrossOver(MA1,MA2);
    dncross=CrossUnder(MA1,MA2);
    If(upcross[1])
    {
        PlotText(H[1],"金叉",1);
    }
    If(dncross[1])
    {
        PlotText(L[1],"死叉",1);
    }
End
```

**要点**：`upcross` / `dncross` 声明为 `BoolSeries` 才能用 `upcross[1]` 回溯；
`CrossOver(MA1, MA2)` 判金叉、`CrossUnder` 判死叉；两条 `PlotNumeric` 并列画双线。

---

## 9. 均线方向改变

**适用场景**：识别均线由下行转为上行（"上弯"）的拐点。

**核心逻辑**：`CurrentBar < 32` 时直接 `Return` 提前退出（数据不足无法判 32 根）；
再检查前 32 根均线是否单调递减（`MA1[i] > MA1[i+1]` 一出现即否），全否即为上弯。

**完整源码**

```text
均线方向改变
Params
    //参数定义
GlobalVars
    //全局变量定义
Vars
    //局部变量定义
    NumericSeries MA1;
Begin
    //策略执行区
    MA1=Average(C,20);
    PlotNumeric("MA1",MA1);
    If(CurrentBar<32)Return;
    If(MA1[1]>=MA1[2])
    {
        Bool balldn=True;
        For(Integer i=2;i<=32;i++)
        {
            If(MA1[i]>MA1[i+1])
            {
                balldn=False;
                Break;
            }
        }
        If(balldn)
        {
            PlotText(H[1],"上弯",1);
        }
    }
End
```

**要点**：**`Return` 是提前退出的标准写法**，可省去大量嵌套 `If`；
降序检查用 `MA1[i] > MA1[i+1]`（当前比下一根更大 = 在下行）。

---

## 10. `StandardKLine` — 标准K线标识指标（自适应基准）

**适用场景**：需要"自适应阈值"的复杂指标；也是**数组操作 + 插入排序 + 嵌套循环**
最完整的官方范例。

**核心逻辑（四步）**

1. 回顾过去 `LookBack`（默认 40）根 K 线，找出波动最大的 `TopCount`（默认 6）根。
2. 排除其中波动最极端的 1 根（`MaxRangeValues[0]`），避免异常值干扰。
3. 对剩下的 5 根，按阴阳线类型取"强弱值"（阳线 `Close-Low`、阴线 `High-Close`），
   求平均作为"标准K线值"。
4. 当前根按同规则算值，`>=` 标准值即判定为标准K线，在最低价下方画黄色圆点。

**关键骨架（数组与循环部分）**

```text
//------------------------------------------------------------------------
// 简称: StandardKLine
// 名称: 标准K线标识指标
// 类别: 技术指标
// 类型: 用户应用
//------------------------------------------------------------------------
Params
    Integer LookBack(40);    // 回看周期数
    Integer TopCount(6);     // 选取最大波动K线数量
    Integer ExcludeCount(1); // 排除的最大波动K线数量

GlobalVars
    NumericSeries StdValue;  // 标准K线值序列

Vars
    Numeric i;
    Numeric j;
    Numeric k;
    Numeric RangeValue;
    Numeric SelectedValue;
    Numeric SumValue;
    Numeric Count;
    NumericArray MaxRangeValues; // 前 TopCount 大波动值，降序
    Numeric MaxRange;
    Numeric CurrentKLineValue;

Begin
    // 初始化最大值数组（先设长度再置 0，避免越界）
    Array_SetSize(MaxRangeValues, TopCount);
    For j = 0 To TopCount - 1
    {
        MaxRangeValues[j] = 0;
    }

    // 维护 TopCount 长度的降序最大波动值数组（插入排序）
    For i = 1 To LookBack
    {
        RangeValue = High[i] - Low[i];
        For j = TopCount - 1 DownTo 0
        {
            If(RangeValue > MaxRangeValues[j])
            {
                If(j < TopCount - 1)
                {
                    For k = TopCount - 1 DownTo j + 1
                    {
                        MaxRangeValues[k] = MaxRangeValues[k - 1];
                    }
                }
                MaxRangeValues[j] = RangeValue;
                Break;
            }
        }
    }

    MaxRange = MaxRangeValues[0];    // 索引 0 是最大波动（要排除的极端值）

    // 筛选"前 6 大且非最大"的 K 线，计算强弱值平均
    SumValue = 0;
    Count = 0;
    For i = 1 To LookBack
    {
        RangeValue = High[i] - Low[i];
        Bool isInTopExcludeMax = False;
        For j = 1 To TopCount - 1          // 跳过索引 0
        {
            If(RangeValue == MaxRangeValues[j])
            {
                isInTopExcludeMax = True;
                Break;
            }
        }

        If(isInTopExcludeMax)
        {
            If(Close[i] > Open[i])
            {
                SelectedValue = Close[i] - Low[i];
            }
            Else If(Close[i] < Open[i])
            {
                SelectedValue = High[i] - Close[i];
            }
            Else                           // 十字星兜底
            {
                SelectedValue = (High[i] - Low[i]) / 2;
            }
            SumValue = SumValue + SelectedValue;
            Count = Count + 1;
        }
    }
    // …后续：StdValue = SumValue / Count；当前根判定后 PlotDot 标黄色圆点
End
```

**要点（这一例的独特价值）**

- **数组必须先 `Array_SetSize` 再按下标赋值**，否则越界。
- `For j = 0 To TopCount - 1` / `For j = TopCount - 1 DownTo j + 1` 两种方向都在用，
  **降序遍历是数组元素后移的正确方向**（升序会覆盖未处理元素）。
- 同一 `For` 结构里 `Break` 用于"找到插入位置即停止"。
- `Bool isInTopExcludeMax = False;` 在循环体内行内声明并初始化。
- 这个指标文本量较大（约 160 行），适合作为"复杂指标也能编译"的验证样本。

---

## 编写指标时的检查清单

- [ ] `PlotText` / `PlotIcon` 的**价格参数与偏移参数**是否配套（看涨用 `H[1]`，看跌用 `L[1]`）。
- [ ] 需要 `[n]` 回溯的变量是否声明为 `NumericSeries` / `BoolSeries`（普通 `Numeric` 不行）。
- [ ] 数组是否先 `Array_SetSize` 再赋值；下标是否可能越界。
- [ ] `For` 循环变量是"行内声明"还是"先用 `Vars` 声明"，两者都可，但要一致。
- [ ] `C` / `O` / `H` / `L` / `V` 是官方简写，等价于 `Close()` / `Open()` / `High()` /
      `Low()` / `Vol()`；`C[1]` 即上一根收盘。
- [ ] 复杂指标建议先加 `If(CurrentBar < N)Return;` 保护，避免历史数据不足时报错。
