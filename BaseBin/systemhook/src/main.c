#include "common.h"

#include <mach-o/dyld.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <paths.h>
#include <util.h>
#include "sandbox.h"
#include "objc.h"
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/codesign.h>
#include "litehook.h"

int necp_match_policy(uint8_t *parameters, size_t parameters_size, void *returned_result);
int necp_open(int flags);
int necp_client_action(int necp_fd, uint32_t action, uuid_t client_id, size_t client_id_len, uint8_t *buffer, size_t buffer_size);
int necp_session_open(int flags);
int necp_session_action(int necp_fd, uint32_t action, uint8_t *in_buffer, size_t in_buffer_length, uint8_t *out_buffer, size_t out_buffer_length);

#define SYSCALL_CSOPS 0xA9
#define SYSCALL_CSOPS_AUDITTOKEN 0xAA
#define SYSCALL_NECP_MATCH_POLICY 0x1CC
#define SYSCALL_NECP_OPEN 0x1F5
#define SYSCALL_NECP_CLIENT_ACTION 0x1F6
#define SYSCALL_NECP_SESSION_OPEN 0x20A
#define SYSCALL_NECP_SESSION_ACTION 0x20B

extern char **environ;
bool gTweaksEnabled = false;

int ptrace(int request, pid_t pid, caddr_t addr, int data);
#define PT_ATTACH       10      /* trace some running process */
#define PT_ATTACHEXC    14      /* attach to running process with signal exception */

void* dlopen_from(const char* path, int mode, void* addressInCaller);
void* dlopen_audited(const char* path, int mode);
bool dlopen_preflight(const char* path);

#define DYLD_INTERPOSE(_replacement,_replacee) \
   __attribute__((used)) static struct{ const void* replacement; const void* replacee; } _interpose_##_replacee \
			__attribute__ ((section ("__DATA,__interpose"))) = { (const void*)(unsigned long)&_replacement, (const void*)(unsigned long)&_replacee };

static char gExecutablePath[PATH_MAX];
static int loadExecutablePath(void)
{
	char executablePath[PATH_MAX];
	uint32_t bufsize = PATH_MAX;
	if (_NSGetExecutablePath(executablePath, &bufsize) == 0) {
		if (realpath(executablePath, gExecutablePath) != NULL) return 0;
	}
	return -1;
}

static char *JB_SandboxExtensions = NULL;
void applySandboxExtensions(void)
{
	if (JB_SandboxExtensions) {
		char *JB_SandboxExtensions_dup = strdup(JB_SandboxExtensions);
		char *extension = strtok(JB_SandboxExtensions_dup, "|");
		while (extension != NULL) {
			sandbox_extension_consume(extension);
			extension = strtok(NULL, "|");
		}
		free(JB_SandboxExtensions_dup);
	}
}

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
#define POSIX_SPAWN_SYSTEMHOOK_HANDLED	0x2000 // _POSIX_SPAWN_ALLOW_DATA_EXEC(0x2000) only used in DEBUG/DEVELOPMENT kernel
int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t * __restrict, int * __restrict) __API_AVAILABLE(macos(10.8), ios(6.0));

int posix_spawn_hook(pid_t *restrict pidp, const char *restrict path,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
    posix_spawnattr_t attr = NULL;
    if (!attrp) {
        attrp = &attr;
        posix_spawnattr_init(&attr);
    }

    short flags = 0;
    posix_spawnattr_getflags(attrp, &flags);

    int proctype = 0;
    posix_spawnattr_getprocesstype_np(attrp, &proctype);

    bool should_suspend = (proctype != POSIX_SPAWN_PROC_TYPE_DRIVER);
    bool should_resume = (flags & POSIX_SPAWN_START_SUSPENDED) == 0;
    bool patch_exec = should_suspend && (flags & POSIX_SPAWN_SETEXEC) != 0;

    if (should_suspend) {
        posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_START_SUSPENDED | POSIX_SPAWN_SYSTEMHOOK_HANDLED);
    }

    if (patch_exec) {
        if (jbclient_patch_exec_add(path, should_resume) != 0) { // jdb fault? restore
            posix_spawnattr_setflags(attrp, flags | POSIX_SPAWN_SYSTEMHOOK_HANDLED);
            patch_exec = false;
            should_suspend = false;
        }
    }

    int pid = 0;
    int ret = spawn_hook_common(&pid, path, file_actions, attrp, argv, envp, (void *)posix_spawn, jbclient_trust_binary, jbclient_platform_set_process_debugged);
    if (pidp) *pidp = pid;

    posix_spawnattr_setflags(attrp, flags); // maybe caller will use it again?

    if (patch_exec) { //exec failed?
        jbclient_patch_exec_del(path);
    } else if (should_suspend && ret == 0 && pid > 0) {
        if (jbclient_patch_spawn(pid, should_resume) != 0) { // jdb fault? let it go
            if (should_resume) {
                kill(pid, SIGCONT);
            }
        }
    }

    if (attr) posix_spawnattr_destroy(&attr);

    return ret;
}

