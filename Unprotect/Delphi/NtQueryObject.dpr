program NtQueryObject;

{$APPTYPE CONSOLE}

{$ALIGN ON}
{$MINENUMSIZE 4}

uses
  WinAPI.Windows, System.SysUtils;

type
  TUnicodeString = record
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PWideChar;
  end;

  TObjectInformationClass = (
                                    ObjectBasicInformation    = 0,
                                    ObjectNameInformation     = 1,
                                    ObjectTypeInformation     = 2,
                                    ObjectAllTypesInformation = 3,
                                    ObjectHandleInformation   = 4
  );

  OBJECT_TYPE_INFORMATION = record
    Name: TUnicodeString;
    ObjectCount: ULONG;
    HandleCount: ULONG;
    Reserved1: array[0..3] of ULONG;
    PeakObjectCount: ULONG;
    PeakHandleCount: ULONG;
    Reserved2: array[0..3] of ULONG;
    InvalidAttributes: ULONG;
    GenericMapping: GENERIC_MAPPING;
    ValidAccess: ULONG;
    Unknown: UCHAR;
    MaintainHandleDatabase: ByteBool;
    Reserved3: array[0..1] of UCHAR;
    PoolType: Byte;
    PagedPoolUsage: ULONG;
    NonPagedPoolUsage: ULONG;
  end;
  POBJECT_TYPE_INFORMATION = ^OBJECT_TYPE_INFORMATION;
  TObjectTypeInformation = OBJECT_TYPE_INFORMATION;
  PObjectTypeInformation = ^TObjectTypeInformation;

  OBJECT_ALL_TYPE_INFORMATION = record
    NumberOfObjectTypes : ULONG;
    ObjectTypeInformation : array[0..0] of TObjectTypeInformation;
  end;
  POBJECT_ALL_TYPE_INFORMATION = ^OBJECT_ALL_TYPE_INFORMATION;
  TObjectAllTypeInformation = OBJECT_ALL_TYPE_INFORMATION;
  PObjectAllTypeInformation = ^TObjectAllTypeInformation;

// https://docs.microsoft.com/en-us/windows/win32/api/winternl/nf-winternl-ntqueryobject
var
  _NtQueryObject : function (
                                ObjectHandle : THandle;
                                ObjectInformationClass : TObjectInformationClass;
                                ObjectInformation : PVOID;
                                ObjectInformationLength : ULONG;
                                ReturnLength : PULONG
                              ): ULONG; stdcall;
var hNTDLL              : THandle;
    ARet                : ULONG;
    ARequiredSize       : ULONG;
    pAllTypeInformation : PObjectAllTypeInformation;
    pTypeInformation    : PObjectTypeInformation;
    i                   : Integer;
    pRow                : PObjectTypeInformation;
    pDummy              : Pointer;
    ADebuggerFound      : Boolean;

begin
  try
    ADebuggerFound := False;

    @_NtQueryObject := nil;
    ///

    hNTDLL := LoadLibrary('NTDLL.DLL');
    if (hNTDLL = 0) then
      Exit();
    try
      @_NtQueryObject := GetProcAddress(hNTDLL, 'NtQueryObject');
      if NOT Assigned(_NtQueryObject) then
        Exit();
      ///

      ARet := _NtQueryObject(0, ObjectAllTypesInformation, @ARequiredSize, SizeOf(ULONG), @ARequiredSize);
      if (ARequiredSize <= 0) then
        Exit();
      ///

      GetMem(pAllTypeInformation, ARequiredSize);
      try
        ARet := _NtQueryObject(0, ObjectAllTypesInformation, pAllTypeInformation, ARequiredSize, nil);
        if (ARet <> 0) then
          Exit();
        ///

        pRow := @pAllTypeInformation^.ObjectTypeInformation;

        for I := 0 to pAllTypeInformation^.NumberOfObjectTypes -1 do begin
            if String.Compare(String(pRow^.Name.Buffer), 'DebugObject', True) = 0 then
              ADebuggerFound := (pRow^.ObjectCount > 0);
            ///

            if ADebuggerFound then
              break;

            pRow := Pointer (
              (NativeUInt(pRow^.Name.Buffer) + pRow^.Name.Length) and (NOT (SizeOf(Pointer)-1)) + SizeOf(Pointer)
            );
        end;
      finally
        FreeMem(pAllTypeInformation, ARequiredSize);
      end;
    finally
      FreeLibrary(hNTDLL);
    end;

    if ADebuggerFound then
      WriteLn('A Debugger Was Found!')
    else
      WriteLn('No Debugger Found!');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.