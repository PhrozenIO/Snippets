program DLLReflector;

// DLL Reflection with both 32 and 64-bit support.
// www.unprotect.it
// @DarkCoderSc

uses
  Winapi.Windows,
  System.Classes,
  System.SysUtils;

const
  IMAGE_REL_BASED_DIR64 = 10;

type
  TImageBaseRelocation = record
    VirtualAddress : DWORD;
    SizeOfBlock    : DWORD;
  end;
  PImageBaseRelocation = ^TImageBaseRelocation;

  TImageOptionalHeader =
  {$IFDEF WIN64}
    TImageOptionalHeader64
  {$ELSE}
    TImageOptionalHeader32
  {$ENDIF};
  PImageOptionalHeader = ^TImageOptionalHeader;

  TImageThunkData =
  {$IFDEF WIN64}
    TImageThunkData64
  {$ELSE}
    TImageThunkData32
  {$ENDIF};
  PImageThunkData = ^TImageThunkData;

  PRelocationInfo =
  {$IFDEF WIN64}
    PCardinal
  {$ELSE}
    PWord
  {$ENDIF};

  TNTSignature = DWORD;
  PNTSignature = ^TNTSignature;

  TPEHeader = record
    pImageBase             : Pointer;

    // Main Headers
    _pImageDosHeader       : PImageDosHeader;
    _pNTSignature          : PNTSignature;
    _pImageFileHeader      : PImageFileHeader;
    _pImageOptionalHeader  : PImageOptionalHeader;
    _pImageSectionHeader   : PImageSectionHeader;

    // Sections Headers
    SectionHeaderCount     : Cardinal;
    pSectionHeaders        : array of PImageSectionHeader;
  end;

  TPEHeaderDirectories = record
    _pImageExportDirectory : PImageExportDirectory;
  end;

{ _.RVAToVA }
function RVAToVA(const pImageBase : Pointer; const ARelativeVirtualAddress : NativeUInt) : Pointer;
begin
  result := Pointer(NativeUInt(pImageBase) + ARelativeVirtualAddress);
end;

{ _.IdentifyPEHeader }
function IdentifyPEHeader(const pImageBase : Pointer) : TPEHeader;
var
  pOffset              : Pointer;
  _pImageSectionHeader : PImageSectionHeader;
  I                    : Cardinal;

  procedure IncOffset(const AIncrement : Cardinal);
  begin
    pOffset := Pointer(NativeUInt(pOffset) + AIncrement);
  end;

begin
  ZeroMemory(@result, SizeOf(TPEheader));
  ///

  if not Assigned(pImageBase) then
    Exit();

  result.pImageBase := pImageBase;

  pOffset := result.pImageBase;

  // Read and validate Library PE Header
  result._pImageDosHeader := pOffset;

  if (result._pImageDosHeader.e_magic <> IMAGE_DOS_SIGNATURE) then
    Exit();

  IncOffset(result._pImageDosHeader^._lfanew);

  if (PNTSignature(pOffset)^ <> IMAGE_NT_SIGNATURE) then
    Exit();

  IncOffset(SizeOf(TNTSignature));

  result._pImageFileHeader := pOffset;

  IncOffset(SizeOf(TImageFileHeader));

  result._pImageOptionalHeader := pOffset;

  IncOffset(SizeOf(TImageOptionalHeader));

  // Read and register section headers
  result.SectionHeaderCount := result._pImageFileHeader^.NumberOfSections;

  SetLength(result.pSectionHeaders, result.SectionHeaderCount);

  for I := 0 to result.SectionHeaderCount -1 do begin
    _pImageSectionHeader := pOffset;
    try
      result.pSectionHeaders[I] := _pImageSectionHeader;
    finally
      IncOffset(SizeOf(TImageSectionHeader));
    end;
  end;
end;

{ _.IdentifyPEHeaderDirectories }
function IdentifyPEHeaderDirectories(const APEHeader : TPEHeader) : TPEHeaderDirectories;
var AVirtualAddress : Cardinal;
begin
  ZeroMemory(@result, SizeOf(TPEHeaderDirectories));
  ///

  // Identify Export Directory
  AVirtualAddress := APEHeader._pImageOptionalHeader^.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;

  result._pImageExportDirectory := Pointer(NativeUInt(APEHeader.pImageBase) + AVirtualAddress);
