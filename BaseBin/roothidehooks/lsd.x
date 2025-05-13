#import <Foundation/Foundation.h>
#import <spawn.h>
#include <roothide.h>
#include "common.h"

extern char **environ;

#pragma GCC diagnostic ignored "-Wobjc-method-access"
#pragma GCC diagnostic ignored "-Wunused-variable"

/*lsd can only get path for normal app via proc_pidpath, or we can use
  xpc_connection_get_audit_token([connection _xpcConnection], &token) //_LSCopyExecutableURLForXPCConnection
  proc_pidpath_audittoken(tokenarg, buffer, size) //_LSCopyExecutableURLForAuditToken 
  */


@interface LSApplicationWorkspace : NSObject
+ (LSApplicationWorkspace*)defaultWorkspace;
- (NSArray*)applicationsAvailableForHandlingURLScheme:(NSString*)scheme;
- (NSArray*)applicationsAvailableForOpeningURL:(NSURL*)url legacySPI:(BOOL)legacySPI;
- (NSArray*)applicationsAvailableForOpeningURL:(NSURL*)url;
@end

BOOL isJailbreakURLScheme(NSString* scheme)
{
	NSArray* apps = [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] applicationsAvailableForHandlingURLScheme:scheme];
	for(id app in apps) //LSApplicationProxy
	{
		NSURL* bundleURL = [app performSelector:@selector(bundleURL)];
		if(!bundleURL) continue;

		if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
			return YES;
		}
	}
	return NO;
}

static const void *kBlockSchemeTagKey = &kBlockSchemeTagKey;

%hook _LSURLOverride
-(id)initWithOriginalURL:(NSURL*)url
{
	NSNumber* tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
	if(tag && tag.boolValue) {
		NSLog(@"block -[LSURLOverride initWithOriginalURL:] %@", url);
		return nil;
	}
	return %orig;
}
%end

%hook _LSCanOpenURLManager

-(void*)getIsURL:(NSURL*)url alwaysCheckable:(BOOL*)pCheckable hasHandler:(BOOL*)pHasHandler
{
	BOOL _checkable = NO;
	BOOL _hasHandler = NO;
	void* result = %orig(url, &_checkable, &_hasHandler);
	NSLog(@"getIsURL:%@ alwaysCheckable:%d hasHandler:%d", url, _checkable, _hasHandler);

	if(_checkable || _hasHandler)
	{
		NSNumber* tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
		if(tag && tag.boolValue) {
			NSLog(@"block -[_LSCanOpenURLManager getIsURL:alwaysCheckable:hasHandler:] %@", url);
			_hasHandler = NO;
			_checkable = NO;
		}
	}

	if(pCheckable) *pCheckable = _checkable;
	if(pHasHandler) *pHasHandler = _hasHandler;
	return result;
}

- (BOOL)canOpenURL:(NSURL*)url publicSchemes:(BOOL)ispublic privateSchemes:(BOOL)isprivate XPCConnection:(NSXPCConnection*)connection error:(NSError*)err
{
	BOOL blocked = NO;
	
	if(connection) //connection=nil if comes from lsd server
	{
		pid_t pid = connection.processIdentifier;

		NSLog(@"canOpenURL:%@ publicSchemes:%d privateSchemes:%d XPCConnection:%@ proc:%d,%s", url, ispublic, isprivate, connection, pid, proc_get_path(pid,NULL));
		//if(connection) NSLog(@"canOpenURL connection=%@", connection);

		if(jbclient_blacklist_check_pid(pid)==true)
		{
			if(isJailbreakURLScheme(url.scheme))
			{
				NSLog(@"block canOpenURL:%@", url);

				objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

				blocked = YES;
			}
		}
	}

	BOOL ret = %orig;
	if(blocked) {
		assert(ret == NO);
	}
	return ret;
}

%end


%hook _LSQueryContext

