#include <windows.h>
#include <shellapi.h>
#include <wincodec.h>
#include <string>
#include <fstream>
#include <filesystem>
int WINAPI wWinMain(HINSTANCE,HINSTANCE,LPWSTR,int){
 int argc=0;auto argv=CommandLineToArgvW(GetCommandLineW(),&argc);if(argc<2)return 1;std::wstring dir=argv[1];bool stop=dir==L"--stop";LocalFree(argv);
 CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED);HWND window=FindWindowW(L"FlowCatPanel",nullptr);if(!window)return 2;if(stop){PostMessageW(window,WM_COMMAND,203,0);return 0;}
 IWICImagingFactory* factory=nullptr;if(FAILED(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory))))return 3;
 for(int page=0;page<3;++page){SendMessageW(window,WM_COMMAND,101+page,0);SendMessageW(window,WM_COMMAND,201,0);Sleep(1800);
  RECT r{};GetWindowRect(window,&r);HDC screen=GetDC(window),memory=CreateCompatibleDC(screen);HBITMAP bitmap=CreateCompatibleBitmap(screen,r.right-r.left,r.bottom-r.top);auto old=SelectObject(memory,bitmap);PrintWindow(window,memory,2);
  IWICBitmap* source=nullptr;IWICStream* stream=nullptr;IWICBitmapEncoder* encoder=nullptr;IWICBitmapFrameEncode* frame=nullptr;
  std::wstring path=dir+L"\\ui-"+std::to_wstring(page)+L".png";
  if(SUCCEEDED(factory->CreateBitmapFromHBITMAP(bitmap,nullptr,WICBitmapIgnoreAlpha,&source))&&SUCCEEDED(factory->CreateStream(&stream))&&SUCCEEDED(stream->InitializeFromFilename(path.c_str(),GENERIC_WRITE))&&SUCCEEDED(factory->CreateEncoder(GUID_ContainerFormatPng,nullptr,&encoder))&&SUCCEEDED(encoder->Initialize(stream,WICBitmapEncoderNoCache))&&SUCCEEDED(encoder->CreateNewFrame(&frame,nullptr))){frame->Initialize(nullptr);frame->SetSize(r.right-r.left,r.bottom-r.top);WICPixelFormatGUID format=GUID_WICPixelFormat32bppBGR;frame->SetPixelFormat(&format);frame->WriteSource(source,nullptr);frame->Commit();encoder->Commit();}
  if(frame)frame->Release();if(encoder)encoder->Release();if(stream)stream->Release();if(source)source->Release();SelectObject(memory,old);DeleteObject(bitmap);DeleteDC(memory);ReleaseDC(window,screen);
 }SendMessageW(window,WM_COMMAND,101,0);factory->Release();CoUninitialize();return 0;
}
