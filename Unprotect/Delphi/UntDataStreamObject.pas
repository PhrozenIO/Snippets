unit UntDataStreamObject;

interface

uses WinAPI.Windows, System.Classes, System.SysUtils, Generics.Collections,
      RegularExpressions;

type
  TEnumDataStream = class;
  TADSBackupStatus = (absTotal, absPartial, absError);

  TDataStream = class
  private
    FOwner      : TEnumDataStream;
    FStreamName : String;
    FStreamSize : Int64;

    {@M}
    function GetStreamPath() : String;
  public
    {@C}
    constructor Create(AOwner : TEnumDataStream; AStreamName : String; AStreamSize : Int64);

    {@M}
    function CopyFileToADS(AFileName : String) : Boolean;
    function BackupFromADS(ADestPath : String) : Boolean;
    function DeleteFromADS() : Boolean;

    {@G/S}
    property StreamName : String read FStreamName;
    property StreamSize : Int64  read FStreamSize;
    property StreamPath : String read GetStreamPath;
  end;

  TEnumDataStream = class
  private
    FTargetFile            : String;
    FItems                 : TObjectList<TDataStream>;
    FForceBackUpReadMethod : Boolean;

    {@M}
    function Enumerate_FindFirstStream() : Int64;
    function Enumerate_BackupRead() : Int64;
    function ExtractADSName(ARawName : String) : String;
    function CopyFromTo(AFrom, ATo : String) : Boolean;
    function GetDataStreamFromName(AStreamName : String) : TDataStream;
  public
    {@C}
    constructor Create(ATargetFile : String; AEnumerateNow : Boolean = True; AForceBackUpReadMethod : Boolean = False);
    destructor Destroy(); override;

    {@M}
    function Refresh() : Int64;

    function CopyFileToADS(AFilePath : String) : Boolean;
    function BackupFromADS(ADataStream : TDataStream; ADestPath : String) : Boolean; overload;
    function DeleteFromADS(ADataStream : TDataStream) : Boolean; overload;
    function BackupAllFromADS(ADestPath : String) : TADSBackupStatus;
    function BackupFromADS(AStreamName, ADestPath : String) : Boolean; overload;
    function DeleteFromADS(AStreamName : String) : Boolean; overload;

    {@G}
    property TargetFile : String                   read FTargetFile;
    property Items      : TObjectList<TDataStream> read FItems;
  end;

implementation

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


   TEnumDataStream


+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

{
  FindFirstStream / FindNextStream API Definition
}
type
  _STREAM_INFO_LEVELS = (FindStreamInfoStandard, FindStreamInfoMaxInfoLevel);
  TStreamInfoLevels = _STREAM_INFO_LEVELS;

  _WIN32_FIND_STREAM_DATA = record
    StreamSize : LARGE_INTEGER;
    cStreamName : array[0..(MAX_PATH + 36)] of WideChar;
  end;
  TWin32FindStreamData = _WIN32_FIND_STREAM_DATA;

var hKernel32         : THandle;
    _FindFirstStreamW : function(lpFileName : LPCWSTR; InfoLevel : TStreamInfoLevels; lpFindStreamData : LPVOID; dwFlags : DWORD) : THandle; stdcall;
    _FindNextStreamW  : function(hFindStream : THandle; lpFindStreamData : LPVOID) : BOOL; stdcall;


{-------------------------------------------------------------------------------
  Return the ADS name from it raw name (:<name>:$DATA)
-------------------------------------------------------------------------------}
function TEnumDataStream.ExtractADSName(ARawName : String) : String;
var AMatch : TMatch;
    AName  : String;
begin
  result := ARawName;
  ///

  AName := '';
  AMatch := TRegEx.Match(ARawName, ':(.*):');
  if (AMatch.Groups.Count < 2) then
    Exit();

  result := AMatch.Groups.Item[1].Value;
end;

{-------------------------------------------------------------------------------
  Scan for ADS using method N�1 (FindFirstStream / FindNextStream). Work since
  Microsoft Windows Vista.
-------------------------------------------------------------------------------}
function TEnumDataStream.Enumerate_FindFirstStream() : Int64;
var hStream     : THandle;
    AData       : TWin32FindStreamData;

    procedure ProcessDataStream();
    var ADataStream : TDataStream;
    begin
      if (String(AData.cStreamName).CompareTo('::$DATA') = 0) then
        Exit();
      ///

      ADataStream := TDataStream.Create(self, ExtractADSName(String(AData.cStreamName)), Int64(AData.StreamSize));

      FItems.Add(ADataStream);
    end;

