#include "store.h"
#include <shlobj.h>
#include <filesystem>
#include <fstream>
#include <climits>
namespace fc {
std::wstring dataDirectory(){PWSTR p=nullptr;std::wstring result;if(SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&p))){result=std::wstring(p)+L"\\FlowCat";CoTaskMemFree(p);}return result;}
Store::Store(const std::wstring& directory){
 std::error_code ec;std::filesystem::create_directories(directory,ec);if(ec){error_=L"无法创建历史目录";return;}
 dll_=LoadLibraryExW(L"winsqlite3.dll",nullptr,LOAD_LIBRARY_SEARCH_SYSTEM32);if(!dll_){error_=L"系统 SQLite 不可用";return;}
#define LOAD(member,symbol) member=reinterpret_cast<decltype(member)>(GetProcAddress(dll_,symbol));if(!member){error_=L"系统 SQLite 接口不可用";return;}
 LOAD(open16_,"sqlite3_open16") LOAD(close_,"sqlite3_close") LOAD(exec_,"sqlite3_exec") LOAD(prepare_,"sqlite3_prepare_v2") LOAD(bindText_,"sqlite3_bind_text16") LOAD(bindInt_,"sqlite3_bind_int64") LOAD(step_,"sqlite3_step") LOAD(finalize_,"sqlite3_finalize") LOAD(text_,"sqlite3_column_text16") LOAD(integer_,"sqlite3_column_int64")
#undef LOAD
 if(open16_((directory+L"\\history.sqlite").c_str(),&db_)!=0){error_=L"无法打开历史数据库";return;}
 // A small busy timeout plus transactions keeps writes infrequent and recoverable.
 exec("PRAGMA busy_timeout=2000; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;");
 auto* version=prepare("PRAGMA user_version");int schema=-1;if(version){if(step_(version)==100)schema=static_cast<int>(integer_(version,0));finalize_(version);}
 if(schema>1){error_=L"历史来自更新的版本，已停止写入";return;}
 exec("CREATE TABLE IF NOT EXISTS usage(day TEXT NOT NULL,network TEXT NOT NULL,key TEXT NOT NULL,name TEXT NOT NULL,proxy INTEGER NOT NULL,down INTEGER NOT NULL,up INTEGER NOT NULL,rd INTEGER NOT NULL,wr INTEGER NOT NULL,PRIMARY KEY(day,network,key));CREATE TABLE IF NOT EXISTS physical(day TEXT NOT NULL,network TEXT NOT NULL,down INTEGER NOT NULL,up INTEGER NOT NULL,PRIMARY KEY(day,network));PRAGMA user_version=1;");
}
Store::~Store(){if(db_&&close_)close_(db_);if(dll_)FreeLibrary(dll_);}
bool Store::exec(const char* sql){if(!db_||exec_(db_,sql,nullptr,nullptr,nullptr)!=0){error_=L"历史读写失败，已停止保存";return false;}return true;}
sqlite3_stmt* Store::prepare(const char* sql){sqlite3_stmt* s=nullptr;if(!db_||prepare_(db_,sql,-1,&s,nullptr)!=0){error_=L"历史查询失败";return nullptr;}return s;}
void Store::text(sqlite3_stmt* s,int i,const std::wstring& v){bindText_(s,i,v.c_str(),-1,reinterpret_cast<void(*)(void*)>(-1));}
bool Store::done(sqlite3_stmt* s){bool good=step_(s)==101;finalize_(s);if(!good)error_=L"历史写入失败，已停止保存";return good;}
static int64_t bounded(uint64_t v){return static_cast<int64_t>(std::min(v,static_cast<uint64_t>(INT64_MAX)));}
bool Store::put(const std::wstring& day,const std::wstring& network,const std::vector<Row>& rows,const Bytes& physical){
 if(!ok()||!exec("BEGIN IMMEDIATE"))return false;
 bool good=true;
 for(auto& r:rows){auto* s=prepare("INSERT INTO usage VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(day,network,key) DO UPDATE SET down=MIN(9223372036854775807,down+excluded.down),up=MIN(9223372036854775807,up+excluded.up),rd=MIN(9223372036854775807,rd+excluded.rd),wr=MIN(9223372036854775807,wr+excluded.wr)");if(!s){good=false;break;}
  text(s,1,day);text(s,2,network);text(s,3,r.key);text(s,4,r.name);bindInt_(s,5,r.proxy);bindInt_(s,6,bounded(r.bytes.down));bindInt_(s,7,bounded(r.bytes.up));bindInt_(s,8,bounded(r.bytes.read));bindInt_(s,9,bounded(r.bytes.write));good=done(s);if(!good)break;
 }
 if(good){auto* s=prepare("INSERT INTO physical VALUES(?,?,?,?) ON CONFLICT(day,network) DO UPDATE SET down=MIN(9223372036854775807,down+excluded.down),up=MIN(9223372036854775807,up+excluded.up)");if(s){text(s,1,day);text(s,2,network);bindInt_(s,3,bounded(physical.down));bindInt_(s,4,bounded(physical.up));good=done(s);}else good=false;}
 if(good)return exec("COMMIT");exec("ROLLBACK");return false;
}
std::vector<Row> Store::rows(const std::wstring& since,const std::wstring& until,bool disk,int proxy){
 std::vector<Row> out;if(!ok())return out;
 auto* s=prepare("SELECT key,MAX(name),MAX(proxy),SUM(down),SUM(up),SUM(rd),SUM(wr) FROM usage WHERE day>=? AND day<=? GROUP BY key");if(!s)return out;text(s,1,since);text(s,2,until);
 while(step_(s)==100){Row r;r.key=static_cast<const wchar_t*>(text_(s,0));r.name=static_cast<const wchar_t*>(text_(s,1));r.proxy=integer_(s,2)!=0;r.bytes={static_cast<uint64_t>(integer_(s,3)),static_cast<uint64_t>(integer_(s,4)),static_cast<uint64_t>(integer_(s,5)),static_cast<uint64_t>(integer_(s,6))};if(r.bytes.total(disk)>0 && (disk||proxy<0||r.proxy==(proxy!=0)))out.push_back(r);}
 finalize_(s);std::sort(out.begin(),out.end(),[disk](auto& a,auto& b){return disk?a.bytes.write>b.bytes.write:a.bytes.total(false)>b.bytes.total(false);});return out;
}
Bytes Store::physical(const std::wstring& since,const std::wstring& until){Bytes b;if(!ok())return b;auto* s=prepare("SELECT SUM(down),SUM(up) FROM physical WHERE day>=? AND day<=?");if(!s)return b;text(s,1,since);text(s,2,until);if(step_(s)==100){b.down=static_cast<uint64_t>(integer_(s,0));b.up=static_cast<uint64_t>(integer_(s,1));}finalize_(s);return b;}
static std::string utf8(const std::wstring& s){int n=WideCharToMultiByte(CP_UTF8,0,s.c_str(),static_cast<int>(s.size()),nullptr,0,nullptr,nullptr);std::string b(n,'\0');WideCharToMultiByte(CP_UTF8,0,s.c_str(),static_cast<int>(s.size()),b.data(),n,nullptr,nullptr);return b;}
static std::string quote(std::wstring s){if(!s.empty()&&(s[0]==L'='||s[0]==L'+'||s[0]==L'-'||s[0]==L'@'))s=L"'"+s;std::string v=utf8(s),out="\"";for(char c:v){out+=c;if(c=='"')out+='"';}return out+'"';}
bool Store::csv(const std::wstring& path,const std::wstring& since,const std::wstring& until){
 if(!ok())return false;auto* s=prepare("SELECT day,network,name,proxy,down,up,rd,wr FROM usage WHERE day>=? AND day<=? ORDER BY day,name");if(!s)return false;text(s,1,since);text(s,2,until);std::ofstream f(std::filesystem::path(path),std::ios::binary);f<<"\xEF\xBB\xBF"<<"date,network,process,proxy,download_bytes,upload_bytes,read_bytes,write_bytes\r\n";
 while(step_(s)==100){for(int i=0;i<8;++i){if(i)f<<',';if(i<3)f<<quote(static_cast<const wchar_t*>(text_(s,i)));else f<<integer_(s,i);}f<<"\r\n";}finalize_(s);return f.good();
}
}