end;

{ _.ResolveImportTable }
procedure ResolveImportTable(const APEHeader : TPEHeader);
var _pImageDataDirectory      : PImageDataDirectory;
    _pImageImportDescriptor   : PImageImportDescriptor;
    hModule                   : THandle;
    _pImageOriginalThunkData  : PImageThunkData;
    _pImageFirstThunkData     : PImageThunkData;
    pFunction                 : Pointer;
    pProcName                 : Pointer;

    function RVA(const Offset : NativeUInt) : Pointer;
    begin
      result := Pointer(NativeUInt(APEHeader.pImageBase) + Offset);
    end;

begin
  _pImageDataDirectory := @APEHeader._pImageOptionalHeader^.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
  if _pImageDataDirectory^.Size = 0 then
    Exit();

  _pImageImportDescriptor := RVA(_pImageDataDirectory^.VirtualAddress);

  while _pImageImportDescriptor^.Name <> 0 do begin
    try
      hModule := LoadLibraryA(RVA(_pImageImportDescriptor^.Name));
      if hModule = 0 then
        continue;
      try

        if _pImageImportDescriptor^.OriginalFirstThunk <> 0 then
          _pImageOriginalThunkData := RVA(_pImageImportDescriptor^.OriginalFirstThunk)
        else
          _pImageOriginalThunkData := RVA(_pImageImportDescriptor^.FirstThunk);

        _pImageFirstThunkData := RVA(_pImageImportDescriptor^.FirstThunk);

        if not Assigned(_pImageOriginalThunkData) then
          continue;

        while _pImageOriginalThunkData^.AddressOfData <> 0 do begin
          try
            if (_pImageOriginalThunkData^.Ordinal and IMAGE_ORDINAL_FLAG) <> 0 then
              pProcName := MAKEINTRESOURCE(_pImageOriginalThunkData^.Ordinal and $FFFF)
            else
              pProcName := RVA(_pImageOriginalThunkData^.AddressOfData + SizeOf(Word));

            pFunction := GetProcAddress(
                hModule,
                PAnsiChar(pProcName)
            );

            if not Assigned(pFunction) then
              continue;

            _pImageFirstThunkData^._Function := NativeUInt(pFunction);
          finally
            Inc(_pImageOriginalThunkData);
            Inc(_pImageFirstThunkData);
          end;
        end;
      finally
        FreeLibrary(hModule);
      end;
    finally
      Inc(_pImageImportDescriptor);
    end;
  end;
end;

{ _.PerformBaseRelocation }
procedure PerformBaseRelocation(const APEHeader: TPEHeader; const ADelta: NativeUInt);
var
  I                     : Cardinal;
  _pImageDataDirectory  : PImageDataDirectory;
  pRelocationTable      : PImageBaseRelocation;
  pRelocationAddress    : Pointer;

  pRelocInfo            : PRelocationInfo;

  pRelocationType       : Integer;
  pRelocationOffset     : NativeUInt;
  ARelocationCount      : Cardinal;

const
  IMAGE_SIZEOF_BASE_RELOCATION = 8;
  IMAGE_REL_BASED_HIGH         = 1;
  IMAGE_REL_BASED_LOW          = 2;
  IMAGE_REL_BASED_HIGHLOW      = 3;
