//+------------------------------------------------------------------+
//|                                       Stochastic Range Regime.mq5 |
//|                       Copyright 2026, atoskueko / AlgoToolbox.com |
//|                                            https://algotoolbox.com |
//+------------------------------------------------------------------+
// MT5 port of "Stochastic Range Regime [MarkitTick]" (TradingView, Pine v6).
// Original work © MarkitTick, licensed CC BY-NC-SA 4.0 — this port keeps the same licence:
// https://creativecommons.org/licenses/by-nc-sa/4.0/
#property copyright   "Port: Copyright 2026, atoskueko / AlgoToolbox.com | Concept: MarkitTick (CC BY-NC-SA 4.0)"
#property link        "https://algotoolbox.com"
#property version     "1.00"
#property description "Stochastic Range Regime: %K inside a bull/bear range + price vs trend SMA = regime, confirmed over N bars."
#property description "Regime candles, BUY/SELL on regime change, ATR stop + 3 targets with hit tracking, HTF confirmation,"
#property description "ADX chop filter, adaptive smoothing, dashboard and alerts."
#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   1
#property indicator_label1  "Open;High;Low;Close"
#property indicator_type1   DRAW_COLOR_CANDLES

enum ENUM_SMOOTH { SM_NONE=0, SM_EMA=1, SM_WMA=2, SM_RMA=3 };

input group "01 · Core Settings"
input int      InpStochLen   = 14;    // Stochastic Length
input int      InpKSmooth    = 3;     // %K Smoothing (1 = Off)
input ENUM_APPLIED_PRICE InpStochSrc = PRICE_CLOSE; // Source
input int      InpTrendLen   = 50;    // Trend MA Length (SMA)
input ENUM_APPLIED_PRICE InpTrendSrc = PRICE_CLOSE; // Trend Source

input group "02 · Filters"
input int      InpBullLo     = 40;    // Bull Range Low
input int      InpBullHi     = 100;   // Bull Range High
input int      InpBearLo     = 0;     // Bear Range Low
input int      InpBearHi     = 60;    // Bear Range High
input int      InpConfirm    = 2;     // Regime Confirm Bars
input bool     InpUseHtf     = false; // Use HTF Confirmation
input ENUM_TIMEFRAMES InpHtf = PERIOD_H4; // HTF Timeframe
input bool     InpUseAdx     = false; // Use Chop Filter (ADX)
input int      InpAdxLen     = 14;    // ADX Length
input int      InpAdxMin     = 20;    // ADX Min Strength
input ENUM_SMOOTH InpSmooth  = SM_NONE; // Adaptive Smoothing
input int      InpSmoothLen  = 5;     // Adaptive Smoothing Length

input group "03 · Trade Tools"
input bool     InpLock       = false; // Lock Signal (Freeze Current, Block New)
input int      InpAtrLen     = 14;    // ATR Length
input double   InpSlMult     = 1.5;   // SL ATR Mult
input double   InpTp1Mult    = 1.0;   // TP1 ATR Mult
input double   InpTp2Mult    = 2.0;   // TP2 ATR Mult
input double   InpTp3Mult    = 3.0;   // TP3 ATR Mult
input int      InpMaxBars    = 5000;  // History Bars Processed

input group "03a · Support & More"
input string   InpInfoTelegram = "https://t.me/algotoolbox"; // Telegram
input string   InpInfoHomepage = "https://algotoolbox.com";  // Homepage

input group "04 · Visuals"
input bool     InpColorCandles = true; // Color Candles (Overlay)
input bool     InpShowSignals  = true; // Show Buy/Sell Signals
input bool     InpShowDash     = true; // Show Dashboard (Top Left)

input group "05 · Alerts (Live Bars Only)"
input bool     InpAlertPopup = true;  // Pop-up Alert
input bool     InpAlertPush  = false; // Push Notification
input string   InpActLong    = "long";              // Long Action Word
input string   InpActShort   = "short";             // Short Action Word
input string   InpActCloseL  = "closelong";         // Close Long Action Word
input string   InpActCloseS  = "closeshort";        // Close Short Action Word
input string   InpActPartL   = "partialcloselong";  // Partial Close Long Action Word
input string   InpActPartS   = "partialcloseshort"; // Partial Close Short Action Word

input group "06 · Colours"
input color    C_SUP   = C'38,166,154';  // Bullish
input color    C_RES   = C'239,83,80';   // Bearish
input color    C_NEUT  = C'120,123,134'; // Neutral Candle
input color    C_SL    = C'239,83,80';   // SL Line
input color    C_ENTRY = C'33,150,243';  // Entry Line
input color    C_TP    = C'38,166,154';  // TP Lines (TP1 40% / TP2 20% / TP3 solid)
input color    C_MID   = C'249,168,37';  // Progress Mid
input color    C_HDR   = C'58,42,109';   // Dashboard Header
input color    C_BG    = C'10,15,26';    // Dashboard Background
input color    C_TXT   = clrWhite;       // Dashboard Text
input color    C_WARN  = C'90,70,30';    // Dashboard Warning Row
input color    C_SIG   = clrWhite;       // Signal Label Text

