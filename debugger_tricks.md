# debugger magic and other stupid pet tricks

These are simple scripts and commands for use in `windbg`, `cdb`, `kd`.

## symbols

Use cached symbols via symbol server and store them in `c:\symbols`. You can
use `.sympath+` to append additional symbols paths.

```
.symfix C:\symbols
.sympath cache*c:\symbols;srv*https://msdl.microsoft.com/download/symbols
.reload
```

## helpful hints

### load helpful commands in Command window

```text
.cmdtree cmdtree.txt
```

## extensions

CMKD

```text
.load cmkd_x64.dll
!stack -p -t
```

Output:

```text
## Stack-Pointer     Return-Address   Call-Site
   ...
01 0000002a38ffeab0  00007ffcc212c1ce KERNELBASE!WaitForMultipleObjectsEx+ef
        Parameter[0] = 0000000000000001 : rcx saved in current frame into NvReg rbx
                                          which is saved by child frames
        Parameter[1] = 000001da01404418 : rdx saved in current frame into NvReg r13
                                          which is saved by child frames
        Parameter[2] = aca30f2100000001 : r8 saved in current frame into stack
        Parameter[3] = 00000000ffffffff : r9 saved in current frame into NvReg r12
   ...
```

```text
!handle poi(000001da01404418) 8
```

Output:

```text
   Handle 248
     Object Sepecific Information
       Event Type Manual Reset
       Event is Waiting
```

## breakpoint scripts

### see files when they are created

```text
bp kernelbase!CreateFileW ".printf \"Opening file %mu\", dwo(@rsp+8); .echo ---; k 3; gc"
bp kernelbase!CreateFileA ".printf \"Opening file %ma\", dwo(@rsp+8); .echo ---; k 3; gc"
```

### determine files that can't open

```text
bp kernelbase!CreateFileW "gu; .if (@rax == 0) {
    .printf \"failed to open file=%mu\", dwo(@rsp+8); .echo ---; k3
} .else {
    gc
}
```

### print virtual memory allocations

```text
r $t0 = 0
bp ntdll~NtAllocateVirtualMemory "r $t0 = @$t0 + dwo(@rdx); gc"
g
.printf "allocated total %d bytes of virtual memory\n", @$t0
.for (r $t0 = 0; @$t0 < 0n10; r $t0 = @$t0 + 1) { .printf "%x ", @@(arr[@$t0]) }
```

### who it calling VirtualAlloc?

```text
bp kernelbase!VirtualAlloc ".printf \"allocating %d bytes of virtual memory\", dwo(@rsp+16);
   .echo; k 5; !clrstack"
```

### list all the functions called by another function

First, set a breakpoint on the function. In this case, what are the functions
that the garbage collector calls in `mark_phase`.

```text
bp clr!WKS::gc_heap::mark_phase
g
```

When the breakpoint fires, now run the following to get a list of the functions
it calls.

> Note that the `1` below, means a depth of 1.

```text
wt -1 1
```

Output:

```text
Tracing clr!WKS::gc_heap::mark_phase to return address 7371359f
   43     0 [  0] clr!WKS::gc_heap::mark_phase
    8     0 [  1]   clr!WKS::gc_heap::generation_size
   76     8 [  0] clr!WKS::gc_heap::mark_phase
   18     0 [  1]   clr!WKS::gc_heap::generation_size
  113    26 [  0] clr!WKS::gc_heap::mark_phase
   33     0 [  1]   clr!SystemDomain::GetTotalNumSizedRefHandles
  133    59 [  0] clr!WKS::gc_heap::mark_phase
  558     0 [  1]   clr!GCToEEInterface::GcScanRoots
  138   617 [  0] clr!WKS::gc_heap::mark_phase
    8     0 [  1]   clr!WKS::fire_mark_event
  145   625 [  0] clr!WKS::gc_heap::mark_phase
 1417     0 [  1]   clr!WKS::gc_heap::scan_background_roots
  ...
```

### find a specific object (example containing 'å')

Command:

```text
!name2ee OrderService!OrderService.Order
```

Output:

```text
  EEClass: 01591830
  Name:    OrderService.Order
```

Command:

```text
!dumpclass 01591830
```

Output:

```text
  MT       Offset    Type           VT  Attr
  727f1638 c         System.Int32   1   instance <Id>k__BackingField
  727ef7a4 4         System.String  0   instance <Address>k__BackingField
  727ee3ac 8  ...Int32, mscorlib]]  0   instance <ItemIds>k__BackingField
```

Command:

```text
.foreach (obj {!dumpheap -mt 01594ddc -short}) { as /my ${/v:address}
   dwo(${obj}+4)+8; .block { .if ($spat("${address}", "*å*")) { .printf "Got it! ${address} in object %x",
   ${obj}; .echo }; ad /q * } }
```

Output:

```text
   Got it! 233 Håmpton St. in object 34f5328
```

## other windbg scripts

### Complete Stack Traces from x64 System:

```text
!for_each_thread "!thread @#Thread 16;.thread /w @#Thread; .reload; kv 256; .effmach AMD64"
```

### x86 Stack Traces from WOW64 Process:

```text
!for_each_thread ".thread @#Thread; r $t0 = @#Thread; .if (@@c++(((nt!_KTHREAD *)@$t0)->Process) == ProcessAddress) {.thread /w @#Thread; .reload; kv 256; .effmach AMD64 }"
```

### Top CPU Consuming Threads:

