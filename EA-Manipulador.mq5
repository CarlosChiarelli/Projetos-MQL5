//+------------------------------------------------------------------+
//|                                               EA-Manipulador.mq5 |
//|                                               Joscelino Oliveira |
//|                                   https://www.mathematice.mat.br |
//+------------------------------------------------------------------+
#property copyright "Joscelino Oliveira"
#property link      "https://www.mathematice.mat.br"
#property version   "1.00"
#include <Trade\TerminalInfo.mqh>   //-- Informacoes do Terminal
#include <Trade\SymbolInfo.mqh>     //-- Informacoes do ativo
#include <Trade\AccountInfo.mqh>    //-- Informacoes da conta
CTerminalInfo terminal;
CSymbolInfo mysymbol;
CAccountInfo myaccount;
//+------------------------------------------------------------------+ 
//| Expert initialization function                                   | 
//+------------------------------------------------------------------+ 
int OnInit() 
  { 
//--- 
   PrintFormat("LAST PING=%.f ms", 
               TerminalInfoInteger(TERMINAL_PING_LAST)/1000.); 
//--- 
   return(INIT_SUCCEEDED); 
  } 
//+------------------------------------------------------------------+ 
//| Expert tick function                                             | 
//+------------------------------------------------------------------+ 
void OnTick() 
  { 
//--- 
  bool flag = SERIES_SYNCHRONIZED;
  if(flag==false)
    {
     Alert("EA manipulador constatou dados nao sincronizados!");
     Sleep(5000);
    }
    
//-- TESTANDO A CONEXAO PRINCIPAL DO TERMINAL COM O SERVIDOR DA CORRETORA  

   if(terminal.IsConnected()==false)
     {
      Print("Terminal nao conectado ao servidor da corretora!");
      SendMail("URGENTE - MT5 Desconectado!!!","Terminal desconectou do servidor da corretora! Verifque URGENTE!");
      RefreshRates();
      double ping =  TerminalInfoInteger(TERMINAL_PING_LAST)/1000; //-- Último valor conhecido do ping até ao servidor de negociação em microssegundos
      Print("Last ping antes da desconexao: ",ping);
      Sleep(10000);
     }

//-- TESTE DE CONEXAO
      
   while(checkTrading()==false)
     {
      Alert("Negociacao nao permitida!");
      Sleep(5000);
      }

  } 
//+------------------------------------------------------------------+ 
//| TradeTransaction function                                        | 
//+------------------------------------------------------------------+ 
void OnTradeTransaction(const MqlTradeTransaction &trans, 
                        const MqlTradeRequest &request, 
                        const MqlTradeResult &result) 
  { 
//--- 
   static int counter=0;   // contador de chamadas da OnTradeTransaction() 
   static uint lasttime=0; // hora da última chamada da OnTradeTransaction() 
//--- 
   uint time=GetTickCount(); 
//--- se a última operação tiver sido realizada há mais de 1 segundo, 
   if(time-lasttime>1000) 
     { 
      counter=0; // significa que se trata de uma nova operação de negociação e, portanto, podemos redefinir o contador 
      if(IS_DEBUG_MODE) 
         Print(" Nova operação de negociação"); 
     } 
   lasttime=time; 
   counter++; 
   Print(counter,". ",__FUNCTION__); 
//--- resultado da execução do pedido de negociação 
   ulong            lastOrderID   =trans.order; 
   ENUM_ORDER_TYPE  lastOrderType =trans.order_type; 
   ENUM_ORDER_STATE lastOrderState=trans.order_state; 
//--- nome do símbolo segundo o qual foi realizada a transação 
   string trans_symbol=trans.symbol; 
//--- tipo de transação 
   ENUM_TRADE_TRANSACTION_TYPE  trans_type=trans.type; 
   switch(trans.type) 
     { 
      case  TRADE_TRANSACTION_POSITION:   // alteração da posição 
        { 
         ulong pos_ID=trans.position; 
         PrintFormat("MqlTradeTransaction: Position  #%d %s modified: SL=%.5f TP=%.5f", 
                     pos_ID,trans_symbol,trans.price_sl,trans.price_tp); 
        } 
      break; 
      case TRADE_TRANSACTION_REQUEST:     // envio do pedido de negociação 
         PrintFormat("MqlTradeTransaction: TRADE_TRANSACTION_REQUEST"); 
         break; 
      case TRADE_TRANSACTION_DEAL_ADD:    // adição da transação 
        { 
         ulong          lastDealID   =trans.deal; 
         ENUM_DEAL_TYPE lastDealType =trans.deal_type; 
         double        lastDealVolume=trans.volume; 
         //--- identificador da transação no sistema externo - bilhete atribuído pela bolsa 
         string Exchange_ticket=""; 
         if(HistoryDealSelect(lastDealID)) 
            Exchange_ticket=HistoryDealGetString(lastDealID,DEAL_EXTERNAL_ID); 
         if(Exchange_ticket!="") 
            Exchange_ticket=StringFormat("(Exchange deal=%s)",Exchange_ticket); 
  
         PrintFormat("MqlTradeTransaction: %s deal #%d %s %s %.2f lot   %s",EnumToString(trans_type), 
                     lastDealID,EnumToString(lastDealType),trans_symbol,lastDealVolume,Exchange_ticket); 
        } 
      break; 
      case TRADE_TRANSACTION_HISTORY_ADD: // adição da ordem ao histórico 
        { 
         //--- identificador da transação no sistema externo - bilhete atribuído pela bolsa 
         string Exchange_ticket=""; 
         if(lastOrderState==ORDER_STATE_FILLED) 
           { 
            if(HistoryOrderSelect(lastOrderID)) 
               Exchange_ticket=HistoryOrderGetString(lastOrderID,ORDER_EXTERNAL_ID); 
            if(Exchange_ticket!="") 
               Exchange_ticket=StringFormat("(Exchange ticket=%s)",Exchange_ticket); 
           } 
         PrintFormat("MqlTradeTransaction: %s order #%d %s %s %s   %s",EnumToString(trans_type), 
                     lastOrderID,EnumToString(lastOrderType),trans_symbol,EnumToString(lastOrderState),Exchange_ticket); 
        } 
      break; 
      default: // outras transações   
        { 
         //--- identificador da ordem no sistema externo - bilhete atribuído pela Bolsa de Valores 
         string Exchange_ticket=""; 
         if(lastOrderState==ORDER_STATE_PLACED) 
           { 
            if(OrderSelect(lastOrderID)) 
               Exchange_ticket=OrderGetString(ORDER_EXTERNAL_ID); 
            if(Exchange_ticket!="") 
               Exchange_ticket=StringFormat("Exchange ticket=%s",Exchange_ticket); 
           } 
         PrintFormat("MqlTradeTransaction: %s order #%d %s %s   %s",EnumToString(trans_type), 
                     lastOrderID,EnumToString(lastOrderType),EnumToString(lastOrderState),Exchange_ticket); 
        } 
      break; 
     } 
//--- bilhete da ordem     
   ulong orderID_result=result.order; 
   string retcode_result=GetRetcodeID(result.retcode); 
   if(orderID_result!=0) 
      PrintFormat("MqlTradeResult: order #%d retcode=%s ",orderID_result,retcode_result); 
//---    
  } 
