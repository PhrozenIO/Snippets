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

function GetCurrentProcessImagePath() : String;
var AFileName : Array[0..MAX_PATH -1] of Char;
begin
    ZeroMemory(@AFileName, MAX_PATH);
    ///

    GetMappedFileName(
                          GetCurrentProcess(),
                          Pointer(GetModuleHandle(nil)),
                          AFileName,
                          MAX_PATH
    );

    result := PhysicalToVirtualPath(UnicodeString(AFileName));
end;