int posix_spawnp_hook(pid_t *restrict pid, const char *restrict file,
					   const posix_spawn_file_actions_t *restrict file_actions,
					   const posix_spawnattr_t *restrict attrp,
					   char *const argv[restrict],
					   char *const envp[restrict])
{
	return resolvePath(file, NULL, ^int(char *path) {
		return posix_spawn_hook(pid, path, file_actions, attrp, argv, envp);
	});
}


int execve_hook(const char *path, char *const argv[], char *const envp[])
{
	posix_spawnattr_t attr = NULL;
	posix_spawnattr_init(&attr);
	posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC);
	int result = posix_spawn_hook(NULL, path, NULL, &attr, argv, envp);
	if (attr) {
		posix_spawnattr_destroy(&attr);
	}
	
	if(result != 0) { // posix_spawn will return errno and restore errno if it fails
		errno = result; // so we need to set errno by ourself
		return -1;
	}

	return result;
}

int execle_hook(const char *path, const char *arg0, ... /*, (char *)0, char *const envp[] */)
{
	va_list args;
	va_start(args, arg0);

	// Get argument count
	va_list args_copy;
	va_copy(args_copy, args);
	int arg_count = 1;
	for (char *arg = va_arg(args_copy, char *); arg != NULL; arg = va_arg(args_copy, char *)) {
		arg_count++;
	}
	va_end(args_copy);

	char *argv[arg_count+1];
	argv[0] = (char*)arg0;
	for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i+1] = arg;
	}
	argv[arg_count] = NULL;

	char *nullChar = va_arg(args, char*);

	char **envp = va_arg(args, char**);
	return execve_hook(path, argv, envp);
}

int execlp_hook(const char *file, const char *arg0, ... /*, (char *)0 */)
{
	va_list args;
	va_start(args, arg0);

	// Get argument count
	va_list args_copy;
	va_copy(args_copy, args);
	int arg_count = 1;
	for (char *arg = va_arg(args_copy, char*); arg != NULL; arg = va_arg(args_copy, char*)) {
		arg_count++;
	}
	va_end(args_copy);

	char **argv = malloc((arg_count+1) * sizeof(char *));
	argv[0] = (char*)arg0;
	for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i+1] = arg;
	}
	argv[arg_count] = NULL;

	int r = resolvePath(file, NULL, ^int(char *path) {
		return execve_hook(path, argv, environ);
	});

	free(argv);

	return r;
}

int execl_hook(const char *path, const char *arg0, ... /*, (char *)0 */)
{
	va_list args;
	va_start(args, arg0);

	// Get argument count
	va_list args_copy;
	va_copy(args_copy, args);
	int arg_count = 1;
	for (char *arg = va_arg(args_copy, char*); arg != NULL; arg = va_arg(args_copy, char*)) {
		arg_count++;
	}
	va_end(args_copy);

	char *argv[arg_count+1];
	argv[0] = (char*)arg0;
	for (int i = 0; i < arg_count-1; i++) {
		char *arg = va_arg(args, char*);
		argv[i+1] = arg;
	}
	argv[arg_count] = NULL;

	return execve_hook(path, argv, environ);
}

int execv_hook(const char *path, char *const argv[])
{
	return execve_hook(path, argv, environ);
}

int execvP_hook(const char *file, const char *search_path, char *const argv[])
{
	__block bool execve_failed = false;
	int err = resolvePath(file, search_path, ^int(char *path) {
		(void)execve_hook(path, argv, environ);
		execve_failed = true;
		return 0;
	});
	if (!execve_failed) {
		errno = err;
	}
	return -1;
}

int execvp_hook(const char *name, char * const *argv)
{
	const char *path;
	/* Get the path we're searching. */
	if ((path = getenv("PATH")) == NULL)
		path = _PATH_DEFPATH;
	return execvP_hook(name, path, argv);
}


