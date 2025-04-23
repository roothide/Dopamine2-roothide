#include <stdio.h>
#include <unistd.h>
#include <sys/sysctl.h>
#include <sys/syscall.h>
#include <dispatch/dispatch.h>

#include "roothider.h"

int __sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen);
int syscall__sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen) {
	return syscall(SYS_sysctl, name, namelen, oldp, oldlenp, newp, newlen);
}
int __sysctl_hook(int *name, u_int namelen, void *oldp, size_t *oldlenp, const void *newp, size_t newlen)
{
	static int cached_namelen = 0;
	static int cached_name[CTL_MAXNAME+2]={0};

	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		int mib[] = {0, 3}; //https://github.com/apple-oss-distributions/Libc/blob/899a3b2d52d95d75e05fb286a5e64975ec3de757/gen/FreeBSD/sysctlbyname.c#L24
		size_t buflen = sizeof(cached_name);
		const char* query = "security.mac.amfi.developer_mode_status";
		if(syscall__sysctl(mib, sizeof(mib)/sizeof(mib[0]), cached_name, &buflen, (void*)query, strlen(query))==0) {
			cached_namelen = buflen / sizeof(cached_name[0]);
		}
	});

	if(name && namelen && cached_namelen &&
	 namelen==cached_namelen && memcmp(cached_name, name, namelen*sizeof(name[0]))==0) {
		if(oldp && oldlenp && *oldlenp>=sizeof(int)) {
			*(int*)oldp = 1;
			*oldlenp = sizeof(int);
			return 0;
		}
	}

	return syscall__sysctl(name,namelen,oldp,oldlenp,newp,newlen);
}

int __sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen);
int syscall__sysctlbyname(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
	return syscall(SYS_sysctlbyname, name, namelen, oldp, oldlenp, newp, newlen);
}
int __sysctlbyname_hook(const char *name, size_t namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
	if(name && namelen && strncmp(name, "security.mac.amfi.developer_mode_status", namelen)==0) {
		if(oldp && oldlenp && *oldlenp>=sizeof(int)) {
			*(int*)oldp = 1;
			*oldlenp = sizeof(int);
			return 0;
		}
	}
	return syscall__sysctlbyname(name,namelen,oldp,oldlenp,newp,newlen);
}
