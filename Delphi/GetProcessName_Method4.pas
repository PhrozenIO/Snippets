// Jean-Pierre LESUEUR (@DarkCoderSc)

function PhysicalToVirtualPath(APath : String) : String;
var i          : integer;
    ADrive     : String;
    ABuffer    : array[0..MAX_PATH-1] of Char;
    ACandidate : String;
begin
  {$I-}
  for I := 0 to 25 do begin
    ADrive := Format('%s:', [Chr(Ord('A') + i)]);
    ///

    if (QueryDosDevice(PWideChar(ADrive), ABuffer, MAX_PATH) = 0) then
      continue;

    ACandidate := String(ABuffer).ToLower();

    if String(Copy(APath, 1, Length(ACandidate))).ToLower() = ACandidate then begin
      Delete(APath, 1, Length(ACandidate));

      result := Format('%s%s', [ADrive, APath]);
    end;
  end;
  {$I+}
end;

function GetProcessImagePath(const AProcessId : Cardinal) : String;
// https://docs.microsoft.com/en-us/windows/win32/api/psapi/nf-psapi-getprocessimagefilenamew
var _GetProcessImageFileNameW : function(
                                          hProcess : THandle;
                                          lpImageFileName : LPWSTR;
                                          nSize : DWORD
                                ) : DWORD; stdcall;
    hPsAPI     : THandle;
    hProc      : THandle;
    ALength    : Cardinal;
    AImagePath : String;

const PROCESS_QUERY_LIMITED_INFORMATION = $00001000;
begin
  result := '';
  ///

  hProc := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, AProcessId);
  if (hProc = 0) then
    Exit();
  try
    hPsAPI := LoadLibrary('psapi.dll');
    if (hPsAPI = 0) then
      Exit();
    try
      @_GetProcessImageFileNameW := GetProcAddress(hPsAPI, 'GetProcessImageFileNameW');
      if NOT Assigned(_GetProcessImageFileNameW) then
        Exit();
      ///

      SetLength(AImagePath, MAX_PATH);

      ALength := _GetProcessImageFileNameW(hProc, @AImagePath[1], MAX_PATH);
      if (ALength > 0) then begin
        SetLength(AImagePath, ALength);
        ///

        result := PhysicalToVirtualPath(AImagePath);
      end;
    finally
      FreeLibrary(hPsAPI);
    end;
  finally
    CloseHandle(hProc);
  end;
end;