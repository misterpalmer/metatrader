//
// EA Studio Portfolio Expert Advisor
//
// Created with: Expert Advisor Studio
// Website: https://studio.eatradingacademy.com/
//
// Copyright 2024, Forex Software Ltd.
//
// This Portfolio Expert works in MetaTrader 5 hedging accounts.
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

#define TRADE_RETRY_COUNT 4
#define TRADE_RETRY_WAIT  100
#define OP_FLAT           -1
#define OP_BUY            ORDER_TYPE_BUY
#define OP_SELL           ORDER_TYPE_SELL

// Session time is set in seconds from 00:00
const int sessionSundayOpen           =     0; // 00:00
const int sessionSundayClose          = 86400; // 24:00
const int sessionMondayThursdayOpen   =     0; // 00:00
const int sessionMondayThursdayClose  = 86400; // 24:00
const int sessionFridayOpen           =     0; // 00:00
const int sessionFridayClose          = 86400; // 24:00
const bool sessionIgnoreSunday        = true;
const bool sessionCloseAtSessionClose = false;
const bool sessionCloseAtFridayClose  = false;

const int    strategiesCount = 5;
const double sigma        = 0.000001;
const int    requiredBars = 52;

datetime barTime;
double   stopLevel;
double   pip;
bool     setProtectionSeparately = false;
ENUM_ORDER_TYPE_FILLING orderFillingType = ORDER_FILLING_FOK;
int indHandlers[5][12][2];

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
   ulong  Ticket;
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
int OnInit()
  {
   barTime   = Time(0);
   stopLevel = (int) SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   pip       = GetPipValue();

   InitIndicatorHandlers();

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
   if(!MQLInfoInteger(MQL_TESTER))
      CheckProtections();

   if(IsForceSessionClose())
     {
      CloseAllPositions();
      return;
     }

   datetime time = Time(0);
   if(time > barTime)
     {
      barTime = time;
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

   for (int i = 0; i < signalsCount; i += 1)
      ManageSignal(signalList[i]);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageSignal(Signal &signal)
  {
   Position position = CreatePosition(signal.MagicNumber);

   if(position.Type != OP_FLAT && signal.Scope == ORDER_SCOPE_EXIT)
     {
      if( (signal.Direction == ORDER_DIRECTION_BOTH) ||
           (position.Type == OP_BUY  && signal.Direction == ORDER_DIRECTION_SELL) ||
           (position.Type == OP_SELL && signal.Direction == ORDER_DIRECTION_BUY ) )
        {
         ClosePosition(position);
         return;
        }

      if(signal.IsTrailingStop)
        {
         double trailingStop = GetTrailingStopPrice(position, signal.StopLossPips);
         ManageTrailingStop(position, trailingStop);
        }
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
         if(CountPositions() < Max_Open_Positions)
            OpenPosition(signal);
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int CountPositions(void)
  {
   const int minMagic = GetMagicNumber(0);
   const int maxMagic = GetMagicNumber(strategiesCount);
   const int posTotal = PositionsTotal();
   int count = 0;

   for (int posIndex = 0; posIndex < posTotal; posIndex += 1)
     {
      const ulong ticket = PositionGetTicket(posIndex);
      if(PositionSelectByTicket(ticket) && PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
         const long magicNumber = PositionGetInteger(POSITION_MAGIC);
         if(magicNumber >= minMagic && magicNumber <= maxMagic)
            count += 1;
        }
     }

   return count;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Position CreatePosition(const int magicNumber)
  {
   Position position;
   position.MagicNumber = magicNumber;
   position.Type        = OP_FLAT;
   position.Ticket      = 0;
   position.Lots        = 0;
   position.Price       = 0;
   position.StopLoss    = 0;
   position.TakeProfit  = 0;

   const int posTotal = PositionsTotal();
   for (int posIndex = 0; posIndex < posTotal; posIndex += 1)
     {
      const ulong ticket = PositionGetTicket(posIndex);
      if(PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magicNumber)
        {
         position.Type       = (int) PositionGetInteger(POSITION_TYPE);
         position.Ticket     = ticket;
         position.Lots       = NormalizeDouble( PositionGetDouble(POSITION_VOLUME),           2);
         position.Price      = NormalizeDouble( PositionGetDouble(POSITION_PRICE_OPEN), _Digits);
         position.StopLoss   = NormalizeDouble( PositionGetDouble(POSITION_SL),         _Digits);
         position.TakeProfit = NormalizeDouble( PositionGetDouble(POSITION_TP),         _Digits);
         break;
        }
     }

   return position;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal CreateEntrySignal(int strategyIndex, bool canOpenLong,    bool canOpenShort,
                         int stopLossPips,  int  takeProfitPips, bool isTrailingStop,
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

   const int    command    = OrderDirectionToCommand(signal.Direction);
   const double stopLoss   = GetStopLossPrice(command, signal.StopLossPips);
   const double takeProfit = GetTakeProfitPrice(command, signal.TakeProfitPips);

   ManageOrderSend(command, Entry_Amount, stopLoss, takeProfit, 0, signal.MagicNumber);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ClosePosition(Position &position)
  {
   const int command = position.Type == OP_BUY ? OP_SELL : OP_BUY;

   ManageOrderSend(command, position.Lots, 0, 0, position.Ticket, position.MagicNumber);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void CloseAllPositions(void)
  {
   for (int i = 0; i < strategiesCount; i += 1)
     {
      const int magicNumber = GetMagicNumber(i);
      Position position = CreatePosition(magicNumber);

      if(position.Type == OP_BUY || position.Type == OP_SELL)
         ClosePosition(position);
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ManageOrderSend(int command, double lots, double stopLoss, double takeProfit, ulong ticket, int magicNumber)
  {
   for(int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      if(IsTradeContextFree())
        {
         MqlTradeRequest request;
         MqlTradeResult  result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action       = TRADE_ACTION_DEAL;
         request.symbol       = _Symbol;
         request.volume       = lots;
         request.type         = command == OP_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         request.price        = command == OP_BUY ? Ask() : Bid();
         request.type_filling = orderFillingType;
         request.deviation    = 10;
         request.sl           = stopLoss;
         request.tp           = takeProfit;
         request.magic        = magicNumber;
         request.position     = ticket;
         request.comment      = IntegerToString(magicNumber);

         bool isOrderCheck = CheckOrder(request);
         bool isOrderSend  = false;

         if(isOrderCheck)
           {
            ResetLastError();
            isOrderSend = OrderSend(request, result);
           }

         if(isOrderCheck && isOrderSend && result.retcode == TRADE_RETCODE_DONE)
            return;
        }

      Sleep(TRADE_RETRY_WAIT);
      Print("Order Send retry " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ModifyPosition(double stopLoss, double takeProfit, ulong ticket, int magicNumber)
  {
   for (int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
     {
      if( IsTradeContextFree() )
        {
         MqlTradeRequest request;
         MqlTradeResult  result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action   = TRADE_ACTION_SLTP;
         request.symbol   = _Symbol;
         request.sl       = stopLoss;
         request.tp       = takeProfit;
         request.magic    = magicNumber;
         request.position = ticket;
         request.comment  = IntegerToString(magicNumber);

         bool isOrderCheck = CheckOrder(request);
         bool isOrderSend  = false;

         if(isOrderCheck)
           {
            ResetLastError();
            isOrderSend = OrderSend(request, result);
           }

         if(isOrderCheck && isOrderSend && result.retcode == TRADE_RETCODE_DONE)
            return;
        }

      Sleep(TRADE_RETRY_WAIT);
      Print("Order Send retry no: " + IntegerToString(attempt + 2));
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckOrder(MqlTradeRequest &request)
  {
   MqlTradeCheckResult check;
   ZeroMemory(check);
   ResetLastError();

   if(OrderCheck(request, check))
      return true;

   Print("Error with OrderCheck: " + check.comment);

   if(check.retcode == TRADE_RETCODE_INVALID_FILL)
     {
      switch (orderFillingType)
        {
         case ORDER_FILLING_FOK:
            Print("Filling mode changed to: ORDER_FILLING_IOC");
            orderFillingType = ORDER_FILLING_IOC;
            break;
         case ORDER_FILLING_IOC:
            Print("Filling mode changed to: ORDER_FILLING_RETURN");
            orderFillingType = ORDER_FILLING_RETURN;
            break;
         case ORDER_FILLING_RETURN:
            Print("Filling mode changed to: ORDER_FILLING_FOK");
            orderFillingType = ORDER_FILLING_FOK;
            break;
        }

      request.type_filling = orderFillingType;

      return CheckOrder(request);
     }

   return false;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetStopLossPrice(const int command, const int stopLossPips)
  {
   if(stopLossPips == 0)
      return 0;

   const double delta    = MathMax(pip * stopLossPips, _Point * stopLevel);
   const double stopLoss = command == OP_BUY ? Bid() - delta : Ask() + delta;

   return NormalizeDouble(stopLoss, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTakeProfitPrice(const int command, const int takeProfitPips)
  {
   if(takeProfitPips == 0)
      return 0;

   const double delta      = MathMax(pip * takeProfitPips, _Point * stopLevel);
   const double takeProfit = command == OP_BUY ? Bid() + delta : Ask() - delta;

   return NormalizeDouble(takeProfit, _Digits);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetTrailingStopPrice(Position &position, const int stopLoss)
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
      ModifyPosition(position.StopLoss, position.TakeProfit, position.Ticket, position.MagicNumber);
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

      if(IsTradeAllowed())
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
   return SymbolInfoDouble(_Symbol, SYMBOL_BID);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Ask(void)
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
datetime Time(int bar)
  {
   datetime buffer[];
   ArrayResize(buffer, 1);
   return CopyTime(_Symbol, _Period, bar, 1, buffer) == 1 ? buffer[0] : 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Open(int bar)
  {
   double buffer[];
   ArrayResize(buffer, 1);
   return CopyOpen(_Symbol, _Period, bar, 1, buffer) == 1 ? buffer[0] : 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double High(int bar)
  {
   double buffer[];
   ArrayResize(buffer, 1);
   return CopyHigh(_Symbol, _Period, bar, 1, buffer) == 1 ? buffer[0] : 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Low(int bar)
  {
   double buffer[];
   ArrayResize(buffer, 1);
   return CopyLow(_Symbol, _Period, bar, 1, buffer) == 1 ? buffer[0] : 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double Close(int bar)
  {
   double buffer[];
   ArrayResize(buffer, 1);
   return CopyClose(_Symbol, _Period, bar, 1, buffer) == 1 ? buffer[0] : 0;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double GetPipValue(void)
  {
   return _Digits == 4 || _Digits == 5 ? 0.0001
        : _Digits == 2 || _Digits == 3 ? 0.01
                        : _Digits == 1 ? 0.1 : 1;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsTradeAllowed(void)
  {
   return (bool) MQL5InfoInteger(MQL5_TRADE_ALLOWED);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void RefreshRates(void)
  {
   // A stub function to make it compatible with MQL4
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int DayOfWeek(void)
  {
   MqlDateTime mqlTime;
   TimeToStruct(Time(0), mqlTime);
   return mqlTime.day_of_week;
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

   for (int attempt = 0; attempt < TRADE_RETRY_COUNT; attempt += 1)
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
   datetime t0 = TimeCurrent();
   datetime t1 = t0 - 60*60*24; // 24 hours ago

   if(!HistorySelect(t1, t0)) return 0;

   int    deals = HistoryDealsTotal();
   double dailyProfit = 0.0;

   for(int i=0; i < deals; i+=1) {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket > 0) {
         dailyProfit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
         dailyProfit -= HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         dailyProfit -= HistoryDealGetDouble(ticket, DEAL_SWAP);
      }
   }

   for(int i = PositionsTotal()-1; i >= 0; i-=1) {
    ulong ticket = PositionGetTicket(i);
    if(PositionSelectByTicket(ticket)) {
        dailyProfit += PositionGetDouble(POSITION_PROFIT);
        dailyProfit -= PositionGetDouble(POSITION_SWAP);
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
ENUM_INIT_RETCODE ValidateInit(void)
  {
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void InitIndicatorHandlers(void)
  {
   TesterHideIndicators(true);
   // Awesome Oscillator, Level: -6.2000
   indHandlers[0][0][0] = iAO(NULL, 0);
   // Williams' Percent Range (48)
   indHandlers[0][1][0] = iWPR(NULL, 0, 48);
   // Awesome Oscillator, Level: 0.0000
   indHandlers[0][2][0] = iAO(NULL, 0);
   // Envelopes (Close, Simple, 20, 0.88)
   indHandlers[1][0][0] = iEnvelopes(NULL, 0, 20, 0, MODE_SMA, PRICE_CLOSE, 0.88);
   // Bears Power (1), Level: 0.0000
   indHandlers[1][1][0] = iBearsPower(NULL, 0, 1);
   // MACD (Close, 6, 20, 9)
   indHandlers[1][2][0] = iMACD(NULL, 0, 6, 20, 9, PRICE_CLOSE);
   // Stochastic (9, 2, 7), Level: 29.0
   indHandlers[2][0][0] = iStochastic(NULL, 0, 9, 2, 7, MODE_SMA, 0);
   // Bulls Power (41), Level: -18.0000
   indHandlers[2][1][0] = iBullsPower(NULL, 0, 41);
   // Accelerator Oscillator, Level: 0.0000
   indHandlers[3][0][0] = iAC(NULL, 0);
   // Bollinger Bands (Close, 2, 3.70)
   indHandlers[3][1][0] = iBands(NULL, 0, 2, 0, 3.70, PRICE_CLOSE);
   // Directional Indicators (20)
   indHandlers[4][0][0] = iADX(NULL, 0, 20);
   // Commodity Channel Index (Typical, 7), Level: 100
   indHandlers[4][1][0] = iCCI(NULL, 0, 7, PRICE_TYPICAL);
   // Momentum (Close, 35), Level: 98.0000
   indHandlers[4][2][0] = iMomentum(NULL, 0, 35, PRICE_CLOSE);
   TesterHideIndicators(false);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetSignals(Signal &signalList[])
  {
   int i = 0;
   ArrayResize(signalList, 2 * strategiesCount);

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

   if(i != 2 * strategiesCount)
      ArrayResize(signalList, i);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
Signal GetEntrySignal_000()
  {
   // Awesome Oscillator, Level: -6.2000
   double ind0buffer[]; CopyBuffer(indHandlers[0][0][0], 0, 1, 3, ind0buffer);
   double ind0val1  = ind0buffer[2];
   double ind0val2  = ind0buffer[1];
   bool   ind0long  = ind0val1 > -6.2000 + sigma && ind0val2 < -6.2000 - sigma;
   bool   ind0short = ind0val1 < 6.2000 - sigma && ind0val2 > 6.2000 + sigma;
   // Williams' Percent Range (48)
   double ind1buffer[]; CopyBuffer(indHandlers[0][1][0], 0, 1, 3, ind1buffer);
   double ind1val1  = ind1buffer[2];
   double ind1val2  = ind1buffer[1];
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
   double ind2buffer[]; CopyBuffer(indHandlers[0][2][0], 0, 1, 3, ind2buffer);
   double ind2val1  = ind2buffer[2];
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
   double ind0buffer0[]; CopyBuffer(indHandlers[1][0][0], 0, 1, 2, ind0buffer0);
   double ind0buffer1[]; CopyBuffer(indHandlers[1][0][0], 1, 1, 2, ind0buffer1);
   double ind0upBand1 = ind0buffer0[1];
   double ind0dnBand1 = ind0buffer1[1];
   double ind0upBand2 = ind0buffer0[0];
   double ind0dnBand2 = ind0buffer1[0];
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
   double ind1buffer[]; CopyBuffer(indHandlers[1][1][0], 0, 1, 3, ind1buffer);
   double ind1val1  = ind1buffer[2];
   bool   ind1long  = ind1val1 < 0.0000 - sigma;
   bool   ind1short = ind1val1 > 0.0000 + sigma;
   // MACD (Close, 6, 20, 9)
   double ind2buffer[]; CopyBuffer(indHandlers[1][2][0], 0, 1, 3, ind2buffer);
   double ind2val1  = ind2buffer[2];
   double ind2val2  = ind2buffer[1];
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
   double ind0buffer[]; CopyBuffer(indHandlers[2][0][0], MAIN_LINE, 1, 3, ind0buffer);
   double ind0val1  = ind0buffer[2];
   double ind0val2  = ind0buffer[1];
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
   double ind1buffer[]; CopyBuffer(indHandlers[2][1][0], 0, 1, 3, ind1buffer);
   double ind1val1  = ind1buffer[2];
   double ind1val2  = ind1buffer[1];
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
   double ind0buffer[]; CopyBuffer(indHandlers[3][0][0], 0, 1, 3, ind0buffer);
   double ind0val1  = ind0buffer[2];
   double ind0val2  = ind0buffer[1];
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
   double ind1buffer0[]; CopyBuffer(indHandlers[3][1][0], 1, 1, 2, ind1buffer0);
   double ind1buffer1[]; CopyBuffer(indHandlers[3][1][0], 2, 1, 2, ind1buffer1);
   double ind1upBand1 = ind1buffer0[1];
   double ind1dnBand1 = ind1buffer1[1];
   double ind1upBand2 = ind1buffer0[0];
   double ind1dnBand2 = ind1buffer1[0];
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
   double ind0buffer0[]; CopyBuffer(indHandlers[4][0][0], 1, 1, 2, ind0buffer0);
   double ind0buffer1[]; CopyBuffer(indHandlers[4][0][0], 2, 1, 2, ind0buffer1);
   double ind0val1  = ind0buffer0[1];
   double ind0val2  = ind0buffer1[1];
   double ind0val3  = ind0buffer0[0];
   double ind0val4  = ind0buffer1[0];
   bool   ind0long  = ind0val1 < ind0val2 - sigma && ind0val3 > ind0val4 + sigma;
   bool   ind0short = ind0val1 > ind0val2 + sigma && ind0val3 < ind0val4 - sigma;
   // Commodity Channel Index (Typical, 7), Level: 100
   double ind1buffer[]; CopyBuffer(indHandlers[4][1][0], 0, 1, 3, ind1buffer);
   double ind1val1  = ind1buffer[2];
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
   double ind2buffer[]; CopyBuffer(indHandlers[4][2][0], 0, 1, 3, ind2buffer);
   double ind2val1  = ind2buffer[2];
   bool   ind2long  = ind2val1 < 98.0000 - sigma;
   bool   ind2short = ind2val1 > 200 - 98.0000 + sigma;

   return CreateExitSignal(4, ind2long, ind2short, 8333, 2744, true);
  }
//+------------------------------------------------------------------+
/*STRATEGY MARKET Premium Data; XAUUSD; M30 */
