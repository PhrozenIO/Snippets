program FindWindowAPI;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, WinAPI.Windows, Generics.Collections, psAPI;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  TFindWindowSignature Class
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

type
  TFindWindowSignature = class
  private
    FDescription : String;
    FClassName   : String;
    FWindowName  : String;
  public
    {@C}
    constructor Create(ADescription, AClassName, AWindowName : String);

    {@G}
    property Description : String read FDescription;
    property ClassName   : String read FClassName;
    property WindowName  : String read FWindowName;
  end;

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TFindWindowSignature.Create(ADescription, AClassName, AWindowName : String);
begin
  FDescription := ADescription;
  FClassName   := AClassName;
  FWindowName  := AWindowName;
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Main
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

var LFindWindowSignatures  : TObjectList<TFindWindowSignature>;
    LEnumWindowsSignatures : TDictionary<String, String>;

{-------------------------------------------------------------------------------
  When a Window handle is found it will output to console several information
  about spotted process.
-------------------------------------------------------------------------------}
procedure Found(ADescription : String; AHandle : THandle);
const CRLF = #13#10;

var AStdout_TXT    : String;
    AProcessId     : Cardinal;
    AProcessHandle : THandle;
    ARet           : DWORD;
    pImagePath     : PWideChar;
begin
  try
      AStdout_TXT := AStdout_TXT + StringOfChar('-', 60) + CRLF;
      AStdout_TXT := AStdout_TXT + ADescription + CRLF;
      AStdout_TXT := AStdout_TXT + StringOfChar('-', 60) + CRLF;

      AStdout_TXT := AStdout_TXT + Format('Handle: %d%s', [AHandle, CRLF]);

      GetWindowThreadProcessId(AHandle, @AProcessId);

      if (AProcessId > 0) then begin
        AProcessHandle := OpenProcess(
                                        (PROCESS_QUERY_INFORMATION or PROCESS_VM_READ),
                                        False,
                                        AProcessId
        );

        if (AProcessHandle > 0) then begin
          AStdout_TXT := AStdout_TXT + Format('Process Id: %d%s', [AProcessId, CRLF]);

          pImagePath := nil;
          try
              GetMem(pImagePath, (MAX_PATH * 2));
              ARet := GetModuleFileNameExW(AProcessHandle, 0, pImagePath, (MAX_PATH * 2));
              if (ARet > 0) then begin
                AStdout_TXT := AStdout_TXT + Format('Process Name: %s%s', [ExtractFileName(String(pImagePath)), CRLF]);
                AStdout_TXT := AStdout_TXT + Format('Image Path: %s%s', [ExtractFilePath(String(pImagePath)), CRLF]);
              end;
          finally
            if Assigned(pImagePath) and (ARet > 0) then
              FreeMem(pImagePath, ARet);
          end;
        end;
      end;

      AStdout_TXT := AStdout_TXT + StringOfChar('-', 60) + CRLF + CRLF;

      ///
  finally
    WriteLn(AStdout_TXT);
  end;
end;

{-------------------------------------------------------------------------------
  Find Debuggers by Window Name or Class Name using FindWindow API
-------------------------------------------------------------------------------}
function Locate_FindWindow() : Boolean;
var AFindWindowSignature : TFindWindowSignature;
    i                    : Integer;
    pClassName           : Pointer;
    pWindowName          : Pointer;
    AHandle              : THandle;
begin
  result := False;
  ///

  for i := 0 to LFindWindowSignatures.Count -1 do begin
    AFindWindowSignature := LFindWindowSignatures.Items[i];
    if NOT Assigned(AFindWindowSignature) then
      continue;
    ///

    pClassName  := nil;
    pWindowName := nil;

    if NOT AFindWindowSignature.ClassName.isEmpty then
      pClassName := PWideChar(AFindWindowSignature.ClassName);

    if NOT AFindWindowSignature.WIndowName.isEmpty then
      pWindowName := PWideChar(AFindWindowSignature.WindowName);

    AHandle := FindWindowW(pClassName, pWindowName);
    if (AHandle > 0) then begin
      Found(AFindWindowSignature.Description, AHandle);

      ///
      result := True;
    end;
  end;
end;

{-------------------------------------------------------------------------------
  Find Debuggers by Window Name (via Window Name Pattern) using EnumWindows API
-------------------------------------------------------------------------------}
function EnumWindowProc(AHandle : THandle; AParam : LPARAM) : BOOL; stdcall;
var AMaxCount   : Integer;
    AWindowName : String;
    AOldLen     : Cardinal;
    APattern    : String;
    AKey        : String;
begin
  result := True;
  ///

  if (AHandle = 0) then
    Exit();
  ///

  AMaxCount := GetWindowTextLength(AHandle) + 1;
  if (AMaxCount = 0) then
    Exit();

  SetLength(AWindowName, AMaxCount); // Other technique instead of using GetMem / FreeMem a new Pointer.
  try
      if (GetWindowTextW(AHandle, PWideChar(AWindowName), AMaxCount) = 0) then
        Exit();
      ///

      AOldLen := Length(AWindowName);

      for AKey {Description} in LEnumWindowsSignatures.keys do begin
        if NOT LEnumWindowsSignatures.TryGetValue(AKey, APattern) then
          continue;

        AWindowName := StringReplace(AWindowName, APattern, '', []);

        if (Length(AWindowName) <> AOldLen) then begin
          Found(AKey, AHandle);

          break;
        end;
      end;
  finally
    SetLength(AWindowName, 0);
  end;
end;

function Locate_EnumWindows() : Boolean;
begin
  EnumWindows(@EnumWindowProc, 0);
end;

{-------------------------------------------------------------------------------
  Append FindWindow Technique Signature
-------------------------------------------------------------------------------}
procedure AppendFindWindowSignature(ADescription, AClassName, AWindowName : String);
var AFindWindowSignature : TFindWindowSignature;
begin
  if NOT Assigned(LFindWindowSignatures) then
    Exit();
  ///

  AFindWindowSignature := TFindWindowSignature.Create(ADescription, AClassName, AWindowName);

  LFindWindowSignatures.Add(AFindWindowSignature);
end;

{-------------------------------------------------------------------------------
  ___entry
-------------------------------------------------------------------------------}
begin
  try
    LFindWindowSignatures := TObjectList<TFindWindowSignature>.Create();
    LEnumWindowsSignatures := TDictionary<String, String>.Create();
    try
      {
        Configure debuggers signatures here for FindWindow API technique.
      }
      AppendFindWindowSignature('OllyDbg', 'OLLYDBG', '');
      AppendFindWindowSignature('x64dbg (x64)', '', 'x64dbg');
      AppendFindWindowSignature('x32dbg (x32)', '', 'x32dbg');

      // ...
      // AppendFindWindowSignature('...', '...', '...');
      // ...

      {
        Configure debuggeers signatures here for EnumWindows API technique.
      }
      LEnumWindowsSignatures.Add('Immunity Debugger', 'Immunity Debugger');

      // ...
      // AEnumWindowsSignatures.Add('...', '...');
      // ...

      {
        Fire !!!
      }
      Locate_FindWindow();
      Locate_EnumWindows();

      readln;
    finally
      if Assigned(LFindWindowSignatures) then
        FreeAndNil(LFindWindowSignatures);

      if Assigned(LEnumWindowsSignatures) then
        FreeAndNil(LEnumWindowsSignatures);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;

end.