void* dlopen_hook(const char* path, int mode)
{
	void* addressInCaller = __builtin_return_address(0);
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library(path, addressInCaller);
	}
    return dlopen_from(path, mode, addressInCaller);
}

void* dlopen_from_hook(const char* path, int mode, void* addressInCaller)
{
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library(path, addressInCaller);
	}
	return dlopen_from(path, mode, addressInCaller);
}

void* dlopen_audited_hook(const char* path, int mode)
{
	void* addressInCaller = __builtin_return_address(0);
	if (path && !(mode & RTLD_NOLOAD)) {
		jbclient_trust_library(path, addressInCaller);
	}
	return dlopen_audited(path, mode);
}

bool dlopen_preflight_hook(const char* path)
{
	void* addressInCaller = __builtin_return_address(0);
	if (path) {
		jbclient_trust_library(path, addressInCaller);
	}
	return dlopen_preflight(path);
}

int sandbox_init_hook(const char *profile, uint64_t flags, char **errorbuf)
{
	int retval = sandbox_init(profile, flags, errorbuf);
	if (retval == 0) {
		applySandboxExtensions();
	}
	return retval;
}

int sandbox_init_with_parameters_hook(const char *profile, uint64_t flags, const char *const parameters[], char **errorbuf)
{
	int retval = sandbox_init_with_parameters(profile, flags, parameters, errorbuf);
	if (retval == 0) {
		applySandboxExtensions();
	}
	return retval;
}

int sandbox_init_with_extensions_hook(const char *profile, uint64_t flags, const char *const extensions[], char **errorbuf)
{
	int retval = sandbox_init_with_extensions(profile, flags, extensions, errorbuf);
	if (retval == 0) {
		applySandboxExtensions();
	}
	return retval;
}

int ptrace_hook(int request, pid_t pid, caddr_t addr, int data)
{
	int retval = ptrace(request, pid, addr, data);

	// ptrace works on any process when the parent is unsandboxed,
	// but when the victim process does not have the get-task-allow entitlement,
	// it will fail to set the debug flags, therefore we patch ptrace to manually apply them
	if (retval == 0 && (request == PT_ATTACHEXC || request == PT_ATTACH)) {
		jbclient_platform_set_process_debugged(pid, true);
		jbclient_platform_set_process_debugged(getpid(), true);
	}

	return retval;
}

#ifdef __arm64e__

void loadForkFix(void)
{
	if (gTweaksEnabled) {
		static dispatch_once_t onceToken;
		dispatch_once (&onceToken, ^{
			// If tweaks have been loaded into this process, we need to load forkfix to ensure forking will work
			// Optimization: If the process cannot fork at all due to sandbox, we don't need to do anything
			if (sandbox_check(getpid(), "process-fork", SANDBOX_CHECK_NO_REPORT, NULL) == 0) {
				dlopen(JBRootPath("/basebin/forkfix.dylib"), RTLD_NOW);
			}
		});
	}
}

pid_t fork_hook(void)
{
	loadForkFix();
	return fork();
}

pid_t vfork_hook(void)
{
	loadForkFix();
	return vfork();
}

pid_t forkpty_hook(int *amaster, char *name, struct termios *termp, struct winsize *winp)
{
	loadForkFix();
	return forkpty(amaster, name, termp, winp);
}

int daemon_hook(int __nochdir, int __noclose)
{
	loadForkFix();
	return daemon(__nochdir, __noclose);
}

#else

// The NECP subsystem is the only thing in the kernel that ever checks CS_VALID on userspace processes (Only on iOS 16)
// In order to not break system functionality, we need to readd CS_VALID before any of these are invoked

int necp_match_policy_hook(uint8_t *parameters, size_t parameters_size, void *returned_result)
{
	jbclient_cs_revalidate();
	return syscall(SYSCALL_NECP_MATCH_POLICY, parameters, parameters_size, returned_result);
}

int necp_open_hook(int flags)
{
	jbclient_cs_revalidate();
	return syscall(SYSCALL_NECP_OPEN, flags);
}

int necp_client_action_hook(int necp_fd, uint32_t action, uuid_t client_id, size_t client_id_len, uint8_t *buffer, size_t buffer_size)
{
	jbclient_cs_revalidate();
	return syscall(SYSCALL_NECP_CLIENT_ACTION, necp_fd, action, client_id, client_id_len, buffer, buffer_size);
}

