#include <Foundation/Foundation.h>
#include <unistd.h>
#include <pthread.h>
#include <mach/mach.h>

#include "../libjailbreak.h"
#include "common.h"
#include "ptrace.h"
#include "log.h"

#ifndef __MigPackStructs
#define __MigPackStructs
#endif
#include "mach_exc.h" //mig -arch arm64 -arch arm64e mach_exc.defs

NSLock* trace_data_lock = nil;
NSMutableDictionary* trace_data_record = nil;

typedef struct {
    uint64_t    traced_flag_addr;
    exception_mask_t       saved_masks[EXC_TYPES_COUNT];
    mach_port_t            saved_ports[EXC_TYPES_COUNT];
    exception_behavior_t   saved_behaviors[EXC_TYPES_COUNT];
    thread_state_flavor_t  saved_flavors[EXC_TYPES_COUNT];
    mach_msg_type_number_t saved_exception_types_count;
} trace_data_t;


static void* exception_server(void* arg)
{
    mach_port_t port = (mach_port_t)(uintptr_t)arg;

    int bufsize = 4096;
    mach_msg_header_t* msg = (mach_msg_header_t*)malloc(bufsize);
    
	while (true) {
        
        memset(msg, 0, bufsize);
        msg->msgh_size = bufsize;
        mach_msg_return_t ret = mach_msg(msg, MACH_RCV_MSG|MACH_RCV_LARGE, 0, msg->msgh_size, port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);

        if(ret != MACH_MSG_SUCCESS) {
            JBLogError("mach_msg error=%x\n", ret);
            usleep(10*1000);
            continue;
        }

        __Request__mach_exception_raise_t *request = (__Request__mach_exception_raise_t*)msg;

        __Reply__mach_exception_raise_t reply = {0};

        reply.NDR = request->NDR;
        reply.RetCode = KERN_SUCCESS;
        // reply.RetCode = KERN_FAILURE;

        pid_t pid=0;
        pid_for_task(request->task.name, &pid);

        arm_thread_state64_t threadState;
        mach_msg_type_number_t threadStateCount = ARM_THREAD_STATE64_COUNT;
        thread_get_state(request->thread.name, ARM_THREAD_STATE64, (thread_state_t)&threadState, &threadStateCount);

        arm_exception_state64_t exceptionState;
        mach_msg_type_number_t exceptionStateCount = ARM_EXCEPTION_STATE64_COUNT;
        thread_get_state(request->thread.name, ARM_EXCEPTION_STATE64, (thread_state_t)&exceptionState, &exceptionStateCount);
        
        uint64_t pc = (uint64_t)__darwin_arm_thread_state64_get_pc(threadState);

        JBLogDebug("pid=%d exception: type=%d ncode=%d code=%d(0x%x) subcode=%d(0x%x) thread=%x pc=%p\n", pid, request->exception, request->codeCnt, 
            request->code[0], request->code[0], request->code[1], request->code[1],
            request->thread.name, (void*)pc);

        [trace_data_lock lock];
        trace_data_t* trace_data = (trace_data_t*)[[trace_data_record objectForKey:@(pid)] pointerValue];

        if(!trace_data) {

        }
        else if (request->exception == EXC_SOFTWARE && request->codeCnt == 2 && request->code[0] == EXC_SOFT_SIGNAL) 
        {

            switch(request->code[1]) {
                case SIGSTOP: {
                    bool data=true;
                    kern_return_t kr = vm_write(request->task.name, trace_data->traced_flag_addr, (mach_vm_address_t)&data, sizeof(data));
                    if(kr != KERN_SUCCESS) {
                        JBLogError("vm_write error: %x, %s\n", kr, mach_error_string(kr));
                    }
                    // JBLogDebug("PT_THUPDATE=%d, %d\n", ptrace(PT_THUPDATE, pid, (caddr_t)(uintptr_t)request->thread.name, 0), errno);
                    int ret = ptrace(PT_CONTINUE, pid, (caddr_t)1, 0);
                    if(ret != 0) {
                        JBLogError("PT_CONTINUE error: %d, %s\n", errno, strerror(errno));
                    }
                    break;
                }
                
                // Our original task port isn't valid anymore check for a SIGTRAP
                // We got a SIGTRAP which indicates we might have exec'ed and possibly
                // lost our old task port during the exec, so we just need to switch over
                // to using this new task port
                case SIGTRAP: {

                    if(roothide_patch_proc(pid) != 0) {
                        JBLogError("roothide_patch_proc error: %d, %s\n", errno, strerror(errno));
                        break;
                    }

                    for (uint32_t i = 0; i < trace_data->saved_exception_types_count; ++i) {
                        kern_return_t kr = task_set_exception_ports(request->task.name, trace_data->saved_masks[i], 
                                                trace_data->saved_ports[i], trace_data->saved_behaviors[i], trace_data->saved_flavors[i]);
                        if(kr != KERN_SUCCESS) {
                            JBLogError("task_set_exception_ports[%d] error: %x, %s\n", i, kr, mach_error_string(kr));
                        }
                        if(MACH_PORT_VALID(trace_data->saved_ports[i])) {
                            mach_port_deallocate(mach_task_self(), trace_data->saved_ports[i]);
                        }
                    }

                    int ret = ptrace(PT_DETACH, pid, NULL, 0);
                    if(ret != 0) {
                        JBLogError("PT_DETACH error: %d, %s\n", errno, strerror(errno));
                    }

                    [trace_data_record removeObjectForKey:@(pid)];
                    free((void*)trace_data);
                    trace_data = NULL;

                    break;
                }
            }
        }

        trace_data = NULL;
        [trace_data_lock unlock];

		reply.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(msg->msgh_bits), 0);
		reply.Head.msgh_size = sizeof(__Reply__mach_exception_raise_t);
		reply.Head.msgh_remote_port = msg->msgh_remote_port;
		reply.Head.msgh_local_port = MACH_PORT_NULL;
		reply.Head.msgh_id = msg->msgh_id + 0x64;

		mach_msg(&reply.Head, MACH_SEND_MSG | MACH_MSG_OPTION_NONE, reply.Head.msgh_size, 0, MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
	}
}

