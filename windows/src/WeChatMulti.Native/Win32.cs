using System.Runtime.InteropServices;

namespace WeChatMulti.Native;

/// <summary>
/// Raw P/Invoke surface for the NT/Win32 calls used to enumerate handles and
/// close the WeChat instance mutex (Appendix B of the Windows port plan).
/// Kept thin and internal — selection logic lives in the tested Core.
/// </summary>
internal static class Win32
{
    // ntdll
    [DllImport("ntdll.dll")]
    internal static extern int NtQuerySystemInformation(
        int systemInformationClass, IntPtr systemInformation, int length, out int returnLength);

    [DllImport("ntdll.dll")]
    internal static extern int NtQueryObject(
        IntPtr handle, int objectInformationClass, IntPtr objectInformation, int length, out int returnLength);

    // kernel32
    [DllImport("kernel32.dll", SetLastError = true)]
    internal static extern IntPtr OpenProcess(uint desiredAccess, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DuplicateHandle(
        IntPtr hSourceProcess, IntPtr hSourceHandle, IntPtr hTargetProcess,
        out IntPtr lpTargetHandle, uint dwDesiredAccess,
        [MarshalAs(UnmanagedType.Bool)] bool bInheritHandle, uint dwOptions);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool CloseHandle(IntPtr hObject);

    // Constants
    internal const int SystemExtendedHandleInformation = 0x40;
    internal const int ObjectNameInformation = 1;
    internal const int ObjectTypeInformation = 2;

    internal const int STATUS_INFO_LENGTH_MISMATCH = unchecked((int)0xC0000004);

    internal const uint PROCESS_DUP_HANDLE = 0x0040;
    internal const uint DUPLICATE_CLOSE_SOURCE = 0x1;
    internal const uint DUPLICATE_SAME_ACCESS = 0x2;

    internal const int ERROR_ACCESS_DENIED = 5;

    // Access mask that makes NtQueryObject(Name) hang on some handle types;
    // skip these during enumeration (well-known gotcha).
    internal const uint GENERIC_PIPE_HANG_MASK = 0x0012019F;

    [StructLayout(LayoutKind.Sequential)]
    internal struct SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX
    {
        public IntPtr Object;
        public IntPtr UniqueProcessId;
        public IntPtr HandleValue;
        public uint GrantedAccess;
        public ushort CreatorBackTraceIndex;
        public ushort ObjectTypeIndex;
        public uint HandleAttributes;
        public uint Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct UNICODE_STRING
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }
}
