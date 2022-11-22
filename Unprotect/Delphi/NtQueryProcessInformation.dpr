program NtQueryProcessInformation;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  Winapi.Windows,
  System.SysUtils;

function NtQueryInformationProcess(
  ProcessHandle : THandle;
  ProcessInformationClass : DWORD;
  ProcessInformation : Pointer;
  ProcessInformationLength : ULONG;
  ReturnLength : PULONG
): LongInt; stdcall; external 'ntdll.dll';

// https://docs.microsoft.com/en-gb/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess
function isDebuggerPresent(): Boolean;
var hProcess : THandle;
    APortNumber : DWORD;
    ARetLen : Cardinal;

const ProcessDebugPort = 7;
begin
  hProcess := GetCurrentProcess();
  if hProcess = 0 then
    Exit();
  ///

  if NtQueryInformationProcess(hProcess, ProcessDebugPort, @APortNumber, sizeOf(DWORD), @ARetLen) <> ERROR_SUCCESS then
    Exit();

  result := APortNumber <> 0;
end;

begin
  try
    if isDebuggerPresent() then
      raise Exception.Create('Debugger Detected !');

    WriteLn('No Debugger Detected :)');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

  WriteLn('Press a return key to close application.');
  ReadLn;
end.