begin
  _pImageDataDirectory := @APEHeader._pImageOptionalHeader^.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC];
  if _pImageDataDirectory^.Size = 0 then
    Exit();

  pRelocationTable := RVAToVA(APEHeader.pImageBase, _pImageDataDirectory^.VirtualAddress);

  while pRelocationTable^.VirtualAddress > 0 do begin
    pRelocationAddress := RVAToVA(APEHeader.pImageBase, pRelocationTable^.VirtualAddress);
    pRelocInfo := RVAToVA(pRelocationTable, IMAGE_SIZEOF_BASE_RELOCATION);

    ARelocationCount := (pRelocationTable^.SizeOfBlock - SizeOf(TImageBaseRelocation)) div SizeOf(Word);

    for I := 0 to ARelocationCount -1 do begin
      pRelocationType := (pRelocInfo^ shr 12);
      pRelocationOffset := pRelocInfo^ and $FFF;

      case pRelocationType of
        IMAGE_REL_BASED_HIGHLOW, IMAGE_REL_BASED_DIR64:
          Inc(PNativeUInt(NativeUInt(pRelocationAddress) + pRelocationOffset)^, ADelta);

        IMAGE_REL_BASED_HIGH:
          Inc(PNativeUInt(NativeUInt(pRelocationAddress) + pRelocationOffset)^, HiWord(ADelta));

        IMAGE_REL_BASED_LOW:
          Inc(PNativeUInt(NativeUInt(pRelocationAddress) + pRelocationOffset)^, LoWord(ADelta));
      end;

      Inc(pRelocInfo);
    end;

    ///
    pRelocationTable := Pointer(NativeUInt(pRelocationTable) + pRelocationTable^.SizeOfBlock);
  end;
end;

{ _.ReflectLibraryFromMemory }
function ReflectLibraryFromMemory(const pSourceBuffer : Pointer; const ABufferSize : UInt) : Pointer;
var pOffset              : Pointer;
    ASourcePEHeader      : TPEHeader;
    ADestPEHeader        : TPEHeader;
    pImageBase           : Pointer;
    _pImageSectionHeader : PImageSectionHeader;
    I                    : Cardinal;
    ADelta               : UInt64;

