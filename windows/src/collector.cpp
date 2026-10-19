#include "collector.h"
#include <tdh.h>
#include <objbase.h>
#include <tlhelp32.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>
#include <wlanapi.h>
#include <filesystem>
#include <ctime>
#include <cstring>
namespace fc {
static const GUID tcp={0x9a280ac0,0xc8e0,0x11d1,{0x84,0xe2,0x00,0xc0,0x4f,0xb9,0x98,0xa2}};
static const GUID udp={0xbf3a50c5,0xa9c9,0x4988,{0xa0,0x05,0x2d,0xf0,0xb7,0xc8,0x0f,0x80}};
static const GUID disk={0x3d6fa8d4,0xfe05,0x11d0,{0x9d,0xda,0x00,0xc0,0x4f,0xd7,0xba,0x7c}};
template<class T> bool property(EVENT_RECORD* r, const wchar_t* name,T& value) {
 PROPERTY_DATA_DESCRIPTOR p{}; p.PropertyName=reinterpret_cast<ULONGLONG>(name); p.ArrayIndex=ULONG_MAX;
 return TdhGetProperty(r,0,nullptr,1,&p,sizeof(T),reinterpret_cast<PBYTE>(&value))==ERROR_SUCCESS;
}
std::wstring dayKey(int offset) {
 std::time_t t=std::time(nullptr); std::tm tm{};localtime_s(&tm,&t);tm.tm_mday+=offset;tm.tm_hour=12;tm.tm_isdst=-1;std::mktime(&tm);
 wchar_t b[16];wcsftime(b,16,L"%Y-%m-%d",&tm);return b;
}
std::wstring currentNetwork() {
 HANDLE client=nullptr; DWORD version=0;
 if(WlanOpenHandle(2,nullptr,&version,&client)!=ERROR_SUCCESS)return L"全部网络";
 PWLAN_INTERFACE_INFO_LIST list=nullptr;std::wstring result=L"全部网络";
 if(WlanEnumInterfaces(client,nullptr,&list)==ERROR_SUCCESS) {
  for(DWORD i=0;i<list->dwNumberOfItems;++i){
   DWORD size=0;PWLAN_CONNECTION_ATTRIBUTES a=nullptr;WLAN_OPCODE_VALUE_TYPE type;
   if(WlanQueryInterface(client,&list->InterfaceInfo[i].InterfaceGuid,wlan_intf_opcode_current_connection,nullptr,&size,reinterpret_cast<PVOID*>(&a),&type)==ERROR_SUCCESS){
    if(a->isState==wlan_interface_state_connected){
     auto& s=a->wlanAssociationAttributes.dot11Ssid;int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,reinterpret_cast<const char*>(s.ucSSID),s.uSSIDLength,nullptr,0);
     if(n>0){result.resize(n);MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,reinterpret_cast<const char*>(s.ucSSID),s.uSSIDLength,result.data(),n);}
    }WlanFreeMemory(a);
   }
  }WlanFreeMemory(list);
 }WlanCloseHandle(client,nullptr);return result;
}
Collector::Collector() { physical(); refreshProcesses(); }
Collector::~Collector() {stop();}
bool Collector::start() {
 FILETIME started;GetSystemTimeAsFileTime(&started);LARGE_INTEGER stamp;stamp.LowPart=started.dwLowDateTime;stamp.HighPart=started.dwHighDateTime;cutoff_=stamp.QuadPart;
 HANDLE token=nullptr;if(OpenProcessToken(GetCurrentProcess(),TOKEN_ADJUST_PRIVILEGES|TOKEN_QUERY,&token)){
  TOKEN_PRIVILEGES p{};p.PrivilegeCount=1;LookupPrivilegeValueW(nullptr,SE_SYSTEM_PROFILE_NAME,&p.Privileges[0].Luid);p.Privileges[0].Attributes=SE_PRIVILEGE_ENABLED;AdjustTokenPrivileges(token,FALSE,&p,0,nullptr,nullptr);CloseHandle(token);
 }
 sessionName_=L"FlowCat-"+std::to_wstring(GetCurrentProcessId());
 props_.resize(sizeof(EVENT_TRACE_PROPERTIES)+(sessionName_.size()+1)*sizeof(wchar_t));
 auto* p=reinterpret_cast<EVENT_TRACE_PROPERTIES*>(props_.data());
 p->Wnode.BufferSize=static_cast<ULONG>(props_.size());CoCreateGuid(&p->Wnode.Guid);p->Wnode.ClientContext=2;p->Wnode.Flags=WNODE_FLAG_TRACED_GUID;
 p->BufferSize=64;p->MinimumBuffers=4;p->MaximumBuffers=16;p->FlushTimer=1;
 p->LogFileMode=EVENT_TRACE_REAL_TIME_MODE|EVENT_TRACE_SYSTEM_LOGGER_MODE;
 p->EnableFlags=EVENT_TRACE_FLAG_NETWORK_TCPIP|EVENT_TRACE_FLAG_DISK_IO|EVENT_TRACE_FLAG_DISK_IO_INIT;
 p->LoggerNameOffset=sizeof(EVENT_TRACE_PROPERTIES);
 ULONG status=StartTraceW(&session_,sessionName_.c_str(),p);error=status;if(status!=ERROR_SUCCESS){session_=0;return false;}
 EVENT_TRACE_LOGFILEW trace{};trace.LoggerName=sessionName_.data();trace.ProcessTraceMode=PROCESS_TRACE_MODE_REAL_TIME|PROCESS_TRACE_MODE_EVENT_RECORD;trace.EventRecordCallback=callback;trace.Context=this;
 consumer_=OpenTraceW(&trace);if(consumer_==INVALID_PROCESSTRACE_HANDLE){error=GetLastError();stop();return false;}
 consumerThread_=std::thread([this]{auto result=ProcessTrace(&consumer_,1,nullptr,nullptr);if(result!=ERROR_SUCCESS && result!=ERROR_CANCELLED)error=result;});return true;
}
void Collector::setPaused(bool value){
 FILETIME now;GetSystemTimeAsFileTime(&now);LARGE_INTEGER stamp;stamp.LowPart=now.dwLowDateTime;stamp.HighPart=now.dwHighDateTime;cutoff_=stamp.QuadPart;resetPhysical_=true;paused=value;
}
void Collector::stop(){
 if(session_){ControlTraceW(session_,sessionName_.c_str(),reinterpret_cast<EVENT_TRACE_PROPERTIES*>(props_.data()),EVENT_TRACE_CONTROL_STOP);session_=0;}
 if(consumer_!=INVALID_PROCESSTRACE_HANDLE){CloseTrace(consumer_);consumer_=INVALID_PROCESSTRACE_HANDLE;}
 if(consumerThread_.joinable())consumerThread_.join();
}
void Collector::refreshProcesses(){
 std::map<DWORD,Row> found;std::map<DWORD,DWORD> threads;
 HANDLE s=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS|TH32CS_SNAPTHREAD,0);if(s==INVALID_HANDLE_VALUE)return;
 PROCESSENTRY32W p{};p.dwSize=sizeof(p);
 if(Process32FirstW(s,&p))do{
  Row r;r.name=p.szExeFile;r.proxy=relay(r.name);r.key=r.name;
  HANDLE h=OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION,FALSE,p.th32ProcessID);
  if(h){wchar_t path[32768];DWORD n=32768;if(QueryFullProcessImageNameW(h,0,path,&n))r.key.assign(path,n);CloseHandle(h);}
  std::transform(r.key.begin(),r.key.end(),r.key.begin(),::towlower);found[p.th32ProcessID]=r;
 }while(Process32NextW(s,&p));
 THREADENTRY32 t{};t.dwSize=sizeof(t);if(Thread32First(s,&t))do{threads[t.th32ThreadID]=t.th32OwnerProcessID;}while(Thread32Next(s,&t));CloseHandle(s);
 std::lock_guard guard(lock_);processes_=std::move(found);threads_=std::move(threads);
}
void WINAPI Collector::callback(EVENT_RECORD* r){static_cast<Collector*>(r->UserContext)->event(r);}
void Collector::event(EVENT_RECORD* r){
 if(paused||r->EventHeader.TimeStamp.QuadPart<cutoff_.load())return;
 auto& g=r->EventHeader.ProviderId;UCHAR op=r->EventHeader.EventDescriptor.Opcode;DWORD pid=0;Bytes bytes;
 bool network=IsEqualGUID(g,tcp)||IsEqualGUID(g,udp);
 if(network){
  if(op!=10&&op!=11&&op!=26&&op!=27)return;
  DWORD size=0;if(!property(r,L"PID",pid)||!property(r,L"size",size)){++parseErrors;return;}
  if(op==10||op==11){DWORD source=0,dest=0;if(property(r,L"saddr",source)&&property(r,L"daddr",dest)){
   // IPv4 fields are network byte order. Exclude local loopback to avoid proxy hop duplication.
   if((source&0xff)==127||(dest&0xff)==127)return;
  }}else{unsigned char src[16]{},dst[16]{};if(property(r,L"saddr",src)&&property(r,L"daddr",dst)){
   unsigned char loop[16]{};loop[15]=1;if(!memcmp(src,loop,16)||!memcmp(dst,loop,16))return;
  }}
  if(op==10||op==26)bytes.up=size;else bytes.down=size;
 }else if(IsEqualGUID(g,disk)){
  if(op!=10&&op!=11)return;
  DWORD size=0,tid=0;if(!property(r,L"TransferSize",size)||!property(r,L"IssuingThreadId",tid)){++parseErrors;return;}
  {std::lock_guard guard(lock_);auto it=threads_.find(tid);if(it!=threads_.end())pid=it->second;}
  if(!pid){HANDLE thread=OpenThread(THREAD_QUERY_LIMITED_INFORMATION,FALSE,tid);if(thread){pid=GetProcessIdOfThread(thread);CloseHandle(thread);}}
  if(!pid){++unattributedDisk;pid=0;}
  if(op==10)bytes.read=size;else bytes.write=size;
 }else return;
 std::lock_guard guard(lock_);Row row;auto it=processes_.find(pid);
 if(!network && pid==0){row.name=L"系统 / 未归属";row.key=L"disk:unattributed";}
 else if(it!=processes_.end())row=it->second;
 else{row.name=L"PID "+std::to_wstring(pid);row.key=sessionName_+L":pid:"+std::to_wstring(pid);}
 FILETIME utc{r->EventHeader.TimeStamp.LowPart,static_cast<DWORD>(r->EventHeader.TimeStamp.HighPart)},local{};SYSTEMTIME calendar{};FileTimeToLocalFileTime(&utc,&local);FileTimeToSystemTime(&local,&calendar);wchar_t date[16];swprintf(date,16,L"%04u-%02u-%02u",calendar.wYear,calendar.wMonth,calendar.wDay);row.day=date;
 auto& pending=pending_[row.day+L"|"+row.key];if(pending.key.empty()){pending.key=row.key;pending.name=row.name;pending.proxy=row.proxy;pending.day=row.day;}pending.bytes.merge(bytes);++eventCount;
}
Bytes Collector::physical(){
 Bytes out;PMIB_IF_TABLE2 table=nullptr;std::map<ULONG64,std::pair<uint64_t,uint64_t>> current;
 auto now=GetTickCount64();bool gap=lastPhysical_ && now-lastPhysical_>15000;
 if(GetIfTable2(&table)==NO_ERROR){for(ULONG i=0;i<table->NumEntries;++i){auto& r=table->Table[i];
  if(!r.InterfaceAndOperStatusFlags.HardwareInterface || r.OperStatus!=IfOperStatusUp || (r.Type!=IF_TYPE_ETHERNET_CSMACD && r.Type!=IF_TYPE_IEEE80211))continue;
  auto key=r.InterfaceLuid.Value;current[key]={r.InOctets,r.OutOctets};auto it=interfaces_.find(key);
  if(it!=interfaces_.end()&&!gap&&!resetPhysical_.load()){out.down=add(out.down,delta(r.InOctets,it->second.first));out.up=add(out.up,delta(r.OutOctets,it->second.second));}
 }FreeMibTable(table);interfaces_=std::move(current);lastPhysical_=now;resetPhysical_=false;}
 return out;
}
Batch Collector::take(){
 if(GetTickCount64()-lastRefresh_>5000){refreshProcesses();lastRefresh_=GetTickCount64();}
 Batch b;b.network=currentNetwork();b.physical=physical();b.events=eventCount;
 {std::lock_guard guard(lock_);for(auto& [key,row]:pending_)b.rows.push_back(std::move(row));pending_.clear();}
 if(paused){b.rows.clear();b.physical={};}
 if(session_){std::vector<unsigned char> p=props_;if(ControlTraceW(session_,sessionName_.c_str(),reinterpret_cast<EVENT_TRACE_PROPERTIES*>(p.data()),EVENT_TRACE_CONTROL_QUERY)==ERROR_SUCCESS)lost=reinterpret_cast<EVENT_TRACE_PROPERTIES*>(p.data())->EventsLost;}
 return b;
}
}
