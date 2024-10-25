#import <Foundation/Foundation.h>
#import <libjailbreak/util.h>
#include <roothide.h>
#include "common.h"

%hook _LSCanOpenURLManager

- (BOOL)canOpenURL:(NSURL*)url publicSchemes:(BOOL)ispublic privateSchemes:(BOOL)isprivate XPCConnection:(NSXPCConnection*)xpc error:(NSError*)err
{
	char pathbuf[PATH_MAX]={0};
	if(xpc) {
		//lsd can only get path for normal app
		proc_pidpath(xpc.processIdentifier, pathbuf, sizeof(pathbuf));
	}

	NSLog(@"canOpenURL:%@ publicSchemes:%d privateSchemes:%d XPCConnection:%@ proc:%d,%s", url, ispublic, isprivate, xpc, xpc.processIdentifier, pathbuf);
	//if(xpc) NSLog(@"canOpenURL:xpc=%@", xpc);

	NSArray* jbschemes = @[
		@"filza", 
		@"db-lmvo0l08204d0a0",
		@"boxsdk-810yk37nbrpwaee5907xc4iz8c1ay3my",
		@"com.googleusercontent.apps.802910049260-0hf6uv6nsj21itl94v66tphcqnfl172r",
		@"sileo",
		@"zbra", 
		@"santander", 
		@"icleaner", 
		@"xina", 
		@"ssh",
		@"apt-repo", 
		@"cydia",
		@"activator",
		@"postbox",
	];

	if(xpc && isSandboxedApp(xpc.processIdentifier, pathbuf))
	{
		if([jbschemes containsObject:url.scheme.lowercaseString]) {
			NSLog(@"block %@ for %s", url, pathbuf);
			return NO;
		}
	}

	return %orig;
}

%end


%hook _LSQueryContext

-(NSMutableDictionary*)_resolveQueries:(id)queries XPCConnection:(NSXPCConnection*)xpc error:(NSError*)err 
{
	NSMutableDictionary* result = %orig;

	char pathbuf[PATH_MAX]={0};
	if(xpc) {
		//lsd can only get path for normal app
		proc_pidpath(xpc.processIdentifier, pathbuf, sizeof(pathbuf));

		/* or 
			token
			xpc_connection_get_audit_token([xpc _xpcConnection], &token) //_LSCopyExecutableURLForXPCConnection
			proc_pidpath_audittoken(tokenarg, buffer, size) //_LSCopyExecutableURLForAuditToken
		*/
		
	}

	NSLog(@"_resolveQueries:%@ XPCConnection:%@ count=%ld proc:%d,%s", queries, xpc, result.count, xpc.processIdentifier, pathbuf);

	if(result)
	{
		NSLog(@"result=%@", result.class);
		//NSLog(@"result=%@, %@", result.allKeys, result.allValues);
		for(id key in result)
		{
			NSLog(@"result=%@, %@", [key class], [result[key] class]);
			if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")])
			{
				//NSLog(@"_pluginUnits=%@", [key valueForKey:@"_pluginUnits"]);
				//NSLog(@"plugins=%@", result[key]);

				if(xpc && isNormalAppPath(pathbuf))
				{
					NSMutableIndexSet* removed = [[NSMutableIndexSet alloc] init];
					for (int i=0; i<[result[key] count]; i++) 
					{
						id plugin = result[key][i];
						id appbundle = [plugin performSelector:@selector(containingBundle)];
						//NSLog(@"plugin=%@, %@", plugin, appbundle);
						if(!appbundle) continue;

						NSURL* bundleURL = [appbundle performSelector:@selector(bundleURL)];
						if(isJailbreakPath(bundleURL.path.fileSystemRepresentation)) {
							NSLog(@"remove %@ for %s", plugin, pathbuf);
							[removed addIndex:i];
						}
					}

					[result[key] removeObjectsAtIndexes:removed];

					NSMutableArray* units = [[key valueForKey:@"_pluginUnits"] mutableCopy];
					[units removeObjectsAtIndexes:removed];
					[key setValue:[units copy] forKey:@"_pluginUnits"];
					
				}
			}
		}
		NSLog(@"result=%@", result);
	}

	return result;
}

%end


//or -[Copier initWithSourceURL:uniqueIdentifier:destURL:callbackTarget:selector:options:] in transitd
NSURL* (*orig_LSGetInboxURLForBundleIdentifier)(NSString* bundleIdentifier)=NULL;
NSURL* new_LSGetInboxURLForBundleIdentifier(NSString* bundleIdentifier)
{
	NSURL* pathURL = orig_LSGetInboxURLForBundleIdentifier(bundleIdentifier);

	if( ![bundleIdentifier hasPrefix:@"com.apple."] 
			&& [pathURL.path hasPrefix:@"/var/mobile/Library/Application Support/Containers/"])
	{
		NSLog(@"redirect Inbox %@ : %@", bundleIdentifier, pathURL);
		pathURL = [NSURL fileURLWithPath:jbroot(pathURL.path)]; //require unsandboxing file-write-read for jbroot:/var/
	}

	return pathURL;
}

int (*orig_LSServer_RebuildApplicationDatabases)()=NULL;
int new_LSServer_RebuildApplicationDatabases()
{
	int r = orig_LSServer_RebuildApplicationDatabases();

	if(access(jbroot("/.disable_auto_uicache"), F_OK) == 0) return r;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		// Ensure jailbreak apps are readded to icon cache after the system reloads it
		// A bit hacky, but works
		const char *uicachePath = jbroot("/usr/bin/uicache");
		if (!access(uicachePath, F_OK)) {
			exec_cmd(uicachePath, "-a", NULL);
		}
	});

	return r;
}

void lsdInit(void)
{
	NSLog(@"lsdInit...");

	MSImageRef coreServicesImage = MSGetImageByName("/System/Library/Frameworks/CoreServices.framework/CoreServices");

	void* _LSGetInboxURLForBundleIdentifier = MSFindSymbol(coreServicesImage, "__LSGetInboxURLForBundleIdentifier");
	NSLog(@"coreServicesImage=%p, _LSGetInboxURLForBundleIdentifier=%p", coreServicesImage, _LSGetInboxURLForBundleIdentifier);
	if(_LSGetInboxURLForBundleIdentifier)
	{
		MSHookFunction(_LSGetInboxURLForBundleIdentifier, (void *)&new_LSGetInboxURLForBundleIdentifier, (void **)&orig_LSGetInboxURLForBundleIdentifier);
	}
	
	void* _LSServer_RebuildApplicationDatabases = MSFindSymbol(coreServicesImage, "__LSServer_RebuildApplicationDatabases");
	NSLog(@"coreServicesImage=%p, _LSServer_RebuildApplicationDatabases=%p", coreServicesImage, _LSServer_RebuildApplicationDatabases);
	if(_LSServer_RebuildApplicationDatabases)
	{
		MSHookFunction(_LSServer_RebuildApplicationDatabases, (void *)&new_LSServer_RebuildApplicationDatabases, (void **)&orig_LSServer_RebuildApplicationDatabases);
	}

	%init();
}
