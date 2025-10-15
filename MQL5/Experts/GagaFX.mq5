//+------------------------------------------------------------------+
//|                                                     GagaFX.mq5   |
//|  MT5 EA (2025-ready): Scalping with MTF context + short-horizon  |
//|  AI predictions, BOS/structure, EMA/SMA/RSI/ATR/TSI, GUI panel,  |
//|  S/R lines, risk mgmt, and research logs                         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"
#property description "GagaFX: MTF bias (EMA/RSI/TSI), BOS/structure, +1/+2/+3 predictions, HTF S/R, GUI, risk controls."

#include <Trade/Trade.mqh>

// Enums
enum ENUM_SENTIMENT_SOURCE { SENTIMENT_INTERNAL=0, SENTIMENT_FILE=1 };
enum ENUM_STRATEGY_MODE { MODE_SCALP=0, MODE_EXTENDED=1 };

//============================== Inputs ================================//
// ======== Basic parameters ========
input string  S1_Basic              = "===== Basic parameters =====";
input string  InpSymbol             = "XAUUSD";
input ENUM_TIMEFRAMES InpTF         = PERIOD_M1;
input long    MagicNumber           = 90201975;

// ======== Risk & Execution ========
input string  S2_Risk               = "===== Risk & Execution =====";
input double  RiskPerTradePct       = 0.50;
input int     MaxOpenPositions      = 1;
input bool    AllowHedge            = false;
input int     MaxSpreadPoints       = 80;
input int     SlippagePoints        = 20;

// ======== Filters ========
input string  S3_Filters            = "===== Filters =====";
input bool    UseSessionFilter      = true;
input int     SessionStartHour      = 7;
input int     SessionEndHour        = 19;
input bool    BlockHighImpactNews   = true;
input int     NewsBlockMinutesBefore= 45;
input int     NewsBlockMinutesAfter = 45;

// ======== Indicators ========
input string  S4_Indicators         = "===== Indicators =====";
input int     FastEMA               = 50;
input int     SlowEMA               = 200;
input int     RSI_Period            = 14;
input int     RSI_LongMin           = 58;
input int     RSI_ShortMax          = 42;
input int     ATR_Period            = 14;

// ======== Stops / Targets ========
input string  S5_TM                 = "===== Stops / Targets =====";
input double  ATR_SL_Mult           = 2.5;
input double  TP_R_Multiple         = 1.6;
input bool    UseTrailing           = true;
input double  TrailATR_Mult         = 1.2;
input bool    MoveToBE_At1R         = true;
input bool    UsePartialTP          = true;
input double  PartialTP_R           = 0.9;
input double  PartialClosePct       = 40.0;

// ======== Prediction Gate ========
input string  S6_Pred               = "===== Prediction Gate =====";
input bool    UsePredictionsForEntries = true;
input double  PredictThreshold      = 0.62;
input int     CalibrationBars       = 3000;
input int     OnlineWindow          = 800;
input bool    ResearchMode          = true;
input ENUM_SENTIMENT_SOURCE SentimentSource = SENTIMENT_INTERNAL;

// Additional required variables (kept for compatibility)
input double  MaxDailyLossPct       = 5.0;
input int     FastSMA               = 20;
input int     SlowSMA               = 100;
input int     SwingLookback         = 5;
input int     StructureConfirmBars  = 2;
input bool    RequireBOS            = true;
input int     TSI_Long              = 25;
input int     TSI_Short             = 13;
input int     TSI_Signal            = 7;
input double  TSI_MinDiff           = 0.0;
input bool    LearnInLive           = false;
input bool    LogPredictions        = true;
input bool    ExportPayload         = false;
input int     PayloadBars           = 100;
input bool    ShowDashboard         = true;
input bool    UseCompactHUD         = true;
input int     HUD_HorizonBars       = 3;
input bool    HUD_AlwaysOnTop       = true;
input ENUM_BASE_CORNER HUD_Corner   = CORNER_RIGHT_LOWER;
input int     HUD_XOffset           = 8;
input int     HUD_YOffset           = 8;
input bool    TradingEnabled        = true;
input bool    ShowControlPanel      = false;
input bool    ShowStructure         = true;
input bool    VerboseLogs           = false;
input ENUM_STRATEGY_MODE StrategyMode = MODE_SCALP;
input bool    UseMTFContext         = true;
input ENUM_TIMEFRAMES HTF1          = PERIOD_M5;
input ENUM_TIMEFRAMES HTF2          = PERIOD_M15;
input ENUM_TIMEFRAMES HTF3          = PERIOD_M30;
input ENUM_TIMEFRAMES HTF4          = PERIOD_H1;
input int     HTF_ExtremeLookback   = 200;
input double  ExtremeProximityATR   = 0.75;

//===================== Runtime-overridable (GUI) ======================//
double g_RiskPerTradePct;
double g_PredictThreshold;
double g_ATR_SL_Mult;
double g_TP_R_Multiple;
int    g_MaxSpreadPoints;
bool   g_UsePredictionsForEntries;
bool   g_UseMTFContext;
bool   g_LogPredictions;
bool   g_ExportPayload;
ENUM_STRATEGY_MODE g_StrategyMode;
ENUM_SENTIMENT_SOURCE g_SentimentSource;
// Advanced/runtime mirrors for inputs that are const at runtime
double g_TrailATR_Mult;
bool   g_UsePartialTP;
double g_PartialTP_R;
double g_PartialClosePct;
bool   g_MoveToBE_At1R;

//============================== Globals ===============================//
CTrade           Trade;

string           sym;
ENUM_TIMEFRAMES  tf;
double           _pt=0.0;
int              SymDigits=0;

// Indicator handles
int hEMAfast=-1, hEMAslow=-1, hSMAfast=-1, hSMAslow=-1, hRSI=-1, hATR=-1;
int hEMAfast_HTF[4]={-1,-1,-1,-1}, hEMAslow_HTF[4]={-1,-1,-1,-1}, hRSI_HTF[4]={-1,-1,-1,-1}, hATR_HTF[4]={-1,-1,-1,-1};
ENUM_TIMEFRAMES hTFs[4];

// Local rates cache
MqlRates gRates[];
int      gBars=0;
datetime lastBarTime=0;

// Daily guard
double   dayStartEquity=0.0;
int      dayOfYear=-1;

// Structure
struct SwingInfo { int idxHigh; double priceHigh; int idxLow; double priceLow; };
SwingInfo swings;
enum TrendBias { BULL=1, BEAR=-1, NEUTRAL=0 };
TrendBias trendBias=NEUTRAL;
bool      bosUp=false, bosDown=false;

// Prediction model
#define FEAT_COUNT 16
double w1[FEAT_COUNT], w2[FEAT_COUNT], w3[FEAT_COUNT];
double lr=0.02;
int    barCount=0;

// Ring buffer for features
#define BUF 1024
double   featBuf[BUF][FEAT_COUNT];
double   closeBuf[BUF];
datetime timeBuf[BUF];
int      writePos=0;

// Metrics
int hits1=0, total1=0, hits2=0, total2=0, hits3=0, total3=0;

// Files
string fPred="predictions.csv";
string fTrades="trades.csv";
string fMetrics="metrics_summary.csv";
string fPayload="payload.json";
string fHUDStatus="hud_status.json";

//==================== Compact HUD / Plan state =====================//
string g_NextPlanSide = "FLAT";
double g_NextPlanLots = 0.0;
double g_NextPlanLev  = 0.0;
double g_NextPlanEstPx= 0.0;
double g_NextPlanEntry= 0.0;

// Track expected vs result per position
#define MAX_TRACK 64
struct PlanTrack { ulong position; ulong deal_in; int dir; double entry; double expected; datetime t_entry; };
PlanTrack g_planTrack[MAX_TRACK];
int g_planCount=0;

int FindTrackByPosition(ulong pos){ for(int i=0;i<g_planCount;i++) if(g_planTrack[i].position==pos) return i; return -1; }
void AddTrack(ulong pos, ulong deal_in, int dir, double entry, double expected, datetime t_entry){
   int i = FindTrackByPosition(pos);
   if(i==-1 && g_planCount<MAX_TRACK){ i=g_planCount++; }
   if(i>=0){ g_planTrack[i].position=pos; g_planTrack[i].deal_in=deal_in; g_planTrack[i].dir=dir; g_planTrack[i].entry=entry; g_planTrack[i].expected=expected; g_planTrack[i].t_entry=t_entry; }
}
void RemoveTrackIndex(int idx){ if(idx<0||idx>=g_planCount) return; for(int i=idx;i<g_planCount-1;i++) g_planTrack[i]=g_planTrack[i+1]; g_planCount--; }

//============================== Helpers ===============================//
double Clamp(double v,double lo,double hi){ if(v<lo) return lo; if(v>hi) return hi; return v; }
double Sigmoid(double x){ return 1.0/(1.0+MathExp(-x)); }

// --- Safe ARGB maker for MQL5 (no dependency on built-in ARGB)
inline color ARGBc(uchar a, uchar r, uchar g, uchar b)
{
   // Explicit cast to color to avoid implicit uint->color warning
   return (color)(((uint)a<<24) | ((uint)r<<16) | ((uint)g<<8) | (uint)b);
}

// ---- Theme colors (dark & light) ----
static const color GFX_PANEL_BG_DARK       = ARGBc(220,  28,  28,  28);
static const color GFX_PANEL_BORDER_DARK   = ARGBc(255,  90,  90,  90);
static const color GFX_TEXT_PRIMARY_DARK   = ARGBc(255, 235, 235, 235);
static const color GFX_TEXT_SECONDARY_DARK = ARGBc(255, 190, 190, 190);

static const color GFX_PANEL_BG_LIGHT      = ARGBc(220, 245, 245, 245);
static const color GFX_PANEL_BORDER_LIGHT  = ARGBc(255, 170, 170, 170);
static const color GFX_TEXT_PRIMARY_LIGHT  = ARGBc(255,  60,  60,  60);
static const color GFX_TEXT_SECONDARY_LIGHT= ARGBc(255, 100, 100, 100);

// Toggles & buttons
static const color GFX_TOGGLE_ON_BG_CONST  = ARGBc(255,  50, 160,  90);
static const color GFX_TOGGLE_OFF_BG_CONST = ARGBc(255, 190,  70,  70);
static const color GFX_BTN_DARK_BG_CONST   = ARGBc(255,  70,  90, 120);
static const color GFX_BTN_LIGHT_BG_CONST  = ARGBc(255, 150, 170, 200);
static const color GFX_WHITE_CONST         = ARGBc(255, 255, 255, 255);
static const color GFX_DARK_CONST          = ARGBc(255,  40,  40,  40);

// Additional color constants for new UI helpers
static const color GFX_TOGGLE_ON_BG   = GFX_TOGGLE_ON_BG_CONST;
static const color GFX_TOGGLE_OFF_BG  = GFX_TOGGLE_OFF_BG_CONST;
static const color GFX_WHITE          = GFX_WHITE_CONST;

//=========================== UI Globals ===========================//
bool   GFX_AdvVisible = false;      // collapsible Advanced section
double GFX_ScaleFactor = 1.0;       // DPI scale
bool   GFX_Dark = true;             // theme

color  GFX_PanelBG, GFX_PanelBorder;
color  GFX_TextPrimary, GFX_TextSecondary;
color  GFX_ToggleOnBG, GFX_ToggleOffBG;
color  GFX_NudgeBG, GFX_NudgeText;

// Optional runtime mirrors for immutable inputs
bool   g_UseSessionFilter = false;      // mirrors UseSessionFilter
bool   g_BlockHighImpactNews = false;   // mirrors BlockHighImpactNews

// Main panel layout cache
int    GFX_PanelX = 10;
int    GFX_PanelY = 10;
int    GFX_PanelW = 440;
int    GFX_PanelH = 0;  // computed

// Compact HUD object names
#define GFX_HUD_BG          "GFX_HUD_BG"
#define GFX_HUD_TEXT        "GFX_HUD_TEXT"
#define GFX_BTN_HUD_TOGGLE  "GFX_BTN_HUD_TOGGLE"
#define GFX_BTN_TOP_TOGGLE  "GFX_BTN_TOP_TOGGLE"
#define GFX_BTN_TRD_TOGGLE  "GFX_BTN_TRD_TOGGLE"

// Minimal HUD + Prediction widget names
#define HUD_BG      "GFX_BG"
#define HUD_T       "GFX_T"
#define HUD_START   "GFX_BTN_START"
#define HUD_PGATE   "GFX_BTN_PG"
#define HUD_RISK    "GFX_L_RISK"
#define HUD_NOTE    "GFX_L_NOTE"

#define PBG         "GFX_PBG"
#define PL1         "GFX_PL1"
#define PL2         "GFX_PL2"
#define PL3         "GFX_PL3"

// Runtime UI mirrors
bool   g_ShowControlPanel = true;
bool   g_UseCompactHUD    = true;
bool   g_HUD_OnTop        = true;
bool   g_TradingEnabled   = true;
bool   g_Enabled          = true;  // alias for g_TradingEnabled for HUD compatibility
// HUD runtime mirrors
double g_RiskPerTradePct_Runtime=0.0;
int    g_MaxSpreadPoints_Runtime=0;

// Note: Old HUD helper functions removed - now using direct object creation
// for precise positioning control in HUD_Build() and PRED_Build()

