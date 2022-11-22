(*
    Example of DLL Code to test DLL Injection:
    ------------------------------------------

    BOF>>

    library UnprotectTestDLL;

          uses
            WinApi.Windows,
            System.SysUtils,
            System.Classes;

          {$R *.res}

          procedure DllMain(AReason: Integer);
          var AMessage   : String;
              AStrReason : String;
          begin
            case AReason of
              DLL_PROCESS_DETACH : AStrReason := 'DLL_PROCESS_DETACH';
              DLL_PROCESS_ATTACH : AStrReason := 'DLL_PROCESS_ATTACH';
              DLL_THREAD_ATTACH  : AStrReason := 'DLL_THREAD_ATTACH';
              DLL_THREAD_DETACH  : AStrReason := 'DLL_THREAD_DETACH';
              else
                AStrReason := 'REASON_UNKNOWN';
            end;

            AMessage := Format('(%s): Injected! Living in %d (%s) process.', [
              AStrReason,
              GetCurrentProcessId(),
              ExtractFileName(GetModuleName(0))
            ]);
            ///

            OutputDebugStringW(PWideChar(AMessage));
          end;

          begin
            DllProc := DllMain;
            DllMain(DLL_PROCESS_ATTACH)


    <<EOF
*)

// Support both x86-32 and x86-64

program DLLInjection_CreateRemoteThread_LoadLibrary;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  WinApi.Windows,
  System.SysUtils;

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

procedure InjectDLL(const ADLLFile : String; const ATargetProcessId : Cardinal);
var hProcess      : THandle;
    pOffset       : Pointer;
    AThreadId     : Cardinal;
    ABytesWritten : SIZE_T;
begin
  if not FileExists(ADLLFile) then
    raise Exception.Create('DLL file not found!');
  ///

  hProcess := OpenProcess(PROCESS_VM_OPERATION or PROCESS_VM_READ or PROCESS_VM_WRITE, False, ATargetProcessId);
  if hProcess = 0 then
    raise EWindowsException.Create('OpenProcess');
  try
    pOffset := VirtualAllocEx(hProcess, nil, Length(ADLLFile), MEM_COMMIT, PAGE_READWRITE);
    if not Assigned(pOffset) then
      raise EWindowsException.Create('VirtualAllocEx');

    if not WriteProcessMemory(hProcess, pOffset, PWideChar(ADLLFile), Length(ADLLFile) * SizeOf(WideChar), ABytesWritten) then
      raise EWindowsException.Create('WriteProcessMemory');

    if CreateRemoteThread(hProcess, nil, 0, GetProcAddress(GetModuleHandle('Kernel32.dll'), 'LoadLibraryW'), pOffset, 0, AThreadId) = 0 then
      raise EWindowsException.Create('CreateRemoteThread');
  finally
    CloseHandle(hProcess);
  end;
end;

begin
  try
    InjectDLL('c:\temp\UnprotectTestDLL.dll' {Desired DLL To Inject}, 12196 {Desired Process Id});
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.