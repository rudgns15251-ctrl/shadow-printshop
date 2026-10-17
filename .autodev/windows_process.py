"""Wait for the launched Windows process tree, including asynchronous termination.

Only descendants of the caller's still-held Popen process are opened. Process
handles stay open until completion, preventing their PIDs from being reused.
"""
import ctypes
from ctypes import wintypes as w
import subprocess
import time


def wait_log_released(path, timeout=20):
    """Observe exclusive availability after our writer closes; never assume a delay."""
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p, w.DWORD, w.DWORD, w.HANDLE]
    kernel.CreateFileW.restype = w.HANDLE
    kernel.CloseHandle.argtypes = [w.HANDLE]
    started = time.monotonic()
    deadline = started + timeout
    attempts = 0
    while True:
        attempts += 1
        handle = kernel.CreateFileW(str(path), 0x80000000, 0, None, 3, 0, None)
        if handle != ctypes.c_void_p(-1).value:
            kernel.CloseHandle(handle)
            return {'exclusive_open_attempts': attempts, 'release_wait_s': time.monotonic() - started}
        error = ctypes.get_last_error()
        if error not in (32, 33):  # Sharing/lock violation only; do not hide other failures.
            raise ctypes.WinError(error)
        if time.monotonic() >= deadline:
            raise subprocess.TimeoutExpired('launched process log release', timeout)
        time.sleep(.01)


def terminate_tree(process, timeout=20):
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)

    class Entry(ctypes.Structure):
        _fields_ = [('dwSize', w.DWORD), ('cntUsage', w.DWORD), ('pid', w.DWORD),
                    ('heap', ctypes.c_size_t), ('module', w.DWORD), ('threads', w.DWORD),
                    ('parent', w.DWORD), ('priority', w.LONG), ('flags', w.DWORD),
                    ('name', w.WCHAR * 260)]

    kernel.CreateToolhelp32Snapshot.argtypes = [w.DWORD, w.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = w.HANDLE
    kernel.Process32FirstW.argtypes = [w.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [w.HANDLE, ctypes.POINTER(Entry)]
    kernel.OpenProcess.argtypes = [w.DWORD, w.BOOL, w.DWORD]
    kernel.OpenProcess.restype = w.HANDLE
    kernel.WaitForSingleObject.argtypes = [w.HANDLE, w.DWORD]
    kernel.WaitForSingleObject.restype = w.DWORD
    kernel.CloseHandle.argtypes = [w.HANDLE]
    snapshot = kernel.CreateToolhelp32Snapshot(2, 0)  # TH32CS_SNAPPROCESS
    if snapshot == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    parents = {}
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(entry)
        available = kernel.Process32FirstW(snapshot, ctypes.byref(entry))
        while available:
            parents[entry.pid] = entry.parent
            available = kernel.Process32NextW(snapshot, ctypes.byref(entry))
        if ctypes.get_last_error() not in (0, 18):  # ERROR_NO_MORE_FILES
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(snapshot)
    owned = {process.pid}
    while True:
        expanded = owned | {pid for pid, parent in parents.items() if parent in owned}
        if expanded == owned:
            break
        owned = expanded
    handles = {}
    try:
        for pid in owned - {process.pid}:
            handle = kernel.OpenProcess(0x00100000, False, pid)  # SYNCHRONIZE only
            if handle:
                handles[pid] = handle
            elif ctypes.get_last_error() != 87:  # Already exited: ERROR_INVALID_PARAMETER
                raise ctypes.WinError(ctypes.get_last_error())
        result = subprocess.run(['taskkill.exe', '/PID', str(process.pid), '/T', '/F'],
                                capture_output=True, timeout=timeout)
        process.kill()
        process.wait(timeout=timeout)
        deadline = time.monotonic() + timeout
        for handle in handles.values():
            remaining_ms = max(0, int((deadline - time.monotonic()) * 1000))
            status = kernel.WaitForSingleObject(handle, remaining_ms)
            if status == 258:  # WAIT_TIMEOUT
                raise subprocess.TimeoutExpired('launched descendant termination', timeout)
            if status != 0:
                raise ctypes.WinError(ctypes.get_last_error())
        return {'taskkill_exit_code': result.returncode, 'waited_descendant_pids': sorted(handles)}
    finally:
        for handle in handles.values():
            kernel.CloseHandle(handle)
