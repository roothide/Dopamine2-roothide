#import <Foundation/Foundation.h>
#include "common.h"
#include <roothide.h>

@interface XBSnapshotContainerIdentity : NSObject
@property NSString* bundleIdentifier;
@end

%hook XBSnapshotContainerIdentity

/*
-(id)_initWithBundleIdentifier:(id)arg1 bundlePath:(id)arg2 dataContainerPath:(id)arg3 bundleContainerPath:(id)arg4 
{
    NSLog(@"snapshot init, id=%@, bundlePath=%@, dataContainerPath=%@, bundleContainerPath=%@", arg1, arg2, arg3, arg4);

    return %orig;
}
*/

-(NSString *)snapshotContainerPath {
    NSString* path = %orig;

    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
        NSLog(@"snapshotContainerPath redirect %@ : %@", self.bundleIdentifier, path);
        path = jbroot(path);
    }

    return path;
}

%end


void sbInit(void)
{
	NSLog(@"sbInit...");
	%init();
}
