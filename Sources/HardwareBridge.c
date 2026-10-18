#include "HardwareBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOBSD.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>
_Static_assert(sizeof(NVMeSMARTData)==512, "Unexpected NVMe SMART log layout");
static uint64_t low128(const uint8_t *p, uint8_t *valid) {
    uint64_t value=0; *valid=1;
    for(int i=8;i<16;i++) if(p[i]) *valid=0;
    for(int i=0;i<8;i++) value|=(uint64_t)p[i]<<(i*8);
    return value;
}
static int result(IOReturn value) { return value==kIOReturnNotPrivileged || value==kIOReturnNotPermitted ? 2 : 3; }
int fc_read_nvme(const char *bsd_name, FCNVMeHealth *out) {
    memset(out,0,sizeof(*out));
    io_service_t node=IOServiceGetMatchingService(kIOMainPortDefault,IOBSDNameMatching(kIOMainPortDefault,0,bsd_name));
    if(!node) return 3;
    for(int depth=0;node && depth<24;depth++) {
        CFTypeRef capable=IORegistryEntryCreateCFProperty(node,CFSTR(kIOPropertyNVMeSMARTCapableKey),kCFAllocatorDefault,0);
        int yes=capable && CFGetTypeID(capable)==CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)capable);
        if(capable) CFRelease(capable);
        if(yes) {
            IOCFPlugInInterface **plugin=NULL; IONVMeSMARTInterface **smart=NULL; SInt32 score=0;
            IOReturn rc=IOCreatePlugInInterfaceForService(node,kIONVMeSMARTUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score);
            if(rc || !plugin) { out->error=rc; if(plugin) IODestroyPlugInInterface(plugin); IOObjectRelease(node); return result(rc); }
            HRESULT query=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),(LPVOID*)&smart);
            if(query || !smart) { out->error=query; if(smart) (*smart)->Release(smart); IODestroyPlugInInterface(plugin); IOObjectRelease(node); return 3; }
            NVMeSMARTData data; memset(&data,0,sizeof(data));
            rc=(*smart)->SMARTReadData(smart,&data);
            (*smart)->Release(smart);
            IODestroyPlugInInterface(plugin); IOObjectRelease(node);
            if(rc) { out->error=rc; return result(rc); }
            // NVMe health log uses little endian values and 128-bit counters.
            const uint8_t *p=(const uint8_t *)&data;
            out->warning=p[0]; out->temperature=(p[1]|(p[2]<<8))-273;
            out->spare=p[3]; out->used=p[5];
            out->read_units=low128(p+32,&out->valid_read);
            out->written_units=low128(p+48,&out->valid_written);
            out->hours=low128(p+128,&out->valid_hours);
            out->errors=low128(p+160,&out->valid_errors);
            return 0;
        }
        io_registry_entry_t parent=0;
        IOReturn rc=IORegistryEntryGetParentEntry(node,kIOServicePlane,&parent);
        IOObjectRelease(node); node=rc==KERN_SUCCESS?parent:0;
    }
    if(node) IOObjectRelease(node);
    return 1;
}
