#include <winsock2.h>
#include <windows.h>
#include <commctrl.h>
#include <commdlg.h>
#include <shellapi.h>
#include <shlobj.h>
#include <d2d1.h>
#include <dwrite.h>
#include <dwmapi.h>
#include <uxtheme.h>
#include <psapi.h>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <condition_variable>
#include "collector.h"
#include "store.h"
#include "health.h"
using namespace fc;
namespace {
constexpr UINT TRAY=WM_APP+1, TICK=WM_APP+2;
struct Pending {std::map<std::wstring,Row> rows;Bytes physical;};
struct Model {
 std::mutex mutex;Store store;Collector collector;std::vector<DiskHealth> health;
 std::map<std::pair<std::wstring,std::wstring>,Pending> pending;
 Bytes rates;std::wstring network=L"全部网络";std::atomic<bool> quit{false};
 bool saved=true;std::thread worker;
 Model(std::wstring directory):store(directory){}
 void sample(){
  auto b=collector.take();std::lock_guard guard(mutex);rates={};network=b.network;
  auto& p=pending[{dayKey(),network}];p.physical.merge(b.physical);rates.down=b.physical.down/2;rates.up=b.physical.up/2;
  for(auto& r:b.rows){auto& existing=pending[{r.day.empty()?dayKey():r.day,network}].rows[r.key];existing.key=r.key;existing.name=r.name;existing.proxy=r.proxy;existing.bytes.merge(r.bytes);rates.read=add(rates.read,r.bytes.read/2);rates.write=add(rates.write,r.bytes.write/2);}
 }
 void flush(){
  std::lock_guard guard(mutex);if(!store.ok()){saved=false;return;}
  for(auto it=pending.begin();it!=pending.end();){std::vector<Row> rows;for(auto& [k,r]:it->second.rows)rows.push_back(r);
   if(!store.put(it->first.first,it->first.second,rows,it->second.physical)){saved=false;return;}it=pending.erase(it);
  }saved=true;
 }
 std::vector<Row> rows(const std::wstring& since,bool disk,int proxy=-1){
  auto list=store.rows(since,dayKey(),disk,proxy);std::map<std::wstring,Row> combined;for(auto& r:list)combined[r.key]=r;
  for(auto& [key,p]:pending)if(key.first>=since&&key.first<=dayKey())for(auto& [k,r]:p.rows)if(disk||proxy<0||r.proxy==(proxy!=0)){auto& a=combined[k];a.key=r.key;a.name=r.name;a.proxy=r.proxy;a.bytes.merge(r.bytes);}
  list.clear();for(auto& [k,r]:combined)if(r.bytes.total(disk))list.push_back(r);return list;
 }
 Bytes physical(const std::wstring& since){auto b=store.physical(since,dayKey());for(auto& [key,p]:pending)if(key.first>=since&&key.first<=dayKey())b.merge(p.physical);return b;}
 void start(HWND notify){collector.start();worker=std::thread([this,notify]{
  auto disks=diskHealth();{std::lock_guard g(mutex);health=std::move(disks);}
  unsigned tick=0;while(!quit){for(int i=0;i<20&&!quit;++i)Sleep(100);if(quit)break;sample();++tick;if(tick%30==0)flush();if(tick%300==0){auto refreshed=diskHealth();std::lock_guard g(mutex);health=std::move(refreshed);}if(notify)PostMessageW(notify,TICK,0,0);}
 });}
 void stop(){quit=true;if(worker.joinable())worker.join();collector.stop();sample();flush();}
};
std::unique_ptr<Model> model;
HWND window,list,search,netButton,diskButton,healthButton,periodBox,proxyBox,pauseButton,exportButton,closeButton;
HFONT font;HICON icon;NOTIFYICONDATAW tray{};bool panel=false,dialogOpen=false;int page=0,period=0,sortColumn=1;bool descending=true;std::wstring filter;
ID2D1Factory* d2d=nullptr;IDWriteFactory* dwrite=nullptr;ID2D1HwndRenderTarget* target=nullptr;
std::wstring since(){if(period==0)return dayKey();if(period==1)return dayKey(-1);if(period==2)return dayKey(-6);if(period==3)return dayKey(-29);return L"0000-00-00";}
std::wstring until(){return period==1?dayKey(-1):dayKey();}
void releaseTarget(){if(target){target->Release();target=nullptr;}}
void text(const std::wstring& value,float x,float y,float width,float height,float size,D2D1_COLOR_F color=D2D1::ColorF(0x233044),bool bold=false){
 IDWriteTextFormat* f=nullptr;ID2D1SolidColorBrush* b=nullptr;
 dwrite->CreateTextFormat(L"Segoe UI",nullptr,bold?DWRITE_FONT_WEIGHT_SEMI_BOLD:DWRITE_FONT_WEIGHT_NORMAL,DWRITE_FONT_STYLE_NORMAL,DWRITE_FONT_STRETCH_NORMAL,size,L"zh-cn",&f);
 if(!f)return;f->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);target->CreateSolidColorBrush(color,&b);if(b){target->DrawTextW(value.c_str(),static_cast<UINT32>(value.size()),f,D2D1::RectF(x,y,x+width,y+height),b,D2D1_DRAW_TEXT_OPTIONS_CLIP);b->Release();}f->Release();
}
void paint(){PAINTSTRUCT ps;BeginPaint(window,&ps);RECT rc;GetClientRect(window,&rc);
 if(!target)d2d->CreateHwndRenderTarget(D2D1::RenderTargetProperties(),D2D1::HwndRenderTargetProperties(window,D2D1::SizeU(rc.right,rc.bottom)),&target);
 if(target){target->BeginDraw();target->Clear(D2D1::ColorF(0xf5f7fa));std::lock_guard g(model->mutex);
  text(L"流量喵",24,20,200,30,20,D2D1::ColorF(0x233044),true);
  std::wstring status=model->collector.error?L"采集失败 · "+std::to_wstring(model->collector.error.load()):model->collector.paused?L"已暂停":L"记录中 · Windows 预览版";
  text(status,240,25,240,25,12,D2D1::ColorF(0x617086));
  if(page!=2){
   auto rows=model->rows(since(),page==1);Bytes total;
   if(page==0)total=model->physical(since());else for(auto& r:rows)total.merge(r.bytes);
   // Yesterday is an exact date, rather than yesterday plus today.
   if(period==1){total={};if(page==0){total=model->store.physical(since(),until());for(auto& [k,p]:model->pending)if(k.first==since())total.merge(p.physical);}else{auto exact=model->store.rows(since(),until(),true);for(auto& r:exact)total.merge(r.bytes);for(auto& [k,p]:model->pending)if(k.first==since())for(auto& [n,r]:p.rows)total.merge(r.bytes);}}
   ID2D1SolidColorBrush* b=nullptr;target->CreateSolidColorBrush(D2D1::ColorF(0xffffff),&b);if(b){target->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(20,164,500,294),12,12),b);b->Release();}
   text(page==0?L"网卡累计流量":L"进程磁盘累计读写",36,178,350,20,12,D2D1::ColorF(0x617086));
   text(volume(total.total(page==1)),36,202,440,46,32,D2D1::ColorF(0x172231),true);
   text((page==0?L"↓ 下载  ":L"读取  ")+volume(page==0?total.down:total.read),36,258,230,22,13);
   text((page==0?L"↑ 上传  ":L"写入  ")+volume(page==0?total.up:total.write),275,258,220,22,13);
   text(page==0?L"当前网络 · "+model->network:L"物理磁盘 I/O · 按写入排序",174,117,178,24,12,D2D1::ColorF(0x617086));
   auto r=model->rates;text(page==0?L"实时网卡  ↓ "+volume(r.down)+L"/s     ↑ "+volume(r.up)+L"/s":L"实时读写  读 "+volume(r.read)+L"/s     写 "+volume(r.write)+L"/s",24,308,480,25,13);
  }else{
   text(L"磁盘自身报告的指标",24,116,470,25,16,D2D1::ColorF(0x233044),true);float y=160;
   if(model->health.empty())text(L"正在读取，或系统未提供可访问的磁盘。",24,y,470,30,13);
   for(auto& d:model->health){text(d.name,24,y,470,28,15,D2D1::ColorF(0x233044),true);y+=32;
    for(auto& field:std::vector<std::pair<std::wstring,std::wstring>>{{L"连接 / 状态",d.bus+L" / "+d.status},{L"温度",d.temperature},{L"耐久度已用",d.wear},{L"累计主机读取",d.read},{L"累计主机写入",d.write},{L"通电时间",d.hours},{L"介质错误",d.errors}}){text(field.first,24,y,180,24,13,D2D1::ColorF(0x617086));text(field.second,205,y,290,24,13);y+=29;}y+=22;if(y>580)break;
   }
   text(L"未提供 ≠ 0；耐久度已用不等于剩余寿命。",24,600,480,25,12,D2D1::ColorF(0x617086));
  }
  std::wstring foot;
  if(!model->saved||!model->store.ok())foot=L"历史保存失败："+model->store.error();
  else if(model->collector.lost)foot=L"ETW 丢失事件："+std::to_wstring(model->collector.lost.load());
  else foot=page==0?L"网卡总量独立统计；应用与代理不可相加。":L"运行后开始统计；进程归属可能不完整。";
  text(foot,24,static_cast<float>(rc.bottom-33),470,23,11,D2D1::ColorF(0x617086));
  if(target->EndDraw()==D2DERR_RECREATE_TARGET)releaseTarget();
 }EndPaint(window,&ps);
}
HWND control(const wchar_t* cls,const wchar_t* title,DWORD style,int x,int y,int w,int h,int id){HWND c=CreateWindowExW(0,cls,title,WS_CHILD|WS_VISIBLE|WS_TABSTOP|style,x,y,w,h,window,reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),GetModuleHandleW(nullptr),nullptr);SendMessageW(c,WM_SETFONT,reinterpret_cast<WPARAM>(font),TRUE);return c;}
void columns(){while(ListView_DeleteColumn(list,0));
 std::vector<std::pair<const wchar_t*,int>> cols={{L"进程",194},{page==0?L"总流量":L"写入",88},{page==0?L"下载":L"读取",88},{page==0?L"上传":L"总读写",88}};
 for(int i=0;i<4;++i){LVCOLUMNW c{};c.mask=LVCF_TEXT|LVCF_WIDTH|LVCF_FMT;c.pszText=const_cast<wchar_t*>(cols[i].first);c.cx=cols[i].second;c.fmt=i?LVCFMT_RIGHT:LVCFMT_LEFT;ListView_InsertColumn(list,i,&c);}
}
void updateList(){
 if(!IsWindowVisible(window)||page==2)return;std::lock_guard g(model->mutex);
 auto rows=model->rows(since(),page==1,page==0?static_cast<int>(SendMessageW(proxyBox,CB_GETCURSEL,0,0)):-1);
 if(period==1){rows=model->store.rows(since(),until(),page==1,page==0?static_cast<int>(SendMessageW(proxyBox,CB_GETCURSEL,0,0)):-1);std::map<std::wstring,Row> m;for(auto& r:rows)m[r.key]=r;for(auto& [k,p]:model->pending)if(k.first==since())for(auto& [name,r]:p.rows)if(page==1||r.proxy==(SendMessageW(proxyBox,CB_GETCURSEL,0,0)!=0)){auto& a=m[name];a.key=r.key;a.name=r.name;a.bytes.merge(r.bytes);}rows.clear();for(auto& [k,r]:m)if(r.bytes.total(page==1))rows.push_back(r);}
 auto metric=[](const Row& r){if(page==0)return sortColumn==2?r.bytes.down:sortColumn==3?r.bytes.up:r.bytes.total(false);return sortColumn==2?r.bytes.read:sortColumn==3?r.bytes.total(true):r.bytes.write;};
 std::sort(rows.begin(),rows.end(),[&](auto& a,auto& b){if(sortColumn==0)return descending?a.name>b.name:a.name<b.name;return descending?metric(a)>metric(b):metric(a)<metric(b);});
 wchar_t query[256];GetWindowTextW(search,query,256);std::wstring q=query;std::transform(q.begin(),q.end(),q.begin(),::towlower);
 SendMessageW(list,WM_SETREDRAW,FALSE,0);ListView_DeleteAllItems(list);int i=0;
 for(auto& r:rows){std::wstring name=r.name;std::transform(name.begin(),name.end(),name.begin(),::towlower);if(!q.empty()&&name.find(q)==std::wstring::npos)continue;
  LVITEMW item{};item.mask=LVIF_TEXT;item.iItem=i;item.pszText=r.name.data();ListView_InsertItem(list,&item);
  auto values=page==0?std::vector<uint64_t>{r.bytes.total(false),r.bytes.down,r.bytes.up}:std::vector<uint64_t>{r.bytes.write,r.bytes.read,r.bytes.total(true)};
  for(int c=1;c<=3;++c){auto v=volume(values[c-1]);ListView_SetItemText(list,i,c,v.data());}++i;
 }SendMessageW(list,WM_SETREDRAW,TRUE,0);InvalidateRect(list,nullptr,FALSE);
}
void updateTray(){std::lock_guard g(model->mutex);std::wstring t=L"流量喵 · "+std::wstring(model->collector.paused?L"已暂停":L"记录中")+L"\n↓ "+volume(model->rates.down)+L"/s  ↑ "+volume(model->rates.up)+L"/s\n读 "+volume(model->rates.read)+L"/s  写 "+volume(model->rates.write)+L"/s";wcsncpy_s(tray.szTip,t.c_str(),_TRUNCATE);Shell_NotifyIconW(NIM_MODIFY,&tray);}
void switchPage(int p){page=p;bool stats=page!=2;for(HWND c:{list,search,periodBox,exportButton})ShowWindow(c,stats?SW_SHOW:SW_HIDE);ShowWindow(proxyBox,page==0?SW_SHOW:SW_HIDE);columns();updateList();for(HWND c:{netButton,diskButton,healthButton})InvalidateRect(c,nullptr,TRUE);InvalidateRect(window,nullptr,FALSE);}
void showPanel(){POINT cursor;GetCursorPos(&cursor);HMONITOR monitor=MonitorFromPoint(cursor,MONITOR_DEFAULTTONEAREST);MONITORINFO info{sizeof(info)};GetMonitorInfoW(monitor,&info);int width=520,height=std::min(740L,info.rcWork.bottom-info.rcWork.top-16);int x=std::clamp(cursor.x-width+20,info.rcWork.left+8,info.rcWork.right-width-8);int y=info.rcWork.bottom-height-8;
 SetWindowPos(window,HWND_TOPMOST,x,y,width,height,SWP_SHOWWINDOW);SetForegroundWindow(window);panel=true;updateList();InvalidateRect(window,nullptr,FALSE);}