#define PFX "SRR_"
#define TAG "[SRR]"
#define BRAND_H 22   // brand box height under the dashboard (px)

//==== BUFFERS ======================================================
double bO[], bH[], bL[], bC[], bCol[];
double bRaw[], bKB[], bK[], bMA[], bSTR[], bSPDM[], bSMDM[], bADX[], bATR[], bState[], bBull[], bBear[];

//==== STATE ========================================================
int    gLast=-1, gTotal=0; bool gLive=false; color gBg=clrBlack;
int    bullLo, bullHi, bearLo, bearHi; double tpM1, tpM2, tpM3; bool tpReordered=false;
// trade
int    tDir=0, tBar=-1, tL1=2, tL2=3, tL3=4, tCloseBar=-1; double tEntry=0, tSl=0, tTp1=0, tTp2=0, tTp3=0; bool tp1Hit=false, tp2Hit=false, tp3Hit=false, slHit=false;
// htf
bool   htfSkipped=false, htfOn=false; datetime gHtfTime=0; double hState[]; int hN=0; double hK[], hMA[];
double gSrc[], gTSrc[];

//==== HELPERS ======================================================
color Blend(const color c,const int pct){ int p=MathMax(0,MathMin(100,pct)); int r=((c&0xFF)*(100-p)+(gBg&0xFF)*p)/100, g=(((c>>8)&0xFF)*(100-p)+((gBg>>8)&0xFF)*p)/100, b=(((c>>16)&0xFF)*(100-p)+((gBg>>16)&0xFF)*p)/100; return((color)(r|(g<<8)|(b<<16))); }
string Px(const double v){ return(DoubleToString(v,_Digits)); }
datetime TimeAt(const int idx){ if(idx<gTotal) return(iTime(_Symbol,_Period,gTotal-1-idx)); return(iTime(_Symbol,_Period,0)+(datetime)((idx-gTotal+1)*PeriodSeconds())); }
double Price(const ENUM_APPLIED_PRICE ap,const double o,const double h,const double l,const double c)
  {
   switch(ap){ case PRICE_OPEN: return(o); case PRICE_HIGH: return(h); case PRICE_LOW: return(l); case PRICE_MEDIAN: return((h+l)/2); case PRICE_TYPICAL: return((h+l+c)/3); case PRICE_WEIGHTED: return((h+l+2*c)/4); }
   return(c);
  }
string TfName(const ENUM_TIMEFRAMES tf){ int s=PeriodSeconds(tf); if(s%604800==0) return(IntegerToString(s/604800)+"W"); if(s%86400==0) return(IntegerToString(s/86400)+"D"); if(s>=2628003) return("1M"); if(s%3600==0) return(IntegerToString(s/3600)+"H"); return(IntegerToString(s/60)+"m"); }
bool Same(const double a,const double b){ return(MathAbs(a-b)<_Point/2); }
void Line(const string nm,const datetime t1,const double p,const datetime t2,const color c,const ENUM_LINE_STYLE st,const int w)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_TREND,0,t1,p,t2,p); ObjectSetInteger(0,nm,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true); ObjectSetInteger(0,nm,OBJPROP_BACK,true); }
   else { ObjectMove(0,nm,0,t1,p); ObjectMove(0,nm,1,t2,p); }
   ObjectSetInteger(0,nm,OBJPROP_COLOR,c); ObjectSetInteger(0,nm,OBJPROP_STYLE,st); ObjectSetInteger(0,nm,OBJPROP_WIDTH,w);
  }
void Text(const string nm,const datetime t,const double p,const string txt,const color c,const int sz,const ENUM_ANCHOR_POINT an)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_TEXT,0,t,p); ObjectSetString(0,nm,OBJPROP_FONT,"Consolas"); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true); }
   else ObjectMove(0,nm,0,t,p);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt); ObjectSetInteger(0,nm,OBJPROP_COLOR,c); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,sz); ObjectSetInteger(0,nm,OBJPROP_ANCHOR,an);
  }
void Label(const string nm,const int corner,const int x,const int y,const string txt,const color c,const int anchor)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_LABEL,0,0,0); ObjectSetString(0,nm,OBJPROP_FONT,"Consolas"); ObjectSetInteger(0,nm,OBJPROP_FONTSIZE,8); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true); }
   ObjectSetInteger(0,nm,OBJPROP_CORNER,corner); ObjectSetInteger(0,nm,OBJPROP_ANCHOR,anchor); ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,nm,OBJPROP_TEXT,txt); ObjectSetInteger(0,nm,OBJPROP_COLOR,c);
  }
