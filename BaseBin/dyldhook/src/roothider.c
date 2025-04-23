#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <limits.h>

#include "machomerger_hook.h"
#include "dyld_jbinfo.h"
#include "dyld.h"

#define ROOTHIDE_LOADER_PREFIX "@loader_path/.jbroot"

typedef struct Loader Loader;
typedef struct LoadOptions LoadOptions;
typedef struct RuntimeState RuntimeState;

//class static method, no "this" parameter
extern bool ORIG(_ZN5dyld46Loader18expandAtLoaderPathERNS_12RuntimeStateEPKcRKNS0_11LoadOptionsEPKS0_bPc)(RuntimeState* state, const char* loadPath, const LoadOptions* options, const Loader* ldr, bool fromLCRPATH, char fixedPath[]);
bool HOOK(_ZN5dyld46Loader18expandAtLoaderPathERNS_12RuntimeStateEPKcRKNS0_11LoadOptionsEPKS0_bPc)(RuntimeState* state, const char* loadPath, const LoadOptions* options, const Loader* ldr, bool fromLCRPATH, char fixedPath[])
{
    bool ret = ORIG(_ZN5dyld46Loader18expandAtLoaderPathERNS_12RuntimeStateEPKcRKNS0_11LoadOptionsEPKS0_bPc)(state, loadPath, options, ldr, fromLCRPATH, fixedPath);
    if(ret) {
        if(strncmp(loadPath, ROOTHIDE_LOADER_PREFIX, sizeof(ROOTHIDE_LOADER_PREFIX)-1) == 0)
        {
            if ( (loadPath[sizeof(ROOTHIDE_LOADER_PREFIX)-1] != '/')
             && (loadPath[sizeof(ROOTHIDE_LOADER_PREFIX)-1] != '\0') ) {
                return ret;
            }
            
            char *jbroot = jbinfo_get_jbroot();
            if (jbroot) {
                strlcpy(fixedPath, jbroot, PATH_MAX);
                strlcat(fixedPath, &loadPath[sizeof(ROOTHIDE_LOADER_PREFIX)-1], PATH_MAX);
            }
        }
    }
    return ret;
}

