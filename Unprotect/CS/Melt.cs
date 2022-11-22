using System;
using System.Diagnostics;

ProcessStartInfo processInfo = new ProcessStartInfo();

processInfo.CreateNoWindow = true;
processInfo.FileName = "cmd.exe";
processInfo.Arguments = String.Format(
    "/c for /l %i in (0) do ( timeout 1 && del \"{0}\" && IF NOT EXIST \"{0}\" (exit /b))",
    System.Diagnostics.Process.GetCurrentProcess().MainModule.FileName
);
Process.Start(processInfo);