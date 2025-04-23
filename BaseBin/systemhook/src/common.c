#include "common.h"
#include "roothider.h"
#include <xpc/xpc.h>
#include "launchd.h"
#include <mach-o/dyld.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sandbox.h>
#include <paths.h>
#include <sys/stat.h>
#include <dlfcn.h>
#include "envbuf.h"
#include "private.h"
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/jbserver_domains.h>

bool string_has_prefix(const char *str, const char* prefix)
{
	if (!str || !prefix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t prefix_len = strlen(prefix);

	if (str_len < prefix_len) {
		return false;
	}

	return !strncmp(str, prefix, prefix_len);
}

bool string_has_suffix(const char* str, const char* suffix)
{
	if (!str || !suffix) {
		return false;
	}

	size_t str_len = strlen(str);
	size_t suffix_len = strlen(suffix);

	if (str_len < suffix_len) {
		return false;
	}

	return !strcmp(str + str_len - suffix_len, suffix);
}

void string_enumerate_components(const char *string, const char *separator, void (^enumBlock)(const char *pathString, bool *stop))
{
	char *stringCopy = strdup(string);
	char *curString = strtok(stringCopy, separator);
	while (curString != NULL) {
		bool stop = false;
		enumBlock(curString, &stop);
		if (stop) break;
		curString = strtok(NULL, separator);
	}
	free(stringCopy);
}

kSpawnConfig spawn_config_for_executable(const char* path, char *const argv[restrict])
{
	// Blacklist to ensure general system stability
	// I don't like this but for some processes it seems neccessary
	const char *processBlacklist[] = {
		"/System/Library/Frameworks/GSS.framework/Helpers/GSSCred",
		"/System/Library/PrivateFrameworks/DataAccess.framework/Support/dataaccessd",
		"/System/Library/PrivateFrameworks/IDSBlastDoorSupport.framework/XPCServices/IDSBlastDoorService.xpc/IDSBlastDoorService",
		"/System/Library/PrivateFrameworks/MessagesBlastDoorSupport.framework/XPCServices/MessagesBlastDoorService.xpc/MessagesBlastDoorService",
	};
	size_t blacklistCount = sizeof(processBlacklist) / sizeof(processBlacklist[0]);
	for (size_t i = 0; i < blacklistCount; i++)
	{
		if (!strcmp(processBlacklist[i], path)) return 0;
	}

	return (kSpawnConfigInject | kSpawnConfigTrust);
}

int __posix_spawn_orig(pid_t *restrict pid, const char *restrict path, struct _posix_spawn_args_desc *desc, char *const argv[restrict], char * const envp[restrict])
{
	return syscall(SYS_posix_spawn, pid, path, desc, argv, envp);
}

int __execve_orig(const char *path, char *const argv[], char *const envp[])
{
	return syscall(SYS_execve, path, argv, envp);
}

// 1. Ensure the binary about to be spawned and all of it's dependencies are trust cached
// 2. Insert "DYLD_INSERT_LIBRARIES=/usr/lib/systemhook.dylib" into all binaries spawned
// 3. Increase Jetsam limit to more sane value (Multipler defined as JETSAM_MULTIPLIER)

static int spawn_exec_hook_common(const char *path,
								  char *const argv[restrict],
								  char *const envp[restrict],
			   struct _posix_spawn_args_desc *desc,
										int (*trust_binary)(const char *path),
									   double jetsamMultiplier,
									    int (^orig)(char *const envp[restrict]))
{
	if (!path) {
		return orig(envp);
	}

	posix_spawnattr_t attr = NULL;
	if (desc) attr = desc->attrp;

	kSpawnConfig spawnConfig = spawn_config_for_executable(path, argv);

	if (spawnConfig & kSpawnConfigTrust) {
		// Upload binary to trustcache if needed
		trust_binary(path);
	}

	const char *existingLibraryInserts = envbuf_getenv((const char **)envp, "DYLD_INSERT_LIBRARIES");
	__block bool systemHookAlreadyInserted = false;
	if (existingLibraryInserts) {
		string_enumerate_components(existingLibraryInserts, ":", ^(const char *existingLibraryInsert, bool *stop) {
			if (!strcmp(existingLibraryInsert, HOOK_DYLIB_PATH)) {
				systemHookAlreadyInserted = true;
			}
		});
	}

	int JBEnvAlreadyInsertedCount = (int)systemHookAlreadyInserted;

	// Check if we can find at least one reason to not insert jailbreak related environment variables
	// In this case we also need to remove pre existing environment variables if they are already set
	bool shouldInsertJBEnv = true;
	bool hasSafeModeVariable = false;
	do {
		if (!(spawnConfig & kSpawnConfigInject)) {
			shouldInsertJBEnv = false;
			break;
		}


/*********** roothide specific ************/
struct statfs fs = {0};
bool isAppPath = is_app_path(path);
bool nonJailbreakPath = statfs(path, &fs)==0 && strcmp(fs.f_mntonname, "/private/var") != 0;
/*********************************** roothide specific *************************************/


		// Check if we can find a _SafeMode or _MSSafeMode variable
		// In this case we do not want to inject anything
		const char *safeModeValue = envbuf_getenv((const char **)envp, "_SafeMode");
		const char *msSafeModeValue = envbuf_getenv((const char **)envp, "_MSSafeMode");
		if (safeModeValue) {
			if (!strcmp(safeModeValue, "1")) {
				if(nonJailbreakPath||isAppPath) shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}
		if (msSafeModeValue) {
			if (!strcmp(msSafeModeValue, "1")) {
				if(nonJailbreakPath||isAppPath) shouldInsertJBEnv = false;
				hasSafeModeVariable = true;
				break;
			}
		}

		int proctype = 0;
		if (posix_spawnattr_getprocesstype_np(&attr, &proctype) == 0) {
			if (proctype == POSIX_SPAWN_PROC_TYPE_DRIVER) {
				// Do not inject hook into DriverKit drivers
				shouldInsertJBEnv = false;
				break;
			}
		}

		if (access(HOOK_DYLIB_PATH, F_OK) != 0) {
			// If the hook dylib doesn't exist, don't try to inject it (would crash the process)
			shouldInsertJBEnv = false;
			break;
		}
	} while (0);

	// If systemhook is being injected and jetsam limits are set, increase them by a factor of jetsamMultiplier
	if (shouldInsertJBEnv) {
		uint8_t *attrStruct = (uint8_t *)attr;
		if (attrStruct) {
			if (jetsamMultiplier == 0 || isnan(jetsamMultiplier)) jetsamMultiplier = 3; // default value (3x)
			if (jetsamMultiplier > 1) {
				int memlimit_active = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE);
				if (memlimit_active != -1) {
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_ACTIVE) = memlimit_active * jetsamMultiplier;
				}
				int memlimit_inactive = *(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE);
				if (memlimit_inactive != -1) {
					*(int*)(attrStruct + POSIX_SPAWNATTR_OFF_MEMLIMIT_INACTIVE) = memlimit_inactive * jetsamMultiplier;
				}
			}
		}
	}

	int r = -1;

	if ((shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 1) || (!shouldInsertJBEnv && JBEnvAlreadyInsertedCount == 0 && !hasSafeModeVariable)) {
		// we're already good, just call orig
		r = orig(envp);
	}
	else {
		// the state we want to be in is not the state we are in right now

		char **envc = envbuf_mutcopy((const char **)envp);

		if (shouldInsertJBEnv) {
			if (!systemHookAlreadyInserted) {
				char newLibraryInsert[strlen(HOOK_DYLIB_PATH) + (existingLibraryInserts ? (strlen(existingLibraryInserts) + 1) : 0) + 1];
				strcpy(newLibraryInsert, HOOK_DYLIB_PATH);
				if (existingLibraryInserts) {
					strcat(newLibraryInsert, ":");
					strcat(newLibraryInsert, existingLibraryInserts);
				}
				envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);
			}
		}
		else {
			if (systemHookAlreadyInserted && existingLibraryInserts) {
				if (!strcmp(existingLibraryInserts, HOOK_DYLIB_PATH)) {
					envbuf_unsetenv(&envc, "DYLD_INSERT_LIBRARIES");
				}
				else {
					char *newLibraryInsert = malloc(strlen(existingLibraryInserts)+1);
					newLibraryInsert[0] = '\0';

					__block bool first = true;
					string_enumerate_components(existingLibraryInserts, ":", ^(const char *existingLibraryInsert, bool *stop) {
						if (strcmp(existingLibraryInsert, HOOK_DYLIB_PATH) != 0) {
							if (first) {
								strcpy(newLibraryInsert, existingLibraryInsert);
								first = false;
							}
							else {
								strcat(newLibraryInsert, ":");
								strcat(newLibraryInsert, existingLibraryInsert);
							}
						}
					});
					envbuf_setenv(&envc, "DYLD_INSERT_LIBRARIES", newLibraryInsert);

					free(newLibraryInsert);
				}
			}
			envbuf_unsetenv(&envc, "_SafeMode");
			envbuf_unsetenv(&envc, "_MSSafeMode");
		}

		r = orig(envc);

		envbuf_free(envc);
	}

	return r;
}

