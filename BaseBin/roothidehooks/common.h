
#include <stdbool.h>


bool isJailbreakPath(const char* path);

bool isNormalAppPath(const char* path);

bool isSandboxedApp(pid_t pid, const char* path);

int proc_pidpath(int pid, void * buffer, uint32_t  buffersize) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

bool isBlacklisted(const char* path);
BOOL isBlacklistedApp(NSString* identifier);

/* csops  operations */
#define	CS_OPS_STATUS		0	/* return status */
#define CS_PLATFORM_BINARY          0x04000000  /* this is a platform binary */
int csops(pid_t pid, unsigned int  ops, void * useraddr, size_t usersize);

//These apps may be signed with a (fake) certificate
#define SENSITIVE_APP_LIST   @[ \
    @"com.icraze.gtatracker", \
    @"com.Alfie.TrollInstallerX", \
    @"com.opa334.Dopamine", \
    @"com.opa334.Dopamine.roothide", \
    @"com.opa334.Dopamine-roothide", \
]
