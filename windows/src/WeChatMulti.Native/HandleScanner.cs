using System.Runtime.InteropServices;
using WeChatMulti.Core;

namespace WeChatMulti.Native;

/// <summary>
/// Implements <see cref="IHandleScanner"/> and <see cref="IMutexCloser"/> via
/// the NT handle-table APIs. Enumerates mutant handles owned by the WeChat
/// processes, resolves their names (on a worker thread with a timeout to dodge
/// the NtQueryObject hang), filters via the tested <see cref="MutexNameRegistry"/>,
/// and closes the matches with DUPLICATE_CLOSE_SOURCE.
///
/// All *decisions* (which names match, what to do on access-denied) live in
/// Core; this class only performs the syscalls.
/// </summary>
public sealed class HandleScanner : IHandleScanner, IMutexCloser
{
    public IReadOnlyList<MutexHandle> FindInstanceMutexHandles(IReadOnlyList<int> pids, WeChatBrand brand)
    {
        var pidSet = new HashSet<int>(pids);
        var results = new List<MutexHandle>();
        var self = System.Diagnostics.Process.GetCurrentProcess().Handle;

        foreach (var entry in EnumerateHandles())
        {
            var ownerPid = (int)entry.UniqueProcessId;
            if (!pidSet.Contains(ownerPid)) continue;
            if (entry.GrantedAccess == Win32.GENERIC_PIPE_HANG_MASK) continue;

            var proc = Win32.OpenProcess(Win32.PROCESS_DUP_HANDLE, false, ownerPid);
            if (proc == IntPtr.Zero) continue;
            try
            {
                if (!Win32.DuplicateHandle(proc, entry.HandleValue, self, out var dup,
                                           0, false, Win32.DUPLICATE_SAME_ACCESS))
                    continue;
                try
                {
                    if (GetObjectType(dup) != "Mutant") continue;
                    var name = GetObjectNameWithTimeout(dup);
                    if (name is null) continue;
                    if (MutexNameRegistry.Matches(name, brand))
                        results.Add(new MutexHandle(ownerPid, (ulong)entry.HandleValue.ToInt64(), name));
                }
                finally { Win32.CloseHandle(dup); }
            }
            finally { Win32.CloseHandle(proc); }
        }

        return results;
    }

    public CloseResult CloseInTarget(MutexHandle handle)
    {
        var proc = Win32.OpenProcess(Win32.PROCESS_DUP_HANDLE, false, handle.Pid);
        if (proc == IntPtr.Zero)
        {
            var err = Marshal.GetLastWin32Error();
            return new CloseResult(handle,
                err == Win32.ERROR_ACCESS_DENIED ? CloseOutcome.AccessDenied : CloseOutcome.Failed);
        }
        try
        {
            var src = new IntPtr((long)handle.HandleValue);
            var self = System.Diagnostics.Process.GetCurrentProcess().Handle;
            if (Win32.DuplicateHandle(proc, src, self, out var dup, 0, false, Win32.DUPLICATE_CLOSE_SOURCE))
            {
                Win32.CloseHandle(dup);   // also closes our duplicate → refcount drops
                return new CloseResult(handle, CloseOutcome.Closed);
            }
            var err = Marshal.GetLastWin32Error();
            return new CloseResult(handle,
                err == Win32.ERROR_ACCESS_DENIED ? CloseOutcome.AccessDenied : CloseOutcome.Failed);
        }
        finally { Win32.CloseHandle(proc); }
    }

    // --- NT enumeration helpers ---------------------------------------------

    private static IEnumerable<Win32.SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX> EnumerateHandles()
    {
        var length = 0x10000;
        IntPtr buffer = Marshal.AllocHGlobal(length);
        try
        {
            int status, returnLength;
            while ((status = Win32.NtQuerySystemInformation(
                       Win32.SystemExtendedHandleInformation, buffer, length, out returnLength))
                   == Win32.STATUS_INFO_LENGTH_MISMATCH)
            {
                Marshal.FreeHGlobal(buffer);
                length = Math.Max(returnLength, length * 2);
                buffer = Marshal.AllocHGlobal(length);
            }
            if (status != 0) yield break;

            // SYSTEM_HANDLE_INFORMATION_EX: { ULONG_PTR Count; ULONG_PTR Reserved; entries[] }
            var count = Marshal.ReadIntPtr(buffer).ToInt64();
            var entrySize = Marshal.SizeOf<Win32.SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX>();
            var cursor = buffer + IntPtr.Size * 2;
            for (long i = 0; i < count; i++)
            {
                yield return Marshal.PtrToStructure<Win32.SYSTEM_HANDLE_TABLE_ENTRY_INFO_EX>(cursor);
                cursor += entrySize;
            }
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    private static string? GetObjectType(IntPtr handle) =>
        QueryUnicodeString(handle, Win32.ObjectTypeInformation);

    private static string? GetObjectNameWithTimeout(IntPtr handle)
    {
        // NtQueryObject(Name) can hang on certain handles; run with a timeout.
        string? name = null;
        var t = new Thread(() => name = QueryUnicodeString(handle, Win32.ObjectNameInformation))
        { IsBackground = true };
        t.Start();
        return t.Join(TimeSpan.FromMilliseconds(50)) ? name : null;
    }

    private static string? QueryUnicodeString(IntPtr handle, int infoClass)
    {
        var length = 0x1000;
        IntPtr buffer = Marshal.AllocHGlobal(length);
        try
        {
            var status = Win32.NtQueryObject(handle, infoClass, buffer, length, out var returnLength);
            if (status != 0 && returnLength > 0)
            {
                Marshal.FreeHGlobal(buffer);
                length = returnLength;
                buffer = Marshal.AllocHGlobal(length);
                status = Win32.NtQueryObject(handle, infoClass, buffer, length, out _);
            }
            if (status != 0) return null;

            // Both OBJECT_NAME_INFORMATION and OBJECT_TYPE_INFORMATION begin with
            // a UNICODE_STRING.
            var us = Marshal.PtrToStructure<Win32.UNICODE_STRING>(buffer);
            return us.Buffer == IntPtr.Zero || us.Length == 0
                ? null
                : Marshal.PtrToStringUni(us.Buffer, us.Length / 2);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
}