void HUD_Build()
{
   // Get chart dimensions for proper positioning
   int chartWidth = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   
   // Much larger panel to prevent text overflow
   int panelWidth = 400;
   int panelHeight = 250;
   int margin = 30;
   
   // Position from left edge (chartWidth - panelWidth - margin)
   int panelX = chartWidth - panelWidth - margin;
   int panelY = chartHeight - panelHeight - margin;
   
   color bg = (color)ChartGetInteger(0,CHART_COLOR_BACKGROUND,0);
   bool dark = (bg==0 || bg==clrBlack);
   color panelBg = dark ? C'40,40,40' : C'240,240,240';
   color textColor = dark ? C'255,255,255' : C'0,0,0';
   color buttonOn = C'0,150,0';
   color buttonOff = C'150,0,0';
   
   // Main panel background
   if(ObjectFind(0,HUD_BG)<0) ObjectCreate(0,HUD_BG,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,HUD_BG,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_BG,OBJPROP_XDISTANCE,panelX);
   ObjectSetInteger(0,HUD_BG,OBJPROP_YDISTANCE,panelY);
   ObjectSetInteger(0,HUD_BG,OBJPROP_XSIZE,panelWidth);
   ObjectSetInteger(0,HUD_BG,OBJPROP_YSIZE,panelHeight);
   ObjectSetInteger(0,HUD_BG,OBJPROP_BGCOLOR,panelBg);
   ObjectSetInteger(0,HUD_BG,OBJPROP_COLOR,C'100,100,100');
   ObjectSetInteger(0,HUD_BG,OBJPROP_BACK,true);
   ObjectSetInteger(0,HUD_BG,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_BG,OBJPROP_ZORDER,0);

   // Title - shorter to fit
   if(ObjectFind(0,HUD_T)<0) ObjectCreate(0,HUD_T,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,HUD_T,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_T,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,HUD_T,OBJPROP_YDISTANCE,panelY + 20);
   ObjectSetInteger(0,HUD_T,OBJPROP_FONTSIZE,14);
   ObjectSetInteger(0,HUD_T,OBJPROP_COLOR,textColor);
   ObjectSetString(0,HUD_T,OBJPROP_FONT,"Arial Bold");
   ObjectSetString(0,HUD_T,OBJPROP_TEXT,"GagaFX Panel");
   ObjectSetInteger(0,HUD_T,OBJPROP_BACK,false);
   ObjectSetInteger(0,HUD_T,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_T,OBJPROP_ZORDER,1);

   // START/STOP button - much larger
   if(ObjectFind(0,HUD_START)<0) ObjectCreate(0,HUD_START,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,HUD_START,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_START,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,HUD_START,OBJPROP_YDISTANCE,panelY + 50);
   ObjectSetInteger(0,HUD_START,OBJPROP_XSIZE,120);
   ObjectSetInteger(0,HUD_START,OBJPROP_YSIZE,35);
   ObjectSetInteger(0,HUD_START,OBJPROP_BGCOLOR,(g_Enabled?buttonOn:buttonOff));
   ObjectSetInteger(0,HUD_START,OBJPROP_COLOR,C'255,255,255');
   ObjectSetInteger(0,HUD_START,OBJPROP_FONTSIZE,12);
   ObjectSetString(0,HUD_START,OBJPROP_FONT,"Arial");
   ObjectSetString(0,HUD_START,OBJPROP_TEXT,(g_Enabled?"START":"STOP"));
   ObjectSetInteger(0,HUD_START,OBJPROP_BACK,false);
   ObjectSetInteger(0,HUD_START,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_START,OBJPROP_ZORDER,2);

   // Gate button - much larger
   if(ObjectFind(0,HUD_PGATE)<0) ObjectCreate(0,HUD_PGATE,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_XDISTANCE,panelX + 160);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_YDISTANCE,panelY + 50);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_XSIZE,120);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_YSIZE,35);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_BGCOLOR,(g_UsePredictionsForEntries?buttonOn:buttonOff));
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_COLOR,C'255,255,255');
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_FONTSIZE,12);
   ObjectSetString(0,HUD_PGATE,OBJPROP_FONT,"Arial");
   ObjectSetString(0,HUD_PGATE,OBJPROP_TEXT,(g_UsePredictionsForEntries?"Gate:ON":"Gate:OFF"));
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_BACK,false);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_PGATE,OBJPROP_ZORDER,2);

   // Risk info
   string rs=StringFormat("Risk: %.2f%%  Spread: %d pts", g_RiskPerTradePct_Runtime, g_MaxSpreadPoints_Runtime);
   if(ObjectFind(0,HUD_RISK)<0) ObjectCreate(0,HUD_RISK,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_YDISTANCE,panelY + 100);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_FONTSIZE,12);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_COLOR,textColor);
   ObjectSetString(0,HUD_RISK,OBJPROP_FONT,"Arial");
   ObjectSetString(0,HUD_RISK,OBJPROP_TEXT,rs);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_BACK,false);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_RISK,OBJPROP_ZORDER,1);

   // Predictions section
   if(ObjectFind(0,PL1)<0) ObjectCreate(0,PL1,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,PL1,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,PL1,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,PL1,OBJPROP_YDISTANCE,panelY + 130);
   ObjectSetInteger(0,PL1,OBJPROP_FONTSIZE,12);
   ObjectSetInteger(0,PL1,OBJPROP_COLOR,textColor);
   ObjectSetString(0,PL1,OBJPROP_FONT,"Arial");
   ObjectSetString(0,PL1,OBJPROP_TEXT,"p(up,1): --");
   ObjectSetInteger(0,PL1,OBJPROP_BACK,false);
   ObjectSetInteger(0,PL1,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PL1,OBJPROP_ZORDER,1);

   if(ObjectFind(0,PL2)<0) ObjectCreate(0,PL2,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,PL2,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,PL2,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,PL2,OBJPROP_YDISTANCE,panelY + 155);
   ObjectSetInteger(0,PL2,OBJPROP_FONTSIZE,12);
   ObjectSetInteger(0,PL2,OBJPROP_COLOR,textColor);
   ObjectSetString(0,PL2,OBJPROP_FONT,"Arial");
   ObjectSetString(0,PL2,OBJPROP_TEXT,"exp +1: --");
   ObjectSetInteger(0,PL2,OBJPROP_BACK,false);
   ObjectSetInteger(0,PL2,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PL2,OBJPROP_ZORDER,1);

   if(ObjectFind(0,PL3)<0) ObjectCreate(0,PL3,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,PL3,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,PL3,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,PL3,OBJPROP_YDISTANCE,panelY + 180);
   ObjectSetInteger(0,PL3,OBJPROP_FONTSIZE,12);
   ObjectSetInteger(0,PL3,OBJPROP_COLOR,textColor);
   ObjectSetString(0,PL3,OBJPROP_FONT,"Arial");
   ObjectSetString(0,PL3,OBJPROP_TEXT,"exp +3: --");
   ObjectSetInteger(0,PL3,OBJPROP_BACK,false);
   ObjectSetInteger(0,PL3,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,PL3,OBJPROP_ZORDER,1);

   // F7 hint
   if(ObjectFind(0,HUD_NOTE)<0) ObjectCreate(0,HUD_NOTE,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_XDISTANCE,panelX + 20);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_YDISTANCE,panelY + 210);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_COLOR,textColor);
   ObjectSetString(0,HUD_NOTE,OBJPROP_FONT,"Arial");
   ObjectSetString(0,HUD_NOTE,OBJPROP_TEXT,"F7: Properties");
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_BACK,false);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,HUD_NOTE,OBJPROP_ZORDER,1);
}
void HUD_Refresh()
{
   color buttonOn = C'0,150,0';
   color buttonOff = C'150,0,0';
   
   // Fix button logic: when g_Enabled=true, show "START" (green), when false show "STOP" (red)
   ObjectSetString (0, HUD_START, OBJPROP_TEXT, (g_Enabled?"START":"STOP"));
   ObjectSetInteger(0, HUD_START, OBJPROP_BGCOLOR, (g_Enabled?buttonOn:buttonOff));

   ObjectSetString (0, HUD_PGATE,  OBJPROP_TEXT, (g_UsePredictionsForEntries?"Gate:ON":"Gate:OFF"));
   ObjectSetInteger(0, HUD_PGATE,  OBJPROP_BGCOLOR,(g_UsePredictionsForEntries?buttonOn:buttonOff));

   string rs=StringFormat("Risk: %.2f%%  Spread: %d pts", g_RiskPerTradePct_Runtime, g_MaxSpreadPoints_Runtime);
   ObjectSetString(0, HUD_RISK, OBJPROP_TEXT, rs);
}

void PRED_Build()
{
   // Predictions are now integrated into the main HUD panel
   // This function is kept for compatibility but does nothing
   // All prediction elements are created in HUD_Build()
}
void PRED_Update(double p1,double atr)
{
   double exp1 = (p1>=0.5 ? +0.20*atr/_pt : -0.20*atr/_pt);
   double exp3 = (p1>=0.5 ? +0.55*atr/_pt : -0.55*atr/_pt);
   ObjectSetString(0, PL1, OBJPROP_TEXT, StringFormat("p(up,1): %.2f", p1));
   ObjectSetString(0, PL2, OBJPROP_TEXT, StringFormat("exp +1: %+.0f", exp1));
   ObjectSetString(0, PL3, OBJPROP_TEXT, StringFormat("exp +3: %+.0f", exp3));
}

// Object name constants (prefix required)
#define GFX_BG               "GFX_BG"
#define GFX_TITLE            "GFX_TITLE"

#define GFX_SEC_STRAT        "GFX_SEC_STRAT"
#define GFX_SEC_RISK         "GFX_SEC_RISK"
#define GFX_SEC_FILTER       "GFX_SEC_FILTER"
#define GFX_SEC_LOG          "GFX_SEC_LOG"
#define GFX_SEC_ADV          "GFX_SEC_ADV"

#define GFX_BTN_MODE         "GFX_BTN_MODE"
#define GFX_BTN_PGATE        "GFX_BTN_PGATE"
#define GFX_BTN_MTF          "GFX_BTN_MTF"

#define GFX_BTN_RISK_MINUS   "GFX_BTN_RISK_MINUS"
#define GFX_BTN_RISK_PLUS    "GFX_BTN_RISK_PLUS"
#define GFX_VAL_RISK         "GFX_VAL_RISK"

#define GFX_BTN_SL_MINUS     "GFX_BTN_SL_MINUS"
#define GFX_BTN_SL_PLUS      "GFX_BTN_SL_PLUS"
#define GFX_VAL_SL           "GFX_VAL_SL"

#define GFX_BTN_TPR_MINUS    "GFX_BTN_TPR_MINUS"
#define GFX_BTN_TPR_PLUS     "GFX_BTN_TPR_PLUS"
#define GFX_VAL_TPR          "GFX_VAL_TPR"

#define GFX_BTN_SPR_MINUS    "GFX_BTN_SPR_MINUS"
#define GFX_BTN_SPR_PLUS     "GFX_BTN_SPR_PLUS"
#define GFX_VAL_SPR          "GFX_VAL_SPR"

#define GFX_BTN_SESSION_TOGGLE "GFX_BTN_SESSION_TOGGLE"
#define GFX_BTN_NEWS_TOGGLE    "GFX_BTN_NEWS_TOGGLE"

#define GFX_BTN_LOG           "GFX_BTN_LOG"
#define GFX_BTN_PAYLOAD       "GFX_BTN_PAYLOAD"

#define GFX_BTN_ADV_TOGGLE    "GFX_BTN_ADV_TOGGLE"
#define GFX_BTN_THR_MINUS     "GFX_BTN_THR_MINUS"
#define GFX_BTN_THR_PLUS      "GFX_BTN_THR_PLUS"
#define GFX_VAL_THR           "GFX_VAL_THR"

#define GFX_BTN_TRAIL_MINUS   "GFX_BTN_TRAIL_MINUS"
#define GFX_BTN_TRAIL_PLUS    "GFX_BTN_TRAIL_PLUS"
#define GFX_VAL_TRAIL         "GFX_VAL_TRAIL"

#define GFX_BTN_PARTIAL_TOGGLE  "GFX_BTN_PARTIAL_TOGGLE"
#define GFX_BTN_PARTIAL_R_MINUS "GFX_BTN_PARTIAL_R_MINUS"
#define GFX_BTN_PARTIAL_R_PLUS  "GFX_BTN_PARTIAL_R_PLUS"
#define GFX_VAL_PARTIAL_R       "GFX_VAL_PARTIAL_R"
#define GFX_BTN_PARTIAL_PC_MINUS "GFX_BTN_PARTIAL_PC_MINUS"
#define GFX_BTN_PARTIAL_PC_PLUS  "GFX_BTN_PARTIAL_PC_PLUS"
#define GFX_VAL_PARTIAL_PC       "GFX_VAL_PARTIAL_PC"

#define GFX_BTN_BE_TOGGLE      "GFX_BTN_BE_TOGGLE"

// Labels (left column)
#define GFX_LBL_MODE        "GFX_LBL_MODE"
#define GFX_LBL_PGATE       "GFX_LBL_PGATE"
#define GFX_LBL_MTF         "GFX_LBL_MTF"
#define GFX_LBL_RISK        "GFX_LBL_RISK"
#define GFX_LBL_SL          "GFX_LBL_SL"
#define GFX_LBL_TPR         "GFX_LBL_TPR"
#define GFX_LBL_SPR         "GFX_LBL_SPR"
#define GFX_LBL_SESSION     "GFX_LBL_SESSION"
#define GFX_LBL_NEWS        "GFX_LBL_NEWS"
#define GFX_LBL_LOG         "GFX_LBL_LOG"
#define GFX_LBL_PAYLOAD     "GFX_LBL_PAYLOAD"
#define GFX_LBL_THR         "GFX_LBL_THR"
#define GFX_LBL_TRAIL       "GFX_LBL_TRAIL"
#define GFX_LBL_PARTIAL     "GFX_LBL_PARTIAL"
#define GFX_LBL_PARTIAL_R   "GFX_LBL_PARTIAL_R"
#define GFX_LBL_PARTIAL_PC  "GFX_LBL_PARTIAL_PC"
#define GFX_LBL_BE          "GFX_LBL_BE"

