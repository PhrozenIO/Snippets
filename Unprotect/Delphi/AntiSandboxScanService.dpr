program AntiSandboxScanService;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  WinAPI.Windows,
  WinAPI.WinSvc;


const ANTI_LIST : array[0..4-1] of String = (
      // VMWare
      'VGAuthService',
      'vmvss',
      'vm3dservice',
      'VMTools' 
      // ...
);

{
  Using Service Manager WinAPI + OpenService()

  * https://docs.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openscmanagerw
  * https://docs.microsoft.com/en-us/windows/win32/api/winsvc/nf-winsvc-openservicew
}
function CheckService_WinSvc() : Boolean;
var AServiceManager : SC_HANDLE;
    I               : Cardinal;
begin
  result := False;
  ///

  AServiceManager := OpenSCManagerW(nil, nil, SC_MANAGER_ENUMERATE_SERVICE);
  if AServiceManager = 0 then
  raise Exception.Create(
      Format('Could not open service manager with error=[%s]', [GetLastError()])
  );
  try
    for I := 0 to Length(ANTI_LIST) -1 do begin
      if (OpenServiceW(AServiceManager, PWideChar(ANTI_LIST[I]), READ_CONTROL) <> 0) then begin
        WriteLn(Format('[*] "%s" service found.', [ANTI_LIST[I]]));

        ///
        result := true;
      end;
    end;
  finally
    CloseServiceHandle(AServiceManager);
  end;
end;

{
  Using Microsoft Windows Registry + RegOpenKeyExW

  * https://docs.microsoft.com/en-us/windows/win32/api/winreg/nf-winreg-regopenkeyexw
}
function CheckService_Registry() : Boolean;
const HIVE : HKEY = HKEY_LOCAL_MACHINE;
      PATH = 'SYSTEM\CurrentControlSet\Services\%s';
var AStatus : Longint;
    AKey    : HKEY;
    I       : Cardinal;
    APath   : String;
begin
  for I := 0 to Length(ANTI_LIST) -1 do begin
    APath := Format(PATH, [ANTI_LIST[i]]);
    if RegOpenKeyExW(HIVE, PWideChar(APath), 0, KEY_READ, AKey) <> ERROR_SUCCESS then
      continue;
    try
        WriteLn(Format('[*] "%s" service found.', [ANTI_LIST[I]]));

        ///
        result := true;
    finally
      RegCloseKey(AKey);
    end;
  end;
end;

procedure Header(ACaption : String);
begin
  WriteLn(StringOfChar('-', 50));
  WriteLn(ACaption);
  WriteLn(StringOfChar('-', 50));
end;

begin
  try
    Header('Check Service (WinSvc):');
    if not CheckService_WinSvc() then
      WriteLn('Nothing found so far...');

    WriteLn;

    Header('Check Service (Registry):');
    if not CheckService_Registry() then
      WriteLn('Nothing found so far...');

    readln;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.