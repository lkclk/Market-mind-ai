#property strict
#property version "1.00"
#property description "MarketMind AI bridge for HFM MT5. Demo trading enabled by default; live trading disabled."
#include <Trade/Trade.mqh>
CTrade trade;
input string RelayBaseUrl = "https://YOUR-WORKER.workers.dev";
input string EAToken = "SET_A_LONG_RANDOM_EA_TOKEN";
input bool AllowDemoTrading = true;
input bool AllowLiveTrading = false;
input double MaxRiskPercent = 1.0;
input int PollSeconds = 5;
input int MaxSlippagePoints = 20;
input ulong MagicNumber = 6110801;
datetime lastPoll = 0;
string lastSignalId = "";

string JsonValue(string body,string key) {
  string needle="\"" + key + "\":";
  int p=StringFind(body,needle); if(p<0) return "";
  p+=StringLen(needle);
  while(p<StringLen(body) && (StringGetCharacter(body,p)==' ' || StringGetCharacter(body,p)=='\"')) p++;
  int e=p;
  while(e<StringLen(body) && StringGetCharacter(body,e)!=',' && StringGetCharacter(body,e)!='}' && StringGetCharacter(body,e)!='\"') e++;
  return StringSubstr(body,p,e-p);
}
bool Http(string method,string path,string payload,string &response) {
  char data[],result[]; string headers="Authorization: Bearer "+EAToken+"\r\nContent-Type: application/json\r\n";
  if(payload!="") StringToCharArray(payload,data,0,WHOLE_ARRAY,CP_UTF8);
  else ArrayResize(data,0);
  string responseHeaders;
  ResetLastError();
  int code=WebRequest(method,RelayBaseUrl+path,headers,7000,data,result,responseHeaders);
  if(code<200 || code>=300) { Print("MarketMind relay HTTP error ",code," terminal error ",GetLastError()); return false; }
  response=CharArrayToString(result,0,WHOLE_ARRAY,CP_UTF8); return true;
}
double LotsForRisk(string symbol,double entry,double sl,double riskPct) {
  double equity=AccountInfoDouble(ACCOUNT_EQUITY);
  double riskMoney=equity*MathMin(riskPct,MaxRiskPercent)/100.0;
  double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
  double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
  double distance=MathAbs(entry-sl);
  if(tickSize<=0 || tickValue<=0 || distance<=0) return 0;
  double lossPerLot=(distance/tickSize)*tickValue;
  if(lossPerLot<=0) return 0;
  double raw=riskMoney/lossPerLot;
  double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
  double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
  double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
  if(step<=0) return 0;
  double lots=MathFloor(raw/step)*step;
  if(lots<minLot) return 0;
  return MathMin(lots,maxLot);
}
void SendResult(string id,string status,string detail) {
  string safe=detail; StringReplace(safe,"\"","'");
  string body="{\"id\":\""+id+"\",\"status\":\""+status+"\",\"detail\":\""+safe+"\"}";
  string ignored; Http("POST","/result",body,ignored);
}
void OnTimer() {
  string body;
  if(!Http("GET","/next","",body)) return;
  string id=JsonValue(body,"id");
  if(id=="" || id==lastSignalId || StringFind(body,"\"signal\":null")>=0) return;
  string symbol=JsonValue(body,"symbol"), side=JsonValue(body,"side");
  double sl=StringToDouble(JsonValue(body,"sl")), tp=StringToDouble(JsonValue(body,"tp"));
  double risk=StringToDouble(JsonValue(body,"riskPercent"));
  lastSignalId=id;
  bool isDemo=(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO);
  if((isDemo && !AllowDemoTrading) || (!isDemo && !AllowLiveTrading)) { SendResult(id,"BLOCKED","Account mode not enabled in EA settings"); return; }
  if(risk<=0 || risk>MaxRiskPercent || risk>1.0) { SendResult(id,"BLOCKED","Risk exceeds hard 1 percent ceiling"); return; }
  if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)) { SendResult(id,"BLOCKED","Enable Algo Trading and EA permissions in MT5"); return; }
  if(!SymbolSelect(symbol,true)) { SendResult(id,"REJECTED","Symbol unavailable in this HFM account"); return; }
  if(PositionSelect(symbol)) { SendResult(id,"BLOCKED","Existing position on symbol; duplicate exposure prevented"); return; }
  MqlTick tick; if(!SymbolInfoTick(symbol,tick)) { SendResult(id,"REJECTED","No current broker quote"); return; }
  double entry=(side=="BUY")?tick.ask:tick.bid;
  if((side=="BUY" && !(sl<entry && tp>entry)) || (side=="SELL" && !(sl>entry && tp<entry))) { SendResult(id,"REJECTED","SL/TP invalid against live broker quote"); return; }
  double lots=LotsForRisk(symbol,entry,sl,risk);
  if(lots<=0) { SendResult(id,"REJECTED","Calculated volume below broker minimum or contract data unavailable"); return; }
  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(MaxSlippagePoints);
  bool ok=(side=="BUY")?trade.Buy(lots,symbol,0,sl,tp,"MarketMind "+id):trade.Sell(lots,symbol,0,sl,tp,"MarketMind "+id);
  if(ok) SendResult(id,"PLACED",StringFormat("%s %.2f lots; order %I64u",side,lots,trade.ResultOrder()));
  else SendResult(id,"FAILED",trade.ResultRetcodeDescription());
}
int OnInit() {
  if(StringFind(RelayBaseUrl,"https://")!=0 || EAToken=="SET_A_LONG_RANDOM_EA_TOKEN") { Print("Set HTTPS relay URL and EA token before enabling."); return INIT_PARAMETERS_INCORRECT; }
  EventSetTimer(MathMax(2,PollSeconds)); return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() {}
// MT5: Tools > Options > Expert Advisors > Allow WebRequest for listed URL. Add your Worker host.
// Keep AllowLiveTrading=false until extensive demo validation and explicit manual configuration.