//=========================== UI Helpers ===========================//
// Map CORNER_* to the correct ANCHOR_* so text grows inwards, not off-screen
int AnchorFromCorner(const int corner)
{
   switch(corner)
   {
      case CORNER_LEFT_UPPER:  return ANCHOR_LEFT_UPPER;
      case CORNER_RIGHT_UPPER: return ANCHOR_RIGHT_UPPER;
      case CORNER_LEFT_LOWER:  return ANCHOR_LEFT_LOWER;
      case CORNER_RIGHT_LOWER: return ANCHOR_RIGHT_LOWER;
      default:                 return ANCHOR_LEFT_UPPER;
   }
}

// Compact DPI scale (>=1.0)
double GFX_Scale()
{
   long dpi = TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi<=0) dpi=96;
   double s=(double)dpi/96.0; if(s<1.0) s=1.0;
   return s;
}

// Theme colors (reuse yours if already defined)
void GFX_GetTheme(color &pbg,color &pbrd,color &txt,bool &dark)
{
   color bg=(color)ChartGetInteger(0,CHART_COLOR_BACKGROUND,0);
   dark=(bg==0 || bg==clrBlack);
   pbg  = dark? GFX_PANEL_BG_DARK     : GFX_PANEL_BG_LIGHT;
   pbrd = dark? GFX_PANEL_BORDER_DARK : GFX_PANEL_BORDER_LIGHT;
   txt  = dark? GFX_TEXT_PRIMARY_DARK : GFX_TEXT_PRIMARY_LIGHT;
}

// Note: Direct object creation is now used in HUD_Build() and PRED_Build() 
// for better control over positioning and anchoring

// Read chart background and decide dark/light theme, fill global colors
void GFX_GetThemeColors()
{
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND, 0);
   // Simple heuristic: black-like background → dark theme
   GFX_Dark = (bg==0 || bg==clrBlack);

   if(GFX_Dark)
   {
      GFX_PanelBG       = GFX_PANEL_BG_DARK;
      GFX_PanelBorder   = GFX_PANEL_BORDER_DARK;
      GFX_TextPrimary   = GFX_TEXT_PRIMARY_DARK;
      GFX_TextSecondary = GFX_TEXT_SECONDARY_DARK;
      GFX_ToggleOnBG    = GFX_TOGGLE_ON_BG_CONST;
      GFX_ToggleOffBG   = GFX_TOGGLE_OFF_BG_CONST;
      GFX_NudgeBG       = GFX_BTN_DARK_BG_CONST;
      GFX_NudgeText     = GFX_WHITE_CONST;
   }
   else
   {
      GFX_PanelBG       = GFX_PANEL_BG_LIGHT;
      GFX_PanelBorder   = GFX_PANEL_BORDER_LIGHT;
      GFX_TextPrimary   = GFX_TEXT_PRIMARY_LIGHT;
      GFX_TextSecondary = GFX_TEXT_SECONDARY_LIGHT;
      GFX_ToggleOnBG    = GFX_TOGGLE_ON_BG_CONST;
      GFX_ToggleOffBG   = GFX_TOGGLE_OFF_BG_CONST;
      GFX_NudgeBG       = GFX_BTN_LIGHT_BG_CONST;
      GFX_NudgeText     = GFX_DARK_CONST;
   }
}

void GFX_CreatePanel(const string name,int x,int y,int w,int h,color bg,color border,int z)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,border);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
}

void GFX_Label(const string name,const string text,int x,int y,int fs,color col,int z=5)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
}

void GFX_Button(const string name,const string text,int x,int y,int w,int h,color bg,color fg,int fs,int z=6)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,name,OBJPROP_COLOR,fg);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,z);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
}

string GFX_OnOffText(bool on){ return (on ? "ON" : "OFF"); }
color  GFX_OnOffBG  (bool on){ return (on ? GFX_ToggleOnBG : GFX_ToggleOffBG); }
// Select position by index and set current position context.
// Returns false if index is out of range or selection fails.
bool SelectPositionByIndexSafe(const int index, string &symbol_out)
{
   symbol_out = PositionGetSymbol(index);
   if(symbol_out==NULL || symbol_out=="") return false;
   if(!PositionSelect(symbol_out)) return false;
   return true;
}

int SpreadPoints(){ long sp=0; SymbolInfoInteger(sym,SYMBOL_SPREAD,sp); return (int)sp; }

int GetVolumeDigits()
{
   // Derive volume digits from SYMBOL_VOLUME_STEP to support all brokers
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step<=0) return 2; // sensible default
   int vd = 0; double x = step;
   for(vd=0; vd<8 && MathAbs(x - MathRound(x))>1e-12; ++vd) x *= 10.0;
   return vd;
}

double ValuePerPoint()
{
   double tv=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_VALUE);
   double ts=SymbolInfoDouble(sym,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0.0||_pt<=0.0) return 0.0;
   return tv/(ts/_pt);
}

//--- session/news
bool InSession(datetime t)
{
   if(!UseSessionFilter) return true;
   MqlDateTime mt; TimeToStruct(t,mt);
   if(SessionStartHour<=SessionEndHour)
      return (mt.hour>=SessionStartHour && mt.hour<SessionEndHour);
   return (mt.hour>=SessionStartHour || mt.hour<SessionEndHour);
}

bool InNewsWindow(datetime t)
{
   if(!BlockHighImpactNews) return false;
   int h=FileOpen("news.csv",FILE_READ|FILE_CSV|FILE_ANSI,59); // ';'
   if(h==INVALID_HANDLE) return false;
   bool blocked=false;
   while(!FileIsEnding(h))
   {
      string ts = FileReadString(h);
      string impact = FileReadString(h);
      if(ts=="" || impact=="") continue;
      datetime when=StringToTime(ts);
      if(when==0) continue;
      if( (t<=when && (when-t)<=NewsBlockMinutesBefore*60)
       || (t> when && (t-when)<=NewsBlockMinutesAfter*60) ) { blocked=true; break; }
   }
   FileClose(h);
   return blocked;
}

double InternalSentiment(double rsi, double tsiDiff, double rangeToATR)
{
   double a=(rsi-50.0)/50.0;
   double b=Clamp(tsiDiff/25.0,-1,1);
   double c=Clamp(rangeToATR-1.0,-1,1);
   double s=0.5*a+0.4*b+0.1*c;
   return Clamp(s,-1,1);
}

//======================== Series / Rates Cache ========================//
bool EnsureRates(int need)
{
   int want = MathMax(need, 600);
   ArraySetAsSeries(gRates,true);
   int copied = CopyRates(sym, tf, 0, want, gRates);
   gBars = copied;
   return (copied>=need);
}
inline double OpenAt(int i){ return gRates[i].open; }
inline double HighAt(int i){ return gRates[i].high; }
inline double LowAt (int i){ return gRates[i].low;  }
inline double CloseAt(int i){ return gRates[i].close;}
inline datetime TimeAt(int i){ return gRates[i].time; }

// Detect new bar using local cache
bool NewBar()
{
   if(!EnsureRates(3)) return false;
   if(TimeAt(1)!=lastBarTime){ lastBarTime=TimeAt(1); return true; }
   return false;
}

//========================== Indicator fetchers =========================//
bool GetBuffers(double &emaF, double &emaS, double &smaF, double &smaS, double &rsi, double &atr, int bars=1)
{
   double b1[],b2[],b3[],b4[],b5[],b6[];
   if(CopyBuffer(hEMAfast,0,0,bars,b1)!=bars) return false;
   if(CopyBuffer(hEMAslow,0,0,bars,b2)!=bars) return false;
   if(CopyBuffer(hSMAfast,0,0,bars,b3)!=bars) return false;
   if(CopyBuffer(hSMAslow,0,0,bars,b4)!=bars) return false;
   if(CopyBuffer(hRSI,    0,0,bars,b5)!=bars) return false;
   if(CopyBuffer(hATR,    0,0,bars,b6)!=bars) return false;
   emaF=b1[0]; emaS=b2[0]; smaF=b3[0]; smaS=b4[0]; rsi=b5[0]; atr=b6[0];
   return true;
}

// EMA helper for TSI
void EmaSeries(const double &src[], int count, int period, double &dst[])
{
   if(count<=0){ return; }
   double k=2.0/(period+1.0);
   dst[count-1]=src[count-1];
   for(int i=count-2;i>=0;i--) dst[i]=k*src[i]+(1.0-k)*dst[i+1];
}

//--- TSI (general TF)
bool TSI_Calc_TF(ENUM_TIMEFRAMES tfX, int shift, double &tsi, double &signal, double &diff)
{
   int need = MathMax(MathMax(TSI_Long,TSI_Short),TSI_Signal)*6 + shift + 10;
   double c[]; int got=CopyClose(sym,tfX,0,need,c); if(got<need) return false;
   ArraySetAsSeries(c,true);

   int n = need-1;
   double mom[], amom[]; ArrayResize(mom,n); ArrayResize(amom,n);
   ArraySetAsSeries(mom,true); ArraySetAsSeries(amom,true);
   for(int i=0;i<n;i++){ mom[i]=c[i]-c[i+1]; amom[i]=MathAbs(mom[i]); }

   double eml_mom[], eml_amom[], es_mom[], es_amom[], tsiBuf[], sigBuf[];
   ArrayResize(eml_mom,n); ArrayResize(eml_amom,n);
   ArrayResize(es_mom,n);  ArrayResize(es_amom,n);
   ArrayResize(tsiBuf,n);  ArrayResize(sigBuf,n);
   ArraySetAsSeries(eml_mom,true); ArraySetAsSeries(eml_amom,true);
   ArraySetAsSeries(es_mom,true);  ArraySetAsSeries(es_amom,true);
   ArraySetAsSeries(tsiBuf,true);  ArraySetAsSeries(sigBuf,true);

   EmaSeries(mom, n, TSI_Long,  eml_mom);
   EmaSeries(amom,n, TSI_Long,  eml_amom);
   EmaSeries(eml_mom,n,TSI_Short,es_mom);
   EmaSeries(eml_amom,n,TSI_Short,es_amom);

   for(int i=0;i<n;i++)
      tsiBuf[i] = (es_amom[i]==0.0 ? 0.0 : 100.0*es_mom[i]/es_amom[i]);

   EmaSeries(tsiBuf, n, TSI_Signal, sigBuf);

   int idx = shift;
   tsi    = tsiBuf[idx];
   signal = sigBuf[idx];
   diff   = tsi - signal;
   return true;
}
bool TSI_Calc(int shift, double &tsi, double &signal, double &diff)
{
   return TSI_Calc_TF(tf, shift, tsi, signal, diff);
}

//========================== Structure detection =======================//
bool IsPivotHigh(int i)
{
   for(int k=1;k<=SwingLookback;k++)
      if(HighAt(i+k)>=HighAt(i) || HighAt(i-k)>=HighAt(i)) return false;
   return true;
}
bool IsPivotLow(int i)
{
   for(int k=1;k<=SwingLookback;k++)
      if(LowAt(i+k)<=LowAt(i) || LowAt(i-k)<=LowAt(i)) return false;
   return true;
}

int BiasFrom(double emaF,double emaS,double rsi, double tsiDiff)
{
   if(emaF>emaS && rsi>=RSI_LongMin && tsiDiff>0)  return +1;
   if(emaF<emaS && rsi<=RSI_ShortMax && tsiDiff<0) return -1;
   return 0;
}

int ComputeCompositeMTFBias()
{
   if(!g_UseMTFContext) return 0;
   int votes=0;
   ENUM_TIMEFRAMES arr[4]={HTF1,HTF2,HTF3,HTF4};
   for(int i=0;i<4;i++)
   {
      double eF[], eS[], r[];
      double t_tsi, t_sig, t_diff=0.0;
      if(CopyBuffer(hEMAfast_HTF[i],0,0,1,eF)!=1) continue;
      if(CopyBuffer(hEMAslow_HTF[i],0,0,1,eS)!=1) continue;
      if(CopyBuffer(hRSI_HTF[i],    0,0,1,r)!=1)  continue;
      if(!TSI_Calc_TF(arr[i],1,t_tsi,t_sig,t_diff)) t_diff=0.0;
      votes += BiasFrom(eF[0],eS[0],r[0],t_diff);
   }
   if(votes>=+2) return +1;
   if(votes<=-2) return -1;
   return 0;
}

bool GetHTFExtremes(ENUM_TIMEFRAMES tfX, int lookback, double &hh, double &ll)
{
   double highs[], lows[];
   int ch = CopyHigh(sym, tfX, 0, lookback, highs);
   int cl = CopyLow (sym, tfX, 0, lookback, lows);
   if(ch<=0 || cl<=0) return false;
   ArraySetAsSeries(highs,true);
   ArraySetAsSeries(lows ,true);
   int ih = ArrayMaximum(highs,0,MathMin(lookback,ch));
   int il = ArrayMinimum(lows ,0,MathMin(lookback,cl));
   hh = highs[ih];
   ll = lows[il];
   return true;
}

