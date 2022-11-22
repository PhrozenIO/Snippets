unit UntPEBDebug;

interface

uses Windows;

const PROCESS_QUERY_LIMITED_INFORMATION = $1000;
        PROCESS_BASIC_INFORMATION         = 0;

// https://docs.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess
var _NtQueryInformationProcess : function(
                                            ProcessHandle : THandle;
                                            ProcessInformationClass : DWORD;
                                            ProcessInformation : Pointer;
                                            ProcessInformationLength :
                                            ULONG; ReturnLength : PULONG) : LongInt; stdcall;

    hNTDLL : THandle;


{$IFDEF WIN64}
type
    PProcessBasicInformation = ^TProcessBasicInformation;
    TProcessBasicInformation = record
    ExitStatus         : Int64;
    PebBaseAddress     : Pointer;
    AffinityMask       : Int64;
    BasePriority       : Int64;
    UniqueProcessId    : Int64;
    InheritedUniquePID : Int64;
    end;
{$ELSE}
type
    PProcessBasicInformation = ^TProcessBasicInformation;
    TProcessBasicInformation = record
    ExitStatus         : DWORD;
    PebBaseAddress     : Pointer;
    AffinityMask       : DWORD;
    BasePriority       : DWORD;
    UniqueProcessId    : DWORD;
    InheritedUniquePID : DWORD;
    end;
{$ENDIF}

function GetProcessDebugStatus(AProcessID : Cardinal; var ADebugStatus : boolean) : Boolean;
function SetProcessDebugStatus(AProcessID : Cardinal; ADebugStatus : Boolean) : Boolean;

implementation

{-------------------------------------------------------------------------------
    Open a process and retrieve the point of debug flag from PEB.

    If function succeed, don't forget to call close process handle.
-------------------------------------------------------------------------------}
function GetDebugFlagPointer(AProcessID : Cardinal; var AProcessHandle : THandle) : Pointer;
var PBI     : TProcessBasicInformation;
    ARetLen : Cardinal;
begin
    result := nil;
    ///

    AProcessHandle := 0;

    if NOT Assigned(_NtQueryInformationProcess) then
    Exit();
    ///

    AProcessHandle := OpenProcess(PROCESS_QUERY_INFORMATION or PROCESS_VM_WRITE or PROCESS_VM_READ, false, AProcessID);
    if (AProcessHandle = 0) then
    Exit;

    if _NtQueryInformationProcess(AProcessHandle, PROCESS_BASIC_INFORMATION, @PBI, sizeOf(TProcessBasicInformation), @ARetLen) = ERROR_SUCCESS then
    result := Pointer(NativeUInt(PBI.PebBaseAddress) + (SizeOf(Byte) * 2))
    else
    CloseHandle(AProcessHandle);
end;

{-------------------------------------------------------------------------------
    Retrieve the target process debug status from PEB.

    ADebugStatus = True  : Target process debug flag is set.
    ADebugStatus = False : Target process debug flag is not set.
-------------------------------------------------------------------------------}
function GetProcessDebugStatus(AProcessID : Cardinal; var ADebugStatus : boolean) : Boolean;
var hProcess         : THandle;

    pDebugFlagOffset : Pointer;
    pDebugFlag       : pByte;
    ABytesRead       : SIZE_T;
begin
    result := false;
    ///

    pDebugFlagOffset := GetDebugFlagPointer(AProcessID, hProcess);

    if not Assigned(pDebugFlagOffset) then
    Exit();
    ///
    try
    getMem(pDebugFlag, sizeOf(Byte));
    try
        if NOT ReadProcessMemory(hProcess, pDebugFlagOffset, pDebugFlag, sizeOf(Byte), ABytesRead) then
        Exit;

        ///
        ADebugStatus := (pDebugFlag^ = 1);
    finally
        FreeMem(pDebugFlag);
    end;

    ///
    result := (ABytesRead = SizeOf(Byte));
    finally
    CloseHandle(hProcess);
    end;
end;

{-------------------------------------------------------------------------------
    Update target process debug flag.

    ADebugStatus = True  : Set target process debug flag.
    ADebugStatus = False : Unset target process debug flag.
-------------------------------------------------------------------------------}
function SetProcessDebugStatus(AProcessID : Cardinal; ADebugStatus : Boolean) : Boolean;
var hProcess         : THandle;

    pDebugFlagOffset : Pointer;
    ADebugFlag       : Byte;
    ABytesWritten    : SIZE_T;
begin
    result := false;
    ///

    pDebugFlagOffset := GetDebugFlagPointer(AProcessID, hProcess);

    if not Assigned(pDebugFlagOffset) then
    Exit();
    ///
    try
    if ADebugStatus then
        ADebugFlag := 1
    else
        ADebugFlag := 0;

    if NOT WriteProcessMemory(hProcess, pDebugFlagOffset, @ADebugFlag, SizeOf(Byte), ABytesWritten) then
        Exit;

    ///
    result := (ABytesWritten = SizeOf(Byte));
    finally
    CloseHandle(hProcess);
    end;
end;

initialization
    {
    Load NtQueryInformationProcess from NTDLL.dll
    }
    _NtQueryInformationProcess := nil;

    hNTDLL := LoadLibrary('ntdll.dll');

    if (hNTDLL <> 0) then
    @_NtQueryInformationProcess := GetProcAddress(hNTDLL, 'NtQueryInformationProcess');

finalization
    _NtQueryInformationProcess := nil;

    if (hNTDLL <> 0) then
    FreeLibrary(hNTDLL);


end.