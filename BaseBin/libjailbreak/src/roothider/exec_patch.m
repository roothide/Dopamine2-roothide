//
// Created by Ylarod on 2024/3/15.
//

#import <Foundation/Foundation.h>

#include "../libjailbreak.h"
#include "exec_patch.h"
#include "common.h"
#include "log.h"

BOOL gExecPatchTimerSuspend;
dispatch_queue_t gExecPatchQueue = nil;
NSMutableDictionary *gExecPatchArray = nil;

void execPatchTimer() {
    @autoreleasepool {

        for (NSNumber *processId in [gExecPatchArray copy]) {

            pid_t pid = [processId intValue];
            bool should_resume = [gExecPatchArray[processId] boolValue];

            bool paused = false;
            if (proc_paused(pid, &paused) != 0) {
                JBLogError("[execPatch] invalid process: %d, total=%d", pid, gExecPatchArray.count);
                [gExecPatchArray removeObjectForKey:processId];
                continue;
            } else if (paused) {
                JBLogDebug("[execPatch] patch for process: %d resume=%d total=%d", pid, should_resume, gExecPatchArray.count);

                if(roothide_patch_proc(pid) == 0) {
                    if (should_resume) kill(pid, SIGCONT);
                } else {
                    JBLogError("[execPatch] failed to patch for process: %d", pid);
                }

                [gExecPatchArray removeObjectForKey:processId];
                continue;
            }
        }
        if (gExecPatchArray.count) {
            dispatch_async(gExecPatchQueue, ^{ execPatchTimer(); });
            usleep(5 * 1000);
        } else {
            gExecPatchTimerSuspend = YES;
        }

    }
}

void initExecPatch() 
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gExecPatchArray = [[NSMutableDictionary alloc] init];
        gExecPatchQueue = dispatch_queue_create("execPatchQueue", DISPATCH_QUEUE_SERIAL);
        gExecPatchTimerSuspend = YES;
    });
}

int spawnExecPatchAdd(int pid, bool resume)
{
    initExecPatch();

    dispatch_async(gExecPatchQueue, ^{
        [gExecPatchArray setObject:@(resume) forKey:@(pid)];
        if (gExecPatchTimerSuspend) {
            JBLogDebug("[execPatch] wakeup execPatchTimer...");
            dispatch_async(gExecPatchQueue, ^{ execPatchTimer(); });
            gExecPatchTimerSuspend = NO;
        }
    });
    return 0;
}

int spawnExecPatchDel(int pid)
{
    initExecPatch();

    __block int ret = -1;

    //synchronous deletion
    dispatch_sync(gExecPatchQueue, ^{
        if([gExecPatchArray objectForKey:@(pid)] != nil) {
            [gExecPatchArray removeObjectForKey:@(pid)];
            ret = 0;
        }
    });
    return ret;
}