void UpdateSwingsAndTrend()
{
   // make sure we have enough bars
   int need = MathMax(500, SwingLookback*10 + 50);
   if(!EnsureRates(need)) return;

   int limit = MathMin(500, gBars-SwingLookback-2);
   int lastHigh=-1, lastLow=-1; double ph=0, pl=0;

   for(int i=SwingLookback+StructureConfirmBars; i<limit; i++)
   {
      if(lastHigh<0 && IsPivotHigh(i)) { lastHigh=i; ph=HighAt(i); }
      if(lastLow<0  && IsPivotLow(i))  { lastLow =i; pl=LowAt(i);  }
      if(lastHigh>0 && lastLow>0) break;
   }
   swings.idxHigh=lastHigh; swings.priceHigh=ph;
   swings.idxLow =lastLow;  swings.priceLow =pl;

   double emaF,emaS,smaF,smaS,rsi,atr;
   if(!GetBuffers(emaF,emaS,smaF,smaS,rsi,atr)) return;

   TrendBias emaBias = (emaF>emaS?BULL:(emaF<emaS?BEAR:NEUTRAL));
   trendBias = emaBias;

   // BOS detection: prior candle closes beyond last pivots
   bosUp   = (swings.idxHigh>0 && CloseAt(1) > swings.priceHigh);
   bosDown = (swings.idxLow >0 && CloseAt(1) < swings.priceLow);

   int mtf = ComputeCompositeMTFBias();
   if(mtf==+1)      trendBias = BULL;
   else if(mtf==-1) trendBias = BEAR;
}

//=========================== Candle patterns ===========================//
bool IsBullishReversal(int i=1)
{
   double body = CloseAt(i)-OpenAt(i);
   double range= HighAt(i)-LowAt(i);
   if(range<=0) return false;
   double upper = HighAt(i)-MathMax(CloseAt(i),OpenAt(i));
   double lower = MathMin(CloseAt(i),OpenAt(i))-LowAt(i);
   bool bullishBody   = (body>0 && body/range>=0.4);
   bool longLowerWick = (lower/range>=0.4) && (upper/range<=0.4);
   bool engulf        = (CloseAt(i)>OpenAt(i) && CloseAt(i)>=OpenAt(i+1) && OpenAt(i)<=CloseAt(i+1));
   return (bullishBody || longLowerWick || engulf);
}
bool IsBearishReversal(int i=1)
{
   double body = OpenAt(i)-CloseAt(i);
   double range= HighAt(i)-LowAt(i);
   if(range<=0) return false;
   double upper = HighAt(i)-MathMax(CloseAt(i),OpenAt(i));
   double lower = MathMin(CloseAt(i),OpenAt(i))-LowAt(i);
   bool bearishBody   = (body>0 && body/range>=0.4);
   bool longUpperWick = (upper/range>=0.4) && (lower/range<=0.4);
   bool engulf        = (CloseAt(i)<OpenAt(i) && CloseAt(i)<=OpenAt(i+1) && OpenAt(i)>=CloseAt(i+1));
   return (bearishBody || longUpperWick || engulf);
}

//============================ Features (AI) ============================//
void BuildFeatures(double &x[])
{
   ArrayInitialize(x,0.0);
   if(!EnsureRates(3)) return;

   double emaF,emaS,smaF,smaS,rsi,atr;
   if(!GetBuffers(emaF,emaS,smaF,smaS,rsi,atr)) return;

   double tsi,tsis,tsid; if(!TSI_Calc(0,tsi,tsis,tsid)){ tsi=0; tsis=0; tsid=0; }

   double emaSlope=0.0, smaSlope=0.0;
   { double t1[],t2[]; if(CopyBuffer(hEMAfast,0,1,2,t1)==2) emaSlope=t1[1]-t1[0]; }
   { double t1[],t2[]; if(CopyBuffer(hSMAfast,0,1,2,t2)==2) smaSlope=t2[1]-t2[0]; }

   double range = HighAt(1)-LowAt(1);
   double body  = MathAbs(CloseAt(1)-OpenAt(1));
   double atrv  = atr;
   double rangeToATR = (atrv>0? range/atrv : 0.0);
   double spreadP = (double)SpreadPoints();

   double isBOSUp = (bosUp?1.0:0.0);
   double isBOSDn = (bosDown?1.0:0.0);
   double tBias   = (trendBias==BULL?1.0 : trendBias==BEAR?-1.0:0.0);

   bool sessionOK = InSession(TimeCurrent());
   bool newsBlk   = InNewsWindow(TimeCurrent());
   double senti   = (g_SentimentSource==SENTIMENT_INTERNAL? InternalSentiment(rsi,tsid,rangeToATR):0.0);

   x[0]=(emaF-emaS)/(_pt*100.0);
   x[1]=(smaF-smaS)/(_pt*100.0);
   x[2]=emaSlope/(_pt*10.0);
   x[3]=smaSlope/(_pt*10.0);
   x[4]=(rsi-50.0)/50.0;
   x[5]=Clamp(tsi/50.0,-2,2);
   x[6]=Clamp(tsid/25.0,-2,2);
   x[7]=Clamp(body/(atrv+1e-9),-2,2);
   x[8]=Clamp(rangeToATR,-2,2);
   x[9]=tBias;
   x[10]=isBOSUp;
   x[11]=isBOSDn;
   x[12]=Clamp(spreadP/g_MaxSpreadPoints,0,2);
   x[13]=(sessionOK?1.0:0.0);
   x[14]=(newsBlk?1.0:0.0);
   x[15]=senti;
}

//============================ Prediction LR ===========================//
double Dot(const double &w[], const double &x[]){ double s=0; for(int i=0;i<FEAT_COUNT;i++) s+=w[i]*x[i]; return s; }
void LR_Predict(const double &x[], double &p1,double &p2,double &p3){ p1=Sigmoid(Dot(w1,x)); p2=Sigmoid(Dot(w2,x)); p3=Sigmoid(Dot(w3,x)); }
void LR_Update (double &w[], const double &x[], double target){ double pred=Sigmoid(Dot(w,x)); double err=target-pred; for(int i=0;i<FEAT_COUNT;i++) w[i]+=lr*err*x[i]; }

// Simple prediction function for HUD
double PredictUpProb()
{
   double x[FEAT_COUNT]; BuildFeatures(x);
   double p1,p2,p3; LR_Predict(x,p1,p2,p3);
   return p1; // return +1 prediction
}

// Console logging functions
void LogTradeEntry(string side, double lots, double entry, double sl, double tp, double p1, double p2, double p3)
{
   Print("=== TRADE ENTRY ===");
   Print("Side: ", side);
   Print("Lots: ", DoubleToString(lots, 2));
   Print("Entry: ", DoubleToString(entry, SymDigits));
   Print("Stop Loss: ", DoubleToString(sl, SymDigits));
   Print("Take Profit: ", DoubleToString(tp, SymDigits));
   Print("Predictions: p1=", DoubleToString(p1, 3), " p2=", DoubleToString(p2, 3), " p3=", DoubleToString(p3, 3));
   Print("Risk Points: ", DoubleToString(MathAbs(entry-sl)/_pt, 1));
   Print("Reward Points: ", DoubleToString(MathAbs(tp-entry)/_pt, 1));
   Print("Risk/Reward: ", DoubleToString(MathAbs(tp-entry)/MathAbs(entry-sl), 2));
   Print("==================");
}

void LogTradeExit(string side, ulong ticket, double exit, double pnl, string reason)
{
   Print("=== TRADE EXIT ===");
   Print("Side: ", side);
   Print("Ticket: ", ticket);
   Print("Exit: ", DoubleToString(exit, SymDigits));
   Print("PnL: ", DoubleToString(pnl, 2));
   Print("Reason: ", reason);
   Print("=================");
}

void LogPredictionUpdate(double p1, double p2, double p3, double atr)
{
   if(g_LogPredictions)
   {
      Print("Prediction Update - p1:", DoubleToString(p1, 3), " p2:", DoubleToString(p2, 3), " p3:", DoubleToString(p3, 3), " ATR:", DoubleToString(atr, SymDigits));
   }
}

void LogEntryConditions(bool longBias, bool shortBias, bool pattLong, bool pattShort, bool oscLong, bool oscShort, bool predLong, bool predShort, bool allowLong, bool allowShort)
{
   Print("=== ENTRY CONDITIONS ===");
   Print("Long Bias: ", longBias, " Short Bias: ", shortBias);
   Print("Pattern Long: ", pattLong, " Pattern Short: ", pattShort);
   Print("Osc Long: ", oscLong, " Osc Short: ", oscShort);
   Print("Pred Long: ", predLong, " Pred Short: ", predShort);
   Print("Allow Long: ", allowLong, " Allow Short: ", allowShort);
   Print("========================");
}

void OnlineScoreAndLearn()
{
   int idx = (writePos-1+BUF)%BUF;
   if(barCount>=1)
   {
      int i0=(idx-1+BUF)%BUF;
      double target = (closeBuf[(idx-0+BUF)%BUF] - closeBuf[i0])>0 ? 1.0:0.0;
      double xrow1[FEAT_COUNT];
      for(int j=0;j<FEAT_COUNT;j++) xrow1[j]=featBuf[i0][j];
      double p=Sigmoid(Dot(w1,xrow1));
      if((p>=0.5 && target>=0.5) || (p<0.5 && target<0.5)) hits1++;
      total1++;
      if(ResearchMode || LearnInLive) LR_Update(w1,xrow1,target);
   }
   if(barCount>=2)
   {
      int i0=(idx-2+BUF)%BUF;
      double target = (closeBuf[(idx-0+BUF)%BUF] - closeBuf[i0])>0 ? 1.0:0.0;
      double xrow2[FEAT_COUNT];
      for(int j=0;j<FEAT_COUNT;j++) xrow2[j]=featBuf[i0][j];
      double p=Sigmoid(Dot(w2,xrow2));
      if((p>=0.5 && target>=0.5) || (p<0.5 && target<0.5)) hits2++;
      total2++;
      if(ResearchMode || LearnInLive) LR_Update(w2,xrow2,target);
   }
   if(barCount>=3)
   {
      int i0=(idx-3+BUF)%BUF;
      double target = (closeBuf[(idx-0+BUF)%BUF] - closeBuf[i0])>0 ? 1.0:0.0;
      double xrow3[FEAT_COUNT];
      for(int j=0;j<FEAT_COUNT;j++) xrow3[j]=featBuf[i0][j];
      double p=Sigmoid(Dot(w3,xrow3));
      if((p>=0.5 && target>=0.5) || (p<0.5 && target<0.5)) hits3++;
      total3++;
      if(ResearchMode || LearnInLive) LR_Update(w3,xrow3,target);
   }
}

