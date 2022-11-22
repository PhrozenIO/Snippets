program NtSetDebugFilterState;

{$APPTYPE CONSOLE}

uses
  WinAPI.Windows, System.SysUtils;

var
  NtSetDebugFilterState : function(AComponentId : ULONG; ALevel : ULONG; AState : Boolean) : NTSTATUS; stdcall;

  hNTDLL  : THandle;
  AStatus : NTSTATUS;

begin
  try
    hNTDLL := LoadLibrary('ntdll.dll');
    if (hNTDLL = 0) then
      Exit();
    try
      @NtSetDebugFilterState := GetProcAddress(hNTDLL, 'NtSetDebugFilterState');

      if NOT Assigned(NtSetDebugFilterState) then
        Exit();

      AStatus := NtSetDebugFilterState(0, 0, True);

      writeln(AStatus);

      if (AStatus <> 0) then
        WriteLn('Not Debugged.')
      else
        WriteLn('Debugged.');
    finally
      FreeLibrary(hNTDLL);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.