int necp_session_open_hook(int flags)
{
	jbclient_cs_revalidate();
	return syscall(SYSCALL_NECP_SESSION_OPEN, flags);
}

int necp_session_action_hook(int necp_fd, uint32_t action, uint8_t *in_buffer, size_t in_buffer_length, uint8_t *out_buffer, size_t out_buffer_length)
{
	jbclient_cs_revalidate();
	return syscall(SYSCALL_NECP_SESSION_ACTION, necp_fd, action, in_buffer, in_buffer_length, out_buffer, out_buffer_length);
}

// For the userland, there are multiple processes that will check CS_VALID for one reason or another
// As we inject system wide (or at least almost system wide), we can just patch the source of the info though - csops itself
// Additionally we also remove CS_DEBUGGED while we're at it, as on arm64e this also is not set and everything is fine
// That way we have unified behaviour between both arm64 and arm64e

int csops_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize)
{
	int rv = syscall(SYSCALL_CSOPS, pid, ops, useraddr, usersize);
	if (rv != 0) return rv;
	if (ops == CS_OPS_STATUS) {
		if (useraddr && usersize == sizeof(uint32_t)) {
			uint32_t* csflag = (uint32_t *)useraddr;
			*csflag |= CS_VALID;
			*csflag &= ~CS_DEBUGGED;
		}
	}
	return rv;
}

int csops_audittoken_hook(pid_t pid, unsigned int ops, void *useraddr, size_t usersize, audit_token_t *token)
{
	int rv = syscall(SYSCALL_CSOPS_AUDITTOKEN, pid, ops, useraddr, usersize, token);
	if (rv != 0) return rv;
	if (ops == CS_OPS_STATUS) {
		if (useraddr && usersize == sizeof(uint32_t)) {
			uint32_t* csflag = (uint32_t *)useraddr;
			*csflag |= CS_VALID;
			*csflag &= ~CS_DEBUGGED;
		}
	}
	return rv;
}

#endif

bool shouldEnableTweaks(void)
{
	if (access(JBRootPath("/var/.safe_mode"), F_OK) == 0) {
		return false;
	}

	char *tweaksDisabledEnv = getenv("DISABLE_TWEAKS");
	if (tweaksDisabledEnv) {
		if (!strcmp(tweaksDisabledEnv, "1")) {
			return false;
		}
	}

	const char *safeModeValue = getenv("_SafeMode");
	const char *msSafeModeValue = getenv("_MSSafeMode");
	if (safeModeValue) {
		if (!strcmp(safeModeValue, "1")) {
			return false;
		}
	}
	if (msSafeModeValue) {
		if (!strcmp(msSafeModeValue, "1")) {
			return false;
		}
	}

	const char *tweaksDisabledPathSuffixes[] = {
		// System binaries
		"/usr/libexec/xpcproxy",

		// Dopamine app itself (jailbreak detection bypass tweaks can break it)
		"Dopamine.app/Dopamine",
	};
	for (size_t i = 0; i < sizeof(tweaksDisabledPathSuffixes) / sizeof(const char*); i++) {
		if (stringEndsWith(gExecutablePath, tweaksDisabledPathSuffixes[i])) return false;
	}

	if (__builtin_available(iOS 16.0, *)) {
		// These seem to be problematic on iOS 16+ (dyld gets stuck in a weird way when opening TweakLoader)
		const char *iOS16TweaksDisabledPaths[] = {
			"/usr/libexec/logd",
			"/usr/sbin/notifyd",
			"/usr/libexec/usermanagerd",
		};
		for (size_t i = 0; i < sizeof(iOS16TweaksDisabledPaths) / sizeof(const char*); i++) {
			if (!strcmp(gExecutablePath, iOS16TweaksDisabledPaths[i])) return false;
		}
	}

	return true;
}

//export for PatchLoader
__attribute__((visibility("default"))) int PLRequiredJIT() {
	return 0;
}


#include <pwd.h>
#include <libgen.h>
#include <stdio.h>
#include <libproc.h>
#include <libproc_private.h>

//some process may be killed by sandbox if call systme getppid()
pid_t __getppid()
{
    struct proc_bsdinfo procInfo;
	if (proc_pidinfo(getpid(), PROC_PIDTBSDINFO, 0, &procInfo, sizeof(procInfo)) <= 0) {
		return -1;
	}
    return procInfo.pbi_ppid;
}