//=============================== Files =================================//
void AppendPredictionsCSV(datetime t, double p1,double p2,double p3, double rsi, double tsi, double tsid, double atr, double spread)
{
   if(!g_LogPredictions) return;
   int h=FileOpen(fPred, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, 44); // ','
   if(h!=INVALID_HANDLE)
   {
      FileSeek(h,0,SEEK_END);
      string ts = TimeToString(t, TIME_DATE|TIME_MINUTES|TIME_SECONDS);
      FileWrite(h, ts, DoubleToString(p1,4), DoubleToString(p2,4), DoubleToString(p3,4),
                   DoubleToString(rsi,2), DoubleToString(tsi,2), DoubleToString(tsid,2),
                   DoubleToString(atr,5), DoubleToString(spread,1));
      FileClose(h);
   }
}
void AppendTradeCSV(const string &side, ulong ticket, double price, double sl, double tp, double lots)
{
   int h=FileOpen(fTrades, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, 44); // ','
   if(h!=INVALID_HANDLE)
   {
      FileSeek(h,0,SEEK_END);
      string ts = TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
      FileWrite(h, ts, side, (long)ticket, DoubleToString(price,SymDigits), DoubleToString(sl,SymDigits),
                   DoubleToString(tp,SymDigits), DoubleToString(lots,2));
      FileClose(h);
   }
}
void WriteMetrics()
{
   int h=FileOpen(fMetrics, FILE_WRITE|FILE_CSV|FILE_ANSI, 44); // ','
   if(h!=INVALID_HANDLE)
   {
      FileWrite(h,"metric","hits","total","accuracy");
      double acc1 = (total1>0? (double)hits1/total1 : 0.0);
      double acc2 = (total2>0? (double)hits2/total2 : 0.0);
      double acc3 = (total3>0? (double)hits3/total3 : 0.0);
      FileWrite(h,"h1",hits1,total1,DoubleToString(acc1,4));
      FileWrite(h,"h2",hits2,total2,DoubleToString(acc2,4));
      FileWrite(h,"h3",hits3,total3,DoubleToString(acc3,4));
      FileClose(h);
   }
}
void WritePayloadJSON()
{
   if(!g_ExportPayload) return;
   int n = MathMin(PayloadBars, barCount);
   int h=FileOpen(fPayload, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   FileWriteString(h,"{\n");
   FileWriteString(h,"  \"meta\": {\"symbol\":\""+sym+"\",\"timeframe\":\""+IntegerToString((int)tf)+"\",\"timestamp_utc\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES|TIME_SECONDS)+"\",\"point\":"+DoubleToString(_pt,10)+",\"digits\":"+IntegerToString(SymDigits)+",\"window\":"+IntegerToString(n)+"},\n");
   FileWriteString(h,"  \"features\": [\n");
   for(int k=0;k<n;k++)
   {
      int idx=(writePos-1-k+BUF)%BUF;
      string line="    {\"time\":\""+TimeToString(timeBuf[idx],TIME_DATE|TIME_MINUTES|TIME_SECONDS)+"\",\"close\":"+DoubleToString(closeBuf[idx],SymDigits);
      for(int j=0;j<FEAT_COUNT;j++)
         line += ",\"x"+IntegerToString(j)+"\":"+DoubleToString(featBuf[idx][j],6);
      line += "}";
      if(k<n-1) line+=",";
      FileWriteString(h,line+"\n");
   }
   FileWriteString(h,"  ]\n}\n");
   FileClose(h);
}

void WriteHUDStatusJSON(double p1,double p2,double p3)
{
   int h=FileOpen(fHUDStatus, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return;
   string ts = TimeToString(TimeAt(1), TIME_DATE|TIME_MINUTES|TIME_SECONDS);
   string side = g_NextPlanSide;
   string json = "{\n"+
      "  \"symbol\": \""+sym+"\",\n"+
      "  \"timeframe\": \""+IntegerToString((int)tf)+"\",\n"+
      "  \"time\": \""+ts+"\",\n"+
      "  \"pred\": {\"p1\":"+DoubleToString(p1,4)+",\"p2\":"+DoubleToString(p2,4)+",\"p3\":"+DoubleToString(p3,4)+"},\n"+
      "  \"next\": {\"side\":\""+side+"\",\"lots\":"+DoubleToString(g_NextPlanLots,2)+",\"entry\":"+DoubleToString(g_NextPlanEntry,SymDigits)+",\"lev\":"+DoubleToString(g_NextPlanLev,2)+",\"est_px\":"+DoubleToString(g_NextPlanEstPx,SymDigits)+"}\n"+
      "}\n";
   FileWriteString(h,json);
   FileClose(h);
}

//============================ Risk / Trades ===========================//
int CountOpenByMagic(int dirFilter=0)
{
   int cnt=0;
   int total=PositionsTotal();
   for(int idx=0; idx<total; idx++)
   {
      string ps;
      if(!SelectPositionByIndexSafe(idx, ps)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(dirFilter>0 && type!=POSITION_TYPE_BUY) continue;
      if(dirFilter<0 && type!=POSITION_TYPE_SELL) continue;
      cnt++;
   }
   return cnt;
}
bool HasOppositePosition(int dir)
{
   int total=PositionsTotal();
   for(int idx=0; idx<total; idx++)
   {
      string ps;
      if(!SelectPositionByIndexSafe(idx, ps)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;
      long type=PositionGetInteger(POSITION_TYPE);
      if(dir>0 && type==POSITION_TYPE_SELL) return true;
      if(dir<0 && type==POSITION_TYPE_BUY)  return true;
   }
   return false;
}
double CalcLots(double sl_price, double entry_price)
{
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * (g_RiskPerTradePct/100.0);
   double vpp  = ValuePerPoint(); if(vpp<=0) return 0;
   double sl_points = MathAbs(entry_price - sl_price)/_pt;
   if(sl_points<=0) return 0;
   double lotsRaw = risk / (sl_points * vpp);
   // normalize
   double minv=SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN);
   double maxv=SymbolInfoDouble(sym,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(sym,SYMBOL_VOLUME_STEP);
   int vd = GetVolumeDigits();
   lotsRaw=Clamp(lotsRaw,minv,maxv);
   if(step>0) lotsRaw = MathFloor(lotsRaw/step)*step;
   return NormalizeDouble(lotsRaw,vd);
}

// precise SL/TP modify by ticket
bool ModifyPositionByTicket(ulong position_ticket, double newSL, double newTP)
{
   if(!PositionSelectByTicket(position_ticket)) return false;
   MqlTradeRequest req; ZeroMemory(req);
   MqlTradeResult  res; ZeroMemory(res);
   req.action   = TRADE_ACTION_SLTP;
   req.symbol   = PositionGetString(POSITION_SYMBOL);
   req.position = position_ticket;
   req.sl       = (newSL>0? NormalizeDouble(newSL, SymDigits):0.0);
   req.tp       = (newTP>0? NormalizeDouble(newTP, SymDigits):0.0);
   req.deviation= SlippagePoints;
   if(!OrderSend(req,res)) { if(VerboseLogs) Print("Modify SLTP failed: ",res.retcode); return false; }
   return (res.retcode==TRADE_RETCODE_DONE || res.retcode==TRADE_RETCODE_PLACED);
}

//=========================== Trade management =========================//
void ManagePositions()
{
   int total=PositionsTotal();
   for(int idx=0; idx<total; idx++)
   {
      string ps;
      if(!SelectPositionByIndexSafe(idx, ps)) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=sym) continue;

      ulong  ticket= (ulong)PositionGetInteger(POSITION_TICKET);
      long   type  = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double price = (type==POSITION_TYPE_BUY? SymbolInfoDouble(sym,SYMBOL_BID) : SymbolInfoDouble(sym,SYMBOL_ASK));

      double riskPts = (type==POSITION_TYPE_BUY? entry - sl : sl - entry)/_pt;
      if(riskPts<=0) continue;
      double plPts   = (type==POSITION_TYPE_BUY? price - entry : entry - price)/_pt;
      double R       = plPts / riskPts;

      if(MoveToBE_At1R && R>=1.0)
      {
         double newSL = entry;
         if(type==POSITION_TYPE_BUY && newSL>sl) ModifyPositionByTicket(ticket,newSL,tp);
         if(type==POSITION_TYPE_SELL && newSL<sl) ModifyPositionByTicket(ticket,newSL,tp);
      }

      if(g_UsePartialTP && R>=g_PartialTP_R && vol>SymbolInfoDouble(sym,SYMBOL_VOLUME_MIN))
      {
         double closeVol = CalcLots(entry, entry); // re-use normalizer; will be clamped below
         int vd2 = GetVolumeDigits();
         closeVol = NormalizeDouble(vol*(g_PartialClosePct/100.0), vd2);
         if(closeVol>0 && closeVol<vol-1e-8)
         {
            // CTrade::PositionClosePartial(ticket, volume) – preferred signature
            Trade.PositionClosePartial(ticket, closeVol);
         }
      }

      if(UseTrailing)
      {
         double emaF,emaS,smaF,smaS,rsi,atr;
         if(!GetBuffers(emaF,emaS,smaF,smaS,rsi,atr)) atr=_pt*100;
         double trail = atr*g_TrailATR_Mult;
         if(type==POSITION_TYPE_BUY)
         {
            double newSL = MathMax(sl, price - trail);
            if(newSL>sl) ModifyPositionByTicket(ticket, NormalizeDouble(newSL,SymDigits), tp);
         }
         else
         {
            double newSL = MathMin(sl, price + trail);
            if(newSL<sl) ModifyPositionByTicket(ticket, NormalizeDouble(newSL,SymDigits), tp);
         }
      }
   }
}

//============================= Entries =================================//
void TryEntries(double p1,double p2,double p3)
{
   if(!g_Enabled) return; // START/STOP master gate
   
   // Spread + microstructure + rollover
   if(SpreadPoints()>g_MaxSpreadPoints_Runtime) return;

   MqlDateTime mt; TimeToStruct(TimeCurrent(), mt);
   if(mt.min<5 || mt.min>=55) return; // first/last 5 minutes of hour
   if((mt.hour==23 && mt.min>=45) || (mt.hour==0 && mt.min<=15)) return; // midnight roll

   // Session & news
   if(UseSessionFilter && !(mt.hour>=SessionStartHour && mt.hour<SessionEndHour)) return;
   if(BlockHighImpactNews && InNewsWindow(TimeCurrent())) return;
   
   if(!EnsureRates(3)) return;

   double emaF,emaS,smaF,smaS,rsi,atr;
   if(!GetBuffers(emaF,emaS,smaF,smaS,rsi,atr)) return;
   double tsi,tsis,tsid; if(!TSI_Calc(1,tsi,tsis,tsid)){ tsi=0; tsid=0; }

   bool longBias  = (emaF>emaS && trendBias!=BEAR);
   bool shortBias = (emaF<emaS && trendBias!=BULL);

   bool pattLong  = IsBullishReversal(1);
   bool pattShort = IsBearishReversal(1);

   bool oscLong   = (rsi>=RSI_LongMin && tsid>=TSI_MinDiff);
   bool oscShort  = (rsi<=RSI_ShortMax && tsid<=-TSI_MinDiff);

   bool bosOkLong  = (!RequireBOS || bosUp);
   bool bosOkShort = (!RequireBOS || bosDown);

   bool predLong  = (p1>=g_PredictThreshold || p2>=g_PredictThreshold || p3>=g_PredictThreshold);
   bool predShort = (p1<=1.0-g_PredictThreshold || p2<=1.0-g_PredictThreshold || p3<=1.0-g_PredictThreshold);

   bool allowLong  = longBias && pattLong  && oscLong  && bosOkLong  && (!g_UsePredictionsForEntries || predLong);
   bool allowShort = shortBias&& pattShort && oscShort && bosOkShort && (!g_UsePredictionsForEntries || predShort);

   // Log entry conditions for debugging
   LogEntryConditions(longBias, shortBias, pattLong, pattShort, oscLong, oscShort, predLong, predShort, allowLong, allowShort);

   // HTF S/R proximity
   bool nearRes=false, nearSup=false;
   double hh=0.0, ll=0.0;
   ENUM_TIMEFRAMES tfRef = HTF2; // M15
   if(g_UseMTFContext && GetHTFExtremes(tfRef, HTF_ExtremeLookback, hh, ll))
   {
      double thr = atr * ExtremeProximityATR;
      nearRes = (hh - CloseAt(1)) <= thr;
      nearSup = (CloseAt(1) - ll) <= thr;
   }

   if(!AllowHedge)
   {
      if(HasOppositePosition(+1)) allowLong=false;
      if(HasOppositePosition(-1)) allowShort=false;
   }
   if(CountOpenByMagic(0)>=MaxOpenPositions) { allowLong=false; allowShort=false; }

   if(nearRes && !bosUp)   allowLong  = false;
   if(nearSup && !bosDown) allowShort = false;

   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);

   // ---------- Update next-plan state for HUD (no orders yet) ----------
   g_NextPlanSide = "FLAT"; g_NextPlanLots=0.0; g_NextPlanLev=0.0; g_NextPlanEstPx=0.0; g_NextPlanEntry=0.0;
   double contract = SymbolInfoDouble(sym,SYMBOL_TRADE_CONTRACT_SIZE);
   int    dec = SymDigits;
   if(allowLong || allowShort)
   {
      // Resolve direction if both allowed using higher confidence
      double buyScore  = MathMax(MathMax(p1,p2),p3);
      double sellScore = MathMax(MathMax(1.0-p1,1.0-p2),1.0-p3);
      bool chooseLong = (allowLong && (!allowShort || buyScore>=sellScore));
      if(chooseLong)
      {
         double sl = (swings.idxLow>0? LowAt(swings.idxLow) : bid - atr*g_ATR_SL_Mult);
         double lots = CalcLots(sl, ask);
         if(lots>0)
         {
            g_NextPlanSide = "BUY"; g_NextPlanLots=lots; g_NextPlanEntry=NormalizeDouble(ask,dec);
            double pos_value = lots*contract*ask;
            double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY),1.0);
            g_NextPlanLev = pos_value/eq;
            double netProb = ((p1-0.5)+(p2-0.5)+(p3-0.5))/3.0; // [-0.5,0.5]
            g_NextPlanEstPx = NormalizeDouble(ask + netProb*atr*HUD_HorizonBars, dec);
         }
      }
      else if(allowShort)
      {
         double sl = (swings.idxHigh>0? HighAt(swings.idxHigh) : ask + atr*g_ATR_SL_Mult);
         double lots = CalcLots(sl, bid);
         if(lots>0)
         {
            g_NextPlanSide = "SELL"; g_NextPlanLots=lots; g_NextPlanEntry=NormalizeDouble(bid,dec);
            double pos_value = lots*contract*bid;
            double eq = MathMax(AccountInfoDouble(ACCOUNT_EQUITY),1.0);
            g_NextPlanLev = pos_value/eq;
            double netProb = ((p1-0.5)+(p2-0.5)+(p3-0.5))/3.0;
            g_NextPlanEstPx = NormalizeDouble(bid - netProb*atr*HUD_HorizonBars, dec);
         }
      }
   }

   if(allowLong)
   {
      double sl = (swings.idxLow>0? LowAt(swings.idxLow) : bid - atr*g_ATR_SL_Mult);
      double lots = CalcLots(sl, ask);
      if(lots>0)
      {
         double riskPts = (ask - sl)/_pt;
         double tp = ask + riskPts*g_TP_R_Multiple*_pt;
         Trade.SetExpertMagicNumber(MagicNumber);
         Trade.SetDeviationInPoints(SlippagePoints);
         if(Trade.Buy(lots, sym, 0.0, NormalizeDouble(sl,SymDigits), NormalizeDouble(tp,SymDigits)))
         {
            // get last deal id
            ulong ticket = (ulong)Trade.ResultDeal();
            AppendTradeCSV("BUY", ticket, ask, sl, tp, lots);
            
            // Log trade entry
            LogTradeEntry("BUY", lots, ask, sl, tp, p1, p2, p3);
            
            // annotate entry + expected
            datetime t0 = TimeCurrent();
            string nE = "GFX_ENT_"+IntegerToString((int)ticket);
            ObjectCreate(0,nE,OBJ_ARROW,0,t0,ask);
            ObjectSetInteger(0,nE,OBJPROP_COLOR,clrLime);
            ObjectSetInteger(0,nE,OBJPROP_ARROWCODE,233);
            // Expected path line
            if(g_NextPlanEstPx>0)
            {
               string nX = "GFX_EXP_"+IntegerToString((int)ticket);
               ObjectCreate(0,nX,OBJ_TREND,0,t0,ask, t0+PeriodSeconds(tf)*HUD_HorizonBars, g_NextPlanEstPx);
               ObjectSetInteger(0,nX,OBJPROP_COLOR,clrAqua);
               ObjectSetInteger(0,nX,OBJPROP_STYLE,STYLE_DOT);
            }
         }
      }
   }

   if(allowShort)
   {
      double sl = (swings.idxHigh>0? HighAt(swings.idxHigh) : ask + atr*g_ATR_SL_Mult);
      double lots = CalcLots(sl, bid);
      if(lots>0)
      {
         double riskPts = (sl - bid)/_pt;
         double tp = bid - riskPts*g_TP_R_Multiple*_pt;
         Trade.SetExpertMagicNumber(MagicNumber);
         Trade.SetDeviationInPoints(SlippagePoints);
         if(Trade.Sell(lots, sym, 0.0, NormalizeDouble(sl,SymDigits), NormalizeDouble(tp,SymDigits)))
         {
            ulong ticket = (ulong)Trade.ResultDeal();
            AppendTradeCSV("SELL", ticket, bid, sl, tp, lots);
            
            // Log trade entry
            LogTradeEntry("SELL", lots, bid, sl, tp, p1, p2, p3);
            
            datetime t0 = TimeCurrent();
            string nE = "GFX_ENT_"+IntegerToString((int)ticket);
            ObjectCreate(0,nE,OBJ_ARROW,0,t0,bid);
            ObjectSetInteger(0,nE,OBJPROP_COLOR,clrTomato);
            ObjectSetInteger(0,nE,OBJPROP_ARROWCODE,234);
            if(g_NextPlanEstPx>0)
            {
               string nX = "GFX_EXP_"+IntegerToString((int)ticket);
               ObjectCreate(0,nX,OBJ_TREND,0,t0,bid, t0+PeriodSeconds(tf)*HUD_HorizonBars, g_NextPlanEstPx);
               ObjectSetInteger(0,nX,OBJPROP_COLOR,clrAqua);
               ObjectSetInteger(0,nX,OBJPROP_STYLE,STYLE_DOT);
            }
         }
      }
   }
}

