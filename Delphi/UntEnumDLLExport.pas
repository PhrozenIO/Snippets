// Jean-Pierre LESUEUR (@DarkCoderSc)
unit UntEnumDLLExport;

interface

uses Classes, Windows, Generics.Collections, SysUtils;

type
  TExportEntry = class
  private
    FName         : String;
    FForwarded    : Boolean;
    FForwardName  : String;
    FRelativeAddr : Cardinal;
    FAddress      : Int64;
    FOrdinal      : Word;

    {@M}
    function GetFormatedAddress() : String;
    function GetFormatedRelativeAddr() : String;
  public
    {@C}
    constructor Create();

    {@G/S}
    property Name         : String   read FName         write FName;
    property Forwarded    : Boolean  read FForwarded    write FForwarded;
    property ForwardName  : String   read FForwardName  write FForwardName;
    property Address      : Int64    read FAddress      write FAddress;
    property RelativeAddr : Cardinal read FRelativeAddr write FRelativeAddr;
    property Ordinal      : Word     read FOrdinal      write FOrdinal;

    {@G}
    property FormatedAddress         : String read GetFormatedAddress;
    property FormatedRelativeAddress : String read GetFormatedRelativeAddr;
  end;

  TEnumDLLExport = class
  private
    FItems  : TObjectList;

    FFileName : String;

    {@M}

  public
    {@C}
    constructor Create(AFileName : String);
    destructor Destroy(); override;

    {@M}
    function Enum() : Integer;

    {@G}
    property Items    : TObjectList read FItems;
    property FileName : String                    read FFileName;
  end;

implementation

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  Local Functions
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

function IntToHexF(AValue : Int64; APad : Word = 0 {0=Auto}) : String;
begin
  if (APad = 0) then begin
    if (AValue <= High(Word)) then
      APad := 2
    else if (AValue <= High(DWORD)) and (AValue > High(Word)) then
      APad := 8
    else if (AValue <= High(Int64)) and (AValue > High(DWORD)) then
      APad := 16;
  end;

  result := '0x' + IntToHex(AValue, APad);
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  TExportEntry
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

constructor TExportEntry.Create();
begin
  FName         := '';
  FForwarded    := False;
  FForwardName  := '';
  FAddress      := 0;
  FRelativeAddr := 0;
  FOrdinal      := 0;
end;

function TExportEntry.GetFormatedAddress() : String;
begin
  result := IntToHexF(FAddress {AUTO});
end;

function TExportEntry.GetFormatedRelativeAddr() : String;
begin
  result := IntToHexF(FRelativeAddr, (SizeOf(FRelativeAddr) * 2));
end;

{+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  TEnumPEExport
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++}

constructor TEnumDLLExport.Create(AFileName : String);
begin
  FItems := TObjectList.Create(True);

  FFileName := AFileName;
end;

destructor TEnumDLLExport.Destroy();
begin
  if Assigned(FItems) then
    FreeAndNil(FItems);

  ///
  inherited Destroy();
end;

