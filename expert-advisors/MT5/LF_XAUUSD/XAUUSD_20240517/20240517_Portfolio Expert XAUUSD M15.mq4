//
// EA Studio Portfolio Expert Advisor
//
// Created with: Expert Advisor Studio
// Website: https://studio.eatradingacademy.com/
//
// Copyright 2024, Forex Software Ltd.
//
// This Portfolio Expert works in MetaTrader 4.
// It opens separate positions for each strategy.
// Every position has an unique magic number, which corresponds to the index of the strategy.
//
// Risk Disclosure
//
// Futures and forex trading contains substantial risk and is not for every investor.
// An investor could potentially lose all or more than the initial investment.
// Risk capital is money that can be lost without jeopardizing ones’ financial security or life style.
// Only risk capital should be used for trading and only those with sufficient risk capital should consider trading.

#property copyright "Forex Software Ltd."
#property version   "3.6"
#property strict

static input double Entry_Amount       =    0.01; // Entry lots
static input int    Base_Magic_Number  =     100; // Base Magic Number

static input string ___Options_______  = "-----"; // --- Options ---
static input int    Max_Open_Positions =     100; // Max Open Positions

static input string ___Protections____ = "------"; // --- Protections ---
static input int    Max_Spread         =        0; // Max spread (points)
static input int    Min_Equity         =        0; // Minimum equity (currency)
static input int    MaxDailyLoss       =        0; // Maximum daily loss (currency)

#define TRADE_RETRY_COUNT   4
#define TRADE_RETRY_WAIT  100
#define OP_FLAT            -1

// Session time is set in seconds from 00:00
const int  sessionSundayOpen           =     0; // 00:00
const int  sessionSundayClose          = 86400; // 24:00
const int  sessionMondayThursdayOpen   =     0; // 00:00
const int  sessionMondayThursdayClose  = 86400; // 24:00
const int  sessionFridayOpen           =     0; // 00:00
const int  sessionFridayClose          = 86400; // 24:00
const bool sessionIgnoreSunday         = true;
const bool sessionCloseAtSessionClose  = false;
const bool sessionCloseAtFridayClose   = false;

const int    strategiesCount = 10;
const double sigma        = 0.000001;
const int    requiredBars = 70;

