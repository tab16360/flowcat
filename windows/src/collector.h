#pragma once
#include <winsock2.h>
#include <windows.h>
#include <evntrace.h>
#include <evntcons.h>
#include <atomic>
#include <map>
#include <mutex>
#include <thread>
#include "core.h"
namespace fc {
struct Batch { std::vector<Row> rows; Bytes physical; std::wstring network; uint64_t events=0; };
struct Collector {
 Collector(); ~Collector();
 bool start(); void stop(); Batch take(); void setPaused(bool value);
 std::atomic<bool> paused{false}; std::atomic<ULONG> error{0},lost{0}; std::atomic<uint64_t> eventCount{0},parseErrors{0},unattributedDisk{0};
 private:
 TRACEHANDLE session_=0, consumer_=INVALID_PROCESSTRACE_HANDLE;
 std::wstring sessionName_; std::vector<unsigned char> props_;
 std::thread consumerThread_; std::mutex lock_;
 std::map<DWORD,Row> processes_; std::map<DWORD,DWORD> threads_;
 std::map<std::wstring,Row> pending_;
 std::map<ULONG64,std::pair<uint64_t,uint64_t>> interfaces_;
 ULONGLONG lastRefresh_=0,lastPhysical_=0;
 std::atomic<LONGLONG> cutoff_{0}; std::atomic<bool> resetPhysical_{false};
 void refreshProcesses(); Bytes physical();
 void event(EVENT_RECORD* r);
 static void WINAPI callback(EVENT_RECORD* r);
};
std::wstring currentNetwork();
std::wstring dayKey(int offset=0);
}
