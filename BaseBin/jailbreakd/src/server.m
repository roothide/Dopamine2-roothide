#include <Foundation/Foundation.h>
#include <bsm/libbsm.h>
#include <libproc.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/roothider.h>

void jailbreakd_received_message(mach_port_t port)
{
	@autoreleasepool {
		xpc_object_t message = nil;
		int err = xpc_pipe_receive(port, &message);
		if (err != 0) {
			JBLogError("xpc_pipe_receive error %d", err);
			return;
		}

		xpc_object_t reply = xpc_dictionary_create_reply(message);

		JBD_MESSAGE_ID msgId = xpc_dictionary_get_uint64(message, "id");
		
		if (xpc_get_type(message) == XPC_TYPE_DICTIONARY) {
			audit_token_t auditToken = {0};
			xpc_dictionary_get_audit_token(message, &auditToken);
			uid_t clientUid = audit_token_to_euid(auditToken);
			pid_t clientPid = audit_token_to_pid(auditToken);

			char* desc = NULL;
			JBLogDebug("received message %d from %d(%s) with dictionary: %s", msgId, clientPid, proc_get_path(clientPid,NULL), (desc=xpc_copy_description(message)));
			if(desc) free(desc);

			switch (msgId) {
				case JBD_MSG_SPAWN_PATCH_CHILD: {
					int64_t result = 0;
					pid_t pid = xpc_dictionary_get_int64(message, "pid");
					bool resume = xpc_dictionary_get_bool(message, "resume");
					pid_t ppid = proc_get_ppid(pid);
					if(ppid == clientPid) {
						JBLogDebug("spawn patch: client pid=%d, child pid=%d, child's parent pid=%d, child proc=%s", clientPid, pid, ppid, proc_get_path(pid,NULL));

						if(roothide_patch_proc(pid) == 0) {
							if(resume) kill(pid, SIGCONT);
						} else {
							JBLogError("spawn patch failed: %d", pid);
							result = -1;
						}

					} else {
						JBLogError("spawn patch denied: %d", pid);
						result = -1;
					}
					xpc_dictionary_set_int64(reply, "result", result);
					break;
				}

				case JBD_MSG_SPAWN_EXEC_START: {
					bool resume = xpc_dictionary_get_bool(message, "resume");
					const char* execfile = xpc_dictionary_get_string(message, "execfile");
					JBLogDebug("add exec patch: %d %s", clientPid, execfile);
					int64_t result = spawnExecPatchAdd(clientPid, resume);
					xpc_dictionary_set_int64(reply, "result", result);
					break;
				}

				case JBD_MSG_SPAWN_EXEC_CANCEL: {
					const char* execfile = xpc_dictionary_get_string(message, "execfile");
					JBLogDebug("del exec patch: %d %s", clientPid, execfile);
					int64_t result = spawnExecPatchDel(clientPid);
					xpc_dictionary_set_int64(reply, "result", result);
					break;
				}

				case JBD_MSG_EXEC_TRACE_START: {
					int64_t result = -1;
					uint64_t traced = xpc_dictionary_get_uint64(message, "traced");
					const char* execfile = xpc_dictionary_get_string(message, "execfile");
					result = execTraceProcess(clientPid, traced);
					xpc_dictionary_set_int64(reply, "result", result);
					break;
				}

				case JBD_MSG_EXEC_TRACE_CANCEL: {
					int64_t result = -1;
					const char* execfile = xpc_dictionary_get_string(message, "execfile");
					result = execTraceCancel(clientPid);
					xpc_dictionary_set_int64(reply, "result", result);
					break;
				}

				case JBD_MSG_SYSTEMWIDE_LOG: {
#ifdef ENABLE_LOGS
					const char* progname = NULL;
					const char* procpath = proc_get_path(clientPid,NULL);
					if(procpath) {
						progname = strrchr(procpath, '/');
						if(progname) progname++; else progname = procpath;
					}
					uint64_t tid = xpc_dictionary_get_uint64(message, "tid");
					const char* log = xpc_dictionary_get_string(message, "log");
					JBLogFunction(JBLogGetLogFilePath("systemwide", NULL), clientPid, tid, progname ? progname : "(null)", "%s", log);
					xpc_dictionary_set_int64(reply, "result", 0);
#else
					abort();
#endif
					break;
				}

				case JBD_MSG_TEST_CALL: {
					int value = xpc_dictionary_get_int64(message, "value");
					JBLogDebug("jailbreakd test call(%llu) from %d,%s", value, clientPid, proc_get_path(clientPid,NULL));	
					xpc_dictionary_set_int64(reply, "result", value * 2);
					
					if(clientUid == 0) {
						abort(); // crashreporter test
					}

					break;
				}
			}
		}
		if (reply) {
			char* desc = NULL;
			JBLogDebug("reply message %d with %s", msgId, (desc=xpc_copy_description(reply)));
			if(desc) free(desc);
			err = xpc_pipe_routine_reply(reply);
			if (err != 0) {
				JBLogError("Error %d sending response", err);
			}
		}
	}
}
