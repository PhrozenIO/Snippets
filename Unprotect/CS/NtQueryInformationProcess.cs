using System;
using System.Runtime.InteropServices;

[DllImport("ntdll.dll", SetLastError = true)]
static extern int NtQueryInformationProcess(
    IntPtr processHandle,
    int processInformationClass,
    ref IntPtr processInformation,
    uint processInformationLength,
    ref IntPtr returnLength
);

[DllImport("kernel32.dll", SetLastError = true)]
static extern IntPtr GetCurrentProcess();

bool isBeingDebugged()
{
    var ERROR_SUCCESS = 0x0;
    var ProcessDebugPort = 0x7;

    IntPtr currProcessHandle = GetCurrentProcess();
    if (currProcessHandle == IntPtr.Zero)
    {
        throw new Exception("Could not retrieve current process handle.");
    }

    IntPtr returnLength = IntPtr.Zero;
    IntPtr portNumber = IntPtr.Zero;

    int ntStatus = NtQueryInformationProcess(currProcessHandle, ProcessDebugPort, ref portNumber, (uint)IntPtr.Size, ref returnLength);        
    if (ntStatus != ERROR_SUCCESS)
    {
        throw new Exception("Could not query information process.");
    }

    return (portNumber != IntPtr.Zero);
}

if (isBeingDebugged())
{
    throw new Exception("Debugger Detected !");
}

Console.WriteLine("No Debugger Detected :)");