begin
  result := nil;
  ///

  ASourcePEHeader := IdentifyPEHeader(pSourceBuffer);

  {$IFDEF WIN64}
    if (ASourcePEHeader._pImageFileHeader^.Machine <> IMAGE_FILE_MACHINE_AMD64) then
  {$ELSE}
    if (ASourcePEHeader._pImageFileHeader^.Machine <> IMAGE_FILE_MACHINE_I386) then
  {$ENDIF}
      raise Exception.Create('You must load a DLL with same architecture as current process!');
  

  // Create a memory region that will contain our Library code
  // We then patch our TPEHeader structure with new image base
  pImageBase := VirtualAlloc(nil, ASourcePEHeader._pImageOptionalHeader^.SizeOfImage, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
  if not Assigned(pImageBase) then
    Exit();

  // Write Library headers to allocated region
  CopyMemory(pImageBase, pSourceBuffer, ASourcePEHeader._pImageOptionalHeader.SizeOfHeaders);

  // Write Library sections code to allocated region
  for I := 0 to ASourcePEHeader.SectionHeaderCount -1 do begin
    _pImageSectionHeader := ASourcePEHeader.pSectionHeaders[I];

    pOffset := Pointer(NativeUInt(pImageBase) + _pImageSectionHeader^.VirtualAddress);

    // Pad new allocated region with zeros
    ZeroMemory(pOffset, _pImageSectionHeader^.Misc.VirtualSize);

    // Copy section content from buffer to freshly allocated region
    CopyMemory(
      pOffset,
      Pointer(NativeUInt(pSourceBuffer) + _pImageSectionHeader^.PointerToRawData),
      _pImageSectionHeader^.SizeOfRawData
    );
  end;

  // Calculate the distance between default library expected image base and mapped library image base
  // Used for relocation
  ADelta := NativeUInt(pImageBase) - NativeUInt(ASourcePEHeader._pImageOptionalHeader.ImageBase);

  // Point to new image header
  ADestPEHeader := IdentifyPEHeader(pImageBase);

  // Patch new image header image base value
  ADestPEHeader._pImageOptionalHeader^.ImageBase := NativeUInt(pImageBase);

  // Resolve import table, load required libraries and exported functions
  ResolveImportTable(ADestPEHeader);

  // Perform Image Base Relocation since it differs from target library PE Header expectation
  if ADelta <> 0 then
    PerformBaseRelocation(ADestPEHeader, ADelta);

  ///
  result := pImageBase;
end;

{ _.GetReflectedProcAddress }
function GetReflectedProcAddress(const pImageBase : Pointer; const AFunctionOrOrdinal : String) : Pointer;
var APEHeader            : TPEHeader;
    APEHeaderDirectories : TPEHeaderDirectories;
    I                    : Cardinal;
    pOffset              : PCardinal;
    pOrdinal             : PWord;
    pFuncAddress         : PCardinal;

    pAddrOfNameOrdinals  : Pointer;
    pAddrOfFunctions     : Pointer;
    pAddrOfNames         : Pointer;

    ACurrentName         : String;
    AOrdinalCandidate    : Integer;
    ACurrentOrdinal      : Word;
    AResolveByName       : Boolean;

begin
  result := nil;
  ///

  if not Assigned(pImageBase) then
    Exit();

  APEHeader := IdentifyPEHeader(pImageBase);
  APEHeaderDirectories := IdentifyPEHeaderDirectories(APEHeader);

  for I := 0 to APEHeaderDirectories._pImageExportDirectory^.NumberOfNames -1 do begin
    pAddrOfNameOrdinals := Pointer(NativeUInt(APEHeader.pImageBase) + APEHeaderDirectories._pImageExportDirectory^.AddressOfNameOrdinals);
    pAddrOfFunctions := Pointer(NativeUInt(APEHeader.pImageBase) + APEHeaderDirectories._pImageExportDirectory^.AddressOfFunctions);
    pAddrOfNames := Pointer(NativeUInt(APEHeader.pImageBase) + APEHeaderDirectories._pImageExportDirectory^.AddressOfNames);

    AResolveByName := False;
    if not TryStrToInt(AFunctionOrOrdinal, AOrdinalCandidate) then
      AResolveByName := True;

    if (AOrdinalCandidate < Low(Word)) or (AOrdinalCandidate > High(Word)) and not AResolveByName then
      AResolveByName := True;

    // Function Name
    pOffset := Pointer(NativeUInt(pAddrOfNames) + (I * SizeOf(Cardinal)));
    ACurrentName := String(PAnsiChar(NativeUInt(pImageBase) + pOffset^));

    // Ordinal
    ACurrentOrdinal := PWord(NativeUInt(pAddrOfNameOrdinals) + (I * SizeOf(Word)))^;

    if AResolveByName then begin
      if (String.Compare(ACurrentName, AFunctionOrOrdinal, True) <> 0) then
        continue;
    end else begin
      if (ACurrentOrdinal + APEHeaderDirectories._pImageExportDirectory^.Base) <> AOrdinalCandidate then
        continue;
    end;

    // Resolve Function Address
    pFuncAddress := PCardinal(NativeUInt(pAddrOfFunctions) + (ACurrentOrdinal * SizeOf(Cardinal)));

    result := Pointer(NativeUInt(pImageBase) + pFuncAddress^);

    break;
  end;
end;

{ _.ReflectLibraryFromFile }
function ReflectLibraryFromFile(const AFileName : String) : Pointer;
var AFileStream : TFileStream;
    pBuffer     : Pointer;
    ASize       : Int64;
begin
  result := nil;
  ///

  AFileStream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    AFileStream.Position := 0;
    ///

    ASize := AFileStream.Size;

    GetMem(pBuffer, ASize);

    AFileStream.ReadBuffer(PByte(pBuffer)^, ASize);

    result := ReflectLibraryFromMemory(pBuffer, ASize);
  finally
    if Assigned(AFileStream) then
      FreeAndNil(AFileStream);
  end;
end;

{ _.ReflectFromMemoryStream }
function ReflectFromMemoryStream(const AStream : TMemoryStream) : Pointer;
begin
  result := nil;
  ///

  if not Assigned(AStream) then
    Exit();

  if AStream.Size = 0 then
    Exit();

  result := ReflectLibraryFromMemory(AStream.Memory, AStream.Size);
end;

// Example (Update Code Accordingly)
var pReflectedModuleBase : Pointer;
    pReflectedMethod     : procedure(); stdcall;
begin
  pReflectedModuleBase := ReflectLibraryFromFile('test.dll');

  // Through Function Name
  @pReflectedMethod := GetReflectedProcAddress(pReflectedModuleBase, 'ModuleAction');
  if Assigned(pReflectedMethod) then
    pReflectedMethod();

  // Through Exported Function Ordinal
  @pReflectedMethod := GetReflectedProcAddress(pReflectedModuleBase, '3');
  if Assigned(pReflectedMethod) then
    pReflectedMethod();

end.
