#ifndef ROOTHIDE_TELEPHONY_BLACKLIST_H
#define ROOTHIDE_TELEPHONY_BLACKLIST_H

#include <stdbool.h>
#include <string.h>

// launchd starts the service as xpcproxy before loading its own executable.
// Match the exact service label so other XPC services keep their usual setup.
static inline bool roothide_is_telephony_blastdoor_proxy(const char *path,
                                                         char *const argv[])
{
    return path && strcmp(path, "/usr/libexec/xpcproxy") == 0 &&
           argv && argv[0] && argv[1] &&
           strcmp(argv[1], "com.apple.TelephonyBlastDoorService") == 0;
}

#endif
