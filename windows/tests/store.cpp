#include "../src/store.h"
#include <filesystem>
#include <cstdio>
#include <cstdlib>
using namespace fc;
void check(bool good,const char* name){if(!good){printf("FAIL: %s\n",name);exit(1);}printf("PASS: %s\n",name);}
int wmain(){
 wchar_t temp[MAX_PATH];GetTempPathW(MAX_PATH,temp);auto dir=std::wstring(temp)+L"FlowCat-test-"+std::to_wstring(GetCurrentProcessId());
 {
  Store s(dir);check(s.ok(),"Windows system SQLite opens isolated history");Row a{L"app",L"App.exe",{10,20,30,40},false};Row proxy{L"proxy",L"mihomo.exe",{100,200,0,0},true};
  check(s.put(L"2026-10-18",L"wifi A",{a,proxy},{1000,2000,0,0}),"transaction saves counters");
  check(s.put(L"2026-10-18",L"wifi B",{a},{4000,5000,0,0}),"same app on second network remains separate");
  check(s.put(L"2026-10-19",L"wifi A",{a},{6000,7000,0,0}),"second day saves independently");
  auto rows=s.rows(L"2026-10-18",L"2026-10-18",false,0);check(rows.size()==1&&rows[0].bytes.down==20&&rows[0].bytes.write==80,"date and proxy filters preserve app totals");
  check(s.physical(L"2026-10-18",L"2026-10-18").total(false)==12000,"physical totals never sum process proxy counters");
 }
 {
  Store reopened(dir);auto rows=reopened.rows(L"2026-10-18",L"2026-10-19",true);check(rows.size()==1&&rows[0].bytes.write==120,"history survives close and reopen");
  check(reopened.csv(dir+L"\\export.csv",L"2026-10-18",L"2026-10-19"),"CSV exports persisted daily records");
 }
 std::filesystem::remove_all(dir);puts("All 8 persistence checks passed.");
}