//=========================== HTF S/R Lines =============================//
void DrawHTFLevels()
{
   struct TFLineSpec { ENUM_TIMEFRAMES tfX; color col; string tag; };
   TFLineSpec specs[4] = {
      {HTF1, clrAliceBlue,  "M5"},
      {HTF2, clrTurquoise,  "M15"},
      {HTF3, clrKhaki,      "M30"},
      {HTF4, clrOrchid,     "H1"}
   };
   for(int i=0;i<4;i++)
   {
      double hh=0.0,ll=0.0;
      if(!GetHTFExtremes(specs[i].tfX, HTF_ExtremeLookback, hh, ll)) continue;
      string nH = "GFX_HH_"+specs[i].tag;
      string nL = "GFX_LL_"+specs[i].tag;
      if(ObjectFind(0,nH)<0) ObjectCreate(0,nH,OBJ_HLINE,0,0,0);
      if(ObjectFind(0,nL)<0) ObjectCreate(0,nL,OBJ_HLINE,0,0,0);
      ObjectSetDouble (0,nH,OBJPROP_PRICE,hh);
      ObjectSetDouble (0,nL,OBJPROP_PRICE,ll);
      ObjectSetInteger(0,nH,OBJPROP_COLOR,specs[i].col);
      ObjectSetInteger(0,nL,OBJPROP_COLOR,specs[i].col);
      ObjectSetInteger(0,nH,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nL,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nH,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nL,OBJPROP_WIDTH,1);
   }
}

//=========================== Dashboard & GUI ===========================//
void DrawDashboard(double p1,double p2,double p3)
{
   if(!ShowDashboard) return;

   if(g_UseCompactHUD)
   {
      // Ensure theme colors are initialized
      GFX_GetThemeColors();
      // Small opaque background
      int x=HUD_XOffset, y=HUD_YOffset, w=240, h=64;
      // Fully opaque panel colors for readability
      color bg = (GFX_Dark? ARGBc(200,30,30,30) : ARGBc(200,245,245,245));
      int z = (g_HUD_OnTop? 100 : 8);
      if(ObjectFind(0,GFX_HUD_BG)<0) ObjectCreate(0,GFX_HUD_BG,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_CORNER,HUD_Corner);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_XSIZE,w);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_YSIZE,h);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_ZORDER,z);
      ObjectSetInteger(0,GFX_HUD_BG,OBJPROP_BACK,true);

      if(ObjectFind(0,GFX_HUD_TEXT)<0) ObjectCreate(0,GFX_HUD_TEXT,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,GFX_HUD_TEXT,OBJPROP_CORNER,HUD_Corner);
      ObjectSetInteger(0,GFX_HUD_TEXT,OBJPROP_XDISTANCE,x+8);
      ObjectSetInteger(0,GFX_HUD_TEXT,OBJPROP_YDISTANCE,y+6);
      ObjectSetInteger(0,GFX_HUD_TEXT,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(0,GFX_HUD_TEXT,OBJPROP_COLOR,(GFX_Dark? GFX_TEXT_PRIMARY_DARK : GFX_TEXT_PRIMARY_LIGHT));
      ObjectSetString (0,GFX_HUD_TEXT,OBJPROP_FONT,"Arial");

      string line1 = (g_TradingEnabled?"TRADING: ON":"TRADING: OFF")+"  "+sym+"  TF:"+IntegerToString((int)tf);
      string line2 = "Pred: "+DoubleToString(p1,2)+","+DoubleToString(p2,2)+","+DoubleToString(p3,2)+
                      "  Next: "+g_NextPlanSide+" "+(g_NextPlanLots>0? DoubleToString(g_NextPlanLots,2):"0");
      ObjectSetString(0,GFX_HUD_TEXT,OBJPROP_TEXT,line1+"\n"+line2);

      // Runtime HUD controls: HUD button toggles panel, TOP toggles on-top
      int btnW=46, btnH=16, padding=4;
      int bx, by;
      bool left  = (HUD_Corner==CORNER_LEFT_UPPER || HUD_Corner==CORNER_LEFT_LOWER);
      bool upper = (HUD_Corner==CORNER_LEFT_UPPER || HUD_Corner==CORNER_RIGHT_UPPER);
      if(left)   bx = x + w - (btnW*3 + padding*4); else bx = x + padding;
      if(upper)  by = y + h - (btnH + padding);     else by = y + padding;
      // HUD toggle
      if(ObjectFind(0,GFX_BTN_HUD_TOGGLE)<0) ObjectCreate(0,GFX_BTN_HUD_TOGGLE,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_CORNER,HUD_Corner);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_XDISTANCE,bx);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_YDISTANCE,by);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_XSIZE,btnW);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_YSIZE,btnH);
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_BGCOLOR,(GFX_Dark? GFX_BTN_DARK_BG_CONST : GFX_BTN_LIGHT_BG_CONST));
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_COLOR,(GFX_Dark? GFX_WHITE_CONST : GFX_DARK_CONST));
      ObjectSetInteger(0,GFX_BTN_HUD_TOGGLE,OBJPROP_FONTSIZE,8);
      ObjectSetString (0,GFX_BTN_HUD_TOGGLE,OBJPROP_TEXT,(g_ShowControlPanel?"Panel-":"Panel+"));

      // Start/Stop trading toggle
      if(ObjectFind(0,GFX_BTN_TRD_TOGGLE)<0) ObjectCreate(0,GFX_BTN_TRD_TOGGLE,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_CORNER,HUD_Corner);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_XDISTANCE,bx+btnW+padding);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_YDISTANCE,by);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_XSIZE,btnW);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_YSIZE,btnH);
      color trdBg = (g_TradingEnabled? GFX_TOGGLE_ON_BG_CONST : GFX_TOGGLE_OFF_BG_CONST);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_BGCOLOR,trdBg);
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_COLOR,(GFX_Dark? GFX_WHITE_CONST : GFX_DARK_CONST));
      ObjectSetInteger(0,GFX_BTN_TRD_TOGGLE,OBJPROP_FONTSIZE,8);
      ObjectSetString (0,GFX_BTN_TRD_TOGGLE,OBJPROP_TEXT,(g_TradingEnabled?"STOP":"START"));

      // TOP toggle (checkbox style)
      if(ObjectFind(0,GFX_BTN_TOP_TOGGLE)<0) ObjectCreate(0,GFX_BTN_TOP_TOGGLE,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_CORNER,HUD_Corner);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_XDISTANCE,bx+btnW*2+padding*2);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_YDISTANCE,by);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_XSIZE,btnW);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_YSIZE,btnH);
      color topBg = (g_HUD_OnTop? GFX_TOGGLE_ON_BG_CONST : GFX_TOGGLE_OFF_BG_CONST);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_BGCOLOR,topBg);
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_COLOR,(GFX_Dark? GFX_WHITE_CONST : GFX_DARK_CONST));
      ObjectSetInteger(0,GFX_BTN_TOP_TOGGLE,OBJPROP_FONTSIZE,8);
      ObjectSetString (0,GFX_BTN_TOP_TOGGLE,OBJPROP_TEXT,(g_HUD_OnTop?"TOP✓":"TOP"));
      return;
   }

   // Legacy, more verbose dashboard
   string name="GagaFX_DASH";
   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,8);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,8);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
      ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   }
   string bias = (trendBias==BULL?"BULL":(trendBias==BEAR?"BEAR":"NEUTRAL"));
   string txt = "GagaFX  |  "+sym+"  TF:"+IntegerToString((int)tf)+
                "\nTrend: "+bias+"  BOS: "+(bosUp?"UP ":"")+(bosDown?"DN ":"")+
                "\nPred P(+1,+2,+3): "+DoubleToString(p1,2)+", "+DoubleToString(p2,2)+", "+DoubleToString(p3,2)+
                "\nRisk%:"+DoubleToString(g_RiskPerTradePct,2)+"  Thr:"+DoubleToString(g_PredictThreshold,2)+
                "  SLxATR:"+DoubleToString(g_ATR_SL_Mult,2)+"  TP_R:"+DoubleToString(g_TP_R_Multiple,2)+
                "\nOpenPos:"+IntegerToString(CountOpenByMagic(0))+"  Spread:"+IntegerToString(SpreadPoints())+
                "  MTF:"+(g_UseMTFContext?"ON":"OFF")+
                "  PredGate:"+(g_UsePredictionsForEntries?"ON":"OFF");
   ObjectSetString(0,name,OBJPROP_TEXT,txt);
}

void DrawPredictionArrows(double p1,double p2,double p3)
{
   string up="GagaFX_UP_"+IntegerToString((int)TimeAt(1));
   string dn="GagaFX_DN_"+IntegerToString((int)TimeAt(1));
   if(ObjectFind(0,up)>=0) ObjectDelete(0,up);
   if(ObjectFind(0,dn)>=0) ObjectDelete(0,dn);

   double price=(HighAt(1)+LowAt(1))/2.0;
   if(p1>=g_PredictThreshold || p2>=g_PredictThreshold || p3>=g_PredictThreshold)
   {
      ObjectCreate(0,up,OBJ_ARROW,0,TimeAt(1),price);
      ObjectSetInteger(0,up,OBJPROP_COLOR,clrLime);
      ObjectSetInteger(0,up,OBJPROP_ARROWCODE,241);
      ObjectSetInteger(0,up,OBJPROP_WIDTH,1);
   }
   if(p1<=1.0-g_PredictThreshold || p2<=1.0-g_PredictThreshold || p3<=1.0-g_PredictThreshold)
   {
      ObjectCreate(0,dn,OBJ_ARROW,0,TimeAt(1),price);
      ObjectSetInteger(0,dn,OBJPROP_COLOR,clrTomato);
      ObjectSetInteger(0,dn,OBJPROP_ARROWCODE,242);
      ObjectSetInteger(0,dn,OBJPROP_WIDTH,1);
   }
}

//---- Simple GUI (buttons & numeric nudges)
int  GUI_X=8, GUI_Y=60, GUI_W=300, GUI_H=170;