void exportCSV(){wchar_t path[MAX_PATH]=L"FlowCat.csv";OPENFILENAMEW of{sizeof(of)};of.hwndOwner=window;of.lpstrFilter=L"CSV 文件\0*.csv\0\0";of.lpstrFile=path;of.nMaxFile=MAX_PATH;of.Flags=OFN_OVERWRITEPROMPT|OFN_PATHMUSTEXIST;of.lpstrDefExt=L"csv";dialogOpen=true;bool chosen=GetSaveFileNameW(&of)!=FALSE;dialogOpen=false;if(chosen){model->flush();std::lock_guard g(model->mutex);if(!model->store.csv(path,since(),until()))MessageBoxW(window,L"导出失败，请检查历史状态和目标目录。",L"流量喵",MB_ICONERROR);}}
void togglePause(){model->collector.setPaused(!model->collector.paused);SetWindowTextW(pauseButton,model->collector.paused?L"继续记录":L"暂停记录");InvalidateRect(window,nullptr,FALSE);updateTray();}
LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){switch(m){
 case WM_CREATE:{window=h;font=CreateFontW(-14,0,0,0,FW_NORMAL,FALSE,FALSE,FALSE,DEFAULT_CHARSET,OUT_DEFAULT_PRECIS,CLIP_DEFAULT_PRECIS,CLEARTYPE_QUALITY,DEFAULT_PITCH,L"Segoe UI");
  netButton=control(L"BUTTON",L"网络",BS_OWNERDRAW,20,66,110,34,101);diskButton=control(L"BUTTON",L"磁盘读写",BS_OWNERDRAW,138,66,110,34,102);healthButton=control(L"BUTTON",L"磁盘状态",BS_OWNERDRAW,256,66,110,34,103);
  pauseButton=control(L"BUTTON",L"暂停记录",BS_OWNERDRAW,380,66,120,34,104);
  periodBox=control(L"COMBOBOX",L"",CBS_DROPDOWNLIST|WS_VSCROLL,20,112,136,200,105);for(auto s:{L"今日",L"昨日",L"近 7 天",L"近 30 天",L"累计"})SendMessageW(periodBox,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(s));SendMessageW(periodBox,CB_SETCURSEL,0,0);
  proxyBox=control(L"COMBOBOX",L"",CBS_DROPDOWNLIST,364,112,136,120,106);for(auto s:{L"应用排行",L"代理排行"})SendMessageW(proxyBox,CB_ADDSTRING,0,reinterpret_cast<LPARAM>(s));SendMessageW(proxyBox,CB_SETCURSEL,0,0);
  search=control(L"EDIT",L"",WS_BORDER|ES_AUTOHSCROLL,20,344,360,30,107);SendMessageW(search,EM_SETCUEBANNER,TRUE,reinterpret_cast<LPARAM>(L"搜索进程"));
  exportButton=control(L"BUTTON",L"导出 CSV",BS_OWNERDRAW,390,344,110,30,108);
  list=control(WC_LISTVIEWW,L"",LVS_REPORT|LVS_SINGLESEL|LVS_SHOWSELALWAYS,20,386,480,280,109);ListView_SetExtendedListViewStyle(list,LVS_EX_FULLROWSELECT|LVS_EX_DOUBLEBUFFER);SetWindowTheme(list,L"Explorer",nullptr);HIMAGELIST rows=ImageList_Create(1,27,ILC_COLOR32,1,1);ListView_SetImageList(list,rows,LVSIL_SMALL);columns();return 0;}
 case WM_DRAWITEM:{auto* item=reinterpret_cast<DRAWITEMSTRUCT*>(l);if(item->CtlType!=ODT_BUTTON)return DefWindowProcW(h,m,w,l);bool chosen=(item->CtlID==101&&page==0)||(item->CtlID==102&&page==1)||(item->CtlID==103&&page==2);bool pressed=(item->itemState&ODS_SELECTED)!=0;RECT r=item->rcItem;HBRUSH bg=CreateSolidBrush(pressed?RGB(224,232,243):chosen?RGB(255,255,255):RGB(239,242,247));FillRect(item->hDC,&r,bg);DeleteObject(bg);SetBkMode(item->hDC,TRANSPARENT);SetTextColor(item->hDC,chosen?RGB(38,99,235):RGB(55,67,85));SelectObject(item->hDC,font);wchar_t label[64];GetWindowTextW(item->hwndItem,label,64);DrawTextW(item->hDC,label,-1,&r,DT_CENTER|DT_VCENTER|DT_SINGLELINE);if(chosen){RECT line=r;line.top=line.bottom-2;HBRUSH accent=CreateSolidBrush(RGB(38,99,235));FillRect(item->hDC,&line,accent);DeleteObject(accent);}if(item->itemState&ODS_FOCUS){InflateRect(&r,-3,-3);DrawFocusRect(item->hDC,&r);}return TRUE;}
 case WM_PAINT:paint();return 0;
 case WM_SIZE:releaseTarget();{RECT r;GetClientRect(h,&r);MoveWindow(list,20,386,std::max(1L,r.right-40),std::max(40L,r.bottom-430),TRUE);}return 0;
 case WM_ERASEBKGND:return 1;
 case WM_ACTIVATE:if(LOWORD(w)==WA_INACTIVE&&panel&&!dialogOpen){ShowWindow(h,SW_HIDE);panel=false;}return 0;
 case WM_QUERYENDSESSION:model->flush();return TRUE;
 case WM_ENDSESSION:if(w)PostQuitMessage(0);return 0;
 case WM_CLOSE:ShowWindow(h,SW_HIDE);panel=false;return 0;
 case WM_COMMAND:{int id=LOWORD(w);if(id==101)switchPage(0);if(id==102)switchPage(1);if(id==103)switchPage(2);if(id==104)togglePause();if(id==105&&HIWORD(w)==CBN_SELCHANGE){period=static_cast<int>(SendMessageW(periodBox,CB_GETCURSEL,0,0));updateList();InvalidateRect(h,nullptr,FALSE);}if(id==106&&HIWORD(w)==CBN_SELCHANGE)updateList();if(id==107&&HIWORD(w)==EN_CHANGE)updateList();if(id==108)exportCSV();if(id==201)showPanel();if(id==202)togglePause();if(id==203)PostQuitMessage(0);return 0;}
 case WM_NOTIFY:{auto* n=reinterpret_cast<NMHDR*>(l);if(n->hwndFrom==list&&n->code==LVN_COLUMNCLICK){int col=reinterpret_cast<NMLISTVIEW*>(l)->iSubItem;if(sortColumn==col)descending=!descending;else{sortColumn=col;descending=true;}updateList();}return 0;}
 case TRAY:if(LOWORD(l)==WM_LBUTTONUP||LOWORD(l)==NIN_SELECT){if(IsWindowVisible(h)){ShowWindow(h,SW_HIDE);panel=false;}else showPanel();}else if(LOWORD(l)==WM_RBUTTONUP||LOWORD(l)==WM_CONTEXTMENU){HMENU menu=CreatePopupMenu();AppendMenuW(menu,MF_STRING,201,L"打开流量喵");AppendMenuW(menu,MF_STRING,202,model->collector.paused?L"继续记录":L"暂停记录");AppendMenuW(menu,MF_SEPARATOR,0,nullptr);AppendMenuW(menu,MF_STRING,203,L"退出");POINT p;GetCursorPos(&p);SetForegroundWindow(h);TrackPopupMenu(menu,TPM_RIGHTBUTTON,p.x,p.y,0,h,nullptr);DestroyMenu(menu);PostMessageW(h,WM_NULL,0,0);}return 0;
 case TICK:updateTray();if(IsWindowVisible(h)){updateList();InvalidateRect(h,nullptr,FALSE);}return 0;
 case WM_DESTROY:PostQuitMessage(0);return 0;
 default:return DefWindowProcW(h,m,w,l);
 }}