begin
  result := 0;
  ///

  self.FItems.Clear();

  if NOT FileExists(FTargetFile) then
    Exit(-1);

  if (NOT Assigned(@_FindFirstStreamW)) or (NOT Assigned(@_FindNextStreamW)) then
    Exit(-2);

  FillChar(AData, SizeOf(TWin32FindStreamData), #0);

  // https://docs.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-findfirststreamw
  hStream := _FindFirstStreamW(PWideChar(FTargetFile), FindStreamInfoStandard, @AData, 0);
  if (hStream = INVALID_HANDLE_VALUE) then begin
    case GetLastError() of
      ERROR_HANDLE_EOF : begin
        Exit(-3); // No ADS Found
      end;

      ERROR_INVALID_PARAMETER : begin
        Exit(-4); // Not compatible
      end;

      else begin
        Exit(-5);
      end;
    end;
  end;

  ProcessDataStream();

  // https://docs.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-findnextstreamw
  while True do begin
    FillChar(AData, SizeOf(TWin32FindStreamData), #0);

    if NOT _FindNextStreamW(hStream, @AData) then
      break;

    ProcessDataStream();
  end;

  ///
  result := self.FItems.Count;
end;

{-------------------------------------------------------------------------------
  Scan for ADS using method N�2 (BackupRead()). Works since
  Microsoft Windows XP.
-------------------------------------------------------------------------------}
function TEnumDataStream.Enumerate_BackupRead() : Int64;
var hFile           : THandle;
    AStreamId       : TWIN32StreamID;
    ABytesRead      : Cardinal;
    pContext        : Pointer;
    ALowByteSeeked  : Cardinal;
    AHighByteSeeked : Cardinal;
    AName           : String;
    ABytesToRead    : Cardinal;
    ASeekTo         : LARGE_INTEGER;
    AClose          : Boolean;
begin
  result := 0;
  AClose := False;
  ///
  hFile := CreateFile(
                        PWideChar(self.TargetFile),
                        GENERIC_READ,
                        FILE_SHARE_READ,
                        nil,
                        OPEN_EXISTING,
                        FILE_FLAG_BACKUP_SEMANTICS,
                        0
  );
  if (hFile = INVALID_HANDLE_VALUE) then
    Exit(-1);
  try
    pContext := nil;
    try
      while True do begin
        FillChar(AStreamId, SizeOf(TWIN32StreamID), #0);
        ///

        {
          Read Stream
        }
        ABytesToRead := SizeOf(TWIN32StreamID) - 4; // We don't count "cStreamName"

        if NOT BackupRead(hFile, @AStreamId, ABytesToRead, ABytesRead, False, False, pContext) then
          break;

        AClose := True;

        if (ABytesRead = 0) then
          break;

        ASeekTo.QuadPart := (AStreamId.Size + AStreamId.dwStreamNameSize);

        case AStreamId.dwStreamId of
          {
            Deadling with ADS Only
          }
          BACKUP_ALTERNATE_DATA : begin
            if (AStreamId.dwStreamNameSize > 0) then begin
              {
                Read ADS Name
              }
              ABytesToRead := AStreamId.dwStreamNameSize;
              SetLength(AName, (ABytesToRead div SizeOf(WideChar)));
              if BackupRead(hFile, PByte(AName), ABytesToRead, ABytesRead, False, False, pContext) then begin
                Dec(ASeekTo.QuadPart, ABytesRead); // Already done

                FItems.Add(TDataStream.Create(self, ExtractADSName(AName), AStreamId.Size));
              end;
            end;
          end;
        end;

        {
          Goto Next Stream.
        }
        if NOT BackupSeek(hFile, ASeekTo.LowPart, ASeekTo.HighPart, ALowByteSeeked, AHighByteSeeked, pContext) then
          break;

        (*
          //////////////////////////////////////////////////////////////////////
          // BackupSeek() Alternative (Manual method)
          //////////////////////////////////////////////////////////////////////

          var ABuffer : array[0..2096-1] of byte;
          // ...
          while True do begin
            if (ASeekTo.QuadPart < SizeOf(ABuffer)) then
              ABytesToRead := ASeekTo.QuadPart
            else
              ABytesToRead := SizeOf(ABuffer);

            if ABytesToRead = 0 then
              break;

            if NOT BackupRead(hFile, PByte(@ABuffer), ABytesToRead, ABytesRead, False, False, pContext) then
              break;
            ///

            Dec(ASeekTo.QuadPart, ABytesRead);

            if (ASeekTo.QuadPart <= 0) then
              break;
          end;
          // ...

          //////////////////////////////////////////////////////////////////////
        *)
      end;
    finally
      if AClose then
        BackupRead(hFile, nil, 0, ABytesRead, True, False, pContext);
    end;
  finally
    CloseHandle(hFile);
  end;
end;

{-------------------------------------------------------------------------------
  Refresh embedded data stream objects using Windows API. Returns number of
  data stream objects or an error identifier.
-------------------------------------------------------------------------------}
function TEnumDataStream.Refresh() : Int64;
var AVersion : TOSVersion;
begin
  result := 0;
  ///

  if (AVersion.Major >= 6) then begin
    {
      Vista and above
    }
    if self.FForceBackUpReadMethod then
      result := self.Enumerate_BackupRead()
    else
      result := self.Enumerate_FindFirstStream();
  end else if (AVersion.Major = 5) and (AVersion.Minor >= 1) then begin
    {
      Windows XP / Server 2003 & R2
    }
    result := self.Enumerate_BackupRead();
  end else begin
    // Unsupported (???)
  end;
end;

{-------------------------------------------------------------------------------
  Refresh ADS Files and retrieve one ADS file by it name.
-------------------------------------------------------------------------------}
function TEnumDataStream.GetDataStreamFromName(AStreamName : String) : TDataStream;
var I       : Integer;
    AStream : TDataStream;
begin
  result := nil;
  ///

  if (self.Refresh() > 0) then begin
    for I := 0 to self.Items.count -1 do begin
      AStream := self.Items.Items[i];
      if NOT Assigned(AStream) then
        continue;
      ///

      if (String.Compare(AStream.StreamName, AStreamName, True) = 0) then
        result := AStream;
    end;
  end;
end;

{-------------------------------------------------------------------------------
  ADS Classic Actions
    - Copy file to current ADS Location.
    - Copy ADS item to destination path.
    - Delete ADS Item.
-------------------------------------------------------------------------------}

function TEnumDataStream.CopyFromTo(AFrom, ATo : String) : Boolean;
var hFromFile     : THandle;
    hToFile       : THandle;

    ABuffer       : array[0..4096-1] of byte;
    ABytesRead    : Cardinal;
    ABytesWritten : Cardinal;
begin
  result := False;
  ///

  hFromFile := INVALID_HANDLE_VALUE;
  hToFile   := INVALID_HANDLE_VALUE;

  try
    hFromFile := CreateFile(PWideChar(AFrom), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
    if (hFromFile = INVALID_HANDLE_VALUE) then
      Exit();

    hToFile := CreateFile(
                            PWideChar(ATo),
                            GENERIC_WRITE,
                            FILE_SHARE_WRITE,
                            nil,
                            CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL,
                            0
    );

    if (hToFile = INVALID_HANDLE_VALUE) then
      Exit();
    ///

    while True do begin
      {
        Read
      }
      if NOT ReadFile(hFromFile, ABuffer, SizeOf(ABuffer), ABytesRead, nil) then
        Exit();

      if ABytesRead = 0 then
        break; // Success

      {
        Write
      }
      if NOT WriteFile(hToFile, ABuffer, ABytesRead, ABytesWritten, nil) then
        Exit();

      if (ABytesWritten <> ABytesRead) then
        Exit();
    end;

    ///
    result := True;
  finally
    if hFromFile <> INVALID_HANDLE_VALUE then
      CloseHandle(hFromFile);

    if hToFile <> INVALID_HANDLE_VALUE then
      CloseHandle(hToFile);

    ///
    self.Refresh();
  end;
end;

function TEnumDataStream.CopyFileToADS(AFilePath : String) : Boolean;
begin
  result := CopyFromTo(AFilePath, Format('%s:%s', [self.FTargetFile, ExtractFileName(AFilePath)]));
end;

function TEnumDataStream.BackupFromADS(ADataStream : TDataStream; ADestPath : String) : Boolean;
begin
  result := False;

  if NOT Assigned(ADataStream) then
    Exit();

  result := CopyFromTo(ADataStream.StreamPath, Format('%s%s', [IncludeTrailingPathDelimiter(ADestPath), ADataStream.StreamName]));
end;

function TEnumDataStream.DeleteFromADS(ADataStream : TDataStream) : Boolean;
begin
  result := DeleteFile(ADataStream.StreamPath);
end;

function TEnumDataStream.BackupAllFromADS(ADestPath : String) : TADSBackupStatus;
var I       : integer;
    AStream : TDataStream;
begin
  result := absError;
  ///

  if (self.Refresh() > 0) then begin
    for I := 0 to self.Items.count -1 do begin
      AStream := self.Items.Items[i];
      if NOT Assigned(AStream) then
        continue;
      ///

      if AStream.BackupFromADS(ADestPath) and (result <> absPartial) then
        result := absTotal
      else
        result := absPartial;
    end;
  end;
end;

function TEnumDataStream.BackupFromADS(AStreamName, ADestPath : String) : Boolean;
var AStream : TDataStream;
begin
  result := False;
  ///

  AStream := self.GetDataStreamFromName(AStreamName);
  if Assigned(AStream) then
    result := self.BackupFromADS(AStream, ADestPath);
end;

function TEnumDataStream.DeleteFromADS(AStreamName : String) : Boolean;
var AStream : TDataStream;
begin
  result := False;
  ///

  AStream := self.GetDataStreamFromName(AStreamName);
  if Assigned(AStream) then
    result := self.DeleteFromADS(AStream);
end;

{-------------------------------------------------------------------------------
  ___constructor
-------------------------------------------------------------------------------}
constructor TEnumDataStream.Create(ATargetFile : String; AEnumerateNow : Boolean = True; AForceBackUpReadMethod : Boolean = False);
begin
  self.FTargetFile := ATargetFile;
  self.FForceBackUpReadMethod := AForceBackupReadMethod;

  FItems := TObjectList<TDataStream>.Create();
  FItems.OwnsObjects := True;

  if AEnumerateNow then
    self.Refresh();
end;

{-------------------------------------------------------------------------------
  ___destructor
-------------------------------------------------------------------------------}
destructor TEnumDataStream.Destroy();
begin
  if Assigned(FItems) then
    FreeAndNil(FItems);

  ///
  inherited Destroy();
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


   TDataStream


+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

constructor TDataStream.Create(AOwner : TEnumDataStream; AStreamName : String; AStreamSize : Int64);
begin
  self.FOwner      := AOwner;
  self.FStreamName := AStreamName;
  self.FStreamSize := AStreamSize;
end;

{-------------------------------------------------------------------------------
  Generate Stream Path Accordingly
-------------------------------------------------------------------------------}
function TDataStream.GetStreamPath() : String;
begin
  result := '';

  if NOT Assigned(FOwner) then
    Exit();

  result := Format('%s:%s', [FOwner.TargetFile, self.FStreamName]);
end;

{-------------------------------------------------------------------------------
  ADS Classic Actions (Redirected to Owner Object)
-------------------------------------------------------------------------------}

function TDataStream.CopyFileToADS(AFileName : String) : Boolean;
begin
  if Assigned(FOwner) then
    result := FOwner.CopyFileToADS(AFileName);
end;

function TDataStream.BackupFromADS(ADestPath : String) : Boolean;
begin
  if Assigned(FOwner) then
    result := FOwner.BackupFromADS(self, ADestPath);
end;

function TDataStream.DeleteFromADS() : Boolean;
begin
  if Assigned(FOwner) then
    result := FOwner.DeleteFromADS(self);
end;

// +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

initialization
  _FindFirstStreamW := nil;
  _FindNextStreamW  := nil;

  hKernel32 := LoadLibrary('KERNEL32.DLL');
  if (hKernel32 > 0) then begin
    @_FindFirstStreamW := GetProcAddress(hKernel32, 'FindFirstStreamW');
    @_FindNextStreamW := GetProcAddress(hKernel32, 'FindNextStreamW');
  end;

finalization
  _FindFirstStreamW := nil;
  _FindNextStreamW  := nil;

end.