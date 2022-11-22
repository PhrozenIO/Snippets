program IsDebuggerPresent;

{$APPTYPE CONSOLE}

uses
  WinAPI.Windows, System.SysUtils;

begin
  try
    if IsDebuggerPresent() then
      WriteLn('Process is currently getting debugged.')
    else
      WriteLn('Process is not likely getting debugged.');

    readln;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.