void GUI_Rect(const string name,int x,int y,int w,int h,color c)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
}
void GUI_Label(const string name,const string text,int x,int y,int fs=9,color col=clrWhite)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_COLOR,col);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,fs);
   ObjectSetString (0,name,OBJPROP_FONT,"Arial");
   ObjectSetString (0,name,OBJPROP_TEXT,text);
}
void GUI_Button(const string name,const string text,int x,int y,int w=46,int h=18)
{
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,name,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,name,OBJPROP_YSIZE,h);
   ObjectSetString (0,name,OBJPROP_TEXT,text);
}
void GUI_Build()
{
   if(!g_ShowControlPanel) { return; }
   // Theme + scale
   GFX_GetThemeColors();
   GFX_ScaleFactor = GFX_Scale();

   // Sizes
   int pad   = (int)MathRound(12 * GFX_ScaleFactor);
   int rowH  = (int)MathRound(28 * GFX_ScaleFactor);
   int lblW  = (int)MathRound(180 * GFX_ScaleFactor);
   int btnW  = (int)MathRound(64 * GFX_ScaleFactor);
   int nudW  = (int)MathRound(26 * GFX_ScaleFactor);
   int valW  = (int)MathRound(80 * GFX_ScaleFactor);
   int fsT   = (int)MathRound(14 * GFX_ScaleFactor);
   int fsH   = (int)MathRound(12 * GFX_ScaleFactor);
   int fsB   = (int)MathRound(11 * GFX_ScaleFactor);

   GFX_PanelW = (int)MathRound(480 * GFX_ScaleFactor);

   int x0= GFX_PanelX + pad;
   int y  = GFX_PanelY + pad;
   int col1 = x0;
   int col2 = x0 + lblW + pad;

   // Background panel behind labels/buttons (lower z-order) - much taller to prevent cropping
   GFX_CreatePanel(GFX_BG, GFX_PanelX, GFX_PanelY, GFX_PanelW, 600, GFX_PanelBG, GFX_PanelBorder, 3);

   GFX_Label(GFX_TITLE, "GagaFX Controls", x0, y, fsT, GFX_TextPrimary, 7);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);

   // Strategy
   GFX_Label(GFX_SEC_STRAT, "Strategy", x0, y, fsH, GFX_TextSecondary, 5);
   y += (int)MathRound(8*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_MODE,  "Mode", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_MODE, (g_StrategyMode==MODE_SCALP?"SCALP":"EXT"), col2, y-2, btnW, rowH, GFX_ToggleOnBG, clrWhite, fsB);
   y += rowH + (int)MathRound(8*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_PGATE, "PredGate", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_PGATE, (g_UsePredictionsForEntries?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_UsePredictionsForEntries), clrWhite, fsB);
   y += rowH + (int)MathRound(8*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_MTF,   "MTF Context", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_MTF,  (g_UseMTFContext?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_UseMTFContext), clrWhite, fsB);
   y += rowH + (int)MathRound(12*GFX_ScaleFactor);

   // Risk
   GFX_Label(GFX_SEC_RISK, "Risk", x0, y, fsH, GFX_TextSecondary, 5);
   y += (int)MathRound(8*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_RISK, "Risk %", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_RISK_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_RISK, DoubleToString(g_RiskPerTradePct,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_RISK_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);

   GFX_Label(GFX_LBL_SL, "SL × ATR", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_SL_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_SL, DoubleToString(g_ATR_SL_Mult,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_SL_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);

   GFX_Label(GFX_LBL_TPR, "TP as R", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_TPR_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_TPR, DoubleToString(g_TP_R_Multiple,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_TPR_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);

   GFX_Label(GFX_LBL_SPR, "Max Spread", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_SPR_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_SPR, IntegerToString(g_MaxSpreadPoints), col2+nudW+4, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_SPR_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   y += rowH + (int)MathRound(12*GFX_ScaleFactor);

   // Filters
   GFX_Label(GFX_SEC_FILTER, "Filters", x0, y, fsH, GFX_TextSecondary, 5);
   y += (int)MathRound(8*GFX_ScaleFactor);
   static bool _mirrors_init=false;
   if(!_mirrors_init){ g_UseSessionFilter=UseSessionFilter; g_BlockHighImpactNews=BlockHighImpactNews; _mirrors_init=true; }
   GFX_Label(GFX_LBL_SESSION,"Session filter", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_SESSION_TOGGLE, (g_UseSessionFilter?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_UseSessionFilter), clrWhite, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_NEWS,"News block", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_NEWS_TOGGLE, (g_BlockHighImpactNews?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_BlockHighImpactNews), clrWhite, fsB);
   y += rowH + (int)MathRound(12*GFX_ScaleFactor);

   // Logging
   GFX_Label(GFX_SEC_LOG, "Logging", x0, y, fsH, GFX_TextSecondary, 5);
   y += (int)MathRound(8*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_LOG,"Predictions log", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_LOG, (g_LogPredictions?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_LogPredictions), clrWhite, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);
   GFX_Label(GFX_LBL_PAYLOAD,"Payload export", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_PAYLOAD, (g_ExportPayload?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_ExportPayload), clrWhite, fsB);
   y += rowH + (int)MathRound(10*GFX_ScaleFactor);

   // Advanced
   string advTitle = (GFX_AdvVisible? "▲ Advanced" : "▼ Advanced");
   GFX_Button(GFX_BTN_ADV_TOGGLE, advTitle, x0, y-2, (int)MathRound(110*GFX_ScaleFactor), rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   y += rowH + (int)MathRound(6*GFX_ScaleFactor);
   if(GFX_AdvVisible)
   {
      GFX_Label(GFX_SEC_ADV, "Advanced", x0, y, fsH, GFX_TextSecondary, 5);
      y += (int)MathRound(8*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_THR,"Predict Thr", col1, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_THR_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
      GFX_Label(GFX_VAL_THR, DoubleToString(g_PredictThreshold,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_THR_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
      y += rowH + (int)MathRound(6*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_TRAIL,"Trail ATR ×", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_TRAIL_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_TRAIL, DoubleToString(g_TrailATR_Mult,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_TRAIL_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
      y += rowH + (int)MathRound(6*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_PARTIAL,"Partial TP", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_PARTIAL_TOGGLE, (g_UsePartialTP?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_UsePartialTP), clrWhite, fsB);
      y += rowH + (int)MathRound(6*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_PARTIAL_R,"Partial TP R", col1, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_PARTIAL_R_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_PARTIAL_R, DoubleToString(g_PartialTP_R,2), col2+nudW+4, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_PARTIAL_R_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
      y += rowH + (int)MathRound(6*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_PARTIAL_PC,"Partial Close %", col1, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_PARTIAL_PC_MINUS,"-", col2, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
   GFX_Label(GFX_VAL_PARTIAL_PC, DoubleToString(g_PartialClosePct,1), col2+nudW+4, y, fsB, GFX_TextPrimary);
      GFX_Button(GFX_BTN_PARTIAL_PC_PLUS, "+", col2+nudW+4+valW+4, y-2, nudW, rowH, GFX_NudgeBG, GFX_NudgeText, fsB);
      y += rowH + (int)MathRound(6*GFX_ScaleFactor);

      GFX_Label(GFX_LBL_BE,"MoveToBE@1R", col1, y, fsB, GFX_TextPrimary);
   GFX_Button(GFX_BTN_BE_TOGGLE, (g_MoveToBE_At1R?"ON":"OFF"), col2, y-2, btnW, rowH, GFX_OnOffBG(g_MoveToBE_At1R), clrWhite, fsB);
      y += rowH + (int)MathRound(4*GFX_ScaleFactor);
   }

   GFX_PanelH = (y - GFX_PanelY) + pad;
   ObjectSetInteger(0, GFX_BG, OBJPROP_YSIZE, GFX_PanelH);
   ObjectSetInteger(0, GFX_BG, OBJPROP_XSIZE, GFX_PanelW);
}
void GUI_RefreshValues()
{
   ObjectSetString (0,GFX_BTN_MODE, OBJPROP_TEXT, (g_StrategyMode==MODE_SCALP?"SCALP":"EXT"));
   ObjectSetInteger(0,GFX_BTN_PGATE,OBJPROP_BGCOLOR, GFX_OnOffBG(g_UsePredictionsForEntries));
   ObjectSetString (0,GFX_BTN_PGATE,OBJPROP_TEXT, GFX_OnOffText(g_UsePredictionsForEntries));
   ObjectSetInteger(0,GFX_BTN_MTF,  OBJPROP_BGCOLOR, GFX_OnOffBG(g_UseMTFContext));
   ObjectSetString (0,GFX_BTN_MTF,  OBJPROP_TEXT, GFX_OnOffText(g_UseMTFContext));
   ObjectSetInteger(0,GFX_BTN_SESSION_TOGGLE,OBJPROP_BGCOLOR, GFX_OnOffBG(g_UseSessionFilter));
   ObjectSetString (0,GFX_BTN_SESSION_TOGGLE,OBJPROP_TEXT, GFX_OnOffText(g_UseSessionFilter));
   ObjectSetInteger(0,GFX_BTN_NEWS_TOGGLE,OBJPROP_BGCOLOR, GFX_OnOffBG(g_BlockHighImpactNews));
   ObjectSetString (0,GFX_BTN_NEWS_TOGGLE,OBJPROP_TEXT, GFX_OnOffText(g_BlockHighImpactNews));
   ObjectSetInteger(0,GFX_BTN_LOG,OBJPROP_BGCOLOR, GFX_OnOffBG(g_LogPredictions));
   ObjectSetString (0,GFX_BTN_LOG,OBJPROP_TEXT, GFX_OnOffText(g_LogPredictions));
   ObjectSetInteger(0,GFX_BTN_PAYLOAD,OBJPROP_BGCOLOR, GFX_OnOffBG(g_ExportPayload));
   ObjectSetString (0,GFX_BTN_PAYLOAD,OBJPROP_TEXT, GFX_OnOffText(g_ExportPayload));

   ObjectSetString(0,GFX_VAL_RISK, OBJPROP_TEXT, DoubleToString(g_RiskPerTradePct,2));
   ObjectSetString(0,GFX_VAL_SL,   OBJPROP_TEXT, DoubleToString(g_ATR_SL_Mult,2));
   ObjectSetString(0,GFX_VAL_TPR,  OBJPROP_TEXT, DoubleToString(g_TP_R_Multiple,2));
   ObjectSetString(0,GFX_VAL_SPR,  OBJPROP_TEXT, IntegerToString(g_MaxSpreadPoints));

   if(ObjectFind(0,GFX_BTN_ADV_TOGGLE)>=0)
      ObjectSetString(0,GFX_BTN_ADV_TOGGLE, OBJPROP_TEXT, (GFX_AdvVisible? "▲ Advanced" : "▼ Advanced"));
   if(ObjectFind(0,GFX_VAL_THR)>=0)    ObjectSetString(0,GFX_VAL_THR,   OBJPROP_TEXT, DoubleToString(g_PredictThreshold,2));
   if(ObjectFind(0,GFX_VAL_TRAIL)>=0)  ObjectSetString(0,GFX_VAL_TRAIL, OBJPROP_TEXT, DoubleToString(g_TrailATR_Mult,2));
   if(ObjectFind(0,GFX_BTN_PARTIAL_TOGGLE)>=0){
      ObjectSetInteger(0,GFX_BTN_PARTIAL_TOGGLE, OBJPROP_BGCOLOR, GFX_OnOffBG(g_UsePartialTP));
      ObjectSetString (0,GFX_BTN_PARTIAL_TOGGLE, OBJPROP_TEXT,    GFX_OnOffText(g_UsePartialTP));
   }
   if(ObjectFind(0,GFX_VAL_PARTIAL_R)>=0)  ObjectSetString(0,GFX_VAL_PARTIAL_R,  OBJPROP_TEXT, DoubleToString(g_PartialTP_R,2));
   if(ObjectFind(0,GFX_VAL_PARTIAL_PC)>=0) ObjectSetString(0,GFX_VAL_PARTIAL_PC, OBJPROP_TEXT, DoubleToString(g_PartialClosePct,1));
}

//============================= Init/Deinit =============================//
int OnInit()
{
   sym = (StringLen(InpSymbol)>0? InpSymbol : _Symbol);
   tf  = InpTF;

   // enforce matching chart
   if(_Symbol!=sym || Period()!=tf)
   {
      Print("GagaFX: Attach EA to chart of ",sym," on TF=",tf," (current: ",_Symbol,"/",Period(),")");
      return(INIT_FAILED);
   }

   _pt       = SymbolInfoDouble(sym,SYMBOL_POINT);
   long digits_l=0; SymbolInfoInteger(sym,SYMBOL_DIGITS,digits_l); SymDigits=(int)digits_l;

   // runtime config
   g_RiskPerTradePct         = RiskPerTradePct;
   g_PredictThreshold        = PredictThreshold;
   g_ATR_SL_Mult             = ATR_SL_Mult;
   g_TP_R_Multiple           = TP_R_Multiple;
   g_MaxSpreadPoints         = MaxSpreadPoints;
   g_UsePredictionsForEntries= UsePredictionsForEntries;
   g_UseMTFContext           = UseMTFContext;
   g_LogPredictions          = LogPredictions;
   g_ExportPayload           = ExportPayload;
   g_StrategyMode            = StrategyMode;
   g_SentimentSource         = SentimentSource;
   // UI mirrors
   g_ShowControlPanel        = ShowControlPanel;
   g_UseCompactHUD           = UseCompactHUD;
   g_HUD_OnTop               = HUD_AlwaysOnTop;
   g_TradingEnabled          = TradingEnabled;
   g_Enabled                 = TradingEnabled;  // sync with g_TradingEnabled
   // advanced mirrors
   g_TrailATR_Mult           = TrailATR_Mult;
   g_UsePartialTP            = UsePartialTP;
   g_PartialTP_R             = PartialTP_R;
   g_PartialClosePct         = PartialClosePct;
   g_MoveToBE_At1R           = MoveToBE_At1R;

   // HUD mirrors
   g_RiskPerTradePct_Runtime = RiskPerTradePct;
   g_MaxSpreadPoints_Runtime = MaxSpreadPoints;

   // indicators (chart TF)
   hEMAfast = iMA(sym,tf,FastEMA,0,MODE_EMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
   hEMAslow = iMA(sym,tf,SlowEMA,0,MODE_EMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
   hSMAfast = iMA(sym,tf,FastSMA,0,MODE_SMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
   hSMAslow = iMA(sym,tf,SlowSMA,0,MODE_SMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
   hRSI     = iRSI(sym,tf,RSI_Period,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
   hATR     = iATR(sym,tf,ATR_Period);

   if(hEMAfast==INVALID_HANDLE || hEMAslow==INVALID_HANDLE || hSMAfast==INVALID_HANDLE ||
      hSMAslow==INVALID_HANDLE || hRSI==INVALID_HANDLE || hATR==INVALID_HANDLE)
   { Print("Indicator handle init failed"); return(INIT_FAILED); }

   // HTF handles
   hTFs[0]=HTF1; hTFs[1]=HTF2; hTFs[2]=HTF3; hTFs[3]=HTF4;
   for(int i=0;i<4;i++)
   {
      hEMAfast_HTF[i] = iMA(sym,hTFs[i],FastEMA,0,MODE_EMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
      hEMAslow_HTF[i] = iMA(sym,hTFs[i],SlowEMA,0,MODE_EMA,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
      hRSI_HTF[i]     = iRSI(sym,hTFs[i],RSI_Period,(ENUM_APPLIED_PRICE)PRICE_CLOSE);
      hATR_HTF[i]     = iATR(sym,hTFs[i],ATR_Period);
      if(hEMAfast_HTF[i]==INVALID_HANDLE || hEMAslow_HTF[i]==INVALID_HANDLE || hRSI_HTF[i]==INVALID_HANDLE || hATR_HTF[i]==INVALID_HANDLE)
      { Print("HTF handle init failed"); return(INIT_FAILED); }
   }

   // init arrays
   ArraySetAsSeries(gRates,true);
   // Note: featBuf/closeBuf/timeBuf are statically-sized; keep natural indexing (no ArraySetAsSeries)

   for(int i=0;i<FEAT_COUNT;i++){ w1[i]=0; w2[i]=0; w3[i]=0; }

   // daily baseline
   dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   MqlDateTime mt; TimeToStruct(TimeCurrent(),mt); dayOfYear=mt.day_of_year;

   Trade.SetExpertMagicNumber(MagicNumber);
   Trade.SetDeviationInPoints(SlippagePoints);

   // Build GUI
   GUI_Build();
   if(g_ShowControlPanel) GUI_RefreshValues();
   // Ensure HUD is visible immediately on attach
   if(ShowDashboard) DrawDashboard(0.0,0.0,0.0);
   // Build minimal HUD widgets
   HUD_Build(); HUD_Refresh(); PRED_Build();

   // prime rates
   EnsureRates(3);
   lastBarTime = (gBars>=2 ? TimeAt(1) : 0);

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(ShowDashboard && ObjectFind(0,"GagaFX_DASH")>=0) ObjectDelete(0,"GagaFX_DASH");
   // clean minimal HUD and prediction widgets
   string pref[] = {HUD_BG,HUD_T,HUD_START,HUD_PGATE,HUD_RISK,HUD_NOTE,PBG,PL1,PL2,PL3};
   for(int i=0;i<ArraySize(pref);i++) if(ObjectFind(0,pref[i])>=0) ObjectDelete(0,pref[i]);

   // clean GUI
   string arr[]={"GFX_PANEL","GFX_HDR","GFX_T0","GFX_T1","GFX_T2","GFX_T3","GFX_T4",
                 "btnPred","btnMTF","btnMode","btnLog","btnPayload",
                 "lblRisk","valRisk","btnRiskMinus","btnRiskPlus",
                 "lblThr","valThr","btnThrMinus","btnThrPlus",
                 "lblSLATR","valSLATR","btnSLMinus","btnSLPlus",
                 "lblTPR","valTPR","btnTPMinus","btnTPPlus",
                 "lblSpr","valSpr","btnSprMinus","btnSprPlus"};
   for(int i=0;i<ArraySize(arr);i++)
   {
      if(ObjectFind(0,arr[i])>=0) ObjectDelete(0,arr[i]);
   }

   // remove HTF lines
   string lns[]={"GFX_HH_M5","GFX_LL_M5","GFX_HH_M15","GFX_LL_M15","GFX_HH_M30","GFX_LL_M30","GFX_HH_H1","GFX_LL_H1"};
   for(int i=0;i<ArraySize(lns);i++)
   {
      if(ObjectFind(0,lns[i])>=0) ObjectDelete(0,lns[i]);
   }

   // remove new GFX_ UI objects (modern panel)
   int _ot = ObjectsTotal(0,0);
   for(int oi=_ot-1; oi>=0; --oi)
   {
      string nm = ObjectName(0,oi,0);
      if(StringLen(nm)>=4 && StringSubstr(nm,0,4)=="GFX_") ObjectDelete(0,nm);
   }

   // write metrics
   WriteMetrics();

   // release indicators
   if(hEMAfast!=-1) IndicatorRelease(hEMAfast);
   if(hEMAslow!=-1) IndicatorRelease(hEMAslow);
   if(hSMAfast!=-1) IndicatorRelease(hSMAfast);
   if(hSMAslow!=-1) IndicatorRelease(hSMAslow);
   if(hRSI!=-1)     IndicatorRelease(hRSI);
   if(hATR!=-1)     IndicatorRelease(hATR);
   for(int i=0;i<4;i++)
   {
      if(hEMAfast_HTF[i]!=-1) IndicatorRelease(hEMAfast_HTF[i]);
      if(hEMAslow_HTF[i]!=-1) IndicatorRelease(hEMAslow_HTF[i]);
      if(hRSI_HTF[i]!=-1)     IndicatorRelease(hRSI_HTF[i]);
      if(hATR_HTF[i]!=-1)     IndicatorRelease(hATR_HTF[i]);
   }
}

//========================= Chart Events (GUI) =========================//
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      HUD_Build(); HUD_Refresh(); PRED_Build(); ChartRedraw(0); return;
   }
   if(id!=CHARTEVENT_OBJECT_CLICK) return;

   // HUD buttons
   if(sparam==HUD_START){ g_TradingEnabled=!g_TradingEnabled; g_Enabled=g_TradingEnabled; HUD_Refresh(); ChartRedraw(0); return; }
   if(sparam==HUD_PGATE){ g_UsePredictionsForEntries=!g_UsePredictionsForEntries; HUD_Refresh(); ChartRedraw(0); return; }
   if(sparam==GFX_BTN_HUD_TOGGLE)
   {
      g_ShowControlPanel = !g_ShowControlPanel;
      GUI_Build();
      if(g_ShowControlPanel) GUI_RefreshValues();
      ChartRedraw(0);
      return;
   }
   else if(sparam==GFX_BTN_TOP_TOGGLE)
   {
      g_HUD_OnTop = !g_HUD_OnTop;
      // Redraw dashboard to apply new z-order and button state
      ChartRedraw(0);
      return;
   }
   else if(sparam==GFX_BTN_TRD_TOGGLE)
   {
      g_TradingEnabled = !g_TradingEnabled;
      g_Enabled = g_TradingEnabled;
      ChartRedraw(0);
      return;
   }

   if(sparam==GFX_BTN_MODE) { g_StrategyMode=(g_StrategyMode==MODE_SCALP?MODE_EXTENDED:MODE_SCALP); }
   else if(sparam==GFX_BTN_PGATE){ g_UsePredictionsForEntries=!g_UsePredictionsForEntries; }
   else if(sparam==GFX_BTN_MTF)  { g_UseMTFContext=!g_UseMTFContext; }
   else if(sparam==GFX_BTN_SESSION_TOGGLE){ g_UseSessionFilter=!g_UseSessionFilter; }
   else if(sparam==GFX_BTN_NEWS_TOGGLE)   { g_BlockHighImpactNews=!g_BlockHighImpactNews; }
   else if(sparam==GFX_BTN_LOG)     { g_LogPredictions=!g_LogPredictions; }
   else if(sparam==GFX_BTN_PAYLOAD) { g_ExportPayload=!g_ExportPayload; }

   else if(sparam==GFX_BTN_RISK_MINUS){ g_RiskPerTradePct=Clamp(g_RiskPerTradePct-0.25, 0.05,10.0); }
   else if(sparam==GFX_BTN_RISK_PLUS) { g_RiskPerTradePct=Clamp(g_RiskPerTradePct+0.25, 0.05,10.0); }
   else if(sparam==GFX_BTN_SL_MINUS){ g_ATR_SL_Mult=Clamp(g_ATR_SL_Mult-0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_SL_PLUS) { g_ATR_SL_Mult=Clamp(g_ATR_SL_Mult+0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_TPR_MINUS){ g_TP_R_Multiple=Clamp(g_TP_R_Multiple-0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_TPR_PLUS) { g_TP_R_Multiple=Clamp(g_TP_R_Multiple+0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_SPR_MINUS){ g_MaxSpreadPoints=(int)Clamp(g_MaxSpreadPoints-10, 10,5000); }
   else if(sparam==GFX_BTN_SPR_PLUS) { g_MaxSpreadPoints=(int)Clamp(g_MaxSpreadPoints+10, 10,5000); }
   else if(sparam==GFX_BTN_ADV_TOGGLE){ GFX_AdvVisible=!GFX_AdvVisible; GUI_Build(); }
   else if(sparam==GFX_BTN_THR_MINUS){ g_PredictThreshold=Clamp(g_PredictThreshold-0.01, 0.50,0.90); }
   else if(sparam==GFX_BTN_THR_PLUS) { g_PredictThreshold=Clamp(g_PredictThreshold+0.01, 0.50,0.90); }
   else if(sparam==GFX_BTN_TRAIL_MINUS){ g_TrailATR_Mult=Clamp(g_TrailATR_Mult-0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_TRAIL_PLUS) { g_TrailATR_Mult=Clamp(g_TrailATR_Mult+0.10, 0.5,6.0); }
   else if(sparam==GFX_BTN_PARTIAL_TOGGLE){ g_UsePartialTP=!g_UsePartialTP; }
   else if(sparam==GFX_BTN_PARTIAL_R_MINUS){ g_PartialTP_R=Clamp(g_PartialTP_R-0.10, 0.1, 6.0); }
   else if(sparam==GFX_BTN_PARTIAL_R_PLUS) { g_PartialTP_R=Clamp(g_PartialTP_R+0.10, 0.1, 6.0); }
   else if(sparam==GFX_BTN_PARTIAL_PC_MINUS){ g_PartialClosePct=Clamp(g_PartialClosePct-1.0, 1.0, 100.0); }
   else if(sparam==GFX_BTN_PARTIAL_PC_PLUS) { g_PartialClosePct=Clamp(g_PartialClosePct+1.0, 1.0, 100.0); }
   else if(sparam==GFX_BTN_BE_TOGGLE){ g_MoveToBE_At1R=!g_MoveToBE_At1R; }

   GUI_RefreshValues();
   ChartRedraw(0);
}

//=============================== Tick =================================//
void OnTick()
{
   // reset daily baseline on day change
   MqlDateTime mt; TimeToStruct(TimeCurrent(),mt);
   if(mt.day_of_year!=dayOfYear){ dayOfYear=mt.day_of_year; dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY); }

   double ddPct = 100.0*(dayStartEquity-AccountInfoDouble(ACCOUNT_EQUITY))/MathMax(dayStartEquity,1.0);
   bool dailyStop = (ddPct>=MaxDailyLossPct);

   if(NewBar())
   {
      barCount++;

      UpdateSwingsAndTrend();
      DrawHTFLevels();

      double x[FEAT_COUNT]; BuildFeatures(x);

      double p1,p2,p3; LR_Predict(x,p1,p2,p3);

      // store for scoring/payload
      for(int i=0;i<FEAT_COUNT;i++) featBuf[writePos][i]=x[i];
      closeBuf[writePos]=CloseAt(1);
      timeBuf[writePos]=TimeAt(1);
      writePos=(writePos+1)%BUF;

      OnlineScoreAndLearn();

      double emaF,emaS,smaF,smaS,rsi,atr;
      if(GetBuffers(emaF,emaS,smaF,smaS,rsi,atr))
      {
         double tsi,tsis,tsid; if(!TSI_Calc(1,tsi,tsis,tsid)){tsi=0;tsid=0;}
         AppendPredictionsCSV(TimeAt(1),p1,p2,p3,rsi,tsi,tsid,atr,(double)SpreadPoints());
         // Update bottom-right prediction widget each bar
         PRED_Update(p1, atr);
         
         // Log prediction updates
         LogPredictionUpdate(p1, p2, p3, atr);
      }

      DrawPredictionArrows(p1,p2,p3);
      DrawDashboard(p1,p2,p3);
      HUD_Refresh();

      if(!dailyStop) TryEntries(p1,p2,p3);

      WritePayloadJSON();
      WriteHUDStatusJSON(p1,p2,p3);
   }

   ManagePositions();
}

//========================= Trade Transactions ========================//
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal=trans.deal;
   if(deal==0) return;
   string dsym = (string)HistoryDealGetString(deal, DEAL_SYMBOL);
   if(dsym!=sym) return;
   long magic = HistoryDealGetInteger(deal, DEAL_MAGIC);
   if((long)magic != (long)MagicNumber) return;
   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   long dtype = HistoryDealGetInteger(deal, DEAL_TYPE);
   double price = HistoryDealGetDouble(deal, DEAL_PRICE);
   datetime dtime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
   ulong pos_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);

   if(entry==DEAL_ENTRY_IN)
   {
      int dir = (dtype==DEAL_TYPE_BUY? +1 : -1);
      AddTrack(pos_id, deal, dir, price, g_NextPlanEstPx, dtime);
   }
   else if(entry==DEAL_ENTRY_OUT)
   {
      int idx = FindTrackByPosition(pos_id);
      if(idx>=0)
      {
         PlanTrack t = g_planTrack[idx];
         double expPts = (t.expected>0? (t.dir>0? (t.expected - t.entry):(t.entry - t.expected))/_pt : 0.0);
         double resPts = (t.dir>0? (price - t.entry) : (t.entry - price))/_pt;
         string name = "GFX_RES_"+IntegerToString((int)deal);
         ObjectCreate(0,name,OBJ_TEXT,0,dtime,price);
         string txt = "E:"+IntegerToString((int)MathRound(expPts))+" R:"+IntegerToString((int)MathRound(resPts));
         ObjectSetString(0,name,OBJPROP_TEXT,txt);
         ObjectSetInteger(0,name,OBJPROP_COLOR, (resPts>=0? clrLime : clrTomato));
         ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
         // Cleanup expected path for the entry deal if present
         string expNm = "GFX_EXP_"+IntegerToString((int)t.deal_in);
         if(ObjectFind(0,expNm)>=0) ObjectDelete(0,expNm);
         RemoveTrackIndex(idx);
      }
   }
}