void RectLbl(const string nm,const int corner,const int x,const int y,const int w,const int h,const color bg)
  {
   if(ObjectFind(0,nm)<0){ ObjectCreate(0,nm,OBJ_RECTANGLE_LABEL,0,0,0); ObjectSetInteger(0,nm,OBJPROP_BORDER_TYPE,BORDER_FLAT); ObjectSetInteger(0,nm,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,nm,OBJPROP_HIDDEN,true); ObjectSetInteger(0,nm,OBJPROP_BACK,false); }
   ObjectSetInteger(0,nm,OBJPROP_CORNER,corner); ObjectSetInteger(0,nm,OBJPROP_XDISTANCE,x); ObjectSetInteger(0,nm,OBJPROP_YDISTANCE,y); ObjectSetInteger(0,nm,OBJPROP_XSIZE,w); ObjectSetInteger(0,nm,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,nm,OBJPROP_BGCOLOR,bg); ObjectSetInteger(0,nm,OBJPROP_COLOR,bg);
  }
void Del(const string nm){ if(ObjectFind(0,nm)>=0) ObjectDelete(0,nm); }

//==== REGIME ENGINE (plain arrays, oldest-first; used for chart and HTF) ====
// raw stoch -> SMA(kSmooth) -> optional EMA/WMA/RMA(smoothLen) -> range test vs trend SMA -> confirm count
void Regime(const double &src[],const double &tsrc[],const double &high[],const double &low[],const int from,const int n,
            double &raw[],double &kb[],double &k[],double &ma[],double &st[],double &bc[],double &rc[])
  {
   for(int i=from;i<n;i++)
     {
      // raw stochastic
      raw[i]=EMPTY_VALUE;
      if(i>=InpStochLen-1)
        {
         double hh=-DBL_MAX, ll=DBL_MAX; for(int j=i-InpStochLen+1;j<=i;j++){ if(high[j]>hh) hh=high[j]; if(low[j]<ll) ll=low[j]; }
         if(hh>ll) raw[i]=(src[i]-ll)/(hh-ll)*100.0;
        }
      // %K smoothing (SMA, na-strict like Pine)
      kb[i]=EMPTY_VALUE;
      if(i>=InpKSmooth-1){ double s=0; bool ok=true; for(int j=i-InpKSmooth+1;j<=i;j++){ if(raw[j]==EMPTY_VALUE){ ok=false; break; } s+=raw[j]; } if(ok) kb[i]=s/InpKSmooth; }
      // adaptive smoothing
      double kv=kb[i];
      if(InpSmooth!=SM_NONE && kv!=EMPTY_VALUE)
        {
         double prev=(i>0 ? k[i-1] : EMPTY_VALUE);
         if(InpSmooth==SM_WMA)
           {
            double s=0, w=0; bool ok=(i>=InpSmoothLen-1);
            if(ok) for(int j=0;j<InpSmoothLen;j++){ double v=kb[i-j]; if(v==EMPTY_VALUE){ ok=false; break; } double wt=InpSmoothLen-j; s+=v*wt; w+=wt; }
            kv=(ok ? s/w : EMPTY_VALUE);
           }
         else
           {
            double a=(InpSmooth==SM_EMA ? 2.0/(InpSmoothLen+1) : 1.0/InpSmoothLen);
            kv=(prev==EMPTY_VALUE ? kv : prev+a*(kv-prev));
           }
        }
      k[i]=kv;
      // trend SMA
      ma[i]=EMPTY_VALUE;
      if(i>=InpTrendLen-1){ double s=0; for(int j=i-InpTrendLen+1;j<=i;j++) s+=tsrc[j]; ma[i]=s/InpTrendLen; }
      bool up=(ma[i]!=EMPTY_VALUE && tsrc[i]>ma[i]), dn=(ma[i]!=EMPTY_VALUE && tsrc[i]<ma[i]);
      bool bullRaw=(kv!=EMPTY_VALUE && up && kv>=bullLo && kv<=bullHi), bearRaw=(kv!=EMPTY_VALUE && dn && kv>=bearLo && kv<=bearHi);
      bc[i]=(bullRaw ? (i>0 ? bc[i-1] : 0)+1 : 0); rc[i]=(bearRaw ? (i>0 ? rc[i-1] : 0)+1 : 0);
      st[i]=(bullRaw && bc[i]>=InpConfirm ? 1 : bearRaw && rc[i]>=InpConfirm ? -1 : 0);
     }
  }
