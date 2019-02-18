echo "Heap Dump for: %1"

"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe" -n "%1" -c ".loadby sos clr; !dumphead -stat -min 10000; qd"