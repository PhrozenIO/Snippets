using System.Net.NetworkInformation;

/*
String[] vmMacAddresses =
{
    "08:00:27",
    "00:0C:29",
    "00:1C:14",
    "00:50:56",
    "00:05:69",
};
*/

var vmMacAddresses = new Dictionary<string, string>();

vmMacAddresses.Add("08:00:27", "VirtualBox");
vmMacAddresses.Add("00:0C:29", "VMWare");
vmMacAddresses.Add("00:1C:14", "VMWare");
vmMacAddresses.Add("00:50:56", "VMWare");
vmMacAddresses.Add("00:05:69", "VMWare");
// Add other ones bellow...

foreach (NetworkInterface netInterface in NetworkInterface.GetAllNetworkInterfaces())
{
    PhysicalAddress physicalAddress = netInterface.GetPhysicalAddress();
    if (physicalAddress == null)
    {
        continue;
    }

    String mac = String.Join(":", (from b in physicalAddress.GetAddressBytes().Take(3) select b.ToString("X2")));

    if (vmMacAddresses.ContainsKey(mac))
    {
        throw new Exception(
            String.Format("{0} Detected from its MAC Address.", vmMacAddresses.GetValueOrDefault(mac))            
        );
    }

    Console.WriteLine("No VM Detected :)");
}