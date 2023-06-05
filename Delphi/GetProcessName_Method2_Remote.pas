// Jean-Pierre LESUEUR (@DarkCoderSc)

// ...
uses psAPI;
// ...

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
var hProc            : THandle;
    pGetModuleHandle : Pointer;
    AFlags           : Cardinal;
    AThreadId        : Cardinal;
    hThread          : THandle;
    hRemoteInstance  : Cardinal;
    AFileName        : Array[0..MAX_PATH -1] of Char;

const PROCESS_QUERY_LIMITED_INFORMATION = $00001000;
begin
  result := '';
  ///

  {
    Alternatively in the case of Kernel32.dll we could simply call GetModuleHandle('Kernel32.dll')
  }
  pGetModuleHandle := GetProcAddress(LoadLibrary('Kernel32.dll'), 'GetModuleHandleW');
  ///

  if NOT Assigned(pGetModuleHandle) then
    Exit();

  AFlags := PROCESS_CREATE_THREAD or
            PROCESS_QUERY_LIMITED_INFORMATION;

  hProc := OpenProcess(AFlags, false, AProcessId);
  if (hProc = 0) then
    Exit();
  try
    hThread := CreateRemoteThread(
                                    hProc,
                                    nil,
                                    0,
                                    pGetModuleHandle,
                                    Pointer(nil),
                                    0,
                                    AThreadId
    );
    if (hThread = 0) then
      Exit();
    try
      WaitForSingleObject(hThread, INFINITE);

      GetExitCodeThread(hThread, hRemoteInstance);

      ZeroMemory(@AFileName, MAX_PATH);
      ///

      GetMappedFileName(
                            hProc,
                            Pointer(hRemoteInstance),
                            AFileName,
                            MAX_PATH
      );

      result := PhysicalToVirtualPath(UnicodeString(AFileName));
    finally
      CloseHandle(hThread);
    end;
  finally
    CloseHandle(hProc);
  end;
end;