{
  ERROR_CODES:
  ------------------------------------------------------------------------------
    -99 : Unknown.
    -1  : Could not open file.
    -2  : Could not read image dos header.
    -3  : Invalid or corrupted PE File.
    -4  : Could not read nt header signature.
    -5  : Could not read image file header.
    -6  : Could not read optional header.
    -7  : Could not retrieve entry export address.
    -8  : Could not read export directory.
    -9  : No exported functions.
}
function TEnumDLLExport.Enum() : Integer;
var hFile                   : THandle;
    dwBytesRead             : Cardinal;
    AImageDosHeader         : TImageDosHeader;
    AImageNtHeaderSignature : DWORD;
    x64Binary               : Boolean;
    AImageFileHeader        : TImageFileHeader;

    AImageOptionalHeader32  : TImageOptionalHeader32;
    AImageOptionalHeader64  : TImageOptionalHeader64;

    AExportAddr             : TImageDataDirectory;
    AExportDir              : TImageExportDirectory;

    I                       : Integer;
    ACanCatchSection        : Boolean;
    AOffset                 : Cardinal;

    AExportName             : AnsiString;
    ALen                    : Cardinal;
    AOrdinal                : Word;
    AFuncAddress            : Cardinal;

    AImageBase              : UInt64;

    AExportEntry            : TExportEntry;

    AForwarded              : Boolean;
    AForwardName            : AnsiString;

    AImportVirtualAddress   : Cardinal;

    function RVAToFileOffset(ARVA : Cardinal) : Cardinal;
    var I                   : Integer;
        AImageSectionHeader : TImageSectionHeader;
        ASectionsOffset     : Cardinal;
    begin
      result := 0;
      ///

      if (ARVA = 0) or (NOT ACanCatchSection) then
        Exit();
      ///

      ASectionsOffset := (
                            AImageDosHeader._lfanew +
                            SizeOf(DWORD) +
                            SizeOf(TImageFileHeader) +
                            AImageFileHeader.SizeOfOptionalHeader
      );
      for I := 0 to (AImageFileHeader.NumberOfSections -1) do begin
        SetFilePointer(hFile, ASectionsOffset + (I * SizeOf(TImageSectionHeader)), nil, FILE_BEGIN);

        if NOT ReadFile(hFile, AImageSectionHeader, SizeOf(TImageSectionHeader), dwBytesRead, 0) then
          continue;

        if (ARVA >= AImageSectionHeader.VirtualAddress) and (ARVA < AImageSectionHeader.VirtualAddress + AImageSectionHeader.SizeOfRawData) then
          result := (ARVA - AImageSectionHeader.VirtualAddress + AImageSectionHeader.PointerToRawData);
      end;
    end;

    {
      Read file from a starting offset to a null character.
    }
    function GetStringLength(AStartAtPos : Cardinal) : Cardinal;
    var ADummy : Byte;
    begin
      result := 0;
      ///

      if (hFile = INVALID_HANDLE_VALUE) then
        Exit();

      SetFilePointer(hFile, AStartAtPos, nil, FILE_BEGIN);

      while True do begin
        if NOT ReadFile(hFile, ADummy, SizeOf(Byte), dwBytesRead, nil) then
          break;
        ///

        if (ADummy = 0) then
          break;

        Inc(result);
      end;
    end;

