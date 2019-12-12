//+------------------------------------------------------------------+
//|                                              DOL-FAREY-BROWN.mq5 |
//|                                               Joscelino Oliveira |
//|                                   https://www.mathematice.mat.br |
//+------------------------------------------------------------------+
#property copyright "Joscelino Oliveira"
#property link      "https://www.mathematice.mat.br"
#property version   "5.00"
//+------------------------------------------------------------------+
//| Bibliotecas Padronizadas do MQL5                                 |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>                   //-- classe para negociação
#include <Trade\TerminalInfo.mqh>            //-- Informacoes do Terminal
#include <Trade\AccountInfo.mqh>             //-- Informacoes da conta
#include <Trade\SymbolInfo.mqh>              //-- Informacoes do ativo

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Numerando o Expert                                               |
//+------------------------------------------------------------------+
static   int            expert = MathRand(); //-- Gerando numero pseudo-aleatorio para numerar EA
#define  EXPERT_MAGIC   expert

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Classes a serem utilizadas                                       |
//+------------------------------------------------------------------+
CTerminalInfo           terminal;
CTrade                  trade;
CAccountInfo            myaccount;
CSymbolInfo             mysymbol;

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|  Input de dados pelo Usuario                                     |
//+------------------------------------------------------------------+
input string            inicio="09:04";           //Horario de inicio de operações1
input string            termino="16:00";          //Horario de termino de operações
input string            fechamento="17:47";       //Horario de fechamento deoperações
input double            lote=1.0;                 //Numero de contratos por operação
input double            stopLoss=3.0;             //Pontos para Stop Loss(Stop Fixo)
input double            TakeProfitLong=5.5;       //Pontos para Lucro Long(Stop Fixo)  
input double            TakeProfitShort=5.5;      //Pontos para Lucro Short(Stop Fixo)
input bool              usarTrailing=true;        //Usar Trailing Stop?
input double            TrailingStop=3.0;         //Pontos para Stop Loss(Stop Movel)
input double            tp_trailing_buy=9.5;      //Lucro alvo-fixo buy(Stop Movel)
input double            tp_trailing_sell=9.5;     //Lucro alvo-fixo sell(Stop Movel)
input double            lucroMinimo=2.0;          //Lucro minimo para mover Stop Movel
input double            passo=2.0;                //Passo do Stop Movel em pontos
input double            alvo=9.5;                 //Meta de lucro em Pontos
input int               max_trades=4;             //Numero maximo de trades
input ulong             desvio=1;                 //Slippage maximo em pontos
input ENUM_TIMEFRAMES   timeframe=PERIOD_M5;      //Time Frame para calculos

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//|   Variaveis globais                                              |
//+------------------------------------------------------------------+
MqlDateTime             Time;
MqlDateTime             horario_inicio,horario_termino,horario_fechamento,horario_atual;
MqlRates                candle[];
MqlBookInfo             book[];
datetime                TimeLastBar;
int                     maxTrades=0;
int                     maxTradesDois=0;
int                     maxTradesTres=0;
int                     limite=max_trades/2;
int                     shift=0;
int                     finalizacao=0;
int                     conta_trailing=0;
int                     conta_avisos=0;
double                  resultado_liquido=0;
long                    account=41764;                // Account login (41764; )
long                    periodo_licenca=365;          // Qtd dias licença
long                    ask_volume,bid_volume;
long                    volume_buy50=0;
long                    volume_sell50=0;
string                  broker=AccountInfoString(ACCOUNT_COMPANY);
string                  titular=AccountInfoString(ACCOUNT_NAME);
string                  subject;
string                  texto;
bool                    trail_mode=true;             //-- Manipulando o Trailing Stop
   
//-- PREPARANDO PARA RECEBIMENTO DE DADOS DE INDICADORES

int                     FORECAST_Handle;
double                  FORECAST_Buffer1[];
double                  FORECAST_Buffer2[];
int                     TRINITY_Handle;
double                  TRINITY_Buffer[];
int                     LYAPUNOV_Handle;
double                  LYAPUNOV_Buffer[];
int                     GARCH_Handle;
double                  GARCH_Buffer[];
int                     GAP_Handle;
double                  GAP_Buffer[];

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   ResetLastError();
   
//-- PREPARANDO RECEBIMENTO DE DADOS DO BOOK

   if(!MarketBookAdd(_Symbol))                     return(INIT_FAILED);
   
//-- LICENCA DO ROBO

   datetime dt_expiracao=datetime(__DATE__+PeriodSeconds(PERIOD_D1)*periodo_licenca);// Data de expiração
   Print("Expiracao da licença: ",dt_expiracao);
  
   if(AccountInfoInteger(ACCOUNT_LOGIN)   != account) //    
     {
      MessageBox(__FUNCTION__,": Login não autorizado!");
      return(INIT_FAILED);
     }
   if(TimeCurrent()>dt_expiracao)
     {
      MessageBox(__FUNCTION__,": Licença expirada!");
      return(INIT_FAILED);
     }
     
