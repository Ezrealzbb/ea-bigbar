//+------------------------------------------------------------------+
//|                                                       Bigbar.mq5 |
//|                                  Copyright 2021, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

//--- input parameters
input double   upPrecent = 0.2; // 正向影线占实体部分的百分比
input double   downPrecent = 0.1; // 反向影线占实体部分的百分比
input float    atrRange = 1.0; // bar 是 atr 的几倍
input ulong  EXPERT_MAGIC = 0; // EA幻数
input double lots = 0.01;      // 交易量手数
input double tpPoint = 400.0; // 固定止盈点数
input double slPoint = 200.0; // 固定止损点数
input int ATRPeriod = 20; // 最近的atr 周期
input double minRangeHeight = 400; // bar 的最小总高度


//--- 内部的局部变量
//--- 用于存储ATR指标句柄
int AtrHandler;
//--- 用于交易的全局变量
CTrade ExtTrade;
//--- 上一条bar的开始时间
datetime lastbar_timeopen;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
//--- 创建ATR指标句柄
    AtrHandler = iATR(_Symbol, _Period, ATRPeriod);
    if(AtrHandler == INVALID_HANDLE) {
        PrintFormat("%s: failed to create iATR, error code %d", __FUNCTION__, GetLastError());
        return(INIT_FAILED);
    }
    ExtTrade.SetExpertMagicNumber(EXPERT_MAGIC);
    ExtTrade.SetMarginMode();
    ExtTrade.SetTypeFillingBySymbol(Symbol());
//---
    return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
//---

}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
//---
    if (isNewBar()) {
        int signal = CheckSignal();
        if (signal != 0) {
            // PrintFormat("%s: getSignal %d. Send OpenOrder", __FUNCTION__, signal);
            SendOpenOrder(signal > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
        }
    }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SendOpenOrder(ENUM_ORDER_TYPE signal)
{
// 需要检测当前是否已经有同方向的头寸，如果已经有了，则不需要重新开单
    int total = PositionsTotal();
    for (int i = total - 1; i >= 0; --i) {
        // 获取当前的订单
        //--- 持仓参数
        ulong positionTicket = PositionGetTicket(i);
        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        int positionMagic = PositionGetInteger(POSITION_MAGIC);
        int positionType = PositionGetInteger(POSITION_TYPE);

        if(positionMagic != EXPERT_MAGIC || positionSymbol != Symbol()) {
            continue;
        }

        // 已经存在做多的单，就不需要创建新的订单了
        if (positionType == POSITION_TYPE_BUY && signal == ORDER_TYPE_BUY) {
            return;
        }

        if (positionType == POSITION_TYPE_SELL && signal == ORDER_TYPE_SELL) {
            return;
        }
    }

    openOrder(signal);
}

//--- 当正向影线和反向影线小于阈值时，出现突破买入信号
int CheckSignal()
{
    double symbolPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double arts[1];
    if (CopyBuffer(AtrHandler, 0, 1, 1, arts) == -1) {
        return 0;
    }

    MqlRates bars[2];
    if (CopyRates(Symbol(), Period(), 1, 2, bars) == -1) {
        return 0;
    }

    MqlRates lastBar = bars[1];

    double barRangeHeight = MathAbs(lastBar.close - lastBar.open);
    double barFullHeight = MathAbs(lastBar.high - lastBar.low);

    if (barFullHeight < minRangeHeight * symbolPoint || barRangeHeight < atrRange * arts[0]) {
        return 0;
    }

    bool isUpBar = lastBar.open < lastBar.close;
    double barTopPrecent = (isUpBar ? lastBar.high - lastBar.close : lastBar.close - lastBar.low) / barRangeHeight;
    double barDownPrecent = (isUpBar ? lastBar.open - lastBar.low : lastBar.high - lastBar.open) / barRangeHeight;

    if (barTopPrecent <= upPrecent && barDownPrecent <= downPrecent) {
        return isUpBar ? 1 : -1;
    }

    return 0;

}

//+------------------------------------------------------------------+
//| Trade function                                                   |
//+------------------------------------------------------------------+
void OnTrade()
{
//---

}
//+------------------------------------------------------------------+



//--- 一些常见的工具函数
//+------------------------------------------------------------------+
//|  当新柱形图出现时返回'true'                                         |
//+------------------------------------------------------------------+
bool isNewBar(const bool print_log = true)
{
    static datetime bartime = 0; //存储当前柱形图的开盘时间
//--- 获得零柱的开盘时间
    datetime currbar_time = iTime(_Symbol, _Period, 0);
//--- 如果开盘时间更改，则新柱形图出现
    if(bartime != currbar_time) {
        bartime = currbar_time;
        lastbar_timeopen = bartime;
        //--- 在日志中显示新柱形图开盘时间的数据
        if(print_log && !(MQLInfoInteger(MQL_OPTIMIZATION) || MQLInfoInteger(MQL_TESTER))) {
            //--- 显示新柱形图开盘时间的信息
            PrintFormat("%s: new bar on %s %s opened at %s", __FUNCTION__, _Symbol,
                        StringSubstr(EnumToString(_Period), 7),
                        TimeToString(TimeCurrent(), TIME_SECONDS));
            //--- 获取关于最后报价的数据
            MqlTick last_tick;
            if(!SymbolInfoTick(Symbol(), last_tick))
                Print("SymbolInfoTick() failed, error = ", GetLastError());
            //--- 显示最后报价的时间，精确至毫秒
            PrintFormat("Last tick was at %s.%03d",
                        TimeToString(last_tick.time, TIME_SECONDS), last_tick.time_msc % 1000);
        }
        //--- 我们有一个新柱形图
        return (true);
    }
//--- 没有新柱形图
    return (false);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool openOrder(ENUM_ORDER_TYPE signal)
{
    double price = SymbolInfoDouble(_Symbol, signal == ORDER_TYPE_SELL ? SYMBOL_BID : SYMBOL_ASK);
    int spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    double symbolPoint = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double spreadValue = spread * symbolPoint;
    double slValue = symbolPoint * slPoint + spreadValue;
    double tpValue = symbolPoint * tpPoint + spreadValue;

    double slPrice = signal == ORDER_TYPE_SELL ? price + slValue : price - slValue;
    double tpPrice = signal == ORDER_TYPE_SELL ? price - tpValue : price + tpValue;
    PrintFormat("%s: openOrder direction %d price %f tp %f sl %f spread %d", __FUNCTION__, signal, price, tpPrice, slPrice, spread);
    return ExtTrade.PositionOpen(Symbol(), signal, lots,
                                 price,
                                 slPrice, tpPrice);
}
//+------------------------------------------------------------------+
