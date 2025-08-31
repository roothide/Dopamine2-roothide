#include <map>
#include <set>
#include <bsm/audit.h>
#include <pthread.h>
#include <dispatch/dispatch.h>

extern "C"
{

#include <libproc.h>
#include <sys/proc_info.h>

#include "../libjailbreak.h"
#include "common.h"

extern int audit_token_to_pidversion(audit_token_t atoken);

}

static std::set<pid_t*> uncachedBlacklistedProcesses;
static std::map<pid_t, int> blacklistedProcessesState;

static pthread_rwlock_t stateLock = {0};

void stateLockInit()
{
    pthread_rwlock_init(&stateLock, NULL);
}
void stateReadLock()
{
    pthread_rwlock_rdlock(&stateLock);
}
void stateReadUnlock()
{
    pthread_rwlock_unlock(&stateLock);
}
void stateWriteLock()
{
    pthread_rwlock_wrlock(&stateLock);
}
void stateWriteUnlock()
{
    pthread_rwlock_unlock(&stateLock);
}

void initBlacklistState()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stateLockInit();
    });
}

bool _isBlacklistedProcess(pid_t pid, int pidversion)
{
    initBlacklistState();
    
    bool blacklisted = false;

    stateReadLock();

    for(auto it = uncachedBlacklistedProcesses.begin(); it != uncachedBlacklistedProcesses.end(); ++it)
    {
        pid_t uncachedPid = *(*it);
        if(uncachedPid>0 && uncachedPid==pid)
        {
            if(pidversion==proc_get_pidversion(uncachedPid)) {
                blacklisted = true;
            }
            break;
        }
    }

    if(!blacklisted)
    {
        auto it = blacklistedProcessesState.find(pid);
        if(it != blacklistedProcessesState.end())
        {
            int cached_pidversion = it->second;
            if(cached_pidversion == pidversion)
            {
                blacklisted = true;
            }
        }        
    }
    
    stateReadUnlock();

    return blacklisted;
}

extern "C" bool isBlacklistedToken(audit_token_t* token)
{
    pid_t pid = audit_token_to_pid(*token);
    int pidversion = audit_token_to_pidversion(*token);
    return _isBlacklistedProcess(pid, pidversion);
}

extern "C" bool isBlacklistedPid(pid_t pid)
{
    return _isBlacklistedProcess(pid, proc_get_pidversion(pid));
}

extern "C" pid_t* allocBlacklistProcessId()
{
    initBlacklistState();

    pid_t* pidp = (pid_t*)malloc(sizeof(pid_t));

    *pidp = 0;

    stateWriteLock();

    uncachedBlacklistedProcesses.insert(pidp);
    
    stateWriteUnlock();

    return pidp;
}

extern "C" void commitBlacklistProcessId(pid_t* pidp)
{
    initBlacklistState();

    stateWriteLock();

    pid_t pid = *pidp;
    if(pid > 0)
    {
        int pidversion = proc_get_pidversion(pid);
        if (pidversion > 0) {
            blacklistedProcessesState[pid] = pidversion;
        }
    }

    uncachedBlacklistedProcesses.erase(pidp);

    free(pidp);

    stateWriteUnlock();
}
