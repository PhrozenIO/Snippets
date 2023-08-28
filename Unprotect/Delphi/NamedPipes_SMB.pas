// This PoC does not handle exceptions, consider handling exception if used it in production.
program NamedPipes;

uses Winapi.Windows,
     System.SysUtils,
     System.Classes;

const PIPE_NAME           = 'NamedPipeExample';
      SERVER_MACHINE_NAME = '.'; // `.` = Local Machine

var SERVER_LISTENING_EVENT : THandle;

Type
  TCommand = (
    cmdPing,
    cmdPong,
    cmdExit
  );

  TServer = class(TThread)
  protected
    {@M}
    procedure Execute(); override;
  end;

  TClient = class(TThread)
  protected
    {@M}
    procedure Execute(); override;
  end;

(* Local *)

{ _.PIPE_WriteInteger
  Write to named pipe a signed integer (4 bytes), since in our example, named pipe has
  a buffer of 2 bytes, we must split our signed integer to two words }
procedure PIPE_WriteInteger(const hPipe : THandle; const AValue : Integer);
var wLow, wHigh   : Word;
    ABytesWritten : Cardinal;
begin
  wLow  := Word(AValue and $FFFF);
  wHigh := Word(AValue shr 16);
  ///

  WriteFile(hPipe, wLow, SizeOf(Word), ABytesWritten, nil);
  WriteFile(hPipe, wHigh, SizeOf(Word), ABytesWritten, nil);
end;

{ _.PIPE_ReadInteger
 Reconstruct signed integer from two words }
function PIPE_ReadInteger(const hPipe : THandle) : Integer;
var wLow, wHigh : Word;
    dwBytesRead : Cardinal;
begin
  result := -1;
  ///

  ReadFile(hPipe, wLow, SizeOf(Word), dwBytesRead, nil);
  ReadFile(hPipe, wHigh, SizeOf(Word), dwBytesRead, nil);

  ///
  result := wLow or (wHigh shl 16);
end;

{ _.PIPE_WriteLine
Write to NamedPipe and append a CRLF to signify end of buffer }
procedure PIPE_WriteLine(const hPipe : THandle; AMessage : String);
var ABytesWritten : Cardinal;
    i             : Cardinal;
begin
  AMessage := Trim(AMessage) + #13#10;
  ///

  for I := 1 to Length(AMessage) do begin
    // https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-writefile?WT_mc_id=SEC-MVP-5005282
    if not WriteFile(
      hPipe,
      AMessage[I],
      SizeOf(WideChar),
      ABytesWritten,
      nil
    ) then
      break;
  end;
end;

{ _.PIPE_ReadLine
Read NamedPipe Buffer until CRLF is reached }
function PIPE_ReadLine(const hPipe : THandle) : String;
var ABuffer     : WideChar;
    dwBytesRead : Cardinal;
    CR          : Boolean;
    LF          : Boolean;
begin
  result := '';
  ///

  CR := False;
  LF := False;

  while True do begin
    // https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-readfile?WT_mc_id=SEC-MVP-5005282
    if not ReadFile(hPipe, ABuffer, SizeOf(ABuffer), dwBytesRead, nil) then
      break;

    case ABuffer of
      #13 : CR := True;
      #10 : LF := True;
    end;

    if CR and LF then
      break;

    ///
    result := result + ABuffer;
  end;
end;

(* TServer *)

{ TServer.Execute }
procedure TServer.Execute();
var hPipe : THandle;
begin
  hPipe := INVALID_HANDLE_VALUE;
  try
    // https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-createnamedpipew?WT_mc_id=SEC-MVP-5005282
    hPipe := CreateNamedPipeW(
      PWideChar(Format('\\.\pipe\%s', [PIPE_NAME])),
      PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE or PIPE_READMODE_MESSAGE or PIPE_WAIT,
      1,
      SizeOf(WideChar),
      SizeOf(WideChar),
      NMPWAIT_USE_DEFAULT_WAIT,
      nil
    );

    if hPipe = INVALID_HANDLE_VALUE then
      Exit();

    SetEvent(SERVER_LISTENING_EVENT); // Signal we are listening for named pipe client

    while (not Terminated) do begin
      // https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-connectnamedpipe?WT_mc_id=SEC-MVP-5005282
      if not ConnectNamedPipe(hPipe, nil) then
        continue;
      try
        while (not Terminated) do begin
          case TCommand(PIPE_ReadInteger(hPipe)) of
            cmdPing : PIPE_WriteLine(hPIpe, Format('Pong: %d', [GetTickCount()]));

            else begin
              WriteLn('Bye!');

              break;
            end;
          end;
        end;

        WriteLn(PIPE_ReadLine(hPipe));
      finally
        // https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-disconnectnamedpipe?WT_mc_id=SEC-MVP-5005282
        DisconnectNamedPipe(hPipe);
      end;
    end;
  finally
    if hPipe <> INVALID_HANDLE_VALUE then
      // https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle?WT_mc_id=SEC-MVP-5005282
      CloseHandle(hPipe);

    ///
    ExitThread(0);
  end;
end;

(* TClient *)

{ TClient.Execute

  An alternative to CreateFileW + WriteFile would be to use:
    - https://learn.microsoft.com/en-us/windows/win32/api/namedpipeapi/nf-namedpipeapi-callnamedpipew?WT_mc_id=SEC-MVP-5005282
}
procedure TClient.Execute();
var hPipe : THandle;
begin
  hPipe := INVALID_HANDLE_VALUE;
  try
    // https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew?WT_mc_id=SEC-MVP-5005282
    hPipe := CreateFileW(
      PWideChar(Format('\\%s\pipe\%s', [
        SERVER_MACHINE_NAME,
        PIPE_NAME
      ])),
      GENERIC_READ or GENERIC_WRITE,
      0,
      nil,
      OPEN_EXISTING,
      0,
      0
    );

    if hPipe = INVALID_HANDLE_VALUE then
      Exit();

    PIPE_WriteInteger(hPipe, Integer(TCommand.cmdPing));

    WriteLn(PIPE_ReadLine(hPipe));

    PIPE_WriteInteger(hPipe, Integer(TCommand.cmdExit));
  finally
    if hPipe <> INVALID_HANDLE_VALUE then
      // https://learn.microsoft.com/en-us/windows/win32/api/handleapi/nf-handleapi-closehandle?WT_mc_id=SEC-MVP-5005282
      CloseHandle(hPipe);

    ///
    ExitThread(0);
  end;
end;

(* _.EntryPoint *)

var Server : TServer;
    Client : TClient;

begin
  AllocConsole();
  ///

  // Create a event to signal when named pipe server is successfully listening for
  // Namedpipe clients.
  // When event is signaled, we can start our named pipe client thread.
  SERVER_LISTENING_EVENT := CreateEvent(nil, False, False, nil);
  if SERVER_LISTENING_EVENT = 0 then
    Exit();
  try
    // Launch NamedPipe Server
    Server := TServer.Create();

    ///
    WaitForSingleObject(SERVER_LISTENING_EVENT, INFINITE);
  finally
    CloseHandle(SERVER_LISTENING_EVENT);
  end;

  // Launch NamedPipe Client
  Client := TClient.Create();

  // Wait for Threads end
  Client.WaitFor();
  Server.WaitFor();

end.