// ADX (Wilder) + ATR, incremental
void Strength(const int i,const double &high[],const double &low[],const double &close[])
  {
   double tr=(i==0 ? high[i]-low[i] : MathMax(high[i],close[i-1])-MathMin(low[i],close[i-1]));
   double pdm=0, mdm=0; if(i>0){ double u=high[i]-high[i-1], d=low[i-1]-low[i]; pdm=(u>d && u>0 ? u : 0); mdm=(d>u && d>0 ? d : 0); }
   int L=MathMax(1,InpAdxLen), A=MathMax(1,InpAtrLen);
   bSTR[i]=(i==0 ? tr : (bSTR[i-1]*(L-1)+tr)/L); bSPDM[i]=(i==0 ? pdm : (bSPDM[i-1]*(L-1)+pdm)/L); bSMDM[i]=(i==0 ? mdm : (bSMDM[i-1]*(L-1)+mdm)/L);
   double dip=(bSTR[i]>0 ? 100*bSPDM[i]/bSTR[i] : 0), dim=(bSTR[i]>0 ? 100*bSMDM[i]/bSTR[i] : 0), dx=(dip+dim>0 ? 100*MathAbs(dip-dim)/(dip+dim) : 0);
   bADX[i]=(i<2*L ? EMPTY_VALUE : (bADX[i-1]==EMPTY_VALUE ? dx : (bADX[i-1]*(L-1)+dx)/L));
   bATR[i]=(i==0 ? tr : (i<A ? (bATR[i-1]*i+tr)/(i+1) : (bATR[i-1]*(A-1)+tr)/A));
  }

//==== HTF REGIME (recomputed once per HTF bar) =====================
void HtfUpdate()
  {
   if(!htfOn) return;
   datetime t0=iTime(_Symbol,InpHtf,0); if(t0==gHtfTime || t0==0) return;
   MqlRates r[]; int n=CopyRates(_Symbol,InpHtf,0,3000,r); if(n<InpStochLen+InpTrendLen) return;
   double s[], ts[], h[], l[], raw[], kb[], ma[], bc[], rc[];
   ArrayResize(s,n); ArrayResize(ts,n); ArrayResize(h,n); ArrayResize(l,n); ArrayResize(raw,n); ArrayResize(kb,n); ArrayResize(ma,n); ArrayResize(bc,n); ArrayResize(rc,n);
   ArrayResize(hK,n); ArrayResize(hMA,n); ArrayResize(hState,n);
   for(int i=0;i<n;i++){ s[i]=Price(InpStochSrc,r[i].open,r[i].high,r[i].low,r[i].close); ts[i]=Price(InpTrendSrc,r[i].open,r[i].high,r[i].low,r[i].close); h[i]=r[i].high; l[i]=r[i].low; }
   Regime(s,ts,h,l,0,n,raw,kb,hK,hMA,hState,bc,rc);
   hN=n; gHtfTime=t0;
  }
// state of the last COMPLETED HTF bar at chart time t (Pine: request.security(..., state[1], lookahead_on))
int HtfStateAt(const datetime t)
  {
   if(!htfOn || hN<2) return(0);
   int sh=iBarShift(_Symbol,InpHtf,t); if(sh<0) return(0);
   int idx=hN-2-sh; return(idx>=0 ? (int)hState[idx] : 0);
  }

//==== TRADE LEVELS =================================================
string GrpTxt(const int idx){ string s=(idx==1 ? "Entry" : ""); if(tL1==idx) s=(s=="" ? "TP1" : s+" / TP1"); if(tL2==idx) s=(s=="" ? "TP2" : s+" / TP2"); if(tL3==idx) s=(s=="" ? "TP3" : s+" / TP3"); return(s); }
string PendTxt(const int idx,const double p){ return((idx==1 ? "> " : idx==3 ? "* " : "# ")+GrpTxt(idx)+" "+Px(p)); }
string PctTxt(const double lvl){ double p=(tDir==1 ? lvl-tEntry : tEntry-lvl)/tEntry*100; return((p>=0 ? "+" : "")+DoubleToString(p,2)+"%"); }
string LblOf(const int idx){ return(PFX+(idx==1 ? "L_E" : idx==2 ? "L_T1" : idx==3 ? "L_T2" : "L_T3")); }
void DeleteLevels(){ string k[]={"SL","E","T1","T2","T3"}; for(int i=0;i<5;i++){ Del(PFX+"LN_"+k[i]); Del(PFX+"L_"+k[i]); } Del(PFX+"SIG"); }
void DrawLevels(const int bar)
  {
   datetime t1=TimeAt(bar), t2=TimeAt(bar+1);
   Line(PFX+"LN_SL",t1,tSl,t2,C_SL,STYLE_SOLID,2);
   Line(PFX+"LN_E",t1,tEntry,t2,C_ENTRY,STYLE_DASH,1);
   Line(PFX+"LN_T1",t1,tTp1,t2,Blend(C_TP,40),STYLE_DASH,1);
   Line(PFX+"LN_T2",t1,tTp2,t2,Blend(C_TP,20),STYLE_DASH,1);
   Line(PFX+"LN_T3",t1,tTp3,t2,C_TP,STYLE_DASH,1);
   Text(PFX+"L_SL",t2,tSl,"x SL "+Px(tSl),C_SL,8,ANCHOR_LEFT);
   Text(PFX+"L_E",t2,tEntry,PendTxt(1,tEntry),C_ENTRY,8,ANCHOR_LEFT);
   if(tL1==2) Text(PFX+"L_T1",t2,tTp1,PendTxt(2,tTp1),C_TP,8,ANCHOR_LEFT);
   if(tL2==3) Text(PFX+"L_T2",t2,tTp2,PendTxt(3,tTp2),C_TP,8,ANCHOR_LEFT);
   if(tL3==4) Text(PFX+"L_T3",t2,tTp3,PendTxt(4,tTp3),C_TP,8,ANCHOR_LEFT);
  }