-(NSMutableDictionary*)_resolveQueries:(NSMutableSet*)queries XPCConnection:(NSXPCConnection*)connection error:(NSError*)err 
{
	NSMutableDictionary* result = %orig;
	/*
	result: @{
		queries[0]: @[data1, data2, ...],
		queries[1]: @[data1, data2, ...],
	}
	*/

	if(!result || !connection) {
		return result;
	}

	pid_t pid = connection.processIdentifier;

	if(jbclient_blacklist_check_pid(pid)==false) {
		return result;
	}

	NSLog(@"_resolveQueries:%@:%@ XPCConnection:%@ result=%@/%ld proc:%d,%s", [queries class], queries, connection, result.class, result.count, pid, proc_get_path(pid,NULL));
	//NSLog(@"result=%@, %@", result.allKeys, result.allValues);
	for(id key in result)
	{
		NSLog(@"key type: %@, value type: %@", [key class], [result[key] class]);
		if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")]
			|| [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")]
			|| [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithQueryDictionary")])
		{
			NSMutableArray* plugins = result[key];
			NSLog(@"plugins bundle count=%ld", plugins.count);

			NSMutableIndexSet* removed = [[NSMutableIndexSet alloc] init];
			for (int i=0; i<[plugins count]; i++) 
			{
				id plugin = plugins[i]; //LSPlugInKitProxy
				id appbundle = [plugin performSelector:@selector(containingBundle)];
				// NSLog(@"plugin=%@, %@", plugin, appbundle);
				if(!appbundle) continue;

				NSURL* bundleURL = [appbundle performSelector:@selector(bundleURL)];
				if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
					NSLog(@"remove plugin %@ (%@)", plugin, bundleURL);
					[removed addIndex:i];
				}
			}

			[plugins removeObjectsAtIndexes:removed];
			NSLog(@"new plugins bundle count=%ld", plugins.count);

			if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")])
			{
				//NSLog(@"_pluginUnits=%@", [key valueForKey:@"_pluginUnits"]);
				NSLog(@"LSPlugInQueryWithUnits: _pluginUnits count=%ld", [[key valueForKey:@"_pluginUnits"] count]);

				NSMutableArray* units = [[key valueForKey:@"_pluginUnits"] mutableCopy];
				[units removeObjectsAtIndexes:removed];
				[key setValue:[units copy] forKey:@"_pluginUnits"];

				NSLog(@"LSPlugInQueryWithUnits: new _pluginUnits count=%ld", [[key valueForKey:@"_pluginUnits"] count]);
			}
			else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithQueryDictionary")])
			{
				NSLog(@"LSPlugInQueryWithQueryDictionary: _queryDict=%@", [key valueForKey:@"_queryDict"]);
				NSLog(@"LSPlugInQueryWithQueryDictionary: _extensionIdentifiers=%@", [key valueForKey:@"_extensionIdentifiers"]);
				NSLog(@"LSPlugInQueryWithQueryDictionary: _extensionPointIdentifiers=%@", [key valueForKey:@"_extensionPointIdentifiers"]);
			}
			else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")])
			{
				NSLog(@"LSPlugInQueryWithIdentifier: _identifier=%@", [key valueForKey:@"_identifier"]);
			}
		}
		else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryAllUnits")])
		{
			NSMutableArray* unitsArray = result[key];
			for (int i=0; i<[unitsArray count]; i++)
			{
				id unitsResult = unitsArray[i]; //LSPlugInQueryAllUnitsResult

				NSUUID* _dbUUID = [unitsResult valueForKey:@"_dbUUID"];
				NSArray* _pluginUnits = [unitsResult valueForKey:@"_pluginUnits"];
				NSLog(@"LSPlugInQueryAllUnits: _dbUUID=%@, _pluginUnits count=%ld", _dbUUID, _pluginUnits.count);
				id unitQuery = [[NSClassFromString(@"LSPlugInQueryWithUnits") alloc] initWithPlugInUnits:_pluginUnits forDatabaseWithUUID:_dbUUID];
				NSMutableDictionary* queriesResult = [self _resolveQueries:[NSSet setWithObject:unitQuery] XPCConnection:connection error:err];
				if(queriesResult)
				{
					for(id queryKey in queriesResult)
					{
						NSArray* new_pluginUnits = [queryKey valueForKey:@"_pluginUnits"];
						[unitsResult setValue:new_pluginUnits forKey:@"_pluginUnits"];
						NSLog(@"LSPlugInQueryAllUnits: new _pluginUnits count=%ld", new_pluginUnits.count);
					}
				}
			}
		}
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
		char* const args[] = {"/usr/bin/uicache", "-a", NULL};
		const char *uicachePath = jbroot(args[0]);
		if (access(uicachePath, F_OK) == 0) {
			posix_spawn(NULL, uicachePath, NULL, NULL, args, environ);
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
