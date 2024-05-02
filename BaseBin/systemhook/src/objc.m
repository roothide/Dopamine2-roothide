#include <libjailbreak/jbclient_xpc.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <os/log.h>
#include <spawn.h>
#import <dlfcn.h>
#import "common.h"
#import "litehook.h"


struct _posix_spawn_args_desc {
	size_t		attr_size;	/* size of attributes block */
	posix_spawnattr_t	attrp;		/* pointer to block */
	size_t	file_actions_size;	/* size of file actions block */
	posix_spawn_file_actions_t file_actions;	/* pointer to block */
}; //https://opensource.apple.com/source/xnu/xnu-4570.31.3/bsd/sys/spawn_internal.h

#define POSIX_SPAWN_PROC_TYPE_DRIVER 0x700
#define POSIX_SPAWN_SYSTEMHOOK_HANDLED	0x2000 // _POSIX_SPAWN_ALLOW_DATA_EXEC(0x2000) only used in DEBUG/DEVELOPMENT kernel
int posix_spawnattr_getprocesstype_np(const posix_spawnattr_t *__restrict, int *__restrict) __API_AVAILABLE(macos(10.8), ios(6.0));

int syscall__posix_spawn(pid_t* pidp, const char * path, struct _posix_spawn_args_desc* ad, char *const argv, char *const envp);
int posix_spawn_hook(pid_t* pidp, const char* path, posix_spawn_file_actions_t* file_actions, posix_spawnattr_t * attrp,char *const argv,char *const envp);
int __posix_spawn(pid_t* pidp, const char * path, struct _posix_spawn_args_desc* ad, char *const argv, char *const envp);
int new__posix_spawn(pid_t* pidp, const char * path, struct _posix_spawn_args_desc* ad, char *const argv, char *const envp)
{
	int ret;

    short flags = 0;
    int proctype = 0;

	if(ad && ad->attrp) {
		posix_spawnattr_getflags(&ad->attrp, &flags);
		posix_spawnattr_getprocesstype_np(&ad->attrp, &proctype);
	}

	if((proctype != POSIX_SPAWN_PROC_TYPE_DRIVER) && (flags & POSIX_SPAWN_SYSTEMHOOK_HANDLED)==0) {
		//reentrant
		ret = posix_spawn_hook(pidp, path, &ad->file_actions, &ad->attrp, argv, envp);

	} else {
		ret =  syscall__posix_spawn(pidp, path, ad, argv, envp);
	}

	return ret;
}


// If you ever wondered how to hook an Objective C method without linking anything (Foundation/libobjc), this is how

extern char **environ;

id (*__objc_getClass)(const char *name);
id (*__objc_alloc)(Class cls);
void (*__objc_release)(id obj);
void *(*__objc_msgSend_0)(id self, SEL _cmd);
void *(*__objc_msgSend_1)(id self, SEL _cmd, void *a1);
void *(*__objc_msgSend_2)(id self, SEL _cmd, void *a1, void *a2);
void *(*__objc_msgSend_3)(id self, SEL _cmd, void *a1, void *a2, void *a3);
void *(*__objc_msgSend_4)(id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4);
void *(*__objc_msgSend_5)(id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4, void *a5);
void *(*__objc_msgSend_6)(id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6);
IMP (*__class_replaceMethod)(Class cls, SEL name, IMP imp, const char *types);

