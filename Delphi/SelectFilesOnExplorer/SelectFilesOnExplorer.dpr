// Jean-Pierre LESUEUR (@DarkCoderSc)
// https://keybase.io/phrozen

program SelectFilesOnExplorer;

{$APPTYPE CONSOLE}

{$R *.res}

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Winapi.ActiveX,
  Winapi.ShlObj;

{ _.ShowFilesOnExplorer }
procedure ShowFilesOnExplorer(const ADirectory : String; const AStringList : TStringList);
var AList : array of PItemIDList;
    pDir  : PItemIDList;
    AFile : String;
    I     : Cardinal;
begin
  if not Assigned(AStringList) then
    Exit();
  ///

  SetLength(AList, AStringList.Count);

  for I := 0 to AStringList.count -1 do begin
    AFile := IncludeTrailingPathDelimiter(ADirectory) + AStringList.Strings[I];

    if not FileExists(AFile) then
      continue;

    AList[I] := ILCreateFromPath(PWideChar(AFile));
  end;

  pDir := ILCreateFromPath(PWideChar(ADirectory));

  SHOpenFolderAndSelectItems(pDir, Length(AList), PItemIDList(AList), 0);

  for I := 0 to Length(AList) -1 do begin
    if Assigned(AList[I]) then
      ILFree(AList[I]);
  end;

  ILFree(pDir);
end;

// Usage example

var AFiles : TStringList;

begin
  try
    CoInitialize(nil); // Important
    try
      AFiles := TStringList.Create();
      try
        AFiles.Add('explorer.exe');
        AFiles.Add('notepad.exe');
        AFiles.Add('HelpPane.exe');

        ///
        ShowFilesOnExplorer('C:\Windows\', AFiles);
      finally
        if Assigned(AFiles) then
          FreeAndNil(AFiles);
      end;
    except
      on E: Exception do
        Writeln(E.ClassName, ': ', E.Message);
    end;
  finally
    CoUninitialize();
  end;
end.
