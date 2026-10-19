#pragma once
#include <windows.h>
#include <string>
#include <vector>
#include "core.h"
struct sqlite3;struct sqlite3_stmt;
namespace fc {
class Store {
 public:
 explicit Store(const std::wstring& directory); ~Store();
 Store(const Store&)=delete;Store& operator=(const Store&)=delete;
 bool ok() const {return db_!=nullptr && error_.empty();} std::wstring error() const{return error_;}
 bool put(const std::wstring& day,const std::wstring& network,const std::vector<Row>& rows,const Bytes& physical);
 std::vector<Row> rows(const std::wstring& since,const std::wstring& until,bool disk,int proxy=-1);
 Bytes physical(const std::wstring& since,const std::wstring& until);
 bool csv(const std::wstring& path,const std::wstring& since,const std::wstring& until);
 private:
 HMODULE dll_=nullptr;sqlite3* db_=nullptr;std::wstring error_;
 int (*open16_)(const void*,sqlite3**)=nullptr;
 int (*close_)(sqlite3*)=nullptr;
 int (*exec_)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**)=nullptr;
 int (*prepare_)(sqlite3*,const char*,int,sqlite3_stmt**,const char**)=nullptr;
 int (*bindText_)(sqlite3_stmt*,int,const void*,int,void(*)(void*))=nullptr;
 int (*bindInt_)(sqlite3_stmt*,int,int64_t)=nullptr;
 int (*step_)(sqlite3_stmt*)=nullptr;
 int (*finalize_)(sqlite3_stmt*)=nullptr;
 const void* (*text_)(sqlite3_stmt*,int)=nullptr;
 int64_t (*integer_)(sqlite3_stmt*,int)=nullptr;
 bool exec(const char* sql);sqlite3_stmt* prepare(const char* sql);
 void text(sqlite3_stmt*,int,const std::wstring&);bool done(sqlite3_stmt*);
};
std::wstring dataDirectory();
}
