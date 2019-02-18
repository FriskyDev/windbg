echo "Crash dump for: %1"

"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe" -z "%1" -c ".logopen C:\temp\crash.log; !analyze -v; .logclose; q"