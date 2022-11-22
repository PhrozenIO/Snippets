program ADB_NtSetInformationThread;

{$APPTYPE CONSOLE}

uses
  WinAPI.Windows, System.SysUtils;

type
  // ntddk.h
  TThreadInfoClass = (
                        ThreadBasicInformation,
                        ThreadTimes,
                        ThreadPriority,
                        ThreadBasePriority,
                        ThreadAffinityMask,
                        ThreadImpersonationToken,
                        ThreadDescriptorTableEntry,
                        ThreadEnableAlignmentFaultFixup,
                        ThreadEventPair_Reusable,
                        ThreadQuerySetWin32StartAddress,
                        ThreadZeroTlsCell,
                        ThreadPerformanceCount,
                        ThreadAmILastThread,
                        ThreadIdealProcessor,
                        ThreadPriorityBoost,
                        ThreadSetTlsArrayAddress,
                        ThreadIsIoPending,
                        ThreadHideFromDebugger, {<--}
                        ThreadBreakOnTermination,
                        ThreadSwitchLegacyState,
                        ThreadIsTerminated,
                        ThreadLastSystemCall,
                        ThreadIoPriority,
                        ThreadCycleTime,
                        ThreadPagePriority,
                        ThreadActualBasePriority,
                        ThreadTebInformation,
                        ThreadCSwitchMon,
                        ThreadCSwitchPmu,
                        ThreadWow64Context,
                        ThreadGroupInformation,
                        ThreadUmsInformation,
                        ThreadCounterProfiling,
                        ThreadIdealProcessorEx,
                        ThreadCpuAccountingInformation,
                        ThreadSuspendCount,
                        ThreadActualGroupAffinity,
                        ThreadDynamicCodePolicyInfo,
                        MaxThreadInfoClass
  );

  var hNtDll    : THandle;
      AThread   : THandle;
      AThreadId : Cardinal;

      NtSetInformationThread : function(
                                          ThreadHandle : THandle;
                                          ThreadInformationClass : TThreadInfoClass;
                                          ThreadInformation : PVOID;
                                          ThreadInformationLength : ULONG
                                      ) : NTSTATUS; stdcall;

  const
    STATUS_SUCCESS = $00000000;

{-------------------------------------------------------------------------------
  Hide Thread From Debugger
-------------------------------------------------------------------------------}
function HideThread(AThreadHandle : THandle) : Boolean;
var AThreadInformation : ULONG;
    AStatus            : NTSTATUS;
begin
  result := False;
  ///

  if not assigned(NtSetInformationThread) then
    Exit();



  // https://docs.microsoft.com/en-us/windows-hardware/drivers/ddi/ntifs/nf-ntifs-ntsetinformationthread
  AStatus := NtSetInformationThread(AThreadHandle, ThreadHideFromDebugger, nil, 0);

  case AStatus of
    {
      STATUS_INFO_LENGTH_MISMATCH
    }
    NTSTATUS($C0000004) : begin
      WriteLn('Error: Status Info Length Mismatch.');
    end;

    {
      STATUS_INVALID_PARAMETER
    }
    NTSTATUS($C000000D) : begin
      WriteLn('Error: Invalid Parameter.');
    end;

    {
      STATUS_SUCCESS
    }
    NTSTATUS($00000000) : begin
      WriteLn(Format('Thread: %d is now successfully hidden from debuggers.', [AThreadHandle]));

      result := True;
    end;

    {
      Other Errors
    }
    else begin
      WriteLn('Error: Unknown.');
    end;
  end;
end;

{-------------------------------------------------------------------------------
  ___thread:example
-------------------------------------------------------------------------------}
procedure ThreadExample(pParam : PVOID); stdcall;
begin
  WriteLn('Example Thread Begin.');


  {
    If we are attached to a debugger, we trigger a new breakpoint.

    If thread is set with hidden from debugger, process should crash.
  }
  if IsDebuggerPresent() then begin
    asm
      int 3
    end;
  end;

  WriteLn('Example Thread Ends.');

  ///
  ExitThread(0);
end;

{-------------------------------------------------------------------------------
  ___entry
-------------------------------------------------------------------------------}
begin
  try
    hNtDll := LoadLibrary('NTDLL.DLL');
    if (hNtDll = 0) then
      Exit();
    try
      @NtSetInformationThread := GetProcAddress(hNtDll, 'NtSetInformationThread');
      if NOT Assigned(NtSetInformationThread) then
        Exit();

      {
        Create an example thread
      }
      SetLastError(0);

      AThread := CreateThread(nil, 0, @ThreadExample, nil, CREATE_SUSPENDED, AThreadId);
      if (AThread <> 0) then begin
        WriteLn(Format('Example thread created. Thread Handle: %d , Thread Id: %d', [AThread, AThreadid]));

        HideThread(AThread);

        ///
        ResumeThread(AThread);

        WaitForSingleObject(AThread, INFINITE);
      end else begin
        WriteLn(Format('Could not create example thread with error: .', [GetLastError()]));
      end;
    finally
      FreeLibrary(hNtDll);
    end;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.