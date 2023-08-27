// This example demonstrates how to use named pipes to route commands to a server and retrieve the corresponding responses.

using System.Diagnostics;
using System.IO.Pipes;
using System.Text;

class Program
{
    public enum Command
    {
        ProcessList,
        Exit,
    }

    const string pipeName = "NamedPipeExample";

    public static void Main(string[] args)
    {               
        Thread namedPipeServerThread = new(() =>
        {
            try
            {
                // https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeserverstream?view=net-7.0?WT_mc_id=SEC-MVP-5005282
                using NamedPipeServerStream serverPipe = new(pipeName, PipeDirection.InOut);

                serverPipe.WaitForConnection();

                using StreamReader reader = new(serverPipe);
                using StreamWriter writer = new(serverPipe) { AutoFlush = true };
                ///

                while (true)
                {
                    switch(Enum.Parse(typeof(Command), reader.ReadLine() ?? ""))
                    {
                        case Command.ProcessList:
                            {
                                StringBuilder sb = new();

                                foreach (Process process in Process.GetProcesses())                                
                                    sb.AppendLine($"({process.Id.ToString().PadRight(5, ' ')}){process.ProcessName}");
                                
                                // Encode as Base64 to send to whole list in one single `WriteLine`
                                writer.WriteLine(Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(sb.ToString())));

                                break;
                            }
                        default:
                            {
                                // Exit or unknown or empty string.
                                break;
                            }
                    }
                }
            }
            catch { }
        });
        namedPipeServerThread.Start();

        Thread namedPipeClientThread = new(() =>
        {
            try
            {
                // `.` means local machine, it can be replaced by the network computer name hosting a the named pipe server.
                // https://learn.microsoft.com/en-us/dotnet/api/system.io.pipes.namedpipeclientstream?view=net-7.0?WT_mc_id=SEC-MVP-5005282
                using NamedPipeClientStream clientPipe = new(".", pipeName, PipeDirection.InOut);

                clientPipe.Connect();

                using StreamReader reader = new(clientPipe);
                using StreamWriter writer = new(clientPipe) { AutoFlush = true };
                ///

                // Ask server for running process
                writer.WriteLine(Command.ProcessList);

                // Receive response
                string? response = reader.ReadLine();  
                if (response != null)
                    Console.WriteLine(System.Text.Encoding.UTF8.GetString(Convert.FromBase64String(response)));                

                // Tell server, we finished our job
                writer.WriteLine(Command.Exit);
            }
            catch { }
        });
        namedPipeClientThread.Start();

        ///
        namedPipeServerThread.Join();
        namedPipeClientThread.Join();        
    }
}