void ExtendLevels(const int toBar)
  {
   if(tDir==0 || ObjectFind(0,PFX+"LN_SL")<0) return;
   datetime tx=TimeAt(toBar);
   string k[]={"SL","E","T1","T2","T3"}; double p[5]; p[0]=tSl; p[1]=tEntry; p[2]=tTp1; p[3]=tTp2; p[4]=tTp3;
   for(int i=0;i<5;i++){ if(ObjectFind(0,PFX+"LN_"+k[i])>=0) ObjectMove(0,PFX+"LN_"+k[i],1,tx,p[i]); if(ObjectFind(0,PFX+"L_"+k[i])>=0) ObjectMove(0,PFX+"L_"+k[i],0,tx,p[i]); }
  }
void SetLbl(const string nm,const string txt){ if(ObjectFind(0,nm)>=0) ObjectSetString(0,nm,OBJPROP_TEXT,txt); }

//==== ALERTS =======================================================
string Q(const double v){ return(v==0 ? "null" : "\""+Px(v)+"\""); }
void Fire(const string title,const string payload)
  {
   if(!gLive) return;
   Print(TAG," ",title,"  ",payload);
   if(InpAlertPopup) Alert(TAG," ",_Symbol," ",TfName(_Period),": ",title);
   if(InpAlertPush) SendNotification(TAG+" "+_Symbol+" "+TfName(_Period)+": "+title+" "+payload);
  }
string EntryPayload(const string act,const string dir,const string regime){ return("{\"action\":\""+act+"\",\"ticker\":\""+_Symbol+"\",\"tf\":\""+TfName(_Period)+"\",\"direction\":\""+dir+"\",\"entry\":"+Q(tEntry)+",\"sl\":"+Q(tSl)+",\"tp1\":"+Q(tTp1)+",\"tp2\":"+Q(tTp2)+",\"tp3\":"+Q(tTp3)+",\"regime\":\""+regime+"\"}"); }
string ExitPayload(const string act,const double tp){ return("{\"action\":\""+act+"\",\"ticker\":\""+_Symbol+"\",\"tf\":\""+TfName(_Period)+"\",\"direction\":\""+(tDir==1 ? "long" : "short")+"\",\"entry\":"+Q(tEntry)+",\"sl\":"+Q(tSl)+",\"tp\":"+Q(tp)+"}"); }

//==== TRADE TRACKING (targets intrabar, stop on close) =============
void TrackTrade(const int i,const double &high[],const double &low[],const double &close[],const bool closedBar)
  {
   if(tDir==0 || i<=tBar || (slHit || tp3Hit)) return;
   bool isL=(tDir==1);
   if(!tp1Hit && (isL ? high[i]>=tTp1 : low[i]<=tTp1)){ tp1Hit=true; SetLbl(LblOf(tL1),GrpTxt(tL1)+" HIT "+PctTxt(tTp1)); Fire("TP1 hit",ExitPayload(isL ? InpActPartL : InpActPartS,tTp1)); }
   if(!tp2Hit && (isL ? high[i]>=tTp2 : low[i]<=tTp2)){ tp2Hit=true; SetLbl(LblOf(tL2),GrpTxt(tL2)+" HIT "+PctTxt(tTp2)); Fire("TP2 hit",ExitPayload(isL ? InpActPartL : InpActPartS,tTp2)); }
   if(!tp3Hit && (isL ? high[i]>=tTp3 : low[i]<=tTp3)){ tp3Hit=true; SetLbl(LblOf(tL3),GrpTxt(tL3)+" HIT "+PctTxt(tTp3)); Fire("TP3 hit",ExitPayload(isL ? InpActCloseL : InpActCloseS,tTp3)); }
   if(!tp3Hit && closedBar && (isL ? close[i]<tSl : close[i]>tSl)){ slHit=true; SetLbl(PFX+"L_SL","SL HIT "+PctTxt(close[i])); Fire("Stop hit",ExitPayload(isL ? InpActCloseL : InpActCloseS,0)); }
   if((slHit || tp3Hit) && tCloseBar<0){ tCloseBar=i; ExtendLevels(i+10); }
  }