HICON catIcon(){
 constexpr int n=32;BITMAPV5HEADER bi{};bi.bV5Size=sizeof(bi);bi.bV5Width=n;bi.bV5Height=-n;bi.bV5Planes=1;bi.bV5BitCount=32;bi.bV5Compression=BI_BITFIELDS;bi.bV5RedMask=0xff0000;bi.bV5GreenMask=0xff00;bi.bV5BlueMask=0xff;bi.bV5AlphaMask=0xff000000;
 void* pixels=nullptr;HDC dc=CreateCompatibleDC(nullptr);HBITMAP color=CreateDIBSection(dc,reinterpret_cast<BITMAPINFO*>(&bi),DIB_RGB_COLORS,&pixels,nullptr,0);auto old=SelectObject(dc,color);memset(pixels,0,n*n*4);HPEN pen=CreatePen(PS_SOLID,2,RGB(38,99,235));auto oldPen=SelectObject(dc,pen);auto oldBrush=SelectObject(dc,GetStockObject(HOLLOW_BRUSH));POINT points[]={{7,14},{6,5},{13,10},{19,10},{26,5},{25,14},{28,19},{25,25},{20,28},{12,28},{7,25},{4,19},{7,14}};Polyline(dc,points,13);for(int x=11;x<=21;x+=5){MoveToEx(dc,x,22,nullptr);LineTo(dc,x,22-(x-6)/2);}
 auto* p=static_cast<DWORD*>(pixels);for(int i=0;i<n*n;++i)if(p[i]&0xffffff)p[i]|=0xff000000;
 SelectObject(dc,oldBrush);SelectObject(dc,oldPen);SelectObject(dc,old);DeleteObject(pen);DeleteDC(dc);HBITMAP mask=CreateBitmap(n,n,1,1,nullptr);ICONINFO ii{};ii.fIcon=TRUE;ii.hbmColor=color;ii.hbmMask=mask;HICON result=CreateIconIndirect(&ii);DeleteObject(color);DeleteObject(mask);return result;
}
std::string utf8(const std::wstring& s){int n=WideCharToMultiByte(CP_UTF8,0,s.data(),static_cast<int>(s.size()),nullptr,0,nullptr,nullptr);std::string b(n,0);WideCharToMultiByte(CP_UTF8,0,s.data(),static_cast<int>(s.size()),b.data(),n,nullptr,nullptr);return b;}
std::string json(const std::wstring& s){std::string out="\"";for(unsigned char c:utf8(s)){if(c=='"'||c=='\\')out+='\\';if(c>=32)out+=c;}return out+'"';}
int diagnostics(int seconds,const std::wstring& report,const std::wstring& dir){
 Model m(dir);if(!m.collector.start())return static_cast<int>(m.collector.error.load());auto health=diskHealth();
 auto begin=GetTickCount64();while(GetTickCount64()-begin<static_cast<ULONGLONG>(seconds)*1000){Sleep(2000);m.sample();}m.collector.stop();m.sample();m.flush();
 PROCESS_MEMORY_COUNTERS pm{};GetProcessMemoryInfo(GetCurrentProcess(),&pm,sizeof(pm));std::ofstream f(std::filesystem::path(report),std::ios::binary);std::lock_guard g(m.mutex);
 f<<"{\"version\":\"0.1.0-preview\",\"events\":"<<m.collector.eventCount<<",\"parseErrors\":"<<m.collector.parseErrors<<",\"unattributedDisk\":"<<m.collector.unattributedDisk<<",\"lostEvents\":"<<m.collector.lost<<",\"workingSetBytes\":"<<pm.WorkingSetSize<<",\"privateBytes\":"<<pm.PagefileUsage<<",\"saved\":"<<(m.saved?"true":"false")<<",\"network\":"<<json(m.network)<<",\"physicalBytes\":"<<m.store.physical(dayKey(),dayKey()).total(false)<<",\"processes\":[";
 auto rows=m.store.rows(dayKey(),dayKey(),true);auto net=m.store.rows(dayKey(),dayKey(),false);std::map<std::wstring,Row> all;for(auto& r:rows)all[r.key]=r;for(auto& r:net)all[r.key]=r;bool first=true;for(auto& [k,r]:all){if(!first)f<<',';first=false;f<<"{\"name\":"<<json(r.name)<<",\"download\":"<<r.bytes.down<<",\"upload\":"<<r.bytes.up<<",\"read\":"<<r.bytes.read<<",\"write\":"<<r.bytes.write<<'}';}
 f<<"],\"disks\":[";first=true;for(auto& d:health){if(!first)f<<',';first=false;f<<"{\"name\":"<<json(d.name)<<",\"status\":"<<json(d.status)<<",\"temperature\":"<<json(d.temperature)<<",\"wear\":"<<json(d.wear)<<",\"write\":"<<json(d.write)<<",\"hours\":"<<json(d.hours)<<'}';}f<<"]}";return m.saved?0:2;
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR,int){
 int argc=0;auto argv=CommandLineToArgvW(GetCommandLineW(),&argc);std::wstring dir=dataDirectory(),report;int seconds=0;bool show=false;int initialPage=0;
 for(int i=1;i<argc;++i){std::wstring a=argv[i];if(a==L"--diagnostics"&&i+1<argc)seconds=_wtoi(argv[++i]);else if(a==L"--report"&&i+1<argc)report=argv[++i];else if(a==L"--data-dir"&&i+1<argc)dir=argv[++i];else if(a==L"--show")show=true;else if(a==L"--page"&&i+1<argc)initialPage=std::clamp(_wtoi(argv[++i]),0,2);}LocalFree(argv);
 if(seconds>0&&!report.empty())return diagnostics(std::min(seconds,600),report,dir);
 HANDLE singleton=CreateMutexW(nullptr,TRUE,L"Local\\FlowCat.Windows.Preview");if(GetLastError()==ERROR_ALREADY_EXISTS){if(singleton)CloseHandle(singleton);return 0;}
 CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);INITCOMMONCONTROLSEX common{sizeof(common),ICC_LISTVIEW_CLASSES};InitCommonControlsEx(&common);
 D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,&d2d);DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),reinterpret_cast<IUnknown**>(&dwrite));if(!d2d||!dwrite)return 3;
 model=std::make_unique<Model>(dir);icon=catIcon();WNDCLASSW wc{};wc.lpfnWndProc=proc;wc.hInstance=instance;wc.lpszClassName=L"FlowCatPanel";wc.hCursor=LoadCursorW(nullptr,IDC_ARROW);wc.hIcon=icon;RegisterClassW(&wc);
 window=CreateWindowExW(WS_EX_TOOLWINDOW|WS_EX_TOPMOST,wc.lpszClassName,L"流量喵 Windows 预览版",WS_POPUP|WS_BORDER,0,0,520,740,nullptr,nullptr,instance,nullptr);
 tray.cbSize=sizeof(tray);tray.hWnd=window;tray.uID=1;tray.uFlags=NIF_ICON|NIF_MESSAGE|NIF_TIP;tray.uCallbackMessage=TRAY;tray.hIcon=icon;wcscpy_s(tray.szTip,L"流量喵 · 正在启动");Shell_NotifyIconW(NIM_ADD,&tray);tray.uVersion=NOTIFYICON_VERSION_4;Shell_NotifyIconW(NIM_SETVERSION,&tray);
 model->start(window);switchPage(initialPage);if(show)showPanel();MSG msg;while(GetMessageW(&msg,nullptr,0,0)>0){if(!IsDialogMessageW(window,&msg)){TranslateMessage(&msg);DispatchMessageW(&msg);}}
 model->stop();Shell_NotifyIconW(NIM_DELETE,&tray);model.reset();releaseTarget();dwrite->Release();d2d->Release();DestroyIcon(icon);DeleteObject(font);CoUninitialize();if(singleton)CloseHandle(singleton);return 0;
}
