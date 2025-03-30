#import <Foundation/Foundation.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

#define PROC_PIDPATHINFO_MAXSIZE        (4*MAXPATHLEN)

bool __thread gAllowRedirection = true;

BOOL preferencePlistNeedsRedirection(NSString *plistPath)
{
	if ( [plistPath hasPrefix:@"/var/db/"]
	  || [plistPath hasPrefix:@"/private/var/preferences/"]
	  || [plistPath hasPrefix:@"/private/var/mobile/Containers/"] ) 
	  return NO;

	NSString *plistName = plistPath.lastPathComponent;

	NSArray* appleInternalBundleIds = @[
		@"com.apple.Terminal.plist",
	];

	if ([appleInternalBundleIds containsObject:plistName])
		return YES;

	if ([plistName hasPrefix:@"com.apple."]
	  || [plistName hasPrefix:@"group.com.apple."]
	 || [plistName hasPrefix:@"systemgroup.com.apple."])
	  return NO;

	NSArray *additionalSystemPlistNames = @[
		@".GlobalPreferences.plist",
		@".GlobalPreferences_m.plist",
		@"bluetoothaudiod.plist",
		@"NetworkInterfaces.plist",
		@"OSThermalStatus.plist",
		@"preferences.plist",
		@"osanalyticshelper.plist",
		@"UserEventAgent.plist",
		@"wifid.plist",
		@"dprivacyd.plist",
		@"silhouette.plist",
		@"nfcd.plist",
		@"kNPProgressTrackerDomain.plist",
		@"siriknowledged.plist",
		@"UITextInputContextIdentifiers.plist",
		@"mobile_storage_proxy.plist",
		@"splashboardd.plist",
		@"mobile_installation_proxy.plist",
		@"languageassetd.plist",
		@"ptpcamerad.plist",
		@"com.google.gmp.measurement.monitor.plist",
		@"com.google.gmp.measurement.plist",
	];

	return ![additionalSystemPlistNames containsObject:plistName];
}

BOOL (*orig_CFPrefsGetPathForTriplet)(CFStringRef, CFStringRef, BOOL, CFStringRef, UInt8*);
BOOL new_CFPrefsGetPathForTriplet(CFStringRef identifier, CFStringRef user, BOOL byHost, CFStringRef container, UInt8 *buffer)
{
	BOOL orig = orig_CFPrefsGetPathForTriplet(identifier, user, byHost, container, buffer);

	NSLog(@"CFPrefsGetPathForTriplet %@ %@ %d %@ : %d %s", identifier, user, byHost, container, orig, orig?(char*)buffer:"");
	// NSLog(@"callstack=%@", [NSThread callStackSymbols]);

	if(!gAllowRedirection) {
		NSLog(@"CFPrefsGetPathForTriplet deny redirection");
		return orig;
	}

	if(orig && buffer)
	{
		NSString* origPath = [NSString stringWithUTF8String:(char*)buffer];
		BOOL needsRedirection = preferencePlistNeedsRedirection(origPath);
		if (needsRedirection) {
			NSLog(@"Plist redirected to jbroot:%@", origPath);
			const char* newpath = jbroot(origPath.UTF8String);
			//buffer size=1024 in CFXPreferences_fileProtectionClassForIdentifier_user_host_container___block_invoke
			if(strlen(newpath) < 1024) {
				strcpy((char*)buffer, newpath);
				NSLog(@"CFPrefsGetPathForTriplet redirect to %s", buffer);
			}
		}
	}

	return orig;
}

void* (*orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__)(id self, SEL selector, xpc_object_t message, xpc_connection_t connection, void* replyHandler);
void* new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(id self, SEL selector, xpc_object_t message, xpc_connection_t connection, void* replyHandler)
{
    uid_t clientUid = xpc_connection_get_euid(connection);
    pid_t clientPid = xpc_connection_get_pid(connection);

	uint32_t csFlags = 0;
	csops(clientPid, CS_OPS_STATUS, &csFlags, sizeof(csFlags));

	char pathbuf[PROC_PIDPATHINFO_MAXSIZE]={0};
	if(proc_pidpath(clientPid, pathbuf, sizeof(pathbuf)) <= 0) {
		NSLog(@"CFPrefsDaemon: unable to get proc path for %d", clientPid);
	}

	NSLog(@"CFPrefsDaemon: handleMessage %p/%d pid=%d uid=%d csflags=%x proc=%s", message, xpc_get_type(message)==XPC_TYPE_DICTIONARY, clientPid, clientUid, csFlags, pathbuf);

	// char* desc = xpc_copy_description(message);
	// NSLog(@"CFPrefsDaemon: handleMessage Operation=%lld, msg=%s", xpc_dictionary_get_int64(message, "CFPreferencesOperation"), desc);
	// if(desc) free(desc);

	bool allow = true;
	if(clientUid==501 && (csFlags & CS_PLATFORM_BINARY)==0) {
		if(isBlacklisted(pathbuf)) {
			NSLog(@"CFPrefsDaemon: deny redirection %s", pathbuf);
			allow = false;
		}
	}
	gAllowRedirection = allow;

	return orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__(self, selector, message, connection, replyHandler);
}

void cfprefsdInit(void)
{
	NSLog(@"cfprefsdInit..");

	MSImageRef coreFoundationImage = MSGetImageByName("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");

	void* CFPrefsGetPathForTriplet_ptr = MSFindSymbol(coreFoundationImage, "__CFPrefsGetPathForTriplet");
	if(CFPrefsGetPathForTriplet_ptr)
	{
		MSHookFunction(CFPrefsGetPathForTriplet_ptr, (void *)&new_CFPrefsGetPathForTriplet, (void **)&orig_CFPrefsGetPathForTriplet);
		NSLog(@"hook __CFPrefsGetPathForTriplet %p => %p : %p", CFPrefsGetPathForTriplet_ptr, new_CFPrefsGetPathForTriplet, orig_CFPrefsGetPathForTriplet);
	}

	void* __CFPrefsDaemon_handleMessage_fromPeer_replyHandler__ = MSFindSymbol(coreFoundationImage, "-[CFPrefsDaemon handleMessage:fromPeer:replyHandler:]");
	if(__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__)
	{
		MSHookFunction(__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__, (void *)new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__, (void **)&orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__);
		NSLog(@"hook __CFPrefsDaemon_handleMessage_fromPeer_replyHandler__ %p => %p : %p", __CFPrefsDaemon_handleMessage_fromPeer_replyHandler__, new__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__, orig__CFPrefsDaemon_handleMessage_fromPeer_replyHandler__);
	}

	%init();
}
