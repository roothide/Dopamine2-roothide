#include <assert.h>

#include "../src/telephony_blacklist.h"

int main(void)
{
    char *service[] = {
        "/usr/libexec/xpcproxy", "com.apple.TelephonyBlastDoorService", NULL
    };
    char *otherService[] = {
        "/usr/libexec/xpcproxy", "com.apple.MessagesBlastDoorService", NULL
    };
    char *missingLabel[] = {"/usr/libexec/xpcproxy", NULL};
    char *noExecutable[] = {NULL};

    assert(roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy", service));
    assert(!roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy", otherService));
    assert(!roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy", missingLabel));
    assert(!roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy", noExecutable));
    assert(!roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy", NULL));
    assert(!roothide_is_telephony_blastdoor_proxy(NULL, service));
    assert(!roothide_is_telephony_blastdoor_proxy("/usr/libexec/xpcproxy-helper", service));
    assert(!roothide_is_telephony_blastdoor_proxy(
        "/System/Library/PrivateFrameworks/TelephonyBlastDoorSupport.framework/"
        "XPCServices/TelephonyBlastDoorService.xpc/TelephonyBlastDoorService",
        service));
    return 0;
}
