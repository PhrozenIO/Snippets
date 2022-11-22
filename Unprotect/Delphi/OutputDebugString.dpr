program OutputDebugString;

{$APPTYPE CONSOLE}

uses
  WinAPI.Windows,
  System.SysUtils;

var AErrorValue : Byte;

begin
  try
    randomize;

    AErrorValue := Random(High(Byte));

    SetLastError(AErrorValue);

    OutputDebugStringW('TEST');

    if (GetLastError() = AErrorValue) then
      WriteLn('Debugger detected using OutputDebugString() technique.')
    else
      WriteLn('No debugger detected using OutputDebugString() technique.');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.