datetime barTime;
double   stopLevel;
double   pip;
bool     setProtectionSeparately = false;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum OrderScope
  {
   ORDER_SCOPE_UNDEFINED,
   ORDER_SCOPE_ENTRY,
   ORDER_SCOPE_EXIT
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
enum OrderDirection
  {
   ORDER_DIRECTION_NONE,
   ORDER_DIRECTION_BUY,
   ORDER_DIRECTION_SELL,
   ORDER_DIRECTION_BOTH
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
struct Position
  {
   int    Type;
   int    Ticket;
   int    MagicNumber;
   double Lots;
   double Price;
   double StopLoss;
   double TakeProfit;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
struct Signal
  {
   int            MagicNumber;
   OrderScope     Scope;
   OrderDirection Direction;
   int            StopLossPips;
   int            TakeProfitPips;
   bool           IsTrailingStop;
   bool           OppositeReverse;
  };
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit(void)
  {
   barTime   = Time[0];
   stopLevel = MarketInfo(_Symbol, MODE_STOPLEVEL);
   pip       = GetPipValue();

   return ValidateInit();
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick(void)
  {
   if(ArraySize(Time) < requiredBars)
      return;

   if(!MQLInfoInteger(MQL_TESTER))
      CheckProtections();

   if(IsForceSessionClose())
     {
      CloseAllPositions();
      return;
     }

   if(Time[0] > barTime)
     {
      barTime = Time[0];
      OnBar();
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnBar(void)
  {
   if(IsOutOfSession())
      return;

   Signal signalList[];
   SetSignals(signalList);
   int signalsCount = ArraySize(signalList);

   for(int i = 0; i < signalsCount; i += 1)
     {
      Signal signal = signalList[i];
      ManageSignal(signal);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageSignal(Signal &signal)
  {
   Position position = CreatePosition(signal.MagicNumber);

   if(position.Type != OP_FLAT && signal.Scope == ORDER_SCOPE_EXIT)
     {
      if((signal.Direction == ORDER_DIRECTION_BOTH) ||
         (position.Type == OP_BUY  && signal.Direction == ORDER_DIRECTION_SELL) ||
         (position.Type == OP_SELL && signal.Direction == ORDER_DIRECTION_BUY ) )
        {
         ClosePosition(position);
        }
     }

   if(position.Type != OP_FLAT && signal.Scope == ORDER_SCOPE_EXIT && signal.IsTrailingStop)
     {
      double trailingStop = GetTrailingStopPrice(position, signal.StopLossPips);
      Print(trailingStop);
      ManageTrailingStop(position, trailingStop);
     }

   if(position.Type != OP_FLAT && signal.OppositeReverse)
     {
      if((position.Type == OP_BUY  && signal.Direction == ORDER_DIRECTION_SELL) ||
         (position.Type == OP_SELL && signal.Direction == ORDER_DIRECTION_BUY ))
        {
         ClosePosition(position);
         ManageSignal(signal);
         return;
        }
     }

   if(position.Type == OP_FLAT && signal.Scope == ORDER_SCOPE_ENTRY)
     {
      if(signal.Direction == ORDER_DIRECTION_BUY || signal.Direction == ORDER_DIRECTION_SELL)
        {
         if( CountPositions() < Max_Open_Positions )
            OpenPosition(signal);
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CountPositions(void)
  {
   int minMagic = GetMagicNumber(0);
   int maxMagic = GetMagicNumber(strategiesCount);
   int posTotal = OrdersTotal();
   int count    = 0;

   for(int posIndex = posTotal - 1; posIndex >= 0; posIndex--)
     {
      if(OrderSelect(posIndex, SELECT_BY_POS, MODE_TRADES) &&
         OrderSymbol() == _Symbol &&
         OrderCloseTime()== 0)
        {
         int magicNumber = OrderMagicNumber();
         if(magicNumber >= minMagic && magicNumber <= maxMagic)
            count += 1;
        }
     }

   return count;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Position CreatePosition(int magicNumber)
  {
   Position position;
   position.MagicNumber = magicNumber;
   position.Type        = OP_FLAT;
   position.Ticket      = 0;
   position.Lots        = 0;
   position.Price       = 0;
   position.StopLoss    = 0;
   position.TakeProfit  = 0;

   int total = OrdersTotal();
   for(int pos = total - 1; pos >= 0; pos--)
     {
      if(OrderSelect(pos, SELECT_BY_POS, MODE_TRADES) &&
          OrderSymbol()      == _Symbol &&
          OrderMagicNumber() == magicNumber &&
          OrderCloseTime()   == 0)
        {
         position.Type       = OrderType();
         position.Lots       = OrderLots();
         position.Ticket     = OrderTicket();
         position.Price      = OrderOpenPrice();
         position.StopLoss   = OrderStopLoss();
         position.TakeProfit = OrderTakeProfit();
         break;
        }
     }

   return position;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal CreateEntrySignal(int strategyIndex, bool canOpenLong,   bool canOpenShort,
                         int stopLossPips,  int takeProfitPips, bool isTrailingStop,
                         bool oppositeReverse = false)
  {
   Signal signal;

   signal.MagicNumber     = GetMagicNumber(strategyIndex);
   signal.Scope           = ORDER_SCOPE_ENTRY;
   signal.StopLossPips    = stopLossPips;
   signal.TakeProfitPips  = takeProfitPips;
   signal.IsTrailingStop  = isTrailingStop;
   signal.OppositeReverse = oppositeReverse;
   signal.Direction       = canOpenLong && canOpenShort ? ORDER_DIRECTION_BOTH
                                         : canOpenLong  ? ORDER_DIRECTION_BUY
                                         : canOpenShort ? ORDER_DIRECTION_SELL
                                                        : ORDER_DIRECTION_NONE;

   return signal;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal CreateExitSignal(int strategyIndex, bool canCloseLong,   bool canCloseShorts,
                        int stopLossPips,  int  takeProfitPips, bool isTrailingStop)
  {
   Signal signal;

   signal.MagicNumber     = GetMagicNumber(strategyIndex);
   signal.Scope           = ORDER_SCOPE_EXIT;
   signal.StopLossPips    = stopLossPips;
   signal.TakeProfitPips  = takeProfitPips;
   signal.IsTrailingStop  = isTrailingStop;
   signal.OppositeReverse = false;
   signal.Direction       = canCloseLong && canCloseShorts ? ORDER_DIRECTION_BOTH
                                          : canCloseLong   ? ORDER_DIRECTION_SELL
                                          : canCloseShorts ? ORDER_DIRECTION_BUY
                                                           : ORDER_DIRECTION_NONE;

   return signal;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OpenPosition(Signal &signal)
  {
   if(!IsWithinMaxSpread()) return;

   for(int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      int    ticket     = 0;
      int    lastError  = 0;
      bool   modified   = false;
      int    command    = OrderDirectionToCommand(signal.Direction);
      double amount     = Entry_Amount;
      int    magicNum   = signal.MagicNumber;
      string comment    = IntegerToString(magicNum);
      color  arrowColor = command == OP_BUY ? clrGreen : clrRed;

      if(IsTradeContextFree())
        {
         double price      = command == OP_BUY ? Ask() : Bid();
         double stopLoss   = GetStopLossPrice(command, signal.StopLossPips);
         double takeProfit = GetTakeProfitPrice(command, signal.TakeProfitPips);
         bool   isSLOrTP   = stopLoss > _Point || takeProfit > _Point;

         if(setProtectionSeparately)
           {
            // Send an entry order without SL and TP
            ticket = OrderSend(_Symbol, command, amount, price, 10, 0, 0, comment, magicNum, 0, arrowColor);

            // If the order is successful, modify the position with the corresponding SL and TP
            if(ticket > 0 && isSLOrTP)
               modified = OrderModify(ticket, 0, stopLoss, takeProfit, 0, clrBlue);
           }
         else
           {
            // Send an entry order with SL and TP
            ticket    = OrderSend(_Symbol, command, amount, price, 10, stopLoss, takeProfit, comment, magicNum, 0, arrowColor);
            lastError = GetLastError();

            // If order fails, check if it is because inability to set SL or TP
            if(ticket <= 0 && lastError == 130)
              {
               // Send an entry order without SL and TP
               ticket = OrderSend(_Symbol, command, amount, price, 10, 0, 0, comment, magicNum, 0, arrowColor);

               // Try to set SL and TP
               if(ticket > 0 && isSLOrTP)
                  modified = OrderModify(ticket, 0, stopLoss, takeProfit, 0, clrBlue);

               // Mark the expert to set SL and TP with a separate order
               if(ticket > 0 && modified)
                 {
                  setProtectionSeparately = true;
                  Print("Detected ECN type position protection.");
                 }
              }
           }
        }

      if(ticket > 0)
         break;

      lastError = GetLastError();

      if(lastError != 135 && lastError != 136 && lastError != 137 && lastError != 138)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Open Position retry " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ClosePosition(Position &position)
  {
   for(int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      bool closed    = 0;
      int  lastError = 0;

      if(IsTradeContextFree())
        {
         double price = position.Type == OP_BUY ? Bid() : Ask();
         closed    = OrderClose(position.Ticket, position.Lots, price, 10, clrYellow);
         lastError = GetLastError();
        }

      if(closed)
        {
         position.Type       = OP_FLAT;
         position.Lots       = 0;
         position.Price      = 0;
         position.StopLoss   = 0;
         position.TakeProfit = 0;
         break;
        }

      if(lastError == 4108)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Close Position retry " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModifyPosition(Position &position)
  {
   for(int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      bool modified  = 0;
      int  lastError = 0;

      if(IsTradeContextFree())
        {
         modified  = OrderModify(position.Ticket, 0, position.StopLoss, position.TakeProfit, 0, clrBlue);
         lastError = GetLastError();
        }

      if(modified)
        {
         position = CreatePosition(position.MagicNumber);
         break;
        }

      if(lastError == 4108)
         break;

      Sleep(TRADE_RETRY_WAIT);
      Print("Modify Position retry " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions(void)
  {
   for(int i = 0; i < strategiesCount; i += 1)
     {
      Position position = CreatePosition(GetMagicNumber(i));

      if(position.Type == OP_BUY || position.Type == OP_SELL)
         ClosePosition(position);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetStopLossPrice(int command, int stopLossPips)
  {
   if(stopLossPips == 0)
      return 0;

   double delta    = MathMax(pip * stopLossPips, _Point * stopLevel);
   double stopLoss = command == OP_BUY ? Bid() - delta : Ask() + delta;

   return NormalizeDouble(stopLoss, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTakeProfitPrice(int command, int takeProfitPips)
  {
   if(takeProfitPips == 0)
      return 0;

   double delta      = MathMax(pip * takeProfitPips, _Point * stopLevel);
   double takeProfit = command == OP_BUY ? Bid() + delta : Ask() - delta;

   return NormalizeDouble(takeProfit, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTrailingStopPrice(Position &position, int stopLoss)
  {
   const double bid             = Bid();
   const double ask             = Ask();
   const double spread          = ask - bid;
   const double stopLevelPoints = _Point * stopLevel;
   const double stopLossPoints  = pip * stopLoss;

   if(position.Type == OP_BUY)
     {
      const double newStopLoss = High(1) - stopLossPoints;
      if(position.StopLoss <= newStopLoss - pip)
         return newStopLoss < bid
                 ? newStopLoss >= bid - stopLevelPoints
                    ? bid - stopLevelPoints
                    : newStopLoss
                 : bid;
     }

   if(position.Type == OP_SELL)
     {
      const double newStopLoss = Low(1) + spread + stopLossPoints;
      if(position.StopLoss >= newStopLoss + pip)
         return newStopLoss > ask
                 ? newStopLoss <= ask + stopLevelPoints
                    ? ask + stopLevelPoints
                    : newStopLoss
                 : ask;
     }

   return position.StopLoss;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageTrailingStop(Position &position, double trailingStop)
  {
   if((position.Type == OP_BUY  && MathAbs(trailingStop - Bid()) < _Point) ||
      (position.Type == OP_SELL && MathAbs(trailingStop - Ask()) < _Point))
     {
      ClosePosition(position);
      return;
     }

   if(MathAbs(trailingStop - position.StopLoss) > _Point)
     {
      position.StopLoss = NormalizeDouble(trailingStop, _Digits);
      ModifyPosition(position);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTradeContextFree(void)
  {
   if(IsTradeAllowed())
      return true;

   const uint startWait = GetTickCount();
   Print("Trade context is busy! Waiting...");

   while(true)
     {
      if(IsStopped())
         return false;

      const uint diff = GetTickCount() - startWait;
      if(diff > 30 * 1000)
        {
         Print("The waiting limit exceeded!");
         return false;
        }

      if( IsTradeAllowed() )
        {
         RefreshRates();
         return true;
        }

      Sleep(TRADE_RETRY_WAIT);
     }

   return true;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsOutOfSession(void)
  {
   const int dayOfWeek    = DayOfWeek();
   const int periodStart  = int(Time(0) % 86400);
   const int periodLength = PeriodSeconds(_Period);
   const int periodFix    = periodStart + (sessionCloseAtSessionClose ? periodLength : 0);
   const int friBarFix    = periodStart + (sessionCloseAtFridayClose || sessionCloseAtSessionClose ? periodLength : 0);

   return dayOfWeek == 0 && sessionIgnoreSunday ? true
        : dayOfWeek == 0 ? periodStart < sessionSundayOpen         || periodFix > sessionSundayClose
        : dayOfWeek  < 5 ? periodStart < sessionMondayThursdayOpen || periodFix > sessionMondayThursdayClose
                         : periodStart < sessionFridayOpen         || friBarFix > sessionFridayClose;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsForceSessionClose(void)
  {
   if(!sessionCloseAtFridayClose && !sessionCloseAtSessionClose)
      return false;

   const int dayOfWeek = DayOfWeek();
   const int periodEnd = int(Time(0) % 86400) + PeriodSeconds(_Period);

   return dayOfWeek == 0 && sessionCloseAtSessionClose ? periodEnd > sessionSundayClose
        : dayOfWeek  < 5 && sessionCloseAtSessionClose ? periodEnd > sessionMondayThursdayClose
        : dayOfWeek == 5 ? periodEnd > sessionFridayClose : false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Bid(void)
  {
   return MarketInfo(_Symbol, MODE_BID);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Ask(void)
  {
   return MarketInfo(_Symbol, MODE_ASK);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime Time(int bar)
  {
   return Time[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Open(int bar)
  {
   return Open[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double High(int bar)
  {
   return High[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Low(int bar)
  {
   return Low[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Close(int bar)
  {
   return Close[bar];
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetPipValue()
  {
   return _Digits == 4 || _Digits == 5 ? 0.0001
        : _Digits == 2 || _Digits == 3 ? 0.01
                        : _Digits == 1 ? 0.1 : 1;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int GetMagicNumber(int strategyIndex)
  {
   return 1000 * Base_Magic_Number + strategyIndex;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OrderDirectionToCommand(OrderDirection dir)
  {
   return dir == ORDER_DIRECTION_BUY  ? OP_BUY
        : dir == ORDER_DIRECTION_SELL ? OP_SELL
                                      : OP_FLAT;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsWithinMaxSpread(void)
  {
   if(Max_Spread == 0)
      return true;

   for(int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      const int spread = (int) MathRound((Ask() - Bid()) / _Point);

      if(spread <= Max_Spread)
         return true;

      Print("Too high spread of " + IntegerToString(spread) + " points. Waiting...");
      Sleep(TRADE_RETRY_WAIT);
     }

   Print("The entry order is cancelled due to too high spread.");

   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CheckProtections()
  {
   if(Min_Equity>0 && AccountInfoDouble(ACCOUNT_EQUITY)<Min_Equity) {
      const string equityTxt = DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
      const string message   = "Minimum equity protection activated at: " + equityTxt;
      ActivateProtection(message);
      return;
   }

   if(MaxDailyLoss>0) {
      const double dailyProfit = CalculateDailyProfit();
      if(dailyProfit < 0 && MathAbs(dailyProfit)>=MaxDailyLoss) {
         ActivateProtection("Maximum daily loss protection activate! Daily loss: " +
                            DoubleToString(MathAbs(dailyProfit), 2));
         return;
      }
   }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double CalculateDailyProfit()
  {
    const datetime t0 = TimeCurrent();
    const datetime t1 = t0 - 60*60*24;

    double dailyProfit = 0.0;

    const int totalOrders = OrdersTotal();
    for(int i=0; i < totalOrders; i+=1) {
        if(OrderSelect(i, SELECT_BY_POS)) {
            if((OrderCloseTime() > t1 && OrderCloseTime() <= t0) ||
               OrderCloseTime() == 0) {
                if(OrderType() <= OP_SELL) {
                    dailyProfit += OrderProfit();
                    dailyProfit -= OrderSwap();
                    dailyProfit -= OrderCommission();
                }
            }
        }
    }

    return dailyProfit;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ActivateProtection(string message)
  {
   CloseAllPositions();

   Comment(message);
   Print(message);

   Sleep(20 * 1000);
   ExpertRemove();
   OnDeinit(0);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetSignals(Signal &signalList[])
  {
   int i = 0;
   ArrayResize(signalList, 2 * strategiesCount);
   HideTestIndicators(true);

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":7678,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Bears Power","listIndexes":[4,-1,-1,-1,-1],"numValues":[3,0,0,0,0,0]},{"name":"MACD Signal","listIndexes":[3,3,-1,-1,-1],"numValues":[24,39,9,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[0,3,-1,-1,-1],"numValues":[47,3.72,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_000();
   signalList[i++] = GetEntrySignal_000();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":3264,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Bulls Power","listIndexes":[7,-1,-1,-1,-1],"numValues":[16,0,0,0,0,0]},{"name":"ADX","listIndexes":[1,-1,-1,-1,-1],"numValues":[13,0,0,0,0,0]}],"closeFilters":[{"name":"Bulls Power","listIndexes":[2,-1,-1,-1,-1],"numValues":[17,24.5,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_001();
   signalList[i++] = GetEntrySignal_001();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":2203,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Average True Range","listIndexes":[7,-1,-1,-1,-1],"numValues":[29,7.94,0,0,0,0]},{"name":"Bears Power","listIndexes":[2,-1,-1,-1,-1],"numValues":[7,4.7,0,0,0,0]}],"closeFilters":[{"name":"Alligator","listIndexes":[6,3,4,-1,-1],"numValues":[42,26,26,11,11,1]}]} */
   signalList[i++] = GetExitSignal_002();
   signalList[i++] = GetEntrySignal_002();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":9706,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":true},"openFilters":[{"name":"Pin Bar","listIndexes":[1,-1,-1,-1,-1],"numValues":[10,34,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[2,3,-1,-1,-1],"numValues":[22,2.38,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_003();
   signalList[i++] = GetEntrySignal_003();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":6550,"takeProfit":3367,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":false},"openFilters":[{"name":"Pin Bar","listIndexes":[1,-1,-1,-1,-1],"numValues":[10,34,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[3,3,-1,-1,-1],"numValues":[41,2.7,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_004();
   signalList[i++] = GetEntrySignal_004();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":4397,"takeProfit":7976,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Accelerator Oscillator","listIndexes":[7,-1,-1,-1,-1],"numValues":[0,0,0,0,0,0]},{"name":"Bollinger Bands","listIndexes":[0,3,-1,-1,-1],"numValues":[28,2.31,0,0,0,0]}],"closeFilters":[{"name":"Envelopes","listIndexes":[5,3,0,-1,-1],"numValues":[44,0.31,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_005();
   signalList[i++] = GetEntrySignal_005();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":6904,"takeProfit":7177,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":false},"openFilters":[{"name":"Pin Bar","listIndexes":[1,-1,-1,-1,-1],"numValues":[10,34,0,0,0,0]}],"closeFilters":[{"name":"Awesome Oscillator","listIndexes":[4,-1,-1,-1,-1],"numValues":[33.5,0,0,0,0,0]},{"name":"MACD","listIndexes":[4,3,-1,-1,-1],"numValues":[22,32,9,0,0,0]}]} */
   signalList[i++] = GetExitSignal_006();
   signalList[i++] = GetEntrySignal_006();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":6367,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Commodity Channel Index","listIndexes":[5,5,-1,-1,-1],"numValues":[36,100,0,0,0,0]},{"name":"Alligator","listIndexes":[1,3,4,-1,-1],"numValues":[32,23,23,7,7,3]}],"closeFilters":[{"name":"Moving Averages Crossover","listIndexes":[0,0,0,-1,-1],"numValues":[25,47,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_007();
   signalList[i++] = GetEntrySignal_007();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":3527,"takeProfit":7655,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":false},"openFilters":[{"name":"Bollinger Bands","listIndexes":[4,3,-1,-1,-1],"numValues":[12,3.03,0,0,0,0]}],"closeFilters":[{"name":"Candle Color","listIndexes":[1,-1,-1,-1,-1],"numValues":[21,5,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_008();
   signalList[i++] = GetEntrySignal_008();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":7454,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Envelopes","listIndexes":[2,3,0,-1,-1],"numValues":[16,0.24,0,0,0,0]},{"name":"RSI","listIndexes":[0,3,-1,-1,-1],"numValues":[41,50,0,0,0,0]}],"closeFilters":[{"name":"Commodity Channel Index","listIndexes":[2,5,-1,-1,-1],"numValues":[50,100,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_009();
   signalList[i++] = GetEntrySignal_009();

   HideTestIndicators(false);
   if(i != 2 * strategiesCount)
      ArrayResize(signalList, i);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_000()
  {
   // Bears Power (3), Level: 0.0000
   double ind0val1  = iBearsPower(NULL, 0, 3, PRICE_CLOSE, 1);
   double ind0val2  = iBearsPower(NULL, 0, 3, PRICE_CLOSE, 2);
   bool   ind0long  = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;
   bool   ind0short = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;
   // MACD Signal (Close, 24, 39, 9)
   double ind1val1  = iMACD(NULL, 0, 24, 39, 9, PRICE_CLOSE, MODE_MAIN, 1) - iMACD(NULL, 0, 24, 39, 9, PRICE_CLOSE ,MODE_SIGNAL, 1);
   bool   ind1long  = ind1val1 < 0 - sigma;
   bool   ind1short = ind1val1 > 0 + sigma;

   return CreateEntrySignal(0, ind0long && ind1long, ind0short && ind1short, 7678, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_000()
  {
   // Bollinger Bands (Close, 47, 3.72)
   double ind2upBand1 = iBands(NULL, 0, 47, 3.72, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind2dnBand1 = iBands(NULL, 0, 47, 3.72, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind2long  = Open(0) > ind2upBand1 + sigma;
   bool   ind2short = Open(0) < ind2dnBand1 - sigma;

   return CreateExitSignal(0, ind2long, ind2short, 7678, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_001()
  {
   // Bulls Power (16)
   double ind0val1  = iBullsPower(NULL, 0, 16, PRICE_CLOSE, 1);
   double ind0val2  = iBullsPower(NULL, 0, 16, PRICE_CLOSE, 2);
   double ind0val3  = iBullsPower(NULL, 0, 16, PRICE_CLOSE, 3);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val2 < ind0val3 - sigma;
   // ADX (13)
   double ind1val1  = iADX(NULL, 0, 13, PRICE_CLOSE, 0, 1);
   double ind1val2  = iADX(NULL, 0, 13, PRICE_CLOSE, 0, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1long;

   return CreateEntrySignal(1, ind0long && ind1long, ind0short && ind1short, 3264, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_001()
  {
   // Bulls Power (17), Level: 24.5000
   double ind2val1  = iBullsPower(NULL, 0, 17, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 > 24.5000 + sigma;
   bool   ind2short = ind2val1 < -24.5000 - sigma;

   return CreateExitSignal(1, ind2long, ind2short, 3264, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_002()
  {
   // Average True Range (29)
   double ind0val1  = iATR(NULL, 0, 29, 1);
   double ind0val2  = iATR(NULL, 0, 29, 2);
   double ind0val3  = iATR(NULL, 0, 29, 3);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   bool   ind0short = ind0long;
   // Bears Power (7), Level: 4.7000
   double ind1val1  = iBearsPower(NULL, 0, 7, PRICE_CLOSE, 1);
   bool   ind1long  = ind1val1 > 4.7000 + sigma;
   bool   ind1short = ind1val1 < -4.7000 - sigma;

   return CreateEntrySignal(2, ind0long && ind1long, ind0short && ind1short, 2203, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_002()
  {
   // Alligator (Smoothed, Median, 42, 26, 26, 11, 11, 1)
   double ind2val1  = iAlligator(NULL, 0, 42, 26, 26, 11, 11, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind2val2  = iAlligator(NULL, 0, 42, 26, 26, 11, 11, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 1);
   double ind2val3  = iAlligator(NULL, 0, 42, 26, 26, 11, 11, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   double ind2val4  = iAlligator(NULL, 0, 42, 26, 26, 11, 11, 1, MODE_SMMA, PRICE_MEDIAN, MODE_GATORTEETH, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val3 < ind2val4 - sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma && ind2val3 > ind2val4 + sigma;

   return CreateExitSignal(2, ind2long, ind2short, 2203, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_003()
  {
   // Pin Bar (10, 34)

   bool ind0long  = false;
   bool ind0short = false;

   {
      double closeOpen = MathAbs(Close(1) - Open(1));
      bool isPinBar = closeOpen < 10 * 0.01 * (High(1) - Low(1));
      bool upWick   = High(1) - MathMax(Close(1), Open(1)) > 34 * 0.01 * closeOpen;
      bool downWick = MathMin(Close(1), Open(1)) - Low(1)  > 34 * 0.01 * closeOpen;
      bool isBearishPinBar = isPinBar && upWick && !downWick;
      bool isBullishPinBar = isPinBar && downWick && !upWick;

      ind0long  = isBearishPinBar;
      ind0short = isBullishPinBar;
   }

   return CreateEntrySignal(3, ind0long, ind0short, 9706, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_003()
  {
   // Bollinger Bands (Close, 22, 2.38)
   double ind1upBand1 = iBands(NULL, 0, 22, 2.38, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 22, 2.38, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind1upBand2 = iBands(NULL, 0, 22, 2.38, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind1dnBand2 = iBands(NULL, 0, 22, 2.38, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind1long    = Open(0) < ind1upBand1 - sigma && Open(1) > ind1upBand2 + sigma;
   bool   ind1short   = Open(0) > ind1dnBand1 + sigma && Open(1) < ind1dnBand2 - sigma;

   return CreateExitSignal(3, ind1long, ind1short, 9706, 0, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_004()
  {
   // Pin Bar (10, 34)

   bool ind0long  = false;
   bool ind0short = false;

   {
      double closeOpen = MathAbs(Close(1) - Open(1));
      bool isPinBar = closeOpen < 10 * 0.01 * (High(1) - Low(1));
      bool upWick   = High(1) - MathMax(Close(1), Open(1)) > 34 * 0.01 * closeOpen;
      bool downWick = MathMin(Close(1), Open(1)) - Low(1)  > 34 * 0.01 * closeOpen;
      bool isBearishPinBar = isPinBar && upWick && !downWick;
      bool isBullishPinBar = isPinBar && downWick && !upWick;

      ind0long  = isBearishPinBar;
      ind0short = isBullishPinBar;
   }

   return CreateEntrySignal(4, ind0long, ind0short, 6550, 3367, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_004()
  {
   // Bollinger Bands (Close, 41, 2.70)
   double ind1upBand1 = iBands(NULL, 0, 41, 2.70, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 41, 2.70, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind1upBand2 = iBands(NULL, 0, 41, 2.70, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind1dnBand2 = iBands(NULL, 0, 41, 2.70, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind1long    = Open(0) > ind1upBand1 + sigma && Open(1) < ind1upBand2 - sigma;
   bool   ind1short   = Open(0) < ind1dnBand1 - sigma && Open(1) > ind1dnBand2 + sigma;

   return CreateExitSignal(4, ind1long, ind1short, 6550, 3367, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_005()
  {
   // Accelerator Oscillator
   double ind0val1  = iAC(NULL, 0, 1);
   double ind0val2  = iAC(NULL, 0, 2);
   double ind0val3  = iAC(NULL, 0, 3);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val2 > ind0val3 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val2 < ind0val3 - sigma;
   // Bollinger Bands (Close, 28, 2.31)
   double ind1upBand1 = iBands(NULL, 0, 28, 2.31, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 28, 2.31, 0, PRICE_CLOSE, MODE_LOWER, 1);
   bool   ind1long  = Open(0) > ind1upBand1 + sigma;
   bool   ind1short = Open(0) < ind1dnBand1 - sigma;

   return CreateEntrySignal(5, ind0long && ind1long, ind0short && ind1short, 4397, 7976, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_005()
  {
   // Envelopes (Close, Simple, 44, 0.31)
   double ind2upBand1 = iEnvelopes(NULL, 0, 44, MODE_SMA, 0, PRICE_CLOSE, 0.31, MODE_UPPER, 1);
   double ind2dnBand1 = iEnvelopes(NULL, 0, 44, MODE_SMA, 0, PRICE_CLOSE, 0.31, MODE_LOWER, 1);
   double ind2upBand2 = iEnvelopes(NULL, 0, 44, MODE_SMA, 0, PRICE_CLOSE, 0.31, MODE_UPPER, 2);
   double ind2dnBand2 = iEnvelopes(NULL, 0, 44, MODE_SMA, 0, PRICE_CLOSE, 0.31, MODE_LOWER, 2);
   bool   ind2long    = Open(0) > ind2dnBand1 + sigma && Open(1) < ind2dnBand2 - sigma;
   bool   ind2short   = Open(0) < ind2upBand1 - sigma && Open(1) > ind2upBand2 + sigma;

   return CreateExitSignal(5, ind2long, ind2short, 4397, 7976, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_006()
  {
   // Pin Bar (10, 34)

   bool ind0long  = false;
   bool ind0short = false;

   {
      double closeOpen = MathAbs(Close(1) - Open(1));
      bool isPinBar = closeOpen < 10 * 0.01 * (High(1) - Low(1));
      bool upWick   = High(1) - MathMax(Close(1), Open(1)) > 34 * 0.01 * closeOpen;
      bool downWick = MathMin(Close(1), Open(1)) - Low(1)  > 34 * 0.01 * closeOpen;
      bool isBearishPinBar = isPinBar && upWick && !downWick;
      bool isBullishPinBar = isPinBar && downWick && !upWick;

      ind0long  = isBearishPinBar;
      ind0short = isBullishPinBar;
   }

   return CreateEntrySignal(6, ind0long, ind0short, 6904, 7177, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_006()
  {
   // Awesome Oscillator, Level: 33.5000
   double ind1val1  = iAO(NULL, 0, 1);
   double ind1val2  = iAO(NULL, 0, 2);
   bool   ind1long  = ind1val1 > 33.5000 + sigma && ind1val2 < 33.5000 - sigma;
   bool   ind1short = ind1val1 < -33.5000 - sigma && ind1val2 > -33.5000 + sigma;
   // MACD (Close, 22, 32, 9)
   double ind2val1  = iMACD(NULL, 0, 22, 32, 9, PRICE_CLOSE, MODE_MAIN, 1);
   double ind2val2  = iMACD(NULL, 0, 22, 32, 9, PRICE_CLOSE, MODE_MAIN, 2);
   bool   ind2long  = ind2val1 > 0 + sigma && ind2val2 < 0 - sigma;
   bool   ind2short = ind2val1 < 0 - sigma && ind2val2 > 0 + sigma;

   return CreateExitSignal(6, ind1long || ind2long, ind1short || ind2short, 6904, 7177, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_007()
  {
   // Commodity Channel Index (Typical, 36), Level: 100
   double ind0val1  = iCCI(NULL, 0, 36, PRICE_TYPICAL, 1);
   double ind0val2  = iCCI(NULL, 0, 36, PRICE_TYPICAL, 2);
   bool   ind0long  = ind0val1 < 100 - sigma && ind0val2 > 100 + sigma;
   bool   ind0short = ind0val1 > -100 + sigma && ind0val2 < -100 - sigma;
   // Alligator (Smoothed, Median, 32, 23, 23, 7, 7, 3)
   double ind1val1  = iAlligator(NULL, 0, 32, 23, 23, 7, 7, 3, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  1);
   double ind1val2  = iAlligator(NULL, 0, 32, 23, 23, 7, 7, 3, MODE_SMMA, PRICE_MEDIAN, MODE_GATORLIPS,  2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateEntrySignal(7, ind0long && ind1long, ind0short && ind1short, 6367, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_007()
  {
   // Moving Averages Crossover (Simple, Simple, 25, 47)
   double ind2val1  = iMA(NULL, 0, 25, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind2val2  = iMA(NULL, 0, 47, 0, MODE_SMA, PRICE_CLOSE, 1);
   double ind2val3  = iMA(NULL, 0, 25, 0, MODE_SMA, PRICE_CLOSE, 2);
   double ind2val4  = iMA(NULL, 0, 47, 0, MODE_SMA, PRICE_CLOSE, 2);
   bool   ind2long  = ind2val1 > ind2val2 + sigma && ind2val3 < ind2val4 - sigma;
   bool   ind2short = ind2val1 < ind2val2 - sigma && ind2val3 > ind2val4 + sigma;

   return CreateExitSignal(7, ind2long, ind2short, 6367, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_008()
  {
   // Bollinger Bands (Close, 12, 3.03)
   double ind0upBand1 = iBands(NULL, 0, 12, 3.03, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind0dnBand1 = iBands(NULL, 0, 12, 3.03, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind0upBand2 = iBands(NULL, 0, 12, 3.03, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind0dnBand2 = iBands(NULL, 0, 12, 3.03, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0dnBand1 - sigma && Open(1) > ind0dnBand2 + sigma;
   bool   ind0short   = Open(0) > ind0upBand1 + sigma && Open(1) < ind0upBand2 - sigma;

   return CreateEntrySignal(8, ind0long, ind0short, 3527, 7655, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_008()
  {
   // Candle Color (21, 5)
   bool ind1long  = false;
   bool ind1short = false;
   {
      int consecutiveBullish = 0;
      int consecutiveBearish = 0;
      double pipVal = pip * 21;

      for (int b = 5 + 2; b > 0; b--)
        {
         consecutiveBullish = Close(b) - Open(b) >= pipVal ? consecutiveBullish + 1 : 0;
         consecutiveBearish = Open(b) - Close(b) >= pipVal ? consecutiveBearish + 1 : 0;
        }

      ind1long  = consecutiveBearish >= 5;
      ind1short = consecutiveBullish >= 5;
   }

   return CreateExitSignal(8, ind1long, ind1short, 3527, 7655, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_009()
  {
   // Envelopes (Close, Simple, 16, 0.24)
   double ind0upBand1 = iEnvelopes(NULL, 0, 16, MODE_SMA, 0, PRICE_CLOSE, 0.24, MODE_UPPER, 1);
   double ind0dnBand1 = iEnvelopes(NULL, 0, 16, MODE_SMA, 0, PRICE_CLOSE, 0.24, MODE_LOWER, 1);
   double ind0upBand2 = iEnvelopes(NULL, 0, 16, MODE_SMA, 0, PRICE_CLOSE, 0.24, MODE_UPPER, 2);
   double ind0dnBand2 = iEnvelopes(NULL, 0, 16, MODE_SMA, 0, PRICE_CLOSE, 0.24, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0upBand1 - sigma && Open(1) > ind0upBand2 + sigma;
   bool   ind0short   = Open(0) > ind0dnBand1 + sigma && Open(1) < ind0dnBand2 - sigma;
   // RSI (Close, 41)
   double ind1val1  = iRSI(NULL, 0, 41, PRICE_CLOSE, 1);
   double ind1val2  = iRSI(NULL, 0, 41, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > ind1val2 + sigma;
   bool   ind1short = ind1val1 < ind1val2 - sigma;

   return CreateEntrySignal(9, ind0long && ind1long, ind0short && ind1short, 7454, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_009()
  {
   // Commodity Channel Index (Typical, 50), Level: 100
   double ind2val1  = iCCI(NULL, 0, 50, PRICE_TYPICAL, 1);
   bool   ind2long  = ind2val1 > 100 + sigma;
   bool   ind2short = ind2val1 < -100 - sigma;

   return CreateExitSignal(9, ind2long, ind2short, 7454, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_INIT_RETCODE ValidateInit()
  {
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
/*STRATEGY MARKET Premium Data; XAUUSD; M15 */