//-- VERIFICA SE ATIVO EH PERMITIDO

   string ativo=SymbolInfoString(_Symbol,SYMBOL_DESCRIPTION);
   if(ativo  !=    "DOLAR MINI")
     {
      MessageBox("A licenca do EA nao permite operar no ativo inserido!");
      ExpertRemove();
     }

//-- VERIFICA SE O EA ESTA HABILITADO A NEGOCIAR
//-- VERIFICACOES DO TERMINAL

   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      Alert("Verifique se a negociação automatizada é permitida nas configurações do terminal!");
   else
     {
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      Alert("A negociação automatizada é proibida nas configurações do EA: ",__FILE__);
     }

//-- DEFINICAO DO ATIVO PARA A CLASSE

   if(!mysymbol.Name(_Symbol))
     {
      Alert("Ativo Inválido!");
      return INIT_FAILED;
     }

//-- VERIFICACAO DO TAMANHO DOS LOTES
//-- VERIFICACAO 1

   if(!mysymbol.LotsMin())          Alert("Erro ao ler dados de lote minimo: #",GetLastError());
   if(!mysymbol.LotsMax())          Alert("Erro ao ler dados de lote maximo: #",GetLastError());
   double volume_minimo = mysymbol.LotsMin();
   double volume_maximo = mysymbol.LotsMax();
   if(lote<volume_minimo || lote>volume_maximo)
     {
      MessageBox("Volume invalido!!");
      ExpertRemove();
     }
     
//-- VERIFICACAO 2

   double lot_step=mysymbol.LotsStep();
   if(MathMod(lote,lot_step)  !=   0)
     {
      MessageBox("Nao eh permitido lote fracionário!");
      ExpertRemove();
     }

//-- VERIFICA PASSO DO TRAILING STOP

   if((passo==0 || TrailingStop==0) && usarTrailing==true)
     {
      string err_text="Nao eh possível executar a função 'Trailing ': parâmetro \"Trailing Step\" zero!";

      //--- when testing, we will only output to the log about incorrect input parameters
      if(MQLInfoInteger(MQL_TESTER))
        {
         Print(__FUNCTION__,", ERROR: ",err_text);
         return(INIT_FAILED);
        }
      else // if the Expert Advisor is run on the chart, tell the user about the error
        {
         Alert(__FUNCTION__,", ERROR: ",err_text);
         return(INIT_PARAMETERS_INCORRECT);
        }
     }

//-- INICIANDO O RECEBIMENTO DE DADOS DOS INDICADORES

   FORECAST_Handle   =     iCustom(_Symbol,_Period,"Forecast.ex5",20,PRICE_OPEN,3);
   if((ArraySetAsSeries(FORECAST_Buffer1,true))==false)                                                              return(INIT_FAILED);
   if((ArraySetAsSeries(FORECAST_Buffer2,true))==false)                                                              return(INIT_FAILED);

   TRINITY_Handle    =     iCustom(_Symbol,timeframe,"trinity-impulse.ex5",5,34,MODE_EMA,PRICE_OPEN,VOLUME_TICK);
   if((ArraySetAsSeries(TRINITY_Buffer,true))==false)                                                                return(INIT_FAILED);

   LYAPUNOV_Handle   =     iCustom(_Symbol,timeframe,"Lyapunov_HP.ex5",7,PRICE_OPEN);
   if((ArraySetAsSeries(LYAPUNOV_Buffer,true))==false)                                                               return(INIT_FAILED);

   GARCH_Handle      =     iCustom(_Symbol,timeframe,"garch.ex5",0.01,0.08,0,PRICE_OPEN);
   if((ArraySetAsSeries(GARCH_Buffer,true))==false)                                                                  return(INIT_FAILED);
   
   GAP_Handle       =      iCustom(_Symbol,timeframe,"Gaps OHLC.ex5");
   if((ArraySetAsSeries(GAP_Buffer,true))==false)                                                                    return(INIT_FAILED);           

// Invertendo a indexacao dos candles
 
   if((ArraySetAsSeries(candle,true))==false)                                                                        return(INIT_FAILED); 

//-- VERIFICANDO O RECEBIMENTO CORRETO DE DADOS DOS INDICADORES

   if (FORECAST_Handle== INVALID_HANDLE)
     {
      Print("Erro no indicador 'FORECAST', erro: #", GetLastError());
     }
   if(TRINITY_Handle == INVALID_HANDLE)
     {
      Print("Erro no indicador 'TRINITY', erro: #", GetLastError());
      return(INIT_FAILED);
     }
   if(LYAPUNOV_Handle == INVALID_HANDLE)
     {
      Print("Erro no indicador 'LYAPUNOV', erro: #", GetLastError());
      return INIT_FAILED;
     }
   if(GARCH_Handle == INVALID_HANDLE)
     {
      Print("Erro no indicador 'GARCH', erro: #", GetLastError());
      return INIT_FAILED;
     }
   if(GAP_Handle == INVALID_HANDLE)
     {
      Print("Erro no indicador 'GAP', erro: #", GetLastError());
      return INIT_FAILED;
     }

//---
   TimeToStruct(StringToTime(inicio),horario_inicio);         //+-------------------------------------+
   TimeToStruct(StringToTime(termino),horario_termino);       //| Conversão das variaveis para mql    |
   TimeToStruct(StringToTime(fechamento),horario_fechamento); //+-------------------------------------+