begin
  result := -99; // Failed
  ///

  if NOT Assigned(FItems) then
    Exit();

  FItems.Clear();

  ACanCatchSection := False;

  {
    Read PE Header to reach Export List
  }
  hFile := CreateFileW(PWideChar(FFileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if hFile = INVALID_HANDLE_VALUE then
    Exit(-1);
  ///
  try
    if NOT ReadFile(hFile, AImageDosHeader, SizeOf(TImageDosHeader), dwBytesRead, 0) then
      Exit(-2);
    ///

    if (AImageDosHeader.e_magic <> IMAGE_DOS_SIGNATURE) then
      Exit(-3); // Not a valid PE File
    ///

    SetFilePointer(hFile, AImageDosHeader._lfanew, nil, FILE_BEGIN);
    if NOT ReadFile(hFile, AImageNtHeaderSignature, SizeOf(DWORD), dwBytesRead, 0) then
      Exit(-4);
    ///

    if (AImageNTHeaderSignature <> IMAGE_NT_SIGNATURE) then
      Exit(-3);
    ///

    SetFilePointer(hFile, (AImageDosHeader._lfanew + sizeOf(DWORD)), nil, FILE_BEGIN);
    if NOT ReadFile(hFile, AImageFileHeader, SizeOf(TImageFileHeader), dwBytesRead, 0) then
      Exit(-5);
    ///

    ACanCatchSection := True;

    x64Binary := (AImageFileHeader.Machine = IMAGE_FILE_MACHINE_AMD64);
    if x64Binary then begin
      if NOT ReadFile(hFile, AImageOptionalHeader64, AImageFileHeader.SizeOfOptionalHeader, dwBytesRead, 0) then
        Exit(-6);
    end else begin
      if NOT ReadFile(hFile, AImageOptionalHeader32, AImageFileHeader.SizeOfOptionalHeader, dwBytesRead, 0) then
        Exit(-6);
    end;
    ///

    AExportAddr.VirtualAddress := 0;
    AExportAddr.Size := 0;

    if x64Binary then begin
      AExportAddr := AImageOptionalHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];

      AImageBase := AImageOptionalHeader64.ImageBase;

      AImportVirtualAddress := AImageOptionalHeader64.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    end else begin
      AExportAddr := AImageOptionalHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT];

      AImageBase := AImageOptionalHeader32.ImageBase;

      AImportVirtualAddress := AImageOptionalHeader32.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    end;

    AOffset := RVAToFileOffset(AExportAddr.VirtualAddress);
    if AOffset = 0 then
      Exit(-7);

    SetFilePointer(hFile, AOffset, nil, FILE_BEGIN);
    if NOT ReadFile(hFile, AExportDir, SizeOf(TImageExportDirectory), dwBytesRead, 0) then
      Exit(-8);
    ///

    if (AExportDir.NumberOfFunctions <= 0) then
      Exit(-9);
    ///

    {
      Enumerate Named Exported Functions
    }
    for I := 0 to AExportDir.NumberOfNames - 1 do begin
      {
        Get Exported Ordinal
      }
      AOffset := RVAToFileOffset(AExportDir.AddressOfNameOrdinals) + (I * SizeOf(Word));

      SetFilePointer(hFile, AOffset, nil, FILE_BEGIN);

      if NOT ReadFile(hFile, AOrdinal, SizeOf(Word), dwBytesRead, 0) then
        continue; // Ignore this entry
      ///

      {
        Get Exported Function Address
      }
      AOffset := RVAToFileOffset(AExportDir.AddressOfFunctions) + (AOrdinal * SizeOf(Cardinal));

      SetFilePointer(hFile, AOffset, nil, FILE_BEGIN);

      if NOT ReadFile(hFile, AFuncAddress, SizeOf(Cardinal), dwBytesRead, 0) then
        continue; // Ignore this entry

      {
        Get Exported Function Name
      }
      AOffset := RVAToFileOffset(AExportDir.AddressOfNames) + (I * SizeOf(Cardinal));

      SetFilePointer(hFile, AOffset, nil, FILE_BEGIN);

      if NOT ReadFile(hFile, AOffset, SizeOf(Cardinal), dwBytesRead, 0) then
        continue; // Ignore this entry
      ///

      ALen := GetStringLength(RVAToFileOffset(AOffset));

      SetLength(AExportName, ALen);

      SetFilePointer(hFile, RVAToFileOffset(AOffset), nil, FILE_BEGIN);

      if NOT ReadFile(hFile, AExportName[1], ALen, dwBytesRead, nil) then
        continue; // Ignore this entry

      {
        Is Function Forwarded ?
        If yes, we catch its name
      }
      AForwarded := (AFuncAddress > RVAToFileOffset(AExportAddr.VirtualAddress)) and
                    (AFuncAddress <= AImportVirtualAddress);

      if AForwarded then begin
        ALen := GetStringLength(RVAToFileOffset(AFuncAddress));

        SetFilePointer(hFile, RVAToFileOffset(AFuncAddress), nil, FILE_BEGIN);

        SetLength(AForwardName, ALen);

        if NOT ReadFile(hFile, AForwardName[1], ALen, dwBytesRead, nil) then
          continue; // Ignore this entry
      end;

      {
        Create and append a new export entry
      }
      AExportEntry := TExportEntry.Create();

      AExportEntry.Name         := AExportName;
      AExportEntry.Ordinal      := (AOrdinal + AExportDir.Base);
      AExportEntry.RelativeAddr := AFuncAddress;
      AExportEntry.Address      := (AImageBase + AFuncAddress);
      AExportEntry.Forwarded    := AForwarded;
      AExportEntry.ForwardName  := AForwardName;

      FItems.Add(AExportEntry);
    end;

    ///
    result := FItems.Count;
  finally
    CloseHandle(hFile);
  end;
end;

end.