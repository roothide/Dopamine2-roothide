#import <Foundation/Foundation.h>

NSString* safe_getExecutablePath()
{
	extern char*** _NSGetArgv();
	char* executablePathC = **_NSGetArgv();
	return [NSString stringWithUTF8String:executablePathC];
}

NSString* getProcessName()
{
	return safe_getExecutablePath().lastPathComponent;
}

%ctor
{
	NSLog(@"rootlesshooks coming... %@", safe_getExecutablePath());
	NSString *processName = getProcessName();
	if ([processName isEqualToString:@"installd"]) {
		extern void installdInit(void);
		//installdInit();
	}
	else if ([processName isEqualToString:@"cfprefsd"]) {
		extern void cfprefsdInit(void);
		cfprefsdInit();
	}
	else if ([processName isEqualToString:@"lsd"]) {
		extern void lsdInit(void);
		lsdInit();
	}
	else if ([processName isEqualToString:@"SpringBoard"]) {
		extern void sbInit(void);
		sbInit();
	}
}