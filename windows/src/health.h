#pragma once
#include <string>
#include <vector>
namespace fc {
struct DiskHealth {std::wstring name,bus,status=L"未提供",temperature=L"未提供",wear=L"未提供",read=L"未提供",write=L"未提供",hours=L"未提供",errors=L"未提供";};
std::vector<DiskHealth> diskHealth();
}
