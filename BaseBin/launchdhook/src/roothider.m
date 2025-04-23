#import <Foundation/Foundation.h>

#include <spawn.h>
#include <substrate.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>

#include "../systemhook/src/common.h"
#include "../systemhook/src/envbuf.h"

const char* HOOK_DYLIB_PATH = NULL;

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
extern int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t *__restrict, int *__restrict) __API_AVAILABLE(macos(10.8), ios(6.0));
extern int posix_spawnattr_setexceptionports_np(posix_spawnattr_t *__restrict, exception_mask_t, mach_port_t, exception_behavior_t, thread_state_flavor_t) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_2_0);

//from launchdhook/spawn_hook.c
extern int platform_set_process_debugged(uint64_t pid, bool fullyDebugged);
extern int __posix_spawn_hook(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);
extern int __posix_spawn_orig_wrapper(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict]);

//from systemhook/roothide_common.c
int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int __sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int __sysctlbyname_hook(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);

void roothide_launchd_preinit()
{
	JBLogDebug("roothide_launchd_preinit");

#ifdef ENABLE_LOGS
	enableJBDLog(JBLogDebugFunction, JBLogErrorFunction);
#endif

	exec_set_patch(false);
}

void roothide_launchd_postinit(bool firstLoad)
{
	JBLogDebug("roothide_launchd_postinit: firstLoad=%d", firstLoad);

	launchdhookFirstLoad = firstLoad;

	exec_set_patch(true);

	if(firstLoad)
	{
		HOOK_DYLIB_PATH = "";
		
		if (__builtin_available(iOS 16.0, *))
		{
			hideDeveloperMode();
		}
	}
	else
	{		
		NSString* systemhookFilePath = [NSString stringWithFormat:@"%@/systemhook-%016llX.dylib", JBROOT_PATH(@"/basebin"), jbinfo(jbrand)];

		if([NSFileManager.defaultManager fileExistsAtPath:JBROOT_PATH(@"/basebin/systemhook.dylib")])
		{
			[NSFileManager.defaultManager removeItemAtPath:systemhookFilePath error:nil];
			assert([NSFileManager.defaultManager moveItemAtPath:JBROOT_PATH(@"/basebin/systemhook.dylib") toPath:systemhookFilePath error:nil]);
		}
		
		assert(unsandbox("/usr/lib", systemhookFilePath.fileSystemRepresentation) == 0);

		//new "real path"
		asprintf(&HOOK_DYLIB_PATH, "/usr/lib/systemhook-%016llX.dylib", jbinfo(jbrand));
	}

	if (__builtin_available(iOS 16.0, *))
	{
		void* __sysctl_orig = NULL;
		void* __sysctlbyname_orig = NULL;
		MSHookFunction(&__sysctl, (void *) __sysctl_hook, &__sysctl_orig);
		MSHookFunction(&__sysctlbyname, (void *) __sysctlbyname_hook, &__sysctlbyname_orig);
	}

	if(!firstLoad)
	{
		int ret = ensure_dyld_trustcache(JBROOT_PATH("/basebin/.fakelib/dyld"));
		if (ret != 0) {
			launchd_panic("ensure dyld trustcache failed: %d", ret);
			return;
		}
	}

	// load jailbreakd after applying hooks
	assert(initJailbreakd(firstLoad) == 0);
}

