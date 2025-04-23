#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sandbox.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <sys/mman.h>

#include "machomerger_hook.h"
#include "dyld_jbinfo.h"
#include "dyld.h"

#include <libjailbreak/jbclient_mach.h>

// Library validation bypass
// Dyld will call fcntl to attach a code signature to a dylib before mapping it in
// So we hook fcntl to ensure the code signature to be attached is added to trustcache

int HOOK(__fcntl)(int fd, int cmd, void *arg1, void *arg2, void *arg3, void *arg4, void *arg5, void *arg6, void *arg7, void *arg8)
{
	// int ret = (int)msyscall_errno(0x5C, fd, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
	// if(ret == 0) return ret;

	switch (cmd) {
		case F_ADDSIGS:
			break;
			
		case F_ADDFILESIGS:
		case F_ADDFILESIGS_INFO:
		case F_ADDFILESIGS_RETURN: {
			struct siginfo siginfo;
			siginfo.source = (cmd == F_ADDSIGS) ? SIGNATURE_SOURCE_PROC : SIGNATURE_SOURCE_FILE;
			if (arg1) memcpy(&siginfo.signature, (fsignatures_t *)arg1, sizeof (fsignatures_t));
			jbclient_mach_trust_file(fd, arg1 ? &siginfo : NULL);
			break;
		}
	}
	return (int)msyscall_errno(0x5C, fd, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8);
}