//+------------------------------------------------------------------+
//|                                                      Entropy.mq5 |
//|                                        Copyright © 2008,   Korey | 
//|                                                                  | 
//+------------------------------------------------------------------+
#property copyright "Copyright © 2008, Korey"
#property link ""
//---- indicator version number
#property version   "1.00"
//---- drawing the indicator in a separate window
#property indicator_separate_window
//---- number of indicator buffers 1
#property indicator_buffers 1 
//---- only one plot is used
#property indicator_plots   1
//+-----------------------------------+
//|  Parameters of indicator drawing  |
//+-----------------------------------+
//---- drawing of the indicator as a line
#property indicator_type1 DRAW_LINE
//---- indian red color is used
#property indicator_color1 IndianRed
//---- indicator line is a solid one
#property indicator_style1 STYLE_SOLID
//---- indicator line width is equal to 2
#property indicator_width1 2
//---- displaying label of the signal line
#property indicator_label1  "Entropy"
//+----------------------------------------------+
//| Horizontal levels display parameters         |
//+----------------------------------------------+
#property indicator_level1 0.0
#property indicator_levelcolor Blue
#property indicator_levelstyle STYLE_SOLID
//+----------------------------------------------+
//| Input parameters of the indicator            |
//+----------------------------------------------+
input int Period_=15; // Period of the indicator 
input int Shift=0;    // Horizontal shift of the indicator in bars 
//+----------------------------------------------+
//---- declaration of dynamic arrays that further 
//---- will be used as indicator buffers
double ExtBuffer[];
//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+  
void OnInit()
  {
//---- transformation of the dynamic array ExtBuffer into an indicator buffer
   SetIndexBuffer(0,ExtBuffer,INDICATOR_DATA);
//---- initializations of variable for indicator short name
   string shortname;
   StringConcatenate(shortname,"Entropy(",Period_,")");
//---- shifting the indicator horizontally by Shift
   PlotIndexSetInteger(0,PLOT_SHIFT,Shift);
//--- create label to display in Data Window
   PlotIndexSetString(0,PLOT_LABEL,shortname);
//---- shifting the start of drawing of the indicator
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,Period_);
//---- creating name for displaying in a separate sub-window and in a tooltip
   IndicatorSetString(INDICATOR_SHORTNAME,shortname);
//---- determination of accuracy of displaying of the indicator values
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits+4);
//---- restriction to draw empty values for the indicator
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
//----
  }
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const int begin,
                const double &price[])
  {
//---- checking the number of bars to be enough for the calculation
   if(rates_total<Period_+begin) return(0);

//---- declarations of local variables 
   int first,bar,kkk;
//---- declaration of variables with a floating point                 
   double sumx,sumx2,avgx,rmsx,Price0,Price1,fPrice,P,G;

//---- calculation of the starting number 'first' for the cycle of recalculation of bars
   if(prev_calculated>rates_total || prev_calculated<=0) // checking for the first start of calculation of an indicator
     {
      first=Period_+begin; // starting number for calculation of all bars
     }
   else
     {
      first=prev_calculated-1; // starting number for calculation of new bars
     }

//---- main cycle of calculation of the indicator
   for(bar=first; bar<rates_total; bar++)
     {
      sumx=0;
      sumx2=0;
      //---       
      for(int jjj=0; jjj<Period_; jjj++)
        {
         kkk=bar-jjj;
         Price0 = price[kkk];
         Price1 = price[kkk - 1];

         fPrice=MathLog(Price0/Price1);
         sumx+=fPrice;
         sumx2+=fPrice*fPrice;
        }
      //----       
      avgx = sumx / Period_;
      rmsx = MathSqrt(sumx2/Period_);
      //----      
      P = (1.0 + avgx/rmsx)/2.0;
      G = P * MathLog(1.0 + rmsx) + (1.0 - P) * MathLog(1.0 - rmsx);
      ExtBuffer[bar]=G;
     }
//----     
   return(rates_total);
  }
//+------------------------------------------------------------------+
