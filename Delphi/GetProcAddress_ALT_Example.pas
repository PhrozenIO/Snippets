// Jean-Pierre LESUEUR (@DarkCoderSc)
// ...
uses tlhelp32, Windows, SysUtils, UntEnumDLLExport;
// ...

{
  Retrieve module full path from it handle (Returned by LoadLibrary()), we need
  that information to parse it PE Header and retrieve function address.
}
function GetModuleImagePath(hModule : HMODULE) : String;
var ASnap        : THandle;
    AModuleEntry : TModuleEntry32;

const TH32CS_SNAPMODULE32 = $00000010;

begin
  result := '';
  ///

  ASnap := CreateToolHelp32Snapshot(TH32CS_SNAPMODULE or TH32CS_SNAPMODULE32, GetCurrentProcessId());
  if ASnap = INVALID_HANDLE_VALUE then
    Exit();
  try
    ZeroMemory(@AModuleEntry, SizeOf(TModuleEntry32));

    AModuleEntry.dwSize := SizeOf(TModuleEntry32);
    ///

    if NOT Module32First(ASnap, AModuleEntry) then
      Exit();

    if (AModuleEntry.hModule = hModule) then begin
      result := AModuleEntry.szExePath;

      Exit();
    end;

    while True do begin
      ZeroMemory(@AModuleEntry, SizeOf(TModuleEntry32));

      AModuleEntry.dwSize := SizeOf(TModuleEntry32);
      ///

      if NOT Module32Next(ASnap, AModuleEntry) then
        Break;

      if (AModuleEntry.hModule = hModule) then begin
        result := AModuleEntry.szExePath;

        break;
      end;
    end;
  finally
    CloseHandle(ASnap);
  end;
end;

{
  Retrieve function address from DLL PE Header Export Function Table.
}
function GetProcAddress_ALT(hModule : HMODULE; lpProcName : LPCSTR) : Pointer;
var ADLLExport : TEnumDLLExport;
    I          : Integer;
begin
  result := nil;
  ///

  ADLLExport := TEnumDLLExport.Create(GetModuleImagePath(hModule));

  if (ADLLExport.Enum > 0) then begin
    for I := 0 to ADLLExport.Items.Count -1 do begin
      if (ADLLExport.Items[i].Name.ToLower = String(lpProcName).ToLower) then begin
        result := Pointer(hModule + ADLLExport.Items[i].RelativeAddr);

        break;
      end;
    end;
  end;
end;

// ...

procedure LoadAndTriggerMessageBox();
var _MessageBoxW : function(hWnd: HWND; lpText, lpCaption: LPCWSTR; uType: UINT): Integer; stdcall;
    hModule      : HMODULE;
begin
  _MessageBoxW := nil;

  hModule := LoadLibrary('user32.dll');

  @_MessageBoxW := GetProcAddress_ALT(hModule, 'MessageBoxW');

  if Assigned(_MessageBoxW) then
    _MessageBoxW(0, 'Hello World', 'Hey', 0);
end;

begin
  LoadAndTriggerMessageBox();
end.

/// ...