int execTraceProcess(pid_t pid, uint64_t traced)
{
    static mach_port_t exception_port = MACH_PORT_NULL;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        trace_data_lock = [[NSLock alloc] init];
        trace_data_record = [[NSMutableDictionary alloc] init];

        mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &exception_port);
        mach_port_insert_right(mach_task_self(), exception_port, exception_port, MACH_MSG_TYPE_MAKE_SEND);

        pthread_t thread;
        pthread_create(&thread, NULL, exception_server, (void*)(uintptr_t)exception_port);

        __uint64_t tid = 0;
        pthread_threadid_np(thread, &tid);
        JBLogDebug("exception_server thread: %x tid=%d", thread, tid);
    });

    if(!proc_cantrace(pid)) {
        JBLogError("can't be able to trace process: %d", pid);
        return -1;
    }

    mach_port_t task=MACH_PORT_NULL;
    kern_return_t kr = task_for_pid(mach_task_self(), pid, &task);
    if(kr != KERN_SUCCESS || !MACH_PORT_VALID(task)) {
        JBLogError("task_for_pid(%d,task=%x) error: %x, %s", pid, task, kr, mach_error_string(kr));
        return -1;
    }

    int ret = 0;
    
    trace_data_t* trace_data = (trace_data_t*)malloc(sizeof(trace_data_t));
    trace_data->traced_flag_addr = traced;

    kr = task_get_exception_ports(task, EXC_MASK_ALL, trace_data->saved_masks, &trace_data->saved_exception_types_count, 
                                            trace_data->saved_ports, trace_data->saved_behaviors, trace_data->saved_flavors);
    if(kr == KERN_SUCCESS) {

        kr = task_set_exception_ports(task, EXC_MASK_ALL, exception_port, EXCEPTION_DEFAULT|MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
        if(kr == KERN_SUCCESS) {

            [trace_data_lock lock];
            [trace_data_record setObject:[NSValue valueWithPointer:trace_data] forKey:@(pid)];

            int ret = ptrace(PT_ATTACHEXC, pid, NULL, 0);
            if(ret != 0) {
                JBLogError("attach error: %d, %s", errno, strerror(errno));
                [trace_data_record removeObjectForKey:@(pid)];
                free(trace_data);
                ret = -1;
            }
            
            [trace_data_lock unlock];
    
        } else {
            JBLogError("task_set_exception_ports error: %x, %s", kr, mach_error_string(kr));
            ret = -1;
        }
    
    } else {
        JBLogError("task_get_exception_ports error: %x, %s", kr, mach_error_string(kr));
        ret = -1;
    }

    mach_port_deallocate(mach_task_self(), task);

    return ret;
}

int execTraceCancel(pid_t pid)
{
    int ret = -1;
    [trace_data_lock lock];
    trace_data_t* trace_data = (trace_data_t*)[[trace_data_record objectForKey:@(pid)] pointerValue];
    if(trace_data) {
        [trace_data_record removeObjectForKey:@(pid)];
        free((void*)trace_data);
        trace_data = NULL;
        ret = 0;
    }
    [trace_data_lock unlock];
    return ret;
}