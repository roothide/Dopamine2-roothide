#include <sandbox.h>
#include <substrate.h>
#include <libproc.h>
#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/codesign.h>
#include <libjailbreak/deny.h>
#include <libjailbreak/log.h>


int (*sandbox_check_by_audit_token_orig)(audit_token_t au, const char *operation, int sandbox_filter_type, ...);
int sandbox_check_by_audit_token_hook(audit_token_t au, const char *operation, int sandbox_filter_type, ...)
{
	va_list a;
	va_start(a, sandbox_filter_type);
	const char *name = va_arg(a, const char *);
	const void *arg2 = va_arg(a, void *);
	const void *arg3 = va_arg(a, void *);
	const void *arg4 = va_arg(a, void *);
	const void *arg5 = va_arg(a, void *);
	const void *arg6 = va_arg(a, void *);
	const void *arg7 = va_arg(a, void *);
	const void *arg8 = va_arg(a, void *);
	const void *arg9 = va_arg(a, void *);
	const void *arg10 = va_arg(a, void *);
	va_end(a);
	if (name && operation) {
		pid_t pid = audit_token_to_pid(au);
		uid_t uid = audit_token_to_euid(au);

		uint32_t csFlags = 0;
		csops(pid, CS_OPS_STATUS, &csFlags, sizeof(csFlags));

		bool allow=false;
		if(strcmp(operation, "mach-lookup") == 0) {
			volatile int result1 = strncmp((char *)name, "cy:", 3);
			volatile int result2 = strncmp((char *)name, "lh:", 3);
			if (result1 == 0 || result2 == 0) {
				allow = true;
			}
		}

		if(uid==501 && (csFlags & CS_PLATFORM_BINARY)==0)
		{
			char pathbuf[4*MAXPATHLEN]={0};
			if(pid>0 && proc_pidpath(pid, pathbuf, sizeof(pathbuf))>0)
			{
				if(isBlacklisted(pathbuf)) {
					JBLogDebug("sandbox_check_by_audit_token operation=%s name=%s from %s", operation, name, pathbuf);
					allow = false;
				}
			}
		}

		if(allow) return 0;
	}
	return sandbox_check_by_audit_token_orig(au, operation, sandbox_filter_type, name, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}

void initIPCHooks(void)
{
	MSHookFunction(&sandbox_check_by_audit_token, (void *)sandbox_check_by_audit_token_hook, (void **)&sandbox_check_by_audit_token_orig);
}