bool (*NSConcreteTask_launchWithDictionary_error__orig)(id self, id sender, NSDictionary *dictionary, NSError **errorOut);
bool NSConcreteTask_launchWithDictionary_error__hook(id self, id sender, NSDictionary *dictionary, NSError **errorOut)
{
	static dispatch_once_t onceToken;
	dispatch_once (&onceToken, ^{
		litehook_hook_function((void *)&__posix_spawn, (void *)&new__posix_spawn);
	});

	if (dictionary) {
		Class NSString_class = __objc_getClass("NSString");
		Class NSMutableDictionary_class = __objc_getClass("NSMutableDictionary");

		NSString *keyExecutablePath = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), "_NSTaskExecutablePath");
		NSString *keyEnvironmentDict = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), "_NSTaskEnvironmentDictionary");
		NSString *dyldInsertLibraries = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), "DYLD_INSERT_LIBRARIES");
		NSString *hookDylibPath = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), HOOK_DYLIB_PATH);

		NSString *executablePath = __objc_msgSend_1(dictionary, @selector(objectForKey:), keyExecutablePath);
		if (executablePath) {
			const char *executablePathC = __objc_msgSend_0(executablePath, @selector(UTF8String));
			jbclient_trust_binary(executablePathC);
		}

		NSDictionary *existingEnvironment = __objc_msgSend_1(dictionary, @selector(objectForKey:), keyEnvironmentDict);
		NSMutableDictionary *mutableEnvironment;
		if (existingEnvironment) {
			// Easy
			mutableEnvironment = __objc_msgSend_0(existingEnvironment, @selector(mutableCopy));
		}
		else {
			// Pain...
			mutableEnvironment = __objc_msgSend_0(__objc_alloc(NSMutableDictionary_class), @selector(init));

			int i = 0;
			while(environ[i]) {
				char *key = NULL;
				char *value = NULL;
				char *full = strdup(environ[i++]);
				char *tok = strtok(full, "=");
				if (tok) {
					key = strdup(tok);
					tok = strtok(NULL, "=");
					if (tok) {
						value = strdup(tok);
					}
				}
				if (full) free(full);

				if (key && value) {
					NSString *nsKey = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), key);
					NSString *nsValue = __objc_msgSend_1(__objc_alloc(NSString_class), @selector(initWithUTF8String:), value);
					if (nsKey && nsValue) {
						__objc_msgSend_2(mutableEnvironment, @selector(setObject:forKey:), nsValue, nsKey);
					}
					if (nsKey) __objc_release(nsKey);
					if (nsValue) __objc_release(nsValue);
				}
				if (key) free(key);
				if (value) free(value);
			}
		}

		NSDictionary *mutableLaunchDictionary = __objc_msgSend_0(dictionary, @selector(mutableCopy));
		__objc_msgSend_2(mutableEnvironment, @selector(setObject:forKey:), hookDylibPath, dyldInsertLibraries);
		__objc_msgSend_2(mutableLaunchDictionary, @selector(setObject:forKey:), mutableEnvironment, keyEnvironmentDict);

		bool r = NSConcreteTask_launchWithDictionary_error__orig(self, sender, dictionary, errorOut);

		__objc_release(mutableEnvironment);
		__objc_release(mutableLaunchDictionary);
		__objc_release(keyExecutablePath);
		__objc_release(keyEnvironmentDict);
		__objc_release(dyldInsertLibraries);
		__objc_release(hookDylibPath);
		return r;
	}
	else {
		return NSConcreteTask_launchWithDictionary_error__orig(self, sender, dictionary, errorOut);;
	}
}

void dopamine_fix_NSTask(void)
{
	// This only works if libobjc and Foundation are already loaded, that is by design
	// So as of right now it only automatically works if some tweak is loaded (as libellekit depends on Foundation)
	// If you want to use NSTask in your app or whatever, call this function yourself after Foundation is loaded
	// This could be automated but it's difficult due to image loading callbacks being shit
	void *libobjcHandle = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOLOAD);
	void *foundationHandle = dlopen("/System/Library/Frameworks/Foundation.framework/Foundation", RTLD_NOLOAD);
	if (libobjcHandle && foundationHandle) {
		static dispatch_once_t onceToken;
		dispatch_once (&onceToken, ^{
			__objc_getClass = dlsym(libobjcHandle, "objc_getClass");
			__objc_alloc = dlsym(libobjcHandle, "objc_alloc");
			__objc_release = dlsym(libobjcHandle, "objc_release");

			void *objc_msgSend = dlsym(libobjcHandle, "objc_msgSend");
			__objc_msgSend_0 = objc_msgSend;
			__objc_msgSend_1 = objc_msgSend;
			__objc_msgSend_2 = objc_msgSend;
			__objc_msgSend_3 = objc_msgSend;
			__objc_msgSend_4 = objc_msgSend;
			__objc_msgSend_5 = objc_msgSend;
			__objc_msgSend_6 = objc_msgSend;

			__class_replaceMethod = dlsym(libobjcHandle, "class_replaceMethod");

			Class NSConcreteTask_class = __objc_getClass("NSConcreteTask");
			NSConcreteTask_launchWithDictionary_error__orig = (void *)__class_replaceMethod(NSConcreteTask_class, @selector(launchWithDictionary:error:), (IMP)NSConcreteTask_launchWithDictionary_error__hook, "B@:@^@");
		});
	}
}