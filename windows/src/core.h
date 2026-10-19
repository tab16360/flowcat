#pragma once
#include <algorithm>
#include <cstdint>
#include <limits>
#include <cwchar>
#include <cwctype>
#include <string>
#include <vector>
namespace fc {
inline uint64_t add(uint64_t a, uint64_t b) { return b > UINT64_MAX-a ? UINT64_MAX : a+b; }
struct Bytes {
 uint64_t down=0, up=0, read=0, write=0;
 void merge(const Bytes& b) { down=add(down,b.down);up=add(up,b.up);read=add(read,b.read);write=add(write,b.write); }
 uint64_t total(bool disk) const { return disk ? add(read,write) : add(down,up); }
};
inline uint64_t delta(uint64_t now,uint64_t before) { return now>=before ? now-before : 0; }
inline std::wstring volume(uint64_t n) {
 static const wchar_t* units[]={L"B",L"KB",L"MB",L"GB",L"TB",L"PB"};
 double v=static_cast<double>(n); int i=0; while(v>=1000 && i<5) {v/=1000;++i;}
 wchar_t b[64]; swprintf(b,64,i ? L"%.2f %ls" : L"%.0f %ls",v,units[i]); return b;
}
inline bool relay(std::wstring name) {
 std::transform(name.begin(),name.end(),name.begin(),::towlower);
 const std::vector<std::wstring> names={L"mihomo.exe",L"verge-mihomo.exe",L"clash.exe",L"clash-meta.exe",L"sing-box.exe",L"tailscaled.exe",L"tailscale-ipn.exe",L"xray.exe",L"v2ray.exe"};
 return std::find(names.begin(),names.end(),name)!=names.end();
}
struct Row { std::wstring key,name; Bytes bytes; bool proxy=false; std::wstring day; };
}