```text
!for_each_thread "r $t1 = dwo( @#Thread + @@c++(#FIELD_OFFSET(nt!_KTHREAD, KernelTime)) ); r $t0 = Ticks; .if (@$t1 > @$t0) {!thread @#Thread 3f}"
!for_each_thread "r $t1 = dwo( @#Thread + @@c++(#FIELD_OFFSET(nt!_KTHREAD, UserTime)) ); r $t0 = Ticks; .if (@$t1 > @$t0) {!thread @#Thread 3f}"
```

## StackFrames - calling conventions

### x64 calling convention

```text
      highest memory address
   |     16-byte aligned     |
   +-------------------------+
   | Local variables         |
   | and                     |
   | nonvolatile registers   |
   +-------------------------+    ^^^ positive offset of locals
   | Frame pointer (if used) |   <== RBP (aka frame/base pointer)
   +-------------------------+
   | alloca (if used)        |
   +-------------------------+  ]+
   |                     (8) |   |
   +-------------------------+   |
   |                     (7) |   |
   +-------------------------+   |
   |                     (6) |   +-- Stack params
   +-------------------------+   |
   |                     (5) |   |
   +-------------------------+   |
   |                     (4) |   |
   +-------------------------+  ]+
   | R9 home             (3) |   |
   +-------------------------+   |
   | R8 home             (2) |   |
   +-------------------------+   +-- Register params
   | RDX home            (1) |   |
   +-------------------------+   |
   | RCX home            (0) |   |
   +-------------------------+  ]+
   |                         |
   | Caller return address   |
---+-------------------------+--- Function call
   | Local variables         |
   | and                     |
   | nonvolatile registers   |
   |                         |
   +-------------------------+    ^^^ positive offset of locals
   | Frame pointer (if used) |   <== RBP (aka frame/base pointer)
   +-------------------------+  ]+vvv negative offset for params
   | alloca space            |   |
   | (if used)               |   +-- Function stack storage
   |                         |   |
   +-------------------------+  ]+
   |                         |   |
   |                         |   |
   | Function param stack    |   +-- Stack parameters (> 4 params RTL)
   |                         |   |
   |                         |   |
   +-------------------------+  ]+
   | R9 home                 |   |
   +-------------------------+   |
   | R8 home                 |   |
   +-------------------------+   +-- Register params (<=4 LTR)
   | RDX home                |   |
   +-------------------------+   |
   | RCX home                |   |
   +-------------------------+  ]+
   |                         |
      lowest memory address
```

### x86 (32-bit) cdecl calling convention

```text
      highest memory address
   |     8-byte aligned      |
   +-------------------------+
   |                         |
   |                         |
   +-------------------------+ ]+
   | param 3                 |  |
   +-------------------------+  |
   | param 2                 |  |
   +-------------------------+  |
   | param 1                 |  |
   +-------------------------+  |
   | return address          |  |
   +-------------------------+  |
+< | frame pointer (EBP)     |  +- Function A
|  +-------------------------+  |
|  | local variable 1        |  |
|  +-------------------------+  |
|  | local variable 2        |  |
|  +-------------------------+  |
|  | saved EDI               |  |
|  +-------------------------+  |
|  | saved ESI               | ]+ <-- ESP
|  +-------------------------+ ]+
|  | param 3                 |  |
|  +-------------------------+  |
|  | param 2                 |  |
|  +-------------------------+  |
|  | param 1                 |  |
|  +-------------------------+  |
|  | return address          |  |
|  +-------------------------+  |
+> | frame pointer (EBP)     |  +- Function B  (previous frame pointer)
   +-------------------------+  |
   | local variable 1        |  |
   +-------------------------+  |
   | local variable 2        |  |
   +-------------------------+  |
   | local variable 3        |  |
   +-------------------------+  |
   | saved EDI               |  |
   +-------------------------+  |
   | saved ESI               | ]+ <-- ESP
   +-------------------------+
   |                         |
      lowest memory address
```

## registers

### x64

| Name | Notes | Type | 64-bit long | 32-bit int | 16-bit short | 8-bit char |
| ---- | ----- | ---- | ----------- | ---------- | ------------ | ---------- |
| rax | Values are returned from functions in this register. | scratch | rax | eax | ax | ah and al |
| rcx | Typical scratch register.  Some instructions also use it as a counter. |scratch | rcx | ecx | cx | ch and cl |
| rdx | Scratch register. | scratch | rdx | edx | dx | dh and dl |
| rbx | Preserved register: **don't use it without saving it!** | preserved | rbx | ebx | bx | bh and bl |
| rsp | The stack pointer.  Points to the top of the stack (details coming soon!) | preserved | rsp | esp | sp | spl |
| rbp | Preserved register.  Sometimes used to store the old value of the stack pointer, or the "base". | preserved | rbp | ebp | bp | bpl |
| rsi | Scratch register used to pass function argument #2 in 64-bit Linux. In 64-bit Windows, a preserved register. | scratch | rsi | esi | si | sil |
| rdi | Scratch register and function argument #1 in 64-bit Linux. In 64-bit Windows, a preserved register. | scratch | rdi | edi | di | dil |
| r8 | Scratch register. These were added in 64-bit mode, so they have numbers, not names. | scratch | r8 | r8d | r8w | r8b |
| r9 | Scratch register. | scratch | r9 | r9d | r9w | r9b |
| r10 | Scratch register. | scratch | r10 | r10d | r10w | r10b |
| r11 | Scratch register. | scratch | r11 | r11d | r11w | r11b |
| r12 | Preserved register. (You can use it, but you need to **save and restore it**.) | preserved | r12 | r12d | r12w | r12b |
| r13 | Preserved register. | preserved | r13 | r13d | r13w | r13b |
| r14 | Preserved register. | preserved | r14 | r14d | r14w | r14b |
| r15 | Preserved register. | preserved | r15 | r15d | r15w | r15b |
