program SuspendThread;

{$APPTYPE CONSOLE}

uses
  WinAPI.Windows, System.SysUtils, Generics.Collections, tlHelp32, Classes;

type
  TProcessItem = class
  private
    FName      : String;
    FProcessId : Cardinal;
    FThreads   : TList<Cardinal>;

    {@M}
    procedure EnumThreads();
  public
    {@C}
    constructor Create(AName : String; AProcessId : Cardinal; AEnumThreads : Boolean = True);
    destructor Destroy(); override;

    {@G}
    property Name      : String          read FName;
    property ProcessId : Cardinal        read FProcessId;
    property Threads   : TList<Cardinal> read FThreads;
  end;

  TEnumProcess = class
  private
    FItems : TObjectList<TProcessItem>;
  public
    {@C}
    constructor Create();
    destructor Destroy(); override;

    {@M}
    function Refresh() : Cardinal;
    procedure Clear();

    function Get(AProcessId : Cardinal) : TProcessItem; overload;
    function Get(AName : String) : TProcessItem; overload;

    {@G}
    property Items : TObjectList<TProcessItem> read FItems;
  end;

{
  Import API's From Kernel32
}
const THREAD_SUSPEND_RESUME = $00000002;

function OpenThread(
                      dwDesiredAccess: DWORD;
                      bInheritHandle: BOOL;
                      dwThreadId: DWORD
          ) : THandle; stdcall; external kernel32 name 'OpenThread';

{
  Global Vars
}
var LFindWindowSignatures  : TDictionary<String, String>;
    LProcessNameSignatures : TStringList;
    LProcesses             : TEnumProcess;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Process Item (Process Name / Process Id / Process Main Thread Id)
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TProcessItem.Create(AName : String; AProcessId : Cardinal; AEnumThreads : Boolean = True);
begin
  FName      := AName;
  FProcessId := AProcessId;

  FThreads := TList<Cardinal>.Create();

  if AEnumThreads then
    self.EnumThreads();
end;

{-------------------------------------------------------------------------------
  ___destructor
-------------------------------------------------------------------------------}
destructor TProcessItem.Destroy();
begin
  if Assigned(FThreads) then
    FreeAndNil(FThreads);

  ///
  inherited Destroy();
end;

{-------------------------------------------------------------------------------
  Enumerate Threads of process object
-------------------------------------------------------------------------------}
procedure TProcessItem.EnumThreads();
var ASnap        : THandle;
    AThreadEntry : TThreadEntry32;

    procedure InitializeItem();
    begin
      ZeroMemory(@AThreadEntry, SizeOf(TThreadEntry32));

      AThreadEntry.dwSize := SizeOf(TThreadEntry32);
    end;

    procedure AppendItem();
    begin
      if (AThreadEntry.th32OwnerProcessID <> FProcessId) then
        Exit();
      ///

      FThreads.Add(AThreadEntry.th32ThreadID);
    end;
begin
  if NOT Assigned(FThreads) then
    Exit();
  ///

  FThreads.Clear();
  ///

  ASnap := CreateToolHelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (ASnap = INVALID_HANDLE_VALUE) then
    Exit();
  try
    InitializeItem();

    if NOT Thread32First(ASnap, AThreadEntry) then
      Exit();

    AppendItem();

    while True do begin
      InitializeItem();

      if NOT Thread32Next(ASnap, AThreadEntry) then
        break;

      AppendItem();
    end;
  finally
    CloseHandle(ASnap);
  end;
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Enumerate Process Class
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TEnumProcess.Create();
begin
  FItems := TObjectList<TProcessItem>.Create();
  FItems.OwnsObjects := True;

  ///
  self.Refresh();
end;

{-------------------------------------------------------------------------------
  ___destructor
-------------------------------------------------------------------------------}
destructor TEnumProcess.Destroy();
begin
  if Assigned(FItems) then
    FreeAndNil(FItems);

  ///
  inherited Destroy();
end;

{-------------------------------------------------------------------------------
  Enumerate Running Process.
  @Return: Process Count
-------------------------------------------------------------------------------}
function TEnumProcess.Refresh() : Cardinal;
var ASnap         : THandle;
    AProcessEntry : TProcessEntry32;

    procedure InitializeItem();
    begin
      ZeroMemory(@AProcessEntry, SizeOf(TProcessEntry32));

      AProcessEntry.dwSize := SizeOf(TProcessEntry32);
    end;

    procedure AppendItem();
    var AItem : TProcessItem;
    begin
      AItem := TProcessItem.Create(
                                    AProcessEntry.szExeFile,
                                    AProcessEntry.th32ProcessID,
                                    True {Enum Threads: Default}
      );

      FItems.Add(AItem);
    end;

begin
  result := 0;
  ///

  if NOT Assigned(FItems) then
    Exit();
  ///

  self.Clear();

  ASnap := CreateToolHelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (ASnap = INVALID_HANDLE_VALUE) then
    Exit();
  try
    InitializeItem();

    if NOT Process32First(ASnap, AProcessEntry) then
      Exit();

    AppendItem();

    while True do begin
      InitializeItem();

      if NOT Process32Next(ASnap, AProcessEntry) then
        break;

      AppendItem();
    end;
  finally
    CloseHandle(ASnap);
  end;
end;

