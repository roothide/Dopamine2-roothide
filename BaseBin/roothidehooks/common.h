
#include <stdbool.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/roothider.h>
#include <libjailbreak/codesign.h>

bool isJailbreakPath(const char* path);

//These apps may be signed with a (fake) certificate
#define SENSITIVE_APP_LIST   @[ \
    @"com.icraze.gtatracker", \
    @"com.Alfie.TrollInstallerX", \
    @"com.opa334.Dopamine", \
    @"com.opa334.Dopamine.roothide", \
    @"com.opa334.Dopamine-roothide", \
]
