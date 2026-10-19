#include <windows.h>
#include <winioctl.h>
#include <ntddstor.h>
#include <array>
#include <cstring>
#include "health.h"
#include "core.h"
namespace fc {
static std::wstring wide(const char* s){int n=MultiByteToWideChar(CP_ACP,0,s,-1,nullptr,0);std::wstring out(n,L'\0');MultiByteToWideChar(CP_ACP,0,s,-1,out.data(),n);if(!out.empty())out.pop_back();return out;}
static std::wstring dataUnits(const unsigned char* p){
 for(int i=8;i<16;++i)if(p[i])return L"超出显示范围";uint64_t n=0;memcpy(&n,p,8);if(n>UINT64_MAX/512000)return L"超出显示范围";return volume(n*512000);
}
static std::wstring counter(const unsigned char* p){for(int i=8;i<16;++i)if(p[i])return L"超出显示范围";uint64_t n=0;memcpy(&n,p,8);return std::to_wstring(n);}
std::vector<DiskHealth> diskHealth(){
 std::vector<DiskHealth> result;
 for(int i=0;i<32;++i){std::wstring path=L"\\\\.\\PhysicalDrive"+std::to_wstring(i);HANDLE h=CreateFileW(path.c_str(),0,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,0,nullptr);if(h==INVALID_HANDLE_VALUE)continue;
  DiskHealth d;d.name=L"磁盘 "+std::to_wstring(i);DWORD returned=0;
  STORAGE_PROPERTY_QUERY query{};query.PropertyId=StorageDeviceProperty;query.QueryType=PropertyStandardQuery;std::array<unsigned char,4096> descriptor{};
  STORAGE_BUS_TYPE bus=BusTypeUnknown;
  if(DeviceIoControl(h,IOCTL_STORAGE_QUERY_PROPERTY,&query,sizeof(query),descriptor.data(),static_cast<DWORD>(descriptor.size()),&returned,nullptr)&&returned>=sizeof(STORAGE_DEVICE_DESCRIPTOR)){
   auto* p=reinterpret_cast<STORAGE_DEVICE_DESCRIPTOR*>(descriptor.data());bus=p->BusType;
   if(p->ProductIdOffset && p->ProductIdOffset<returned){size_t remaining=returned-p->ProductIdOffset;char* name=reinterpret_cast<char*>(descriptor.data()+p->ProductIdOffset);if(memchr(name,0,remaining))d.name+=L" · "+wide(name);}
  }
  d.bus=bus==BusTypeNvme?L"NVMe":bus==BusTypeUsb?L"USB":bus==BusTypeSata?L"SATA":L"其他";
  if(bus==BusTypeNvme){
   constexpr size_t offset=offsetof(STORAGE_PROPERTY_QUERY,AdditionalParameters);
   std::vector<unsigned char> buffer(offset+sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)+512);
   auto* q=reinterpret_cast<STORAGE_PROPERTY_QUERY*>(buffer.data());q->PropertyId=StorageDeviceProtocolSpecificProperty;q->QueryType=PropertyStandardQuery;
   auto* protocol=reinterpret_cast<STORAGE_PROTOCOL_SPECIFIC_DATA*>(buffer.data()+offset);protocol->ProtocolType=ProtocolTypeNvme;protocol->DataType=NVMeDataTypeLogPage;protocol->ProtocolDataRequestValue=2;protocol->ProtocolDataOffset=sizeof(*protocol);protocol->ProtocolDataLength=512;
   if(DeviceIoControl(h,IOCTL_STORAGE_QUERY_PROPERTY,buffer.data(),static_cast<DWORD>(buffer.size()),buffer.data(),static_cast<DWORD>(buffer.size()),&returned,nullptr)&&returned>=sizeof(STORAGE_PROTOCOL_DATA_DESCRIPTOR)){
    auto* out=reinterpret_cast<STORAGE_PROTOCOL_DATA_DESCRIPTOR*>(buffer.data());auto& p=out->ProtocolSpecificData;
    size_t start=offsetof(STORAGE_PROTOCOL_DATA_DESCRIPTOR,ProtocolSpecificData)+p.ProtocolDataOffset;
    if(p.ProtocolDataLength>=512&&start<=returned&&512<=returned-start){auto* s=buffer.data()+start;
     d.status=s[0]?L"存在警告（"+std::to_wstring(s[0])+L"）":L"无关键警告";
     unsigned temp=s[1]+s[2]*256;if(temp>=273&&temp<=600)d.temperature=std::to_wstring(temp-273)+L" °C";
     d.wear=std::to_wstring(s[5])+L" %";d.read=dataUnits(s+32);d.write=dataUnits(s+48);d.hours=counter(s+128)+L" 小时";d.errors=counter(s+160);
    }
   }
  }
  CloseHandle(h);result.push_back(std::move(d));
 }
 return result;
}
}
