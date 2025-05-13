#include <sandbox.h>
#include <substrate.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>

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

/************************** roothide specific *******************************/
if(isBlacklistedToken(&au)) {
	JBLogDebug("sandbox_check_by_audit_token operation=%s name=%s from %s", operation, name, proc_get_path(audit_token_to_pid(au),NULL));
} else {
/************************** roothide specific *******************************/
		
		if (strcmp(operation, "mach-lookup") == 0) {
			if (strncmp((char *)name, "cy:", 3) == 0 || strncmp((char *)name, "lh:", 3) == 0) {
				/* always allow */
				return 0;
			}
		}
	}

}

	return sandbox_check_by_audit_token_orig(au, operation, sandbox_filter_type, name, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}

void initIPCHooks(void)
{
	MSHookFunction(&sandbox_check_by_audit_token, (void *)sandbox_check_by_audit_token_hook, (void **)&sandbox_check_by_audit_token_orig);
}