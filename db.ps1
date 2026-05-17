cmd /c sc stop $Args

cmd /c sc delete $Args

nasm -f win64 "$Args.asm" -o "$Args.obj"


#lld-link /nodefaultlib /subsystem:native /driver /release /entry:DriverEntry /nxcompat:no /tsaware:no /highentropyva:no /SECTION:.text,PER /out:"$Args.sys" "$Args.obj" ntoskrnl.lib wdmsec.lib

lld-link /nodefaultlib /subsystem:native /driver /release /entry:DriverEntry /nxcompat:no /tsaware:no /highentropyva:no /SECTION:.text,ER /out:"$Args.sys" "$Args.obj" ntoskrnl.lib wdmsec.lib

#Signtool sign /f TestCert.pfx /fd sha256 /p test1234 "$Args.sys"

#Signtool verify /v /pa "$Args.sys"

cmd /c sc create $Args binpath= "$PWD\$Args.sys" type= kernel
cmd /c sc start $Args