//verificação de erros nas entradas de horario

   if(horario_inicio.hour>horario_termino.hour || (horario_inicio.hour==horario_termino.hour && horario_inicio.min>horario_termino.min))
     {
      Print("Parametos de horarios invalidos!");
      return INIT_FAILED;
     }

   if(horario_termino.hour>horario_fechamento.hour || (horario_termino.hour==horario_fechamento.hour && horario_termino.min>horario_fechamento.min))
     {
      Print("Parametos de horarios invalidos!");
      return INIT_FAILED;
     }
//--
   RefreshRates();

//--- DEFINICAO DO TIMER

   EventSetMillisecondTimer(20);               //-- Eventos de timer recebidos uma vez por milisegundo

//-- PARAMETROS DE PREENCHIMENTO DE ORDENS

   bool preenchimento=IsFillingTypeAllowed(_Symbol,ORDER_FILLING_RETURN);
//---
   if(preenchimento=SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else
      if(preenchimento=SYMBOL_FILLING_IOC)
         trade.SetTypeFilling(ORDER_FILLING_IOC);
      else
         trade.SetTypeFilling(ORDER_FILLING_RETURN);

//-- SLIPPAGE MAXIMO EM PONTOS

   trade.SetDeviationInPoints(desvio);

//-- VERIFICANDO TF DOS CALCULOS

   bool OK_Period  =  false;
   switch(timeframe)
     {
      case PERIOD_M1   :   OK_Period   =     true;       break;
      case PERIOD_M2   :   OK_Period   =     true;       break;
      case PERIOD_M3   :   OK_Period   =     true;       break;
      case PERIOD_M4   :   OK_Period   =     true;       break;
      case PERIOD_M5   :   OK_Period   =     true;       break;
      case PERIOD_M6   :   OK_Period   =     true;       break;
      case PERIOD_M10  :   OK_Period   =     true;       break;
      case PERIOD_M12  :   OK_Period   =     true;       break;
      case PERIOD_M15  :   OK_Period   =     true;       break;
      case PERIOD_M20  :   OK_Period   =     true;       break;
      case PERIOD_M30  :   OK_Period   =     true;       break;
      case PERIOD_H1   :   OK_Period   =     true;       break;
      case PERIOD_H2   :   OK_Period   =     true;       break;
      case PERIOD_H3   :   OK_Period   =     true;       break;
      case PERIOD_H4   :   OK_Period   =     true;       break;
      case PERIOD_H6   :   OK_Period   =     true;       break;
      case PERIOD_H8   :   OK_Period   =     true;       break;
      case PERIOD_H12  :   OK_Period   =     true;       break;
      case PERIOD_D1   :   OK_Period   =     true;       break;
      case PERIOD_W1   :   OK_Period   =     true;       break;
      case PERIOD_MN1  :   OK_Period   =     true;       break;
     }
   if(OK_Period==false)
     {
      MessageBox("Você escolheu um 'Time frame' fora do padrão!");
      ExpertRemove();
     }
   if(Period()>timeframe || Period()<timeframe)
     {
      MessageBox("O período definido deve ser DIFERENTE que o atual! Altere o TIME FRAME do GRAFICO para: "+EnumToString(timeframe)+"!");
      ExpertRemove();
     }

//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//-- ZERANDO A MEMORIA DE DADOS DO BOOK

   if(!MarketBookRelease(_Symbol))                             return;

//-- Zerando a memoria dos indicadores

   if(!IndicatorRelease(FORECAST_Handle))                      return;
   if(!IndicatorRelease(TRINITY_Handle))                       return;
   if(!IndicatorRelease(LYAPUNOV_Handle))                      return;
   if(!IndicatorRelease(GARCH_Handle))                         return;
   if(!IndicatorRelease(GAP_Handle))                           return;

//--- destroy timer

   EventKillTimer();

//--- A primeira maneira de obter o código de razão de desinicialização
   Print(__FUNCTION__,"_Código do motivo de não inicialização = ",reason);
//--- A segunda maneira de obter o código de razão de desinicialização
   Print(__FUNCTION__,"_UninitReason = ",getUninitReasonText(_UninitReason));

  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

//-- ENVIO DE ORDENS

   Trades();

//--RESUMO DAS OPERACOES

   if(HorarioFechamento()==true && finalizacao==0)
     {
      ResumoOperacoes(EXPERT_MAGIC);
      finalizacao=1;
     }

//-- PRE-CALCULO VOLUMES REAIS DOS ULTIMOS 50 TICKS 

   MqlTick tick_array50[];
   if(CopyTicks(_Symbol,tick_array50,COPY_TICKS_TRADE,0,50)!=50)return;
   
   for(int i=0;i<ArraySize(tick_array50);i++)
     {
      if((tick_array50[i].flags&TICK_FLAG_BUY)==TICK_FLAG_BUY && (tick_array50[i].flags&TICK_FLAG_SELL)==0)volume_buy50+=(long)tick_array50[i].volume_real;   //-- VOLUME AGRESSOES DE COMPRA
      if((tick_array50[i].flags&TICK_FLAG_BUY)==0 && (tick_array50[i].flags&TICK_FLAG_SELL)==TICK_FLAG_SELL)volume_sell50+=(long)tick_array50[i].volume_real;//-- VOLUME AGRESSOES DE VENDA
      //Comment(StringFormat("\n\nVolume Vendas 50: %d\nVolume Compras 50: %d",volume_sell50,volume_buy50));
     }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Timer function                                                   |
//+------------------------------------------------------------------+
void OnTimer()
  {
   //Trades();
   if(!TimeTradeServer())                                      return;
   double   saldo           =     myaccount.Balance();
   double   lucro_posicao   =     PositionGetDouble(POSITION_PROFIT);
   Comment(_Symbol,",",EnumToString(_Period),"\n\n",
           " Titular/Autor: ",titular,"\n\n",
           " Data/Hora: ",TimeTradeServer(),"\n\n",
           " Lucro/Prejuizo posicao atual R$: ",DoubleToString(lucro_posicao,Digits()),"\n",
           " Resultado parcial R$: ",DoubleToString(resultado_liquido,Digits()),"\n\n",
           " SALDO EM R$: ",saldo,"\n"
          );
          
//-- ENVIO DE EMAILS DE AVISO DE RESULTADOS PARCIAIS
//-- 1o TRADE
     if(PositionSelect(_Symbol)==false && maxTrades==1 && conta_avisos==0)
       {
        SendMail(_Symbol+" - 1o Resultado Parcial","Lucro/Prejuizo parcial R$: "+DoubleToString(resultado_liquido,Digits())+".");
        conta_avisos++;
       }
       
//-- 2o TRADE
     if(PositionSelect(_Symbol)==false && maxTrades==2 && conta_avisos==1)
       {
        SendMail(_Symbol+" - 2o Resultado Parcial","Lucro/Prejuizo parcial R$: "+DoubleToString(resultado_liquido,Digits())+".");
        conta_avisos++;
       }
       
//-- 3o TRADE
     if(PositionSelect(_Symbol)==false && maxTrades==3 && conta_avisos==2)
       {
        SendMail(_Symbol+" - 3o Resultado Parcial","Lucro/Prejuizo parcial R$: "+DoubleToString(resultado_liquido,Digits())+".");
        conta_avisos++;
       }
       
//-- VERIFICACAO DE SEGURANCA DE RECEBIMENTO DE DADOS

   if(HorarioEntrada()==true && PositionSelect(_Symbol)==false && 
   (bid_volume==0 || ask_volume==0 || volume_buy50==0 || volume_sell50==0))
     {
      Print("Falha de dados de mercado! - EA sera excluido por seguranca!");
      SendMail("EA excluido por seguranca!","EA excluido por falta de recebimento de dados da corretora!");
      ExpertRemove();
     }         
          
//-- VERIFICANDO SE O SERVIDOR PERMITE NEGOCIACAO

   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      Alert("Negociação automatizada é proibida para a conta ",
            AccountInfoInteger(ACCOUNT_LOGIN)," no lado do servidor de negociação");

//--OUTROS PARAMETROS

   if(!RefreshRates())                                         return;
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| FUNCAO DE TRADES                                                 |
//+------------------------------------------------------------------+
void Trades()
  {
//-- BUFFERS DOS INDICADORES
   
   if(!CopyBuffer(FORECAST_Handle,0,0,5,FORECAST_Buffer1))     return;
   if(!CopyBuffer(FORECAST_Handle,1,0,5,FORECAST_Buffer2))     return;
   if(!CopyBuffer(TRINITY_Handle,0,0,5,TRINITY_Buffer))        return;
   if(!CopyBuffer(LYAPUNOV_Handle,0,0,5,LYAPUNOV_Buffer))      return;
   if(!CopyBuffer(GARCH_Handle,0,0,5,GARCH_Buffer))            return;
   if(!CopyBuffer(GAP_Handle,0,0,5,GAP_Buffer))                return;

//-- PARAMETROS INICIAIS

   ResetLastError();
   MqlTradeRequest         request;
   MqlTradeResult          result;
   MqlTick                 price;
   if(!SymbolInfoTick(_Symbol,price))                           return;
   if(!CopyRates(_Symbol,_Period,0,5,candle))                   return;
   ResumoOperacoes(EXPERT_MAGIC);
   trade.SetExpertMagicNumber(EXPERT_MAGIC);                           //-- Setando o numero magico do EA

//-- VARIAVEIS LOCAIS

   ulong    ticket            =     trade.RequestPosition();           //-- Ticket da Posicao
   double   tp_dinamico       =     7.5;
   double   ask               =     price.ask;                         //-- Preco atual na ponta vendedora
   double   bid               =     price.bid;                         //-- Preco atual na ponta compradora
   double   sloss_long        =     price.bid-stopLoss;                //-- Stop Loss Posicao Comprada
   double   tprofit_long      =     price.bid+TakeProfitLong;          //-- Take Profit Posicao Comprada
   double   sloss_short       =     price.ask+stopLoss;                //-- Stop Loss Posicao Vendida
   double   tprofit_short     =     price.ask-TakeProfitShort;         //-- Take Profit Posicao Vendida
   double   meta              =     (alvo*10)*lote;                    //-- Meta financeira
   double   prejuizo          =     (((stopLoss-1.0)*10)*lote)*(-1);   //-- Prejuizo Maximo Consecutivo no DayTrade

//-- VERIFICACAO DE SEGURANCA

   if(result.retcode == 10026)
     {
      Alert("Autotrading desabilitado pelo servidor da corretora!!");
     }
   
// Rates structure array for last two bars
   MqlRates mrate[2];
   if(!CopyRates(Symbol(), Period(), 0, 2, mrate))                   return;

// NEW BAR CHECK.
//---------------
   static double   dBar_Open;
   static double   dBar_High;
   static double   dBar_Low;
   static double   dBar_Close;
   static long     lBar_Volume;
   static datetime nBar_Time;

// Boolean for new BAR confirmation.
   bool bStart_NewBar = false;

// Check if the price data has changed tov the previous bar.
   if(mrate[0].open != dBar_Open || mrate[0].high != dBar_High || mrate[0].low != dBar_Low ||
      mrate[0].close != dBar_Close || mrate[0].tick_volume != lBar_Volume || mrate[0].time != nBar_Time)
     {
      bStart_NewBar = true; // A new BAR has appeared!

      // Update the new BAR data.
      dBar_Open   = mrate[0].open;
      dBar_High   = mrate[0].high;
      dBar_Low    = mrate[0].low;
      dBar_Close  = mrate[0].close;
      lBar_Volume = mrate[0].tick_volume;
      nBar_Time   = mrate[0].time;
     }

// Check if a new bar has formed.
   if(bStart_NewBar == true && HorarioEntrada()==true)
     {
      Print(_Symbol+ ": NOVA BARRA!");
     }

//+------------------------------------------------------------------+
//|  ESTRATEGIA DE COMPRA 1                                          |
//+------------------------------------------------------------------+

   if(PositionSelect(_Symbol)==false && bid<ask && HorarioEntrada()==true && bStart_NewBar == true 
     && maxTrades<max_trades &&  maxTradesDois<limite && resultado_liquido>prejuizo && resultado_liquido<meta)
     {
      if(LYAPUNOV_Buffer[0]>LYAPUNOV_Buffer[1] && LYAPUNOV_Buffer[0]>=35.0 && TRINITY_Buffer[0]>0 
         && FORECAST_Buffer1[0]>FORECAST_Buffer2[0] && GAP_Buffer[0]==0 && GAP_Buffer[1]==0  
         && GARCH_Buffer[0]>=0.25 && GARCH_Buffer[0]>=GARCH_Buffer[1] && price.last==candle[0].open)
        {
         trade.Buy(lote,_Symbol,0,sloss_long,tprofit_long,"Ordem de COMPRA!");
         //-- VALIDACAO DE SEGURANCA

         if(trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009)
           {
            Print("Ordem de COMPRA no ativo: "+_Symbol+", enviada e executada com sucesso!");
            maxTrades++;
            maxTradesDois++;
            TradeEmailBuy();
            if(usarTrailing==true)
              {
               trail_mode=true;
              }
            else
              {
               trail_mode=false;
              }
            Print("Trail Mode (Pre - trailing): ",trail_mode);
           }
         else
           {
            Print("Erro ao enviar ordem! Erro #",GetLastError()," - ",trade.ResultRetcodeDescription());
            return;
           }
        }
     }

//+------------------------------------------------------------------+
//|  ESTRATEGIA DE VENDA 1                                           |
//+------------------------------------------------------------------+

   if(PositionSelect(_Symbol)==false && bid<ask  && HorarioEntrada()==true && bStart_NewBar == true  
     && maxTrades<max_trades && maxTradesTres<limite  && resultado_liquido>prejuizo && resultado_liquido<meta)
     {
      if(LYAPUNOV_Buffer[0]<LYAPUNOV_Buffer[1] && LYAPUNOV_Buffer[0]<=-35.0 && TRINITY_Buffer[0]<0 
         && FORECAST_Buffer1[0]<FORECAST_Buffer2[0] && GAP_Buffer[0]==0 && GAP_Buffer[1]==0 
         && GARCH_Buffer[0]>=0.25 && GARCH_Buffer[0]>=GARCH_Buffer[1] && price.last==candle[0].open)
        {
         trade.Sell(lote,_Symbol,0,sloss_short,tprofit_short,"Ordem de VENDA!");
         //-- VALIDACAO DE SEGURANCA

         if(trade.ResultRetcode()==10008 || trade.ResultRetcode()==10009)
           {
            Print("Ordem de VENDA no ativo: "+_Symbol+", enviada e executada com sucesso!");
            maxTrades++;
            maxTradesTres++;
            TradeEmailSell();
            if(usarTrailing==true)
              {
               trail_mode=true;
              }
            else
              {
               trail_mode=false;
              }
            Print("Trail Mode (Pre - trailing): ",trail_mode);
           }
         else
           {
            Print("Erro ao enviar ordem! Erro #",GetLastError()," - ",trade.ResultRetcodeDescription());
            return;
           }
        }
     }

//+------------------------------------------------------------------+
//-- DEFININDO CONTAGEM DO TRAILING STOP
     
   if(PositionSelect(_Symbol)==false)
     {
      conta_trailing = 0;
     }

//+------------------------------------------------------------------+
//-- INSERINDO TRAILING STOP DE PASSO FIXO E LUCRO MINIMO (PRIMEIRO TRADE) - APENAS 2 PASSOS

   if(usarTrailing==true && PositionSelect(_Symbol)==true && TrailingStop>0 && maxTrades==1 && trail_mode==true)
     {
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;

      ENUM_POSITION_TYPE posType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentStop=PositionGetDouble(POSITION_SL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);

      double minProfit=lucroMinimo;
      double step=passo;
      double trailStop=TrailingStop;

      double trailStopPrice;
      double currentProfit;
      double tp_fixo;

      //-- TRAILING STOP DE 2 PASSOS EM POSICOES COMPRADAS

      if(posType==POSITION_TYPE_BUY)
        {
         trailStopPrice=bid-trailStop;
         currentProfit=bid-openPrice;
         tp_fixo=openPrice+tp_trailing_buy;

         if(trailStopPrice>=currentStop+step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            if(!OrderSend(request,result))                        return;
            Print(__FUNCTION__,": ",result.comment," - Codigo de resposta: #",result.retcode);
            conta_trailing++;
            if(conta_trailing>1)
             {
              trail_mode=false;
              Print("Trail Mode  (Pos-Trailing): ",trail_mode);
              SendMail("Nao perde mais neste Trade!","Segundo passo do Trailing executado! Go Profit!!");
             }
           }
        }

      //-- TRAILING STOP DE 2 PASSOS EM POSICOES VENDIDAS

      if(posType==POSITION_TYPE_SELL)
        {
         trailStopPrice=ask+trailStop;
         currentProfit=openPrice-ask;
         tp_fixo=openPrice-tp_trailing_sell;

         if(trailStopPrice<=currentStop-step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            if(!OrderSend(request,result))                        return;
            Print(__FUNCTION__,": ",result.comment," - Codigo de resposta: #",result.retcode);
            conta_trailing++;
            if(conta_trailing>1)
             {
              trail_mode=false;
              Print("Trail Mode  (Pos-Trailing): ",trail_mode);
              SendMail("Nao perde mais neste Trade!","Segundo passo do Trailing executado! Go Profit!!");
             }
           }
        }
     }

//+------------------------------------------------------------------+
//-- INSERINDO TRAILING STOP DE PASSO FIXO E LUCRO MINIMO (APOS 2o TRADE)- APENAS 2 PASSOS

   if(usarTrailing==true && PositionSelect(_Symbol)==true && TrailingStop>0 && maxTrades>1 && trail_mode==true)
     {
      request.action = TRADE_ACTION_SLTP;
      request.symbol = _Symbol;

      ENUM_POSITION_TYPE posType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double currentStop=PositionGetDouble(POSITION_SL);
      double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);

      double minProfit=lucroMinimo;
      double step=passo;
      double trailStop=TrailingStop;

      double trailStopPrice;
      double currentProfit;
      double tp_fixo;

      //-- TRAILING STOP DE 2 PASSOS EM POSICOES COMPRADAS

      if(posType==POSITION_TYPE_BUY)
        {
         trailStopPrice=bid-trailStop;
         currentProfit=bid-openPrice;
         tp_fixo=openPrice+tp_dinamico;

         if(trailStopPrice>=currentStop+step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            if(!OrderSend(request,result))                        return;
            Print(__FUNCTION__,": ",result.comment," - Codigo de resposta: #",result.retcode);
            conta_trailing++;
            if(conta_trailing>1)
             {
              trail_mode=false;
              Print("Trail Mode  (Pos-Trailing): ",trail_mode);
              SendMail("Nao perde mais neste Trade!","Segundo passo do Trailing executado! Go Profit!!");
             }
           }
        }

      //-- TRAILING STOP DE 2 PASSOS EM POSICOES VENDIDAS

      if(posType==POSITION_TYPE_SELL)
        {
         trailStopPrice=ask+trailStop;
         currentProfit=openPrice-ask;
         tp_fixo=openPrice-tp_dinamico;

         if(trailStopPrice<=currentStop-step && currentProfit>=minProfit)
           {
            request.sl=trailStopPrice;
            request.tp=tp_fixo;
            if(!OrderSend(request,result))                           return;
            Print(__FUNCTION__,": ",result.comment," - Codigo de resposta: #",result.retcode);
            conta_trailing++;
            if(conta_trailing>1)
             {
              trail_mode=false;
              Print("Trail Mode (Pos-Trailing): ",trail_mode);
              SendMail("Nao perde mais neste Trade!","Segundo passo do Trailing executado! Go Profit!!");
             }
           }
        }
     }
     
//+------------------------------------------------------------------+
//-- ENCERRANDO POSICAO DEVIDO AO LIMITE DE HORARIO 

   if(HorarioFechamento()==true && PositionSelect(_Symbol)==true)
     {

      //-- Fecha a posicao pelo limite de horario

      trade.PositionClose(ticket,-1);

      //--- VALIDACAO DE SEGURANCA

      if(!trade.PositionClose(_Symbol))
        {
         //--- MENSAGEM DE FALHA
         Print("PositionClose() falhou. Return code=",trade.ResultRetcode(),
               ". Codigo de retorno: ",trade.ResultRetcodeDescription());
        }
      else
        {
         Print("PositionClose() executado com sucesso. codigo de retorno=",trade.ResultRetcode(),
               " (",trade.ResultRetcodeDescription(),")");
        }
     }

//+------------------------------------------------------------------+
//-- ENVIANDO AVISO DE LUCRO DO DIA

   if(maxTrades>0 && PositionSelect(_Symbol)==false && resultado_liquido!=0 && HorarioFechamento()==true && (maxTradesDois>0 || maxTradesTres>0))
     {
      SendMail(_Symbol+" - Negociacoes encerradas!","Resultado bruto do ativo R$: "+DoubleToString(resultado_liquido,Digits())+" !");
      ResumoOperacoes(EXPERT_MAGIC);
      maxTradesDois=0;
      maxTradesTres=0;
     }

//+------------------------------------------------------------------+
//-- PARALISANDO ROBO APOS ATINGIR LUCRO

   if(PositionSelect(_Symbol)==false && resultado_liquido>=meta && HorarioEntrada()==true)
     {
      SendMail(_Symbol+" - Meta atingida, robo paralisado!","Lucro do dia no ativo R$: "+DoubleToString(resultado_liquido,Digits())+" !");
      ResumoOperacoes(EXPERT_MAGIC);
      ExpertRemove();
     }

//+------------------------------------------------------------------+
//-- ZERANDO OS VALORES DO PEDIDO E SEU RESULTADO

   ZeroMemory(request);
   ZeroMemory(result);
   ZeroMemory(price);
   ZeroMemory(mrate);

  }//-- Final da funcao Trades

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Funcao para enviar email ao iniciar trade (compra)               |
//+------------------------------------------------------------------+
void TradeEmailBuy()
  {
   MqlTick price;
   if(!SymbolInfoTick(_Symbol,price))                          return;
   subject="Trade (COMPRA) iniciado - EA: FAREY-BROWN - na corretora - "
           +broker+" - Hora: "+TimeToString(TimeTradeServer(),TIME_SECONDS)+" .";
   texto="O Trade foi iniciado no ativo: "+_Symbol+", ao preco aproximado de R$: "+DoubleToString(price.last,Digits())+"!";
   SendMail(subject,texto);
   ZeroMemory(price);
  }

//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Funcao para enviar email ao iniciar trade (venda)                |
//+------------------------------------------------------------------+
void TradeEmailSell()
  {
   MqlTick price;
   if(!SymbolInfoTick(_Symbol,price))                          return;
   subject="Trade (VENDA) iniciado - EA: FAREY-BROWN - na corretora - "
           +broker+" - Hora: "+TimeToString(TimeTradeServer(),TIME_SECONDS)+" .";
   texto="O Trade foi iniciado no ativo: "+_Symbol+", ao preco aproximado de R$: "+DoubleToString(price.last,Digits())+"!";
   SendMail(subject,texto);
   ZeroMemory(price);
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
      Print("Falha com dados de preco!");
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
//|VALIDACAO DOS HORARIOS                                            |
//+------------------------------------------------------------------+
bool HorarioEntrada()
  {
   TimeToStruct(TimeCurrent(),horario_atual);

   if(horario_atual.hour>=horario_inicio.hour && horario_atual.hour<=horario_termino.hour)
     {
      // Hora atual igual a de início
      if(horario_atual.hour==horario_inicio.hour)
         // Se minuto atual maior ou igual ao de início => está no horário de entradas
         if(horario_atual.min>=horario_inicio.min)
            return true;
      // Do contrário não está no horário de entradas
         else
            return false;

      // Hora atual igual a de término
      if(horario_atual.hour==horario_termino.hour)
         // Se minuto atual menor ou igual ao de término => está no horário de entradas
         if(horario_atual.min<=horario_termino.min)
            return true;
      // Do contrário não está no horário de entradas
         else
            return false;

      // Hora atual maior que a de início e menor que a de término
      return true;
     }

// Hora fora do horário de entradas
   return false;
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool HorarioFechamento()
  {
   TimeToStruct(TimeCurrent(),horario_atual);

// Hora dentro do horário de fechamento
   if(horario_atual.hour>=horario_fechamento.hour)
     {
      // Hora atual igual a de fechamento
      if(horario_atual.hour==horario_fechamento.hour)
         // Se minuto atual maior ou igual ao de fechamento => está no horário de fechamento
         if(horario_atual.min>=horario_fechamento.min)
            return true;
      // Do contrário não está no horário de fechamento
         else
            return false;

      // Hora atual maior que a de fechamento
      return true;
     }

// Hora fora do horário de fechamento
   return false;
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

//+--------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Verifica se um modo de preenchimento específico é permitido      |
//+------------------------------------------------------------------+
bool IsFillingTypeAllowed(string symbol,int fill_type)
  {
//--- Obtém o valor da propriedade que descreve os modos de preenchimento permitidos
   int filling=(int)SymbolInfoInteger(symbol,SYMBOL_FILLING_MODE);
//--- Retorna true, se o modo fill_type é permitido
   return((filling & fill_type)==fill_type);
  }

//+------------------------------------------------------------------+
//|  RESUMO DAS OPERACOES DO DIA                                     |
//+------------------------------------------------------------------+
void ResumoOperacoes(ulong numero_magico)
  {

//Declaração de Variáveis
   datetime    comeco, fim;
   double      lucro = 0, perda  = 0;
   int         contador_trades   = 0;
   int         contador_ordens   = 0;
   double      resultado;
   ulong       ticket;

//Obtenção do Histórico

   MqlDateTime comeco_struct;
   if(!TimeCurrent())                                 return;
   fim = TimeCurrent(comeco_struct);
   comeco_struct.hour   =  0;
   comeco_struct.min    =  0;
   comeco_struct.sec    =  0;
   if(!StructToTime(comeco_struct))                   return;
   comeco = StructToTime(comeco_struct);

   if(!HistorySelect(comeco, fim))                    return;

//Cálculos
   for(int i=0; i<HistoryDealsTotal(); i++)
     {
      ticket = HistoryDealGetTicket(i);
      long Entry  = HistoryDealGetInteger(ticket, DEAL_ENTRY);

      if(ticket > 0)
        {
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol && HistoryDealGetInteger(ticket, DEAL_MAGIC) == numero_magico)
           {
            contador_ordens++;
            resultado = HistoryDealGetDouble(ticket, DEAL_PROFIT);

            if(resultado < 0)
              {
               perda += -resultado;
              }
            else
              {
               lucro += resultado;
              }

            if(Entry == DEAL_ENTRY_OUT)
              {
               contador_trades++;
              }
           }
        }
     }

   double fator_lucro;

   if(perda > 0)
     {
      fator_lucro = lucro/perda;
     }
   else
      fator_lucro = -1;

   resultado_liquido = lucro - perda;


//Exibição
   if(HorarioFechamento()==true && finalizacao==0)
     {
      Print("RESUMO - Trades:  ", contador_trades, " | Expert: ",EXPERT_MAGIC, " | Ordens: ", contador_ordens, " | Lucro: R$ ", DoubleToString(lucro, 2), " | Perdas: R$ ", DoubleToString(perda, 2),
            " | Resultado: R$ ", DoubleToString(resultado_liquido, 2), " | FatorDeLucro: ", DoubleToString(fator_lucro, 2));
      finalizacao++;
     }
  }

//+------------------------------------------------------------------+
//| BookEvent function                                               |
//+------------------------------------------------------------------+
void OnBookEvent(const string &symbol)
  {
  
  if(!MarketBookGet(_Symbol,book))                             return;
    
  for(int i=0;i<ArraySize(book);i++)
    {
    if(book[i].type == BOOK_TYPE_SELL)
      {
       ask_volume   = (long)book[i].volume_real;
      }
     else
       {
        bid_volume  = (long)book[i].volume_real;
        break;
       }
    }
  }


//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| OBTENDO MOTIVOS DA DESINICIALIZACAO                              |
//+------------------------------------------------------------------+
string getUninitReasonText(int reasonCode)
  {
   string text="";
//---
   switch(reasonCode)
     {
      case REASON_ACCOUNT:
         text="Alterações nas configurações de conta!";
         break;
      case REASON_CHARTCHANGE:
         text="O período do símbolo ou gráfico foi alterado!";
         break;
      case REASON_CHARTCLOSE:
         text="O gráfico foi encerrado!";
         break;
      case REASON_PARAMETERS:
         text="Os parâmetros de entrada foram alterados por um usuário!";
         break;
      case REASON_RECOMPILE:
         text="O programa "+__FILE__+" foi recompilado!";
         break;
      case REASON_REMOVE:
         text="O programa "+__FILE__+" foi excluído do gráfico!";
         break;
      case REASON_TEMPLATE:
         text="Um novo modelo foi aplicado!";
         break;
      default:
         text="Outro motivo!";
     }
//---
   return text;
  }
/*
//+------------------------------------------------------------------+
//|  VALIDACAO DE CONTAS AUTORIZADAS                                 |
//+------------------------------------------------------------------+
bool IsValidAccount()
  {
   long login=AccountInfoInteger(ACCOUNT_LOGIN);
//
   int users[][3]=
     {
        // Conta | Validade
        {11111111, D'2020.12.31'},
        {22222222, D'2020.12.31'},
        {33333333, D'2020.12.31'},
        {44444444, D'2020.12.31'}
     };

   datetime now=TimeTradeServer();
   for(int i=0; i<ArraySize(users)/3; i++)
     {
      if(users[i][0]==login)
        {
         if(now>users[i][1])
           {
            MessageBox("Venceu dia "+TimeToString(users[i][1]));
            return false;
           }

         return true;
        }
     }

   MessageBox("Conta Inválida: "+DoubleToString(login));
   return false;
  }

*/