#define CONTAINER_PATH_PREFIX   "/private/var/mobile/Containers/Data/" // +/Application,PluginKitPlugin,InternalDaemon

void redirectEnvPath(const char* rootdir)
{
    // char executablePath[PATH_MAX]={0};
    // uint32_t bufsize=sizeof(executablePath);
    // if(_NSGetExecutablePath(executablePath, &bufsize)==0 && strstr(executablePath,"testbin2"))
    //     printf("redirectNSHomeDir %s, %s\n\n", rootdir, getenv("CFFIXED_USER_HOME"));

    //for now libSystem should be initlized, container should be set.

    char* homedir = NULL;

/* 
there is a bug in NSHomeDirectory,
if a containerized root process changes its uid/gid, 
NSHomeDirectory will return a home directory that it cannot access. (exclude NSTemporaryDirectory)
We just keep this bug:
*/
    if(!issetugid()) // issetugid() should always be false at this time. (but how about persona-mgmt? idk)
    {
        homedir = getenv("CFFIXED_USER_HOME");
        if(homedir)
        {
            if(strncmp(homedir, CONTAINER_PATH_PREFIX, sizeof(CONTAINER_PATH_PREFIX)-1) == 0)
            {
                return; //containerized
            }
            else
            {
                homedir = NULL; //from parent, drop it
            }
        }
    }

    if(!homedir) {
        struct passwd* pwd = getpwuid(geteuid());
        if(pwd && pwd->pw_dir) {
            homedir = pwd->pw_dir;
        }
    }

    // if(!homedir) {
    //     //CFCopyHomeDirectoryURL does, but not for NSHomeDirectory
    //     homedir = getenv("HOME");
    // }

    if(!homedir) {
        homedir = "/var/empty";
    }

    char newhome[PATH_MAX]={0};
    snprintf(newhome,sizeof(newhome),"%s/%s",rootdir,homedir);
    setenv("CFFIXED_USER_HOME", newhome, 1);
}

void redirectDirs(const char* rootdir)
{
    do {
        
        char executablePath[PATH_MAX]={0};
        uint32_t bufsize=sizeof(executablePath);
        if(_NSGetExecutablePath(executablePath, &bufsize) != 0)
            break;
        
        char realexepath[PATH_MAX];
        if(!realpath(executablePath, realexepath))
            break;
            
        char realjbroot[PATH_MAX];
        if(!realpath(rootdir, realjbroot))
            break;
        
        if(realjbroot[strlen(realjbroot)] != '/')
            strcat(realjbroot, "/");
        
        if(strncmp(realexepath, realjbroot, strlen(realjbroot)) != 0)
            break;

        //for jailbroken binaries
        redirectEnvPath(rootdir);
    
        pid_t ppid = __getppid();
        assert(ppid > 0);
        if(ppid != 1)
            break;
        
        char pwd[PATH_MAX];
        if(getcwd(pwd, sizeof(pwd)) == NULL)
            break;
        if(strcmp(pwd, "/") != 0)
            break;
    
        assert(chdir(rootdir)==0);
        
    } while(0);
}


char HOOK_DYLIB_PATH[PATH_MAX] = {0};