int roothide_launchd___posix_spawn_prehook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	if(!desc || !desc->attrp) {
		posix_spawnattr_t attr=NULL;
		posix_spawnattr_init(&attr);
		int ret = posix_spawn(pidp, path, (desc && desc->file_actions) ? &desc->file_actions : NULL, &attr, argv, envp);
		posix_spawnattr_destroy(&attr);
		return ret;
	}
	posix_spawnattr_t attrp = &desc->attrp;

	if(!path) {
		return __posix_spawn_hook(pidp, path, desc, argv, envp);
	}

	if(strcmp(path, "/sbin/launchd") == 0) {
		short flags = 0;
		posix_spawnattr_getflags(attrp, &flags);
		posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);
		return __posix_spawn_hook(pidp, path, desc, argv, envp);
	}

	if(launchdhookFirstLoad) {
		//we should not enable system-wide injection until the jailbreak is finalized (userspace reboot).
		return __posix_spawn_orig_wrapper(pidp, path, desc, argv, envp);
	}
	
	if(string_has_suffix(path, "/basebin/jailbreakd")) {
		return __posix_spawn_orig_wrapper(pidp, path, desc, argv, envp);
	}

	if (isBlacklistedPath(path)) 
	{
		int ret;

		JBLogDebug("blacklisted app %s", path);

		char **envc = envbuf_mutcopy((const char **)envp);

		// mitigate spinlock panic on ios15(A12+) devices
		bool iOS15Arm64e =false;
#ifdef __arm64e__
		if (!__builtin_available(iOS 16.0, *)) {
			iOS15Arm64e = true;
		}
#endif
		if(iOS15Arm64e && (strstr(path, "/PlugIns/") || strstr(path, ".appex/"))) {
			JBLogDebug("prevent blacklisted app's extension from running: ", path);
			ret = EPERM;
		}
		else if(envbuf_getenv(envc, "ActivePrewarm") || envbuf_getenv(envc, "DYLD_USE_CLOSURES")) {
			JBLogDebug("prevent blacklisted app from prewarming: ", path);
			ret = EPERM;
		}
		else
		{
			//choicy may set these 
			envbuf_unsetenv(&envc, "_SafeMode");
			envbuf_unsetenv(&envc, "_MSSafeMode");
	
			/* According to xnu, the new thread in new process will not run in userland until after copyout pid
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4321
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4882
			https://github.com/apple-oss-distributions/xnu/blob/8d741a5de7ff4191bf97d57b9f54c2f6d4a15585/bsd/kern/kern_exec.c#L4933
			*/
	
			/* and posix_spawn->kernel->amfid->launchd may cause xpc dead loop so we can't use lock-spawn-unlock here */
	
			volatile pid_t* blacklistedPidp = allocBlacklistProcessId();
	
			ret = __posix_spawn_orig_wrapper(blacklistedPidp, path, desc, argv, envc);
	
			pid_t pid = *blacklistedPidp;
			if(pidp) *pidp = pid;

			commitBlacklistProcessId(blacklistedPidp); // will release blacklistedPidp
			blacklistedPidp = NULL;
				
			if(ret==0 && pid>0) {
				short flags = 0;
				posix_spawnattr_getflags(attrp, &flags);
				if((flags & POSIX_SPAWN_START_SUSPENDED) != 0) {
					platform_set_process_debugged(pid, false);
				}
			}
		}
	
		envbuf_free(envc);
	
		return ret;
	}

	return __posix_spawn_hook(pidp, path, desc, argv, envp);
}

int roothide_launchd___posix_spawn_posthook(pid_t *restrict pidp, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char *const envp[restrict])
{
	//spawn_prehook ensure this is always available
	posix_spawnattr_t attrp = &desc->attrp;

	short flags = 0;
	posix_spawnattr_getflags(attrp, &flags);

	int proctype = 0;
	posix_spawnattr_getprocesstype_np(attrp, &proctype);

	bool should_suspend = (proctype != POSIX_SPAWN_PROC_TYPE_DRIVER);
	bool should_resume = should_suspend && (flags & POSIX_SPAWN_START_SUSPENDED)==0;

	if (should_suspend) {
		posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED);
	}

	// on some devices dyldhook may fail due to vm_protect(VM_PROT_READ|VM_PROT_WRITE), 2, (os/kern) protection failure in dsc::__DATA_CONST:__const, 
	// so we need to disable dyld-in-cache here. (or we can use VM_PROT_READ|VM_PROT_WRITE|VM_PROT_COPY)
	char **envc = envbuf_mutcopy((const char **)envp);
	envbuf_setenv(&envc, "DYLD_IN_CACHE", "0");

	int pid = 0;
	if (!pidp) pidp = &pid;
	int ret = __posix_spawn_orig_wrapper(pidp, path, desc, argv, envc);
	pid = *pidp;

	envbuf_free(envc);
	
	posix_spawnattr_setflags(attrp, flags); // maybe caller will use it again?

	if (ret == 0 && pid > 0) {
		if(should_suspend) {
			jbdSpawnPatchChild(pid, should_resume);
		}
	} else {
		JBLogError("spawn failed: %d %s, pid=%d", ret, strerror(ret), pid);
	}

	return ret;
}

