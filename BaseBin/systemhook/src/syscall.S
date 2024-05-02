.text

.align 4

.global _syscall__posix_spawn
_syscall__posix_spawn:
	MOV X16, #0xF4
	SVC 0x80
	B.CC _spawn_ret
	STP X29, X30, [SP,#-0x10]!
	MOV X29, SP
	BL _cerror
	LDP X29, X30, [SP],#0x10
_spawn_ret:
	ret