int posix_spawn_hook_shared(pid_t *restrict pid, 
					   const char *restrict path,
			 struct _posix_spawn_args_desc *desc,
						  	    char *const argv[restrict],
					   			char *const envp[restrict],
					   				  void *orig,
					   				  int (*trust_binary)(const char *path),
					   				  int (*set_process_debugged)(uint64_t pid, bool fullyDebugged),
					   				 double jetsamMultiplier)
{
	int (*posix_spawn_orig)(pid_t *restrict, const char *restrict, struct _posix_spawn_args_desc *, char *const[restrict], char *const[restrict]) = orig;

	int r = spawn_exec_hook_common(path, argv, envp, desc, trust_binary, jetsamMultiplier, ^int(char *const envp_patched[restrict]) {
		return posix_spawn_orig(pid, path, desc, argv, envp_patched);
	});

	if (r == 0 && pid && desc) {
		posix_spawnattr_t attr = desc->attrp;
		short flags = 0;
		if (posix_spawnattr_getflags(&attr, &flags) == 0) {
			if (flags & POSIX_SPAWN_START_SUSPENDED) {
				// If something spawns a process as suspended, ensure mapping invalid pages in it is possible
				// Normally it would only be possible after systemhook.dylib enables it
				// Fixes Frida issues
				int r = set_process_debugged(*pid, false);
			}
		}
	}

	return r;
}

int execve_hook_shared(const char *path,
					   char *const argv[],
					   char *const envp[],
			 				 void *orig,
			 				 int (*trust_binary)(const char *path))
{
	int (*execve_orig)(const char *, char *const[], char *const[]) = orig;

	int r = spawn_exec_hook_common(path, argv, envp, NULL, trust_binary, 0, ^int(char *const envp_patched[restrict]){
		return execve_orig(path, argv, envp_patched);
	});

	return r;
}
