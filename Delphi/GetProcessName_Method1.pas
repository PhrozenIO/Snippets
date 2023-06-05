// Jean-Pierre LESUEUR (@DarkCoderSc)

//...
uses Windows, SysUtils;
//...

function GetProcessName(AProcessID : Cardinal) : String;
var hProc      : THandle;
    ALength    : DWORD;
    hDLL       : THandle;

    QueryFullProcessImageNameW : function(
                                            AProcess: THANDLE;
                                            AFlags: DWORD;
                                            AFileName: PWideChar;
                                            var ASize: DWORD): BOOL; stdcall;

const PROCESS_QUERY_LIMITED_INFORMATION = $00001000;
begin
  result := '';
  ///

  if (TOSVersion.Major < 6) then  
    Exit();
  ///
  
  QueryFullProcessImageNameW := nil;
  
  hDLL := LoadLibrary('kernel32.dll');
  if hDLL = 0 then
    Exit();  
  try
    @QueryFullProcessImageNameW := GetProcAddress(hDLL, 'QueryFullProcessImageNameW');
    ///
    
    if Assigned(QueryFullProcessImageNameW) then begin
      hProc := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, AProcessID);
      if hProc = 0 then exit;
      try
        ALength := (MAX_PATH * 2);
        
        SetLength(result, ALength);
        
        if NOT QueryFullProcessImageNameW(hProc, 0, @result[1], ALength) then 
          Exit();

        SetLength(result, ALength); // Get rid of extra junk
      finally
        CloseHandle(hProc);
      end;
    end;
  finally
    FreeLibrary(hDLL);
  end;
end;