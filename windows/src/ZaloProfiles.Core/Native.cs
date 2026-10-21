using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace ZaloProfiles.Core;

/// <summary>The Windows calls the core needs and .NET doesn't offer.</summary>
internal static unsafe partial class Native
{
    // MARK: Renaming

    const uint MOVEFILE_WRITE_THROUGH = 0x8;
    public const int ERROR_FILE_NOT_FOUND = 2;
    public const int ERROR_PATH_NOT_FOUND = 3;
    public const int ERROR_ACCESS_DENIED = 5;
    public const int ERROR_NOT_SAME_DEVICE = 17;
    public const int ERROR_SHARING_VIOLATION = 32;
    public const int ERROR_FILE_EXISTS = 80;
    public const int ERROR_ALREADY_EXISTS = 183;

    [LibraryImport("kernel32.dll", EntryPoint = "MoveFileExW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool MoveFileEx(string existing, string newName, uint flags);

    /// <summary>Renames without MOVEFILE_REPLACE_EXISTING and without MOVEFILE_COPY_ALLOWED, so it
    /// fails rather than replace what is at the destination or copy to another drive. Returns 0 or the
    /// Windows error code.</summary>
    public static int RenameExclusive(string from, string to) =>
        MoveFileEx(from, to, MOVEFILE_WRITE_THROUGH) ? 0 : Marshal.GetLastPInvokeError();

    public static string Describe(int error) => new Win32Exception(error).Message;

    // MARK: Hard links

    [LibraryImport("kernel32.dll", EntryPoint = "CreateHardLinkW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CreateHardLinkW(string newLink, string existing, IntPtr security);

    public static bool CreateHardLink(string newLink, string existing) => CreateHardLinkW(newLink, existing, IntPtr.Zero);

    [StructLayout(LayoutKind.Sequential)]
    struct BY_HANDLE_FILE_INFORMATION
    {
        public uint FileAttributes;
        public long CreationTime, LastAccessTime, LastWriteTime;
        public uint VolumeSerialNumber, FileSizeHigh, FileSizeLow, NumberOfLinks, FileIndexHigh, FileIndexLow;
    }

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetFileInformationByHandle(SafeFileHandle file, out BY_HANDLE_FILE_INFORMATION info);

    /// <summary>For a file with more than one name: "volume-index", the same for every name of it.</summary>
    public static string? HardLinkGroup(string path)
    {
        try
        {
            using var handle = File.OpenHandle(path, FileMode.Open, FileAccess.Read,
                                               FileShare.ReadWrite | FileShare.Delete);
            if (!GetFileInformationByHandle(handle, out var info) || info.NumberOfLinks < 2) return null;
            return $"{info.VolumeSerialNumber:x}-{((ulong)info.FileIndexHigh << 32) | info.FileIndexLow:x}";
        }
        catch { return null; }
    }

    // MARK: Disks

    [LibraryImport("kernel32.dll", EntryPoint = "GetDiskFreeSpaceExW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetDiskFreeSpaceEx(string directory, out ulong freeToCaller, out ulong total, out ulong totalFree);

    public static long? FreeBytes(string existingDirectory) =>
        GetDiskFreeSpaceEx(existingDirectory, out var free, out _, out _) ? (long)free : null;

    [LibraryImport("kernel32.dll", EntryPoint = "GetVolumePathNameW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetVolumePathName(string path, char* buffer, uint length);

    [LibraryImport("kernel32.dll", EntryPoint = "GetVolumeNameForVolumeMountPointW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetVolumeNameForVolumeMountPoint(string mountPoint, char* buffer, uint length);

    /// <summary>The volume's GUID path (\\?\Volume{…}\), the same for every path on one drive.</summary>
    public static string? VolumeId(string existingPath)
    {
        var mount = stackalloc char[1024];
        if (!GetVolumePathName(existingPath, mount, 1024)) return null;
        var mountPoint = new string(mount);
        var name = stackalloc char[1024];
        return GetVolumeNameForVolumeMountPoint(mountPoint, name, 1024) ? new string(name) : mountPoint.ToUpperInvariant();
    }

    // MARK: Known folders

    [LibraryImport("shell32.dll")]
    private static partial int SHGetKnownFolderPath(in Guid id, uint flags, IntPtr token, out IntPtr path);

    public static readonly Guid FolderProfile = new("5E6C858F-0E22-4760-9AFE-EA3317B67173");
    public static readonly Guid FolderRoamingAppData = new("3EB685DB-65F9-4CF6-A03A-E3EF65729F3D");
    public static readonly Guid FolderLocalAppData = new("F1B32785-6FBA-4FCF-9D55-7B8E7F157091");
    public static readonly Guid FolderDesktop = new("B4BFCC3A-DB2C-424C-B029-7FE99A87C641");
    public static readonly Guid FolderDocuments = new("FDD39AD0-238F-46AF-ADB4-6C85480369C7");
    public static readonly Guid FolderDownloads = new("374DE290-123F-4565-9164-39C4925E467B");
    public static readonly Guid FolderMusic = new("4BD8D571-6D19-48D3-BE97-422220080E43");
    public static readonly Guid FolderPictures = new("33E28130-4E1E-4676-835A-98395C3BC3BB");
    public static readonly Guid FolderVideos = new("18989B1D-99B5-455B-841C-AB7C74E4DDFC");

    public static string? KnownFolder(Guid id)
    {
        if (SHGetKnownFolderPath(id, 0, IntPtr.Zero, out var path) != 0) return null;
        try { return Marshal.PtrToStringUni(path); }
        finally { Marshal.FreeCoTaskMem(path); }
    }

    // MARK: Processes

    const uint TH32CS_SNAPPROCESS = 0x2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct PROCESSENTRY32W
    {
        public uint dwSize, cntUsage, th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID, cntThreads, th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool Process32FirstW(IntPtr snapshot, ref PROCESSENTRY32W entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool Process32NextW(IntPtr snapshot, ref PROCESSENTRY32W entry);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseHandle(IntPtr handle);

    /// <summary>Every running process: pid, parent pid and executable name.</summary>
    public static List<(int Pid, int ParentPid, string Name)> ListProcesses()
    {
        var result = new List<(int, int, string)>();
        var snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snapshot == new IntPtr(-1)) return result;
        try
        {
            var entry = new PROCESSENTRY32W { dwSize = (uint)Marshal.SizeOf<PROCESSENTRY32W>() };
            if (!Process32FirstW(snapshot, ref entry)) return result;
            do { result.Add(((int)entry.th32ProcessID, (int)entry.th32ParentProcessID, entry.szExeFile)); }
            while (Process32NextW(snapshot, ref entry));
        }
        finally { CloseHandle(snapshot); }
        return result;
    }

    const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const uint STILL_ACTIVE = 259;

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial IntPtr OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, uint pid);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetExitCodeProcess(IntPtr process, out uint code);

    [LibraryImport("kernel32.dll", EntryPoint = "QueryFullProcessImageNameW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool QueryFullProcessImageName(IntPtr process, uint flags, char* name, ref uint size);

    [LibraryImport("ntdll.dll")]
    private static partial int NtQueryInformationProcess(IntPtr process, int infoClass, void* info, uint length, out uint returned);

    public static bool IsAlive(int pid)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (handle == IntPtr.Zero) return Marshal.GetLastPInvokeError() == ERROR_ACCESS_DENIED;
        try { return GetExitCodeProcess(handle, out var code) && code == STILL_ACTIVE; }
        finally { CloseHandle(handle); }
    }

    public static string? ImagePath(int pid)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (handle == IntPtr.Zero) return null;
        try
        {
            var buffer = stackalloc char[2048];
            uint size = 2048;
            return QueryFullProcessImageName(handle, 0, buffer, ref size) ? new string(buffer, 0, (int)size) : null;
        }
        finally { CloseHandle(handle); }
    }

    /// <summary>A process's command line (ProcessCommandLineInformation, Windows 8.1 and later).</summary>
    public static string? CommandLine(int pid)
    {
        var handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, (uint)pid);
        if (handle == IntPtr.Zero) return null;
        try
        {
            uint length = 4096;
            for (var attempt = 0; attempt < 3; attempt++)
            {
                var buffer = new byte[length];
                fixed (byte* p = buffer)
                {
                    var status = NtQueryInformationProcess(handle, 60, p, length, out var needed);
                    if (status == 0)
                    {
                        // A UNICODE_STRING whose text follows it in the same buffer.
                        var bytes = *(ushort*)p;
                        var text = *(IntPtr*)(p + IntPtr.Size);
                        return bytes == 0 ? "" : new string((char*)text, 0, bytes / 2);
                    }
                    if (needed <= length) return null;
                    length = needed;
                }
            }
            return null;
        }
        finally { CloseHandle(handle); }
    }

    // MARK: Junctions

    const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
    const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
    const uint FSCTL_SET_REPARSE_POINT = 0x000900A4;
    const uint IO_REPARSE_TAG_MOUNT_POINT = 0xA0000003;

    [LibraryImport("kernel32.dll", EntryPoint = "CreateFileW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    private static partial SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool DeviceIoControl(SafeFileHandle device, uint code, void* input, uint inputSize, void* output, uint outputSize, out uint returned, IntPtr overlapped);

    /// <summary>Creates a directory junction at <paramref name="link"/> pointing to <paramref name="target"/>.
    /// Unlike a symbolic link, a junction needs no administrator rights.</summary>
    public static void CreateJunction(string link, string target)
    {
        Directory.CreateDirectory(link);
        try
        {
            var substitute = @"\??\" + Path.GetFullPath(target).TrimEnd('\\');
            var print = Path.GetFullPath(target).TrimEnd('\\');
            var substituteBytes = Encoding.Unicode.GetBytes(substitute);
            var printBytes = Encoding.Unicode.GetBytes(print);
            // MOUNT_POINT_REPARSE_BUFFER: 4 offsets/lengths, then both names, each NUL-terminated.
            var pathBuffer = substituteBytes.Length + 2 + printBytes.Length + 2;
            var dataLength = 8 + pathBuffer;
            var buffer = new byte[8 + dataLength];
            BitConverter.GetBytes(IO_REPARSE_TAG_MOUNT_POINT).CopyTo(buffer, 0);
            BitConverter.GetBytes((ushort)dataLength).CopyTo(buffer, 4);
            BitConverter.GetBytes((ushort)0).CopyTo(buffer, 8);
            BitConverter.GetBytes((ushort)substituteBytes.Length).CopyTo(buffer, 10);
            BitConverter.GetBytes((ushort)(substituteBytes.Length + 2)).CopyTo(buffer, 12);
            BitConverter.GetBytes((ushort)printBytes.Length).CopyTo(buffer, 14);
            substituteBytes.CopyTo(buffer, 16);
            printBytes.CopyTo(buffer, 16 + substituteBytes.Length + 2);

            using var handle = CreateFile(link, 0x40000000 /* GENERIC_WRITE */, 0, IntPtr.Zero, 3 /* OPEN_EXISTING */,
                                          FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT, IntPtr.Zero);
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastPInvokeError());
            fixed (byte* p = buffer)
            {
                if (!DeviceIoControl(handle, FSCTL_SET_REPARSE_POINT, p, (uint)buffer.Length, null, 0, out _, IntPtr.Zero))
                    throw new Win32Exception(Marshal.GetLastPInvokeError());
            }
        }
        catch
        {
            try { Directory.Delete(link); } catch { }
            throw;
        }
    }

    // MARK: Recycle Bin

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct SHFILEOPSTRUCTW
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SHFileOperationW(ref SHFILEOPSTRUCTW op);

    const uint FO_DELETE = 3;
    const ushort FOF_NOCONFIRMATION = 0x10;
    const ushort FOF_ALLOWUNDO = 0x40;
    const ushort FOF_NOERRORUI = 0x400;
    const ushort FOF_WANTNUKEWARNING = 0x4000;

    /// <summary>Moves a folder to the Recycle Bin. If it can't be recycled (too big, or the bin is off),
    /// Windows asks before deleting it for good, and the person can say no.</summary>
    public static bool MoveToRecycleBin(string path)
    {
        var op = new SHFILEOPSTRUCTW
        {
            wFunc = FO_DELETE,
            pFrom = Path.GetFullPath(path) + "\0\0",
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_WANTNUKEWARNING | FOF_NOERRORUI,
        };
        // The shell may show that question, so it runs on a thread of its own that can host a window.
        var ok = false;
        var thread = new Thread(() => ok = SHFileOperationW(ref op) == 0 && !op.fAnyOperationsAborted);
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        return ok;
    }
}