__attribute__((constructor)) static void initializer(void)
{
	struct dl_info di={0};
    dladdr((void*)initializer, &di);
	strncpy(HOOK_DYLIB_PATH, di.dli_fname, sizeof(HOOK_DYLIB_PATH));

	jbclient_process_checkin(&JB_RootPath, &JB_BootUUID, &JB_SandboxExtensions);

	redirectDirs(JB_RootPath);

	// Apply sandbox extensions
	applySandboxExtensions();

	dlopen_hook(JBRootPath("/usr/lib/roothideinit.dylib"), RTLD_NOW);

	// Unset DYLD_INSERT_LIBRARIES, but only if systemhook itself is the only thing contained in it
	const char *dyldInsertLibraries = getenv("DYLD_INSERT_LIBRARIES");
	if (dyldInsertLibraries) {
		if (!strcmp(dyldInsertLibraries, HOOK_DYLIB_PATH)) {
			unsetenv("DYLD_INSERT_LIBRARIES");
		}
	}

	if (loadExecutablePath() == 0) {
		if (strcmp(gExecutablePath, "/usr/sbin/cfprefsd") == 0
		|| strcmp(gExecutablePath, "/usr/libexec/lsd") == 0
		|| strcmp(gExecutablePath, "/System/Library/CoreServices/SpringBoard.app/SpringBoard") == 0) {
			dlopen_hook(JBRootPath("/basebin/rootlesshooks.dylib"), RTLD_NOW);
		}
		else if (strcmp(gExecutablePath, "/usr/libexec/watchdogd") == 0) {
			dlopen_hook(JBRootPath("/basebin/watchdoghook.dylib"), RTLD_NOW);
		}

#ifndef __arm64e__
		// On arm64, writing to executable pages removes CS_VALID from the csflags of the process
		// These hooks are neccessary to get the system to behave with this
		// They are ugly but needed
		litehook_hook_function(csops, csops_hook);
		litehook_hook_function(csops_audittoken, csops_audittoken_hook);
		if (__builtin_available(iOS 16.0, *)) {
			litehook_hook_function(necp_match_policy, necp_match_policy_hook);
			litehook_hook_function(necp_open, necp_open_hook);
			litehook_hook_function(necp_client_action, necp_client_action_hook);
			litehook_hook_function(necp_session_open, necp_session_open_hook);
			litehook_hook_function(necp_session_action, necp_session_action_hook);
		}
#endif

		dlopen_hook(JBRootPath("/usr/lib/roothidepatch.dylib"), RTLD_NOW); //require jit

		if (shouldEnableTweaks()) {
			const char *tweakLoaderPath = JBRootPath("/usr/lib/TweakLoader.dylib");
			if(access(tweakLoaderPath, F_OK) == 0) {
				gTweaksEnabled = true;
				void *tweakLoaderHandle = dlopen_hook(tweakLoaderPath, RTLD_NOW);
				if (tweakLoaderHandle != NULL) {
					dlclose(tweakLoaderHandle);
					dopamine_fix_NSTask();
				}
			}
		}

#ifndef __arm64e__
		// Feeable attempt at adding back CS_VALID
		jbclient_cs_revalidate();
#endif
	}
}

DYLD_INTERPOSE(posix_spawn_hook, posix_spawn)
DYLD_INTERPOSE(posix_spawnp_hook, posix_spawnp)
DYLD_INTERPOSE(execve_hook, execve)
DYLD_INTERPOSE(execle_hook, execle)
DYLD_INTERPOSE(execlp_hook, execlp)
DYLD_INTERPOSE(execv_hook, execv)
DYLD_INTERPOSE(execl_hook, execl)
DYLD_INTERPOSE(execvp_hook, execvp)
DYLD_INTERPOSE(execvP_hook, execvP)
DYLD_INTERPOSE(dlopen_hook, dlopen)
DYLD_INTERPOSE(dlopen_from_hook, dlopen_from)
DYLD_INTERPOSE(dlopen_audited_hook, dlopen_audited)
DYLD_INTERPOSE(dlopen_preflight_hook, dlopen_preflight)
DYLD_INTERPOSE(sandbox_init_hook, sandbox_init)
DYLD_INTERPOSE(sandbox_init_with_parameters_hook, sandbox_init_with_parameters)
DYLD_INTERPOSE(sandbox_init_with_extensions_hook, sandbox_init_with_extensions)
DYLD_INTERPOSE(ptrace_hook, ptrace)
#ifdef __arm64e__
DYLD_INTERPOSE(fork_hook, fork)
DYLD_INTERPOSE(vfork_hook, vfork)
DYLD_INTERPOSE(forkpty_hook, forkpty)
DYLD_INTERPOSE(daemon_hook, daemon)
#endif


int new_issetugidhook()
{
	return 0;
}

void loadPathFix(void)
{
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		litehook_hook_function((void *)&issetugid, (void *)&new_issetugidhook);
	});
}

uid_t setuid_hook(uid_t uid) {
	loadPathFix();
	return setuid(uid);
}
uid_t seteuid_hook(uid_t uid) {
	loadPathFix();
	return seteuid(uid);
}
uid_t setgid_hook(uid_t uid) {
	loadPathFix();
	return setgid(uid);
}
uid_t setegid_hook(uid_t uid) {
	loadPathFix();
	return setegid(uid);
}

DYLD_INTERPOSE(setuid_hook, setuid)
DYLD_INTERPOSE(seteuid_hook, seteuid)
DYLD_INTERPOSE(setgid_hook, setgid)
DYLD_INTERPOSE(setegid_hook, setegid)
