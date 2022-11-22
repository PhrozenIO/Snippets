using System;
using System.IO;

void timeStomp(String targetFile)
{
    targetFile = Path.GetFullPath(targetFile);

    if (!File.Exists(targetFile))
    {
        throw new FileNotFoundException(String.Format("File \"{0}\" does not exists.", targetFile));
    }

    string? parentDirectory = Path.GetDirectoryName(targetFile);
    bool isInRoot = false;

    if (parentDirectory == null)
    {
        parentDirectory = Directory.GetDirectoryRoot(targetFile);
        isInRoot = true;
    }

    var options = new EnumerationOptions()
    {
        IgnoreInaccessible = true,
        RecurseSubdirectories = true,
        AttributesToSkip = FileAttributes.System | FileAttributes.Hidden,
    };

    var candidates = new DirectoryInfo(parentDirectory)
        .GetFiles("*.*", options)
        .Where(file => !file.FullName.Equals(targetFile, StringComparison.OrdinalIgnoreCase))
        .OrderByDescending(file => file.LastWriteTime)
        .ToList();

    FileInfo? candidate = null;    
    
    if (candidates.Count > 0)
    {
        candidate = candidates.First();
    }   
    else if (!isInRoot)
    {
        candidate = new FileInfo(parentDirectory);
    }

    if (candidate != null)
    {
        Console.WriteLine(string.Format("Using \"{0}\" file for timeStomping...", candidate));

        File.SetCreationTime(targetFile, candidate.CreationTime);
        File.SetLastAccessTime(targetFile, candidate.LastAccessTime);
        File.SetLastWriteTime(targetFile, candidate.LastWriteTime);

        Console.WriteLine("Done.");
    }
    else
    {
       throw new Exception("Could not find suitable existing file for timeStomping...");
    }
}

timeStomp("G:\\test\\sub7.exe");