//==== ONE CLOSED BAR ===============================================
void ProcessBar(const int i,const datetime &time[],const double &high[],const double &low[],const double &close[])
  {
   TrackTrade(i,high,low,close,true);
   int st=(int)bState[i], prev=(i>0 ? (int)bState[i-1] : 0);
   bool chopOk=(!InpUseAdx || (bADX[i]!=EMPTY_VALUE && bADX[i]>=InpAdxMin));
   int hs=HtfStateAt(time[i]);
   double atr=bATR[i], risk=atr*InpSlMult; bool lvlOk=(atr>0 && risk>_Point);
   bool rawLong=(st==1 && prev!=1 && (!htfOn || hs==1) && chopOk && lvlOk && close[i]-risk>0);
   bool rawShort=(st==-1 && prev!=-1 && (!htfOn || hs==-1) && chopOk && lvlOk && close[i]-atr*tpM3>0);
   if(!(rawLong || rawShort)) return;
   if(InpLock && gLive) return;
   // close the previous trade on a new signal
   if(tDir!=0 && !(slHit || tp3Hit)) Fire("Trade closed by new signal",ExitPayload(tDir==1 ? InpActCloseL : InpActCloseS,0));
   DeleteLevels();
   tDir=(rawLong ? 1 : -1); tBar=i; tCloseBar=-1; tp1Hit=false; tp2Hit=false; tp3Hit=false; slHit=false;
   double d=tDir; tEntry=close[i]; tSl=close[i]-d*risk; tTp1=close[i]+d*atr*tpM1; tTp2=close[i]+d*atr*tpM2; tTp3=close[i]+d*atr*tpM3;
   tL1=(Same(tTp1,tEntry) ? 1 : 2); tL2=(Same(tTp2,tEntry) ? 1 : Same(tTp2,tTp1) ? 2 : 3); tL3=(Same(tTp3,tEntry) ? 1 : Same(tTp3,tTp1) ? 2 : Same(tTp3,tTp2) ? 3 : 4);
   if(InpShowSignals) Text(PFX+"SIG",time[i],(rawLong ? low[i]-0.3*atr : high[i]+0.3*atr),(rawLong ? "BUY" : "SELL"),(rawLong ? C_SUP : C_RES),9,rawLong ? ANCHOR_UPPER : ANCHOR_LOWER);
   DrawLevels(i);
   Fire(rawLong ? "BUY signal" : "SELL signal",EntryPayload(rawLong ? InpActLong : InpActShort,rawLong ? "long" : "short",rawLong ? "bull" : "bear"));
  }