{-------------------------------------------------------------------------------
  Clear Items (Process Objects)
-------------------------------------------------------------------------------}
procedure TEnumProcess.Clear();
begin
  if Assigned(FItems) then
    FItems.Clear;
end;

{-------------------------------------------------------------------------------
  Get Process Item by Process Id or Name
-------------------------------------------------------------------------------}
function TEnumProcess.Get(AProcessId : Cardinal) : TProcessItem;
var AItem : TProcessItem;
    I     : Integer;
begin
  result := nil;
  ///

  for I := 0 to self.Items.count -1 do begin
    AItem := self.Items.Items[I];
    if NOT Assigned(AItem) then
      continue;
    ///

    if (AItem.ProcessId = AProcessId) then begin
      result := AItem;

      Break;
    end;
  end;
end;

function TEnumProcess.Get(AName : String) : TProcessItem;
var AItem : TProcessItem;
    I     : Integer;
begin
  result := nil;
  ///

  for I := 0 to self.Items.count -1 do begin
    AItem := self.Items.Items[I];
    if NOT Assigned(AItem) then
      continue;
    ///

    if (AItem.Name.ToLower = AName.ToLower) then begin
      result := AItem;

      Break;
    end;
  end;
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Main
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{-------------------------------------------------------------------------------
  Suspend Threads of target process.
-------------------------------------------------------------------------------}
function SuspendThreadsByProcessId(AProcessId : Cardinal) : Boolean;
var AItem     : TProcessItem;
    AThreadId : Cardinal;
    I         : Integer;
    AThread   : THandle;
begin
  result := False;
  ///

  if NOT Assigned(LProcesses) then
    Exit();

  AItem := LProcesses.Get(AProcessId);
  if NOT Assigned(AItem) then
    Exit();
  ///

  if (AItem.Threads.count = 0) then
    Exit();
  ///

  for I := 0 to AItem.Threads.Count -1 do begin
    AThreadId := AItem.Threads.Items[I];
    ///

    AThread := OpenThread(THREAD_SUSPEND_RESUME, False, AThreadId);
    if (AThread = 0) then
      continue;
    try
      WriteLn(Format('Suspending: %s(%d), Thread Id: %d...', [
                                                                    AItem.Name,
                                                                    AItem.ProcessId,
                                                                    AThreadId
      ]));

      WinAPI.Windows.SuspendThread(AThread);

      result := True;
    finally
      CloseHandle(AThread);
    end;
  end;
end;

{-------------------------------------------------------------------------------
  FindWindow API Example
-------------------------------------------------------------------------------}
function method_FindWindow() : Boolean;
var AHandle     : THandle;
    AProcessId  : Cardinal;
    AClassName  : String;
    AWindowName : String;
    pClassName  : Pointer;
    pWindowName : Pointer;
begin
  result := False;
  ///

  for AClassName in LFindWindowSignatures.Keys do begin
    if NOT LFindWindowSignatures.TryGetValue(AClassName, AWindowName) then
      continue;
    ///

    pClassName  := nil;
    pWindowName := nil;

    if NOT AClassName.isEmpty then
      pClassName := PWideChar(AClassName);

    if NOT AWindowName.isEmpty then
      pWindowName := PWideChar(AWindowName);

    AHandle := FindWindowW(pClassName, pWindowName);
    if (AHandle > 0) then begin
      GetWindowThreadProcessId(AHandle, @AProcessId);
      if (AProcessId > 0) then
        SuspendThreadsByProcessId(AProcessId);

      ///
      result := True;
    end;
  end;
end;

{-------------------------------------------------------------------------------
  Find Process Example (Uses the TEnumProcess Class) - See above
-------------------------------------------------------------------------------}
function method_FindProcess() : Boolean;
var AItem : TProcessItem;
    AName : String;
    I     : Integer;
begin
  result := False;
  ///

  for I := 0 to LProcessNameSignatures.count -1 do begin
    AName := LProcessNameSignatures.Strings[I];

    AItem := LProcesses.Get(AName);
    if (NOT Assigned(AItem)) then
      continue;
    ///

    SuspendThreadsByProcessId(AItem.ProcessId);

    ///
    result := True;
  end;
end;

{-------------------------------------------------------------------------------
  ___entry
-------------------------------------------------------------------------------}
begin
  try
    LProcesses := TEnumProcess.Create();
    try
      // FindWindow API
      LFindWindowSignatures := TDictionary<String, String>.Create();
      try
        {
          ...

          @Param1: ClassName  (Empty = NULL)
          @Param2: WindowName (Empty = NULL)

          Add your own signatures bellow...
        }
        LFindWindowSignatures.Add('OLLYDBG', '');
        {
          ...
        }
        method_FindWindow();
      finally
        if Assigned(LFindWindowSignatures) then
          FreeAndNil(LFindWindowSignatures);
      end;

      // Find by Process Name
      LProcessNameSignatures := TStringList.Create();
      try
        {
          ...

          @Param1: Process Name (Example: OllyDbg.exe) - Case Insensitive

          Add your own signatures bellow...
        }
        LProcessNameSignatures.Add('ImmunityDebugger.exe');
        {
          ...
        }
        method_FindProcess();
      finally
        if Assigned(LProcessNameSignatures) then
          FreeAndNil(LProcessNameSignatures);
      end;
    finally
      if Assigned(LProcesses) then
        FreeAndNil(LProcesses);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.