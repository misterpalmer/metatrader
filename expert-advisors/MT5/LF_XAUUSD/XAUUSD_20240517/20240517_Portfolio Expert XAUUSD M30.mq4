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

const int    strategiesCount = 5;
const double sigma        = 0.000001;
const int    requiredBars = 52;

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

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":6871,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Awesome Oscillator","listIndexes":[4,-1,-1,-1,-1],"numValues":[-6.2,0,0,0,0,0]},{"name":"Williams' Percent Range","listIndexes":[1,-1,-1,-1,-1],"numValues":[48,-20,0,0,0,0]}],"closeFilters":[{"name":"Awesome Oscillator","listIndexes":[2,-1,-1,-1,-1],"numValues":[0,0,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_000();
   signalList[i++] = GetEntrySignal_000();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":4157,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Envelopes","listIndexes":[2,3,0,-1,-1],"numValues":[20,0.88,0,0,0,0]}],"closeFilters":[{"name":"Bears Power","listIndexes":[3,-1,-1,-1,-1],"numValues":[1,0,0,0,0,0]},{"name":"MACD","listIndexes":[4,3,-1,-1,-1],"numValues":[6,20,9,0,0,0]}]} */
   signalList[i++] = GetExitSignal_001();
   signalList[i++] = GetEntrySignal_001();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":9921,"takeProfit":2372,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":false},"openFilters":[{"name":"Stochastic","listIndexes":[5,-1,-1,-1,-1],"numValues":[9,2,7,29,0,0]}],"closeFilters":[{"name":"Bulls Power","listIndexes":[4,-1,-1,-1,-1],"numValues":[41,-18,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_002();
   signalList[i++] = GetEntrySignal_002();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":7731,"takeProfit":1000,"useStopLoss":true,"useTakeProfit":false,"isTrailingStop":false},"openFilters":[{"name":"Accelerator Oscillator","listIndexes":[5,-1,-1,-1,-1],"numValues":[0,0,0,0,0,0]}],"closeFilters":[{"name":"Bollinger Bands","listIndexes":[4,3,-1,-1,-1],"numValues":[2,3.7,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_003();
   signalList[i++] = GetEntrySignal_003();

   /*STRATEGY CODE {"properties":{"entryLots":0.1,"tradeDirectionMode":0,"oppositeEntrySignal":0,"stopLoss":8333,"takeProfit":2744,"useStopLoss":true,"useTakeProfit":true,"isTrailingStop":true},"openFilters":[{"name":"Directional Indicators","listIndexes":[1,-1,-1,-1,-1],"numValues":[20,0,0,0,0,0]},{"name":"Commodity Channel Index","listIndexes":[3,5,-1,-1,-1],"numValues":[7,100,0,0,0,0]}],"closeFilters":[{"name":"Momentum","listIndexes":[3,3,-1,-1,-1],"numValues":[35,98,0,0,0,0]}]} */
   signalList[i++] = GetExitSignal_004();
   signalList[i++] = GetEntrySignal_004();

   HideTestIndicators(false);
   if(i != 2 * strategiesCount)
      ArrayResize(signalList, i);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_000()
  {
   // Awesome Oscillator, Level: -6.2000
   double ind0val1  = iAO(NULL, 0, 1);
   double ind0val2  = iAO(NULL, 0, 2);
   bool   ind0long  = ind0val1 > -6.2000 + sigma && ind0val2 < -6.2000 - sigma;
   bool   ind0short = ind0val1 < 6.2000 - sigma && ind0val2 > 6.2000 + sigma;
   // Williams' Percent Range (48)
   double ind1val1  = iWPR(NULL, 0, 48, 1);
   double ind1val2  = iWPR(NULL, 0, 48, 2);
   bool   ind1long  = ind1val1 < ind1val2 - sigma;
   bool   ind1short = ind1val1 > ind1val2 + sigma;

   return CreateEntrySignal(0, ind0long && ind1long, ind0short && ind1short, 6871, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_000()
  {
   // Awesome Oscillator, Level: 0.0000
   double ind2val1  = iAO(NULL, 0, 1);
   bool   ind2long  = ind2val1 > 0.0000 + sigma;
   bool   ind2short = ind2val1 < 0.0000 - sigma;

   return CreateExitSignal(0, ind2long, ind2short, 6871, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_001()
  {
   // Envelopes (Close, Simple, 20, 0.88)
   double ind0upBand1 = iEnvelopes(NULL, 0, 20, MODE_SMA, 0, PRICE_CLOSE, 0.88, MODE_UPPER, 1);
   double ind0dnBand1 = iEnvelopes(NULL, 0, 20, MODE_SMA, 0, PRICE_CLOSE, 0.88, MODE_LOWER, 1);
   double ind0upBand2 = iEnvelopes(NULL, 0, 20, MODE_SMA, 0, PRICE_CLOSE, 0.88, MODE_UPPER, 2);
   double ind0dnBand2 = iEnvelopes(NULL, 0, 20, MODE_SMA, 0, PRICE_CLOSE, 0.88, MODE_LOWER, 2);
   bool   ind0long    = Open(0) < ind0upBand1 - sigma && Open(1) > ind0upBand2 + sigma;
   bool   ind0short   = Open(0) > ind0dnBand1 + sigma && Open(1) < ind0dnBand2 - sigma;

   return CreateEntrySignal(1, ind0long, ind0short, 4157, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_001()
  {
   // Bears Power (1), Level: 0.0000
   double ind1val1  = iBearsPower(NULL, 0, 1, PRICE_CLOSE, 1);
   bool   ind1long  = ind1val1 < 0.0000 - sigma;
   bool   ind1short = ind1val1 > 0.0000 + sigma;
   // MACD (Close, 6, 20, 9)
   double ind2val1  = iMACD(NULL, 0, 6, 20, 9, PRICE_CLOSE, MODE_MAIN, 1);
   double ind2val2  = iMACD(NULL, 0, 6, 20, 9, PRICE_CLOSE, MODE_MAIN, 2);
   bool   ind2long  = ind2val1 > 0 + sigma && ind2val2 < 0 - sigma;
   bool   ind2short = ind2val1 < 0 - sigma && ind2val2 > 0 + sigma;

   return CreateExitSignal(1, ind1long || ind2long, ind1short || ind2short, 4157, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_002()
  {
   // Stochastic (9, 2, 7), Level: 29.0
   double ind0val1  = iStochastic(NULL, 0, 9, 2, 7, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
   double ind0val2  = iStochastic(NULL, 0, 9, 2, 7, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 2);
   bool   ind0long  = ind0val1 < 29.0 - sigma && ind0val2 > 29.0 + sigma;
   bool   ind0short = ind0val1 > 100 - 29.0 + sigma && ind0val2 < 100 - 29.0 - sigma;

   return CreateEntrySignal(2, ind0long, ind0short, 9921, 2372, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_002()
  {
   // Bulls Power (41), Level: -18.0000
   double ind1val1  = iBullsPower(NULL, 0, 41, PRICE_CLOSE, 1);
   double ind1val2  = iBullsPower(NULL, 0, 41, PRICE_CLOSE, 2);
   bool   ind1long  = ind1val1 > -18.0000 + sigma && ind1val2 < -18.0000 - sigma;
   bool   ind1short = ind1val1 < 18.0000 - sigma && ind1val2 > 18.0000 + sigma;

   return CreateExitSignal(2, ind1long, ind1short, 9921, 2372, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_003()
  {
   // Accelerator Oscillator, Level: 0.0000
   double ind0val1  = iAC(NULL, 0, 1);
   double ind0val2  = iAC(NULL, 0, 2);
   bool   ind0long  = ind0val1 < 0.0000 - sigma && ind0val2 > 0.0000 + sigma;
   bool   ind0short = ind0val1 > 0.0000 + sigma && ind0val2 < 0.0000 - sigma;

   return CreateEntrySignal(3, ind0long, ind0short, 7731, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_003()
  {
   // Bollinger Bands (Close, 2, 3.70)
   double ind1upBand1 = iBands(NULL, 0, 2, 3.70, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double ind1dnBand1 = iBands(NULL, 0, 2, 3.70, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double ind1upBand2 = iBands(NULL, 0, 2, 3.70, 0, PRICE_CLOSE, MODE_UPPER, 2);
   double ind1dnBand2 = iBands(NULL, 0, 2, 3.70, 0, PRICE_CLOSE, MODE_LOWER, 2);
   bool   ind1long    = Open(0) < ind1dnBand1 - sigma && Open(1) > ind1dnBand2 + sigma;
   bool   ind1short   = Open(0) > ind1upBand1 + sigma && Open(1) < ind1upBand2 - sigma;

   return CreateExitSignal(3, ind1long, ind1short, 7731, 0, false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_004()
  {
   // Directional Indicators (20)
   double ind0val1  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 1);
   double ind0val2  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 1);
   double ind0val3  = iADX(NULL, 0, 20, PRICE_CLOSE, 1, 2);
   double ind0val4  = iADX(NULL ,0 ,20, PRICE_CLOSE, 2, 2);
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Commodity Channel Index (Typical, 7), Level: 100
   double ind1val1  = iCCI(NULL, 0, 7, PRICE_TYPICAL, 1);
   bool   ind1long  = ind1val1 < 100 - sigma;
   bool   ind1short = ind1val1 > -100 + sigma;

   return CreateEntrySignal(4, ind0long && ind1long, ind0short && ind1short, 8333, 2744, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetExitSignal_004()
  {
   // Momentum (Close, 35), Level: 98.0000
   double ind2val1  = iMomentum(NULL, 0, 35, PRICE_CLOSE, 1);
   bool   ind2long  = ind2val1 < 98.0000 - sigma;
   bool   ind2short = ind2val1 > 200 - 98.0000 + sigma;

   return CreateExitSignal(4, ind2long, ind2short, 8333, 2744, true);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
ENUM_INIT_RETCODE ValidateInit()
  {
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
/*STRATEGY MARKET Premium Data; XAUUSD; M30 */
