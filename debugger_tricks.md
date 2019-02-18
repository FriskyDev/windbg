# debugger magic and other stupid pet tricks

These are simple scripts and commands for use in `windbg`, `cdb`, `kd`.

## helpful hints

### load helpful commands in Command window

```
.cmdtree cmdtree.txt
```

## extensions

CMKD

```
.load cmkd_x64.dll
!stack -p -t
```

Output:
```
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

```
!handle poi(000001da01404418) 8
```

Output:
```
   Handle 248
     Object Sepecific Information
       Event Type Manual Reset
       Event is Waiting
```

## breakpoint scripts

### see files when they are created

```
bp kernelbase!CreateFileW ".printf \"Opening file %mu\", dwo(@rsp+8); .echo ---; k 3; gc"
bp kernelbase!CreateFileA ".printf \"Opening file %ma\", dwo(@rsp+8); .echo ---; k 3; gc"
```

### determine files that can't open

```
bp kernelbase!CreateFileW "gu; .if (@rax == 0) {
    .printf \"failed to open file=%mu\", dwo(@rsp+8); .echo ---; k3
} .else {
    gc
}
```

### print virtual memory allocations

```
r $t0 = 0
bp ntdll~NtAllocateVirtualMemory "r $t0 = @$t0 + dwo(@rdx); gc"
g
.printf "allocated total %d bytes of virtual memory\n", @$t0
.for (r $t0 = 0; @$t0 < 0n10; r $t0 = @$t0 + 1) { .printf "%x ", @@(arr[@$t0]) }
```

### who it calling VirtualAlloc?

```
bp kernelbase!VirtualAlloc ".printf \"allocating %d bytes of virtual memory\", dwo(@rsp+16);
   .echo; k 5; !clrstack"
```

### list all the functions called by another function

First, set a breakpoint on the function. In this case, what are the functions
that the garbage collector calls in `mark_phase`.

```
bp clr!WKS::gc_heap::mark_phase
g
```

When the breakpoint fires, now run the following to get a list of the functions
it calls.

> Note that the `1` below, means a depth of 1.

```
wt -1 1
```

Output:
```
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
```
!name2ee OrderService!OrderService.Order
```

Output:
```
  EEClass: 01591830
  Name:    OrderService.Order
```

Command:
```
!dumpclass 01591830
```

Output:
```
  MT       Offset    Type           VT  Attr
  727f1638 c         System.Int32   1   instance <Id>k__BackingField
  727ef7a4 4         System.String  0   instance <Address>k__BackingField
  727ee3ac 8  ...Int32, mscorlib]]  0   instance <ItemIds>k__BackingField
```

Command:
```
.foreach (obj {!dumpheap -mt 01594ddc -short}) { as /my ${/v:address}
   dwo(${obj}+4)+8; .block { .if ($spat("${address}", "*å*")) { .printf "Got it! ${address} in object %x",
   ${obj}; .echo }; ad /q * } }
```

Output:
```
   Got it! 233 Håmpton St. in object 34f5328
```

## StackFrames - calling conventions

### x64 calling convention

```
      highest memory address
   |     16-byte aligned     |
   +-------------------------+
   |                         |
   |                         |
   +-------------------------+
   |                         |
   +-------------------------+
   |                         |
   |                         |
   |                         |
   |                         |
   +-------------------------+
   |                         |
   +-------------------------+
   | R9 home                 |
   +-------------------------+
   | R8 home                 |
   +-------------------------+
   | RDX home                |
   +-------------------------+
   | RCX home                |
   +-------------------------+
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

