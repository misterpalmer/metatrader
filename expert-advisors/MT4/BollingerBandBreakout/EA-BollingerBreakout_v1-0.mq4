#property copyright     "EarnForex.com"
#property link          "https://www.earnforex.com/metatrader-expert-advisors/bollinger-bands-breakout/"
#property version       "1.00"
#property strict
#property description   "This Expert Advisor open orders at the breakout of Bollinger Bands"
#property description   " "
#property description   "DISCLAIMER: This code comes with no guarantee, you can use it at your own risk"
#property description   "We recommend to test it first on a Demo Account"

/*
The Alligator Indicator is basically a combination of 3 MA with different periods and shifts
ENTRY BUY: The price breaks above the top bollinger band
ENTRY SELL: The price breaks below the low bollinger band
EXIT: Fixed take profit or hit stop loss
Only 1 order at a time
*/


extern double LotSize=0.1;             //Position size

extern double StopLoss=20;             //Stop loss in pips
extern double TakeProfit=50;           //Take profit in pips

extern int Slippage=2;                 //Slippage in pips

extern bool TradeEnabled=true;         //Enable trade

//Functional variables
double ePoint;                         //Point normalized

bool CanOrder;                         //Check for risk management
bool CanOpenBuy;                       //Flag if there are buy orders open
bool CanOpenSell;                      //Flag if there are sell orders open

int OrderOpRetry=10;                   //Number of attempts to perform a trade operation
int SleepSecs=3;                       //Seconds to sleep if can't order
int MinBars=60;                        //Minimum bars in the graph to enable trading

//Functional variables to determine prices
double MinSL;
double MaxSL;
double TP;
double SL;
double Spread;
int Slip; 


//Variable initialization function
void Initialize(){          
   RefreshRates();
   ePoint=Point;
   Slip=Slippage;
   if (MathMod(Digits,2)==1){
      ePoint*=10;
      Slip*=10;
   }
   TP=TakeProfit*ePoint;
   SL=StopLoss*ePoint;
   CanOrder=TradeEnabled;
   CanOpenBuy=true;
   CanOpenSell=true;
}


//Check if orders can be submitted
void CheckCanOrder(){            
   if( Bars<MinBars ){
      Print("INFO - Not enough Bars to trade");
      CanOrder=false;
   }
   OrdersOpen();
   return;
}


//Check if there are open orders and what type
void OrdersOpen(){
   for( int i = 0 ; i < OrdersTotal() ; i++ ) {
      if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) == false ) {
         Print("ERROR - Unable to select the order - ",GetLastError());
         break;
      } 
      if( OrderSymbol()==Symbol() && OrderType() == OP_BUY) CanOpenBuy=false;
      if( OrderSymbol()==Symbol() && OrderType() == OP_SELL) CanOpenSell=false;
   }
   return;
}


//Close all the orders of a specific type and current symbol
void CloseAll(int Command){
   double ClosePrice=0;
   for( int i = 0 ; i < OrdersTotal() ; i++ ) {
      if( OrderSelect( i, SELECT_BY_POS, MODE_TRADES ) == false ) {
         Print("ERROR - Unable to select the order - ",GetLastError());
         break;
      }
      if( OrderSymbol()==Symbol() && OrderType()==Command) {
         if(Command==OP_BUY) ClosePrice=Bid;
         if(Command==OP_SELL) ClosePrice=Ask;
         double Lots=OrderLots();
         int Ticket=OrderTicket();
         for(int j=1; j<OrderOpRetry; j++){
            bool res=OrderClose(Ticket,Lots,ClosePrice,Slip,Red);
            if(res){
               Print("TRADE - CLOSE - Order ",Ticket," closed at price ",ClosePrice);
               break;
            }
            else Print("ERROR - CLOSE - error closing order ",Ticket," return error: ",GetLastError());
         }
      }
   }
   return;
}


//Open new order of a given type
void OpenNew(int Command){
   RefreshRates();
   double OpenPrice=0;
   double SLPrice = 0;
   double TPPrice = 0;
   if(Command==OP_BUY){
      OpenPrice=Ask;
      SLPrice=OpenPrice-SL;
      TPPrice=OpenPrice+TP;
   }
   if(Command==OP_SELL){
      OpenPrice=Bid;
      SLPrice=OpenPrice+SL;
      TPPrice=OpenPrice-TP;
   }
   for(int i=1; i<OrderOpRetry; i++){
      int res=OrderSend(Symbol(),Command,LotSize,OpenPrice,Slip,NormalizeDouble(SLPrice,Digits),NormalizeDouble(TPPrice,Digits),"",0,0,Green);
      if(res){
         Print("TRADE - NEW - Order ",res," submitted: Command ",Command," Volume ",LotSize," Open ",OpenPrice," Slippage ",Slip," Stop ",SLPrice," Take ",TPPrice);
         break;
      }
      else Print("ERROR - NEW - error sending order, return error: ",GetLastError());
   }
   return;
}


//Technical analysis of the indicators


extern int BandsPeriod = 200;          //Period of the Bollinger Bands
extern double BandsDeviation = 2;      //Deviation of the Bollinger Bands
bool BandsBreakUp=false;
bool BandsBreakDown=false;

void FindBandsTrend(){
   BandsBreakUp=false;
   BandsBreakDown=false;
   double BandsTopCurr=iBands(Symbol(),0,BandsPeriod,BandsDeviation,0,PRICE_CLOSE,MODE_UPPER,0);
   double BandsLowCurr=iBands(Symbol(),0,BandsPeriod,BandsDeviation,0,PRICE_CLOSE,MODE_LOWER,0);
   double BandsTopPrev=iBands(Symbol(),0,BandsPeriod,BandsDeviation,0,PRICE_CLOSE,MODE_UPPER,1);
   double BandsLowPrev=iBands(Symbol(),0,BandsPeriod,BandsDeviation,0,PRICE_CLOSE,MODE_LOWER,1);
   if(Close[1]<BandsTopPrev && Close[0]>BandsTopCurr) BandsBreakUp=true;
   if(Close[1]>BandsLowPrev && Close[0]<BandsLowCurr) BandsBreakDown=true;
}


//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   
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
   //Calling initialization, checks and technical analysis
   Initialize();
   CheckCanOrder();
   FindBandsTrend();
   //Check of Entry/Exit signal with operations to perform
   if(BandsBreakUp){
      if(CanOpenBuy && CanOpenSell && CanOrder) OpenNew(OP_BUY);
   }
   if(BandsBreakDown){
      if(CanOpenSell && CanOpenBuy && CanOrder) OpenNew(OP_SELL);
   }
  }
//+------------------------------------------------------------------+