//==== DASHBOARD ====================================================
string Bar10(const double v,const double mx){ int f=(int)MathRound(MathMin(v/mx,1.0)*10); string s=""; for(int i=1;i<=10;i++) s+=(i<=f ? "█" : "░"); return(s+"  "+IntegerToString((int)MathRound(v/mx*100))+"%"); }
color BarCol(const double p){ return(p>=0.66 ? C_SUP : p>=0.33 ? C_MID : C_RES); }
int   dRows=0; string dL[32], dR[32]; color dC[32], dBg[32];
void Row(const string l,const string r,const color c,const bool warn=false){ if(dRows>=32) return; dL[dRows]=l; dR[dRows]=r; dC[dRows]=c; dBg[dRows]=(warn ? C_WARN : (dRows%2==1 ? C_BG : Blend(C_BG,40))); dRows++; }
void Dashboard(const int last)
  {
   if(!InpShowDash && !(htfSkipped) && !tpReordered){ ObjectsDeleteAll(0,PFX+"D_"); return; }
   dRows=0;
   if(InpShowDash)
     {
      Row("SRR",_Symbol+"  ·  "+TfName(_Period),C_TXT); dBg[0]=C_HDR;
      Row("Lock",InpLock ? "ACTIVE" : "OFF",InpLock ? C_RES : C_TXT);
      bool warm=(bK[last]==EMPTY_VALUE || bMA[last]==EMPTY_VALUE); int st=(int)bState[last];
      Row("Regime",warm ? "—" : st==1 ? "Bullish" : st==-1 ? "Bearish" : "Neutral",warm ? C_TXT : st==1 ? C_SUP : st==-1 ? C_RES : C_TXT);
      Row("Stochastic %K",bK[last]==EMPTY_VALUE ? "—" : Bar10(bK[last],100),bK[last]==EMPTY_VALUE ? C_TXT : BarCol(bK[last]/100));
      Row("Bull Range",IntegerToString(bullLo)+"–"+IntegerToString(bullHi),C_TXT);
      Row("Bear Range",IntegerToString(bearLo)+"–"+IntegerToString(bearHi),C_TXT);
      bool up=(bMA[last]!=EMPTY_VALUE && gTSrc[last]>bMA[last]), dn=(bMA[last]!=EMPTY_VALUE && gTSrc[last]<bMA[last]);
      Row("Trend",up ? "Up" : dn ? "Down" : "—",up ? C_SUP : dn ? C_RES : C_TXT);
      Row("ADX Strength",bADX[last]==EMPTY_VALUE ? "—" : Bar10(bADX[last],100),bADX[last]==EMPTY_VALUE ? C_TXT : BarCol(bADX[last]/100));
      if(InpUseAdx){ bool ok=(bADX[last]!=EMPTY_VALUE && bADX[last]>=InpAdxMin); Row("Chop Filter",bADX[last]==EMPTY_VALUE ? "—" : ok ? "Pass" : "Blocked",bADX[last]==EMPTY_VALUE ? C_TXT : ok ? C_SUP : C_RES); }
      if(InpUseHtf)
        {
         if(htfSkipped) Row("HTF Regime","Skipped",C_TXT,true);
         else { int hs=HtfStateAt(iTime(_Symbol,_Period,0)); Row("HTF Regime "+TfName(InpHtf),hs==1 ? "Bullish" : hs==-1 ? "Bearish" : "Neutral",hs==1 ? C_SUP : hs==-1 ? C_RES : C_TXT); }
        }
      if(InpSmooth!=SM_NONE) Row("Adaptive Smoothing",StringSubstr(EnumToString(InpSmooth),3)+" · "+IntegerToString(InpSmoothLen),C_TXT);
      int conf=(int)MathMax(bBull[last],bBear[last]);
      Row("Confirm Bars",IntegerToString(MathMin(conf,InpConfirm))+" / "+IntegerToString(InpConfirm),C_TXT);
      Row("ATR Value",bATR[last]>0 ? Px(bATR[last]) : "—",C_TXT);
      string stx=(tDir==0 ? "—" : slHit ? "Stopped" : tp3Hit ? "Targets Done" : tDir==1 ? "Long Open" : "Short Open");
      Row("Trade",stx,tDir==0 ? C_TXT : slHit ? C_RES : tp3Hit ? C_SUP : tDir==1 ? C_SUP : C_RES);
      Row("Entry",tDir==0 ? "—" : Px(tEntry),C_TXT);
      Row("Stop",tDir==0 ? "—" : Px(tSl)+(slHit ? " v" : ""),slHit ? C_RES : C_TXT);
      Row("TP1",tDir==0 ? "—" : Px(tTp1)+(tp1Hit ? " v" : ""),tp1Hit ? C_SUP : C_TXT);
      Row("TP2",tDir==0 ? "—" : Px(tTp2)+(tp2Hit ? " v" : ""),tp2Hit ? C_SUP : C_TXT);
      Row("TP3",tDir==0 ? "—" : Px(tTp3)+(tp3Hit ? " v" : ""),tp3Hit ? C_SUP : C_TXT);
     }
   if(InpUseHtf && htfSkipped && !InpShowDash) Row("HTF Regime","Skipped",C_TXT,true);
   if(tpReordered) Row("Targets","Reordered",C_TXT,true);
   // render
   int rh=18, W=240, H=dRows*rh+6;
   int corner=CORNER_LEFT_UPPER; bool right=false, lower=false;   // dashboard fixed top-left
   RectLbl(PFX+"D_BG",corner,4,4,W,H,C_BG);
   for(int r=0;r<dRows;r++)
     {
      int y=(lower ? 7+(dRows-1-r)*rh : 7+r*rh);
      RectLbl(PFX+"D_R"+IntegerToString(r),corner,4,y-2,W,rh,dBg[r]);
      int aL=(lower ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER), aR=(lower ? ANCHOR_RIGHT_LOWER : ANCHOR_RIGHT_UPPER);
      if(lower) y+=rh-4;
      Label(PFX+"D_L"+IntegerToString(r),corner,right ? W-2 : 10,y,dL[r],Blend(C_TXT,r==0 ? 0 : 25),aL);
      Label(PFX+"D_V"+IntegerToString(r),corner,right ? 10 : W-2,y,dR[r],dC[r],aR);
     }
   for(int r=dRows;r<32;r++){ Del(PFX+"D_R"+IntegerToString(r)); Del(PFX+"D_L"+IntegerToString(r)); Del(PFX+"D_V"+IntegerToString(r)); }
   // brand box under the dashboard
   if(InpShowDash)
     {
      string tg=InpInfoTelegram, hp=InpInfoHomepage; StringReplace(tg,"https://",""); StringReplace(hp,"https://",""); StringReplace(tg,"http://",""); StringReplace(hp,"http://","");
      int by=4+H+4;
      RectLbl(PFX+"D_BRAND",corner,4,by,W,BRAND_H,C_HDR);
      Label(PFX+"D_BRANDL",corner,10,by+BRAND_H/2,tg+" | "+hp,C_MID,ANCHOR_LEFT);
     }
   else { Del(PFX+"D_BRAND"); Del(PFX+"D_BRANDL"); }
  }