//+------------------------------------------------------------------+ 
//| converte códigos numéricos de respostas em códigos Mnemonic de string        
//+------------------------------------------------------------------+ 
string GetRetcodeID(int retcode) 
  { 
   switch(retcode) 
     { 
      case 10004: return("TRADE_RETCODE_REQUOTE");             break; 
      case 10006: return("TRADE_RETCODE_REJECT");              break; 
      case 10007: return("TRADE_RETCODE_CANCEL");              break; 
      case 10008: return("TRADE_RETCODE_PLACED");              break; 
      case 10009: return("TRADE_RETCODE_DONE");                break; 
      case 10010: return("TRADE_RETCODE_DONE_PARTIAL");        break; 
      case 10011: return("TRADE_RETCODE_ERROR");               break; 
      case 10012: return("TRADE_RETCODE_TIMEOUT");             break; 
      case 10013: return("TRADE_RETCODE_INVALID");             break; 
      case 10014: return("TRADE_RETCODE_INVALID_VOLUME");      break; 
      case 10015: return("TRADE_RETCODE_INVALID_PRICE");       break; 
      case 10016: return("TRADE_RETCODE_INVALID_STOPS");       break; 
      case 10017: return("TRADE_RETCODE_TRADE_DISABLED");      break; 
      case 10018: return("TRADE_RETCODE_MARKET_CLOSED");       break; 
      case 10019: return("TRADE_RETCODE_NO_MONEY");            break; 
      case 10020: return("TRADE_RETCODE_PRICE_CHANGED");       break; 
      case 10021: return("TRADE_RETCODE_PRICE_OFF");           break; 
      case 10022: return("TRADE_RETCODE_INVALID_EXPIRATION");  break; 
      case 10023: return("TRADE_RETCODE_ORDER_CHANGED");       break; 
      case 10024: return("TRADE_RETCODE_TOO_MANY_REQUESTS");   break; 
      case 10025: return("TRADE_RETCODE_NO_CHANGES");          break; 
      case 10026: return("TRADE_RETCODE_SERVER_DISABLES_AT");  break; 
      case 10027: return("TRADE_RETCODE_CLIENT_DISABLES_AT");  break; 
      case 10028: return("TRADE_RETCODE_LOCKED");              break; 
      case 10029: return("TRADE_RETCODE_FROZEN");              break; 
      case 10030: return("TRADE_RETCODE_INVALID_FILL");        break; 
      case 10031: return("TRADE_RETCODE_CONNECTION");          break; 
      case 10032: return("TRADE_RETCODE_ONLY_REAL");           break; 
      case 10033: return("TRADE_RETCODE_LIMIT_ORDERS");        break; 
      case 10034: return("TRADE_RETCODE_LIMIT_VOLUME");        break; 
      case 10035: return("TRADE_RETCODE_INVALID_ORDER");       break; 
      case 10036: return("TRADE_RETCODE_POSITION_CLOSED");     break; 
      default: 
         return("TRADE_RETCODE_UNKNOWN="+IntegerToString(retcode)); 
         break; 
     } 
//--- 
  }
//+------------------------------------------------------------------+ 
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void)
  {
//--- refresh rates
   if(!mysymbol.RefreshRates())
     {
      printf("Falha com dados de preco!");
      return(false);
     }
//--- protection against the return value of "zero"
   if(mysymbol.Ask()==0 || mysymbol.Bid()==0)
      return(false);
//---
   return(true);
  }  
//+------------------------------------------------------------------+  
//+------------------------------------------------------------------+
//|  Checks if our Expert Advisor can go ahead and perform trading   |
//+------------------------------------------------------------------+
bool checkTrading()
  {
   bool can_trade=false;
// check if terminal is syncronized with server, etc
   if(myaccount.TradeAllowed() && myaccount.TradeExpert() && mysymbol.IsSynchronized())
     {
      // do we have enough bars?
      int mbars=Bars(_Symbol,_Period);
      if(mbars>0)
        {
         can_trade=true;
        }
     }
   return(can_trade);
  }
//+------------------------------------------------------------------+  