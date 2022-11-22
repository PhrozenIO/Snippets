program DetectMouseMove;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  WinApi.Windows,
  WinApi.ShellAPI,
  System.Classes,
  System.SysUtils;

var APoint     : TPoint;
    AOldPoint  : TPoint;
    AMoveCount : Cardinal;

// Update bellow constant to require more mouse move check before continue code execution
const AMaxMove = 5;

begin
  try
    GetCursorPos(AOldPoint);
    ///

    AMoveCount := 0;
    while True do begin
      GetCursorPos(APoint);

      if not PointsEqual(APoint, AOldPoint) then begin
        AOldPoint := APoint;

        Inc(AMoveCount);
      end;

      if AMoveCount >= AMaxMove then
        break;

      Sleep(1000);
    end;

    ///

    WriteLn('Mouse has moved, continue execution...');

    ShellExecuteW(0, 'open', 'calc.exe', nil, nil, SW_SHOW);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.