//==== INIT / DEINIT / RESET ========================================
int OnInit()
  {
   SetIndexBuffer(0,bO,INDICATOR_DATA); SetIndexBuffer(1,bH,INDICATOR_DATA); SetIndexBuffer(2,bL,INDICATOR_DATA); SetIndexBuffer(3,bC,INDICATOR_DATA); SetIndexBuffer(4,bCol,INDICATOR_COLOR_INDEX);
   SetIndexBuffer(5,bRaw,INDICATOR_CALCULATIONS); SetIndexBuffer(6,bKB,INDICATOR_CALCULATIONS); SetIndexBuffer(7,bK,INDICATOR_CALCULATIONS); SetIndexBuffer(8,bMA,INDICATOR_CALCULATIONS);
   SetIndexBuffer(9,bSTR,INDICATOR_CALCULATIONS); SetIndexBuffer(10,bSPDM,INDICATOR_CALCULATIONS); SetIndexBuffer(11,bSMDM,INDICATOR_CALCULATIONS); SetIndexBuffer(12,bADX,INDICATOR_CALCULATIONS);
   SetIndexBuffer(13,bATR,INDICATOR_CALCULATIONS); SetIndexBuffer(14,bState,INDICATOR_CALCULATIONS); SetIndexBuffer(15,bBull,INDICATOR_CALCULATIONS); SetIndexBuffer(16,bBear,INDICATOR_CALCULATIONS);
   PlotIndexSetInteger(0,PLOT_COLOR_INDEXES,3); PlotIndexSetInteger(0,PLOT_LINE_COLOR,0,C_NEUT); PlotIndexSetInteger(0,PLOT_LINE_COLOR,1,C_SUP); PlotIndexSetInteger(0,PLOT_LINE_COLOR,2,C_RES);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE); PlotIndexSetInteger(0,PLOT_SHOW_DATA,false);
   if(!InpColorCandles) PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_NONE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Stochastic Range Regime"); IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   gBg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND);
   bullLo=MathMin(InpBullLo,InpBullHi); bullHi=MathMax(InpBullLo,InpBullHi); bearLo=MathMin(InpBearLo,InpBearHi); bearHi=MathMax(InpBearLo,InpBearHi);
   tpM1=MathMin(InpTp1Mult,MathMin(InpTp2Mult,InpTp3Mult)); tpM3=MathMax(InpTp1Mult,MathMax(InpTp2Mult,InpTp3Mult));
   tpM2=MathMax(MathMin(InpTp1Mult,InpTp2Mult),MathMin(MathMax(InpTp1Mult,InpTp2Mult),InpTp3Mult));
   tpReordered=(tpM1!=InpTp1Mult || tpM2!=InpTp2Mult || tpM3!=InpTp3Mult);
   htfSkipped=(InpUseHtf && PeriodSeconds(InpHtf)<PeriodSeconds()); htfOn=(InpUseHtf && !htfSkipped);
   ResetState();
   return(INIT_SUCCEEDED);
  }
void ResetState(){ ObjectsDeleteAll(0,PFX); gLast=-1; gLive=false; tDir=0; tBar=-1; tCloseBar=-1; tp1Hit=false; tp2Hit=false; tp3Hit=false; slHit=false; gHtfTime=0; hN=0; }
void OnDeinit(const int reason){ ObjectsDeleteAll(0,PFX); }

//==== CALCULATE ====================================================
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],const double &open[],const double &high[],const double &low[],const double &close[],const long &tick_volume[],const long &volume[],const int &spread[])
  {
   int need=MathMax(InpStochLen+InpKSmooth+InpSmoothLen,MathMax(InpTrendLen,2*InpAdxLen))+2;
   if(rates_total<need) return(0);
   gTotal=rates_total;
   if(prev_calculated==0) ResetState();
   int start=(prev_calculated>0 ? prev_calculated-1 : 0);
   ArrayResize(gSrc,rates_total); ArrayResize(gTSrc,rates_total);
   for(int i=start;i<rates_total;i++){ gSrc[i]=Price(InpStochSrc,open[i],high[i],low[i],close[i]); gTSrc[i]=Price(InpTrendSrc,open[i],high[i],low[i],close[i]); }
   Regime(gSrc,gTSrc,high,low,start,rates_total,bRaw,bKB,bK,bMA,bState,bBull,bBear);
   for(int i=start;i<rates_total;i++)
     {
      Strength(i,high,low,close);
      bO[i]=open[i]; bH[i]=high[i]; bL[i]=low[i]; bC[i]=close[i]; bCol[i]=(bState[i]==1 ? 1 : bState[i]==-1 ? 2 : 0);
     }
   HtfUpdate();
   int lastClosed=rates_total-2;
   int from=(gLast<0 ? MathMax(need,lastClosed-InpMaxBars) : gLast+1);
   bool newBar=false;
   for(int i=from;i<=lastClosed;i++){ ProcessBar(i,time,high,low,close); gLast=i; newBar=true; }
   if(!gLive && prev_calculated>0) gLive=true;
   // forming bar: targets are intrabar, stop waits for the close
   TrackTrade(rates_total-1,high,low,close,false);
   if(tDir!=0 && tCloseBar<0) ExtendLevels(rates_total-1+10);
   Dashboard(rates_total-1);
   return(rates_total);
  }
//+------------------------------------------------------------------+
