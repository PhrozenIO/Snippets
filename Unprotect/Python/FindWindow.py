import ctypes
import os

from ctypes.wintypes import BOOL, HWND, LPARAM,\
                            LPWSTR, INT, MAX_PATH,\
                            LPDWORD, DWORD, HANDLE,\
                            HMODULE


def found(description, hwnd):
    """
    When a Window handle is found it will output to console several information about spotted process.
    :param description: Description of found object.
    :param hwnd: Handle of found object.
    """
    lpdwProcessId = ctypes.c_ulong()

    output = "-" * 60 + "\r\n"
    output += description + "\r\n"
    output += "-" * 60 + "\r\n"

    output += f"Handle: {hwnd}\r\n"

    _GetWindowThreadProcessId(hwnd, ctypes.byref(lpdwProcessId))

    if (lpdwProcessId is not None) and (lpdwProcessId.value > 0):
        PROCESS_QUERY_INFORMATION = 0x0400
        PROCESS_VM_READ = 0x0010

        procHandle = ctypes.windll.kernel32.OpenProcess(
            PROCESS_QUERY_INFORMATION | PROCESS_VM_READ,
            False,
            lpdwProcessId.value
        )

        if procHandle > 0:
            output += f"Process Id: {lpdwProcessId.value}\r\n"

            lpFilename = ctypes.create_unicode_buffer(MAX_PATH)

            if _GetModuleFileNameEx(procHandle, 0, lpFilename, MAX_PATH) > 0:
                path, process_name = os.path.split(lpFilename.value)

                output += f"Process Name: {process_name}\r\n"
                output += f"Image Path: {path}\r\n"

            ctypes.windll.kernel32.CloseHandle(procHandle)

    output += "-" * 60 + "\r\n\r\n"

    print(output)


def enum_window_proc(hwnd, lparam):
    """
    EnumWindows API CallBack
    :param hwnd: Current Window Handle
    :param lparam: Not used in our case
    :return: Always True in our case
    """
    if hwnd > 0:
        nMaxCount = ctypes.windll.user32.GetWindowTextLengthW(hwnd)+1

        if nMaxCount > 0:
            lpWindowName = ctypes.create_unicode_buffer(nMaxCount)

            if _GetWindowText(hwnd, lpWindowName, nMaxCount) > 0:
                for description, in_title in contains_in_title:
                    if in_title in lpWindowName.value:
                        found(description, hwnd)

    return True


if __name__ == '__main__':
    '''
        Description | Window Class Name (lpClassName) | Window Title (lpWindowName)
    '''
    fw_debuggers = [
        ("OllyDbg", "OLLYDBG", None),
        ("x64dbg (x64)", None, "x64dbg"),
        ("x32dbg (x32)", None, "x32dbg"),
        # ......... #
    ]

    '''
        Description | Text contained in debugger title.
    '''
    contains_in_title = [
        ("Immunity Debugger", "Immunity Debugger"),
        # ......... #
    ]

    # Define GetWindowThreadProcessId API
    _GetWindowThreadProcessId = ctypes.windll.user32.GetWindowThreadProcessId

    _GetWindowThreadProcessId.argtypes = HWND, LPDWORD
    _GetWindowThreadProcessId.restype = DWORD

    # Define GetModuleFileNameEx API
    _GetModuleFileNameEx = ctypes.windll.psapi.GetModuleFileNameExW
    _GetModuleFileNameEx.argtypes = HANDLE, HMODULE, LPWSTR, DWORD
    _GetModuleFileNameEx.restype = DWORD

    '''
        Search for Debuggers using the FindWindowW API with ClassName /+ WindowName
    '''
    for description, lpClassName, lpWindowName in fw_debuggers:
        handle = ctypes.windll.user32.FindWindowW(lpClassName, lpWindowName)

        if handle > 0:
            found(description, handle)

    '''
        Search for Debuggers using EnumWindows API.
        We first list all Windows titles then search for a debugger title pattern.
        This is useful against debuggers or tools without specific title / classname. 
    '''

    # Define EnumWindows API
    lpEnumFunc = ctypes.WINFUNCTYPE(
        BOOL,
        HWND,
        LPARAM
    )

    _EnumWindows = ctypes.windll.user32.EnumWindows

    _EnumWindows.argtypes = [
        lpEnumFunc,
        LPARAM
    ]

    # Define GetWindowTextW API
    _GetWindowText = ctypes.windll.user32.GetWindowTextW

    _GetWindowText.argtypes = HWND, LPWSTR, INT
    _GetWindowText.restype = INT

    # Enumerate Windows through Windows API
    _EnumWindows(lpEnumFunc(enum_window_proc), 0)