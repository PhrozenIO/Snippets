// Jean-Pierre LESUEUR (@DarkCoderSc)
// https://keybase.io/phrozen

using System;
using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Threading;


[DllImport("Shell32.dll", CharSet = CharSet.Auto, SetLastError = true)]
static extern IntPtr ShellExecute(IntPtr hwnd, string lpOperation, string lpFile, string lpParameters, string lpDirectory, int nShowCmd);

string PIPE_NAME = "DarkCoderScPipe";

static IEnumerable<string> ExtensionGenerator(int max_length)
{
    string charList = "abcdefghijklmnopqrstuvwxyz0123456789";

    if (max_length > 1)
    {        
        foreach (string candidate in ExtensionGenerator(max_length -1))
        {           
            foreach (char c in charList)
            {                
                yield return candidate + c;
            }
        }
    }
    else
    {
        foreach (char c in charList)
        {
            yield return c.ToString();
        }
    }
}

string GetCurrentImagePath()
{
    return Process.GetCurrentProcess()?.MainModule?.FileName ?? "";
}

void SendClientPipeMessage(string message = "")
{
    NamedPipeClientStream client = new NamedPipeClientStream("localhost", PIPE_NAME, PipeDirection.InOut, PipeOptions.None);

    client.Connect(100);
    try
    {
        StreamWriter writer = new StreamWriter(client);

        writer.WriteLine(message);

        writer.Flush();
    }
    finally
    {
        client.Close();
    }
}

// __entry__
string currentImage = GetCurrentImagePath();

if (Path.GetExtension(currentImage).ToLower() != ".exe")
{
    SendClientPipeMessage(currentImage);
}
else
{
    Console.WriteLine("Checking...");
    ///

    if (!String.IsNullOrEmpty(currentImage))
    {
        // Check routine
        Thread checkThread = new Thread(() =>
        {
            try
            {
                using (NamedPipeServerStream server = new NamedPipeServerStream(PIPE_NAME, PipeDirection.InOut))
                {
                    while (true)
                    {
                        server.WaitForConnection();

                        StreamReader reader = new StreamReader(server);

                        string message = reader.ReadLine() ?? "";

                        Thread.Sleep(1); // To signal "ThreadInterruptedException", dirty but it works

                        if (!String.IsNullOrEmpty(message))
                        {
                            Console.Write("Executable Extension Found: \"");

                            Console.ForegroundColor = ConsoleColor.Green;

                            Console.Write(Path.GetExtension(message));

                            Console.ResetColor();

                            Console.WriteLine("\".");
                        }

                        server.Disconnect();
                    }
                }
            }
            catch (ThreadInterruptedException)
            {}
        });

        checkThread.Start();

        // Bruteforce
        foreach (string extension in ExtensionGenerator(3)) 
        {
            string newImageExtension = Path.ChangeExtension(currentImage, extension);

            try
            {
                File.Copy(currentImage, newImageExtension, true);
            }
            catch(IOException)
            {
                continue;
            }

            try
            {
                ShellExecute(IntPtr.Zero, "open", newImageExtension, "", "", 0);                
            }
            finally
            {
                while (Process.GetProcessesByName(Path.GetFileName(newImageExtension)).Length > 0)
                {
                    Thread.Sleep(1);
                }
                
                ///
                File.Delete(newImageExtension);                                
            }
        }

        Thread.Sleep(5000);

        SendClientPipeMessage();

        checkThread.Interrupt();

        checkThread.Join();

        Console.WriteLine("Done.");
    }
}