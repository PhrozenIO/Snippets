// Jean-Pierre LESUEUR (@DarkCoderSc)

function PhysicalToVirtualPath(APath : String) : String;
var i          : integer;Ge
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
type PUnicodeString = ^TUnicodeString;
     TUnicodeString = record
        Length         : USHORT;
        MaximumLength  : USHORT;
        Buffer         : PWideChar;
    end;
// https://docs.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryinformationprocess
var _NtQueryInformationProcess : function(
                                          ProcessHandle : THandle;
                                          ProcessInformationClass : DWORD;
                                          ProcessInformation : Pointer;
                                          ProcessInformationLength : ULONG;
                                          ReturnLength : PULONG
                               ) : LongInt; stdcall;

    hNTDLL     : THandle;
    hProc      : THandle;
    ALength    : ULONG;
    pImagePath : PUnicodeString;


const PROCESS_QUERY_LIMITED_INFORMATION = $00001000;
      ProcessImageFileName = 27;
begin
  hProc := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, AProcessId);
  if (hProc = 0) then
    Exit();
  try
    hNTDLL := LoadLibrary('NTDLL.DLL');
    if (hNTDLL = 0) then
      Exit();
    try
      @_NtQueryInformationProcess := GetProcAddress(hNTDLL, 'NtQueryInformationProcess');

      if NOT Assigned(_NtQueryInformationProcess) then
        Exit();
      ///

      ALength := (MAX_PATH + SizeOf(TUnicodeString)); // Should be enough :)

      GetMem(pImagePath, ALength);
      try
        if (_NtQueryInformationProcess(hProc, ProcessImageFileName, pImagePath, ALength, @ALength) <> 0) then
          Exit();
        ///

        result := PhysicalToVirtualPath(String(pImagePath^.Buffer));
      finally
        FreeMem(pImagePath, ALength);
      end;
    finally
      FreeLibrary(hNTDLL);
    end;
  finally
    CloseHandle(hProc);
  end;
end;