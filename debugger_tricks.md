# debugger magic and other stupid pet tricks

These are simple scripts and commands for use in `windbg`, `cdb`, `kd`.

## helpful hints

### load helpful commands in Command window

```
.cmdtree cmdtree.txt
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
