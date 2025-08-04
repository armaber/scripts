from enum import Enum
import win32file, winioctlcon
import numpy as np
import subprocess, sys, os
from ctypes import Structure, c_uint, c_uint64, c_voidp, c_char_p, cast, POINTER, windll

if sys.platform != "win32":
    raise Exception("Module available exclusively on Windows")

class PageCache(Enum):
    PAGE_NOCACHE = 0
    PAGE_CACHE = 1
    PAGE_WRITECOMBINE = 2

class PageDirection(Enum):
    PAGE_READWRITE = 4
    PAGE_READONLY = 2

class InvalidParameter(Exception):
    pass

class SubprocessFailure(Exception):
    pass

class SlashMemoryControl(Enum):
    IOCTL_MEM_SEEK = winioctlcon.CTL_CODE(32768 + winioctlcon.FILE_DEVICE_UNKNOWN,
                                          2048,
                                          winioctlcon.METHOD_BUFFERED,
                                          winioctlcon.FILE_ANY_ACCESS)
class DeviceCommand(Structure):
    _fields_ = [
        ("offset", c_uint64),
        ("caching", c_uint),
        ("readwrite", c_uint)
    ]

class WinMemDevice:
    
    """
    Map physical memory on Windows, using a PAGE_SIZE block. Specify direction as 
    READONLY or READWRITE, caching type NOCACHE, CACHE, WRITECOMBINE, offset.
    """
    @staticmethod
    def install_driver():
        """
        Call by itself to have it permanently installed.
        """
        if not windll.shell32.IsUserAnAdmin():
            raise OSError("SlashMemory driver installation requires elevated privileges.")
        pydir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slash_memory.sys")
        print(f"Installing \"{pydir}\"")
        rc = subprocess.call(["sc.exe", "create", "SlashMemory", "type=kernel", "binPath=", pydir], stdout = subprocess.DEVNULL)
        if rc == 1073:
            rc = subprocess.call(["sc.exe", "delete", "SlashMemory"], stdout = subprocess.DEVNULL)
            if rc != 0:
                raise SubprocessFailure("Cannot delete SlashMemory")
            rc = subprocess.call(["sc.exe", "create", "SlashMemory", "type=kernel", "binPath=", pydir], stdout = subprocess.DEVNULL)
        if rc != 0:
            raise SubprocessFailure("Failed to install SlashMemory driver")
        rc = subprocess.call(["sc.exe", "start", "SlashMemory"], stdout = subprocess.DEVNULL)
        if rc != 0:
            raise SubprocessFailure("Failed to start SlashMemory")

    @staticmethod
    def uninstall_driver(test = False):
        if test:
            if not windll.shell32.IsUserAnAdmin():
                raise OSError("Driver uninstall requires elevated privileges.")
        rc = subprocess.call(["sc.exe", "stop", "SlashMemory"], stdout = subprocess.DEVNULL)
        rc = subprocess.call(["sc.exe", "delete", "SlashMemory"], stdout = subprocess.DEVNULL)
        if rc:
            raise SubprocessFailure("Cannot delete SlashMemory")

    def __init__(self):
        self._file = win32file.INVALID_HANDLE_VALUE
        self._offset = -1
        self._vptr = c_voidp(0)
        self._drv = False

    def open(self):
        try:
            self._file = win32file.CreateFile(r"\\.\SlashMemory", 
                                              win32file.GENERIC_READ | win32file.GENERIC_WRITE, 
                                              win32file.FILE_SHARE_READ | win32file.FILE_SHARE_WRITE,
                                              None,
                                              win32file.OPEN_EXISTING,
                                              win32file.FILE_ATTRIBUTE_NORMAL,
                                              None)
        except:
            WinMemDevice.install_driver()
            self._file = win32file.CreateFile(r"\\.\SlashMemory", 
                                              win32file.GENERIC_READ | win32file.GENERIC_WRITE, 
                                              win32file.FILE_SHARE_READ | win32file.FILE_SHARE_WRITE,
                                              None,
                                              win32file.OPEN_EXISTING,
                                              win32file.FILE_ATTRIBUTE_NORMAL,
                                              None)           
            self._drv = True
    def __enter__(self):
        self.open()
        return self
    
    def seek(self, pa: np.uint64, type: PageDirection, caching: PageCache):
        """Go to physical address, map PAGE_SIZE internally"""
        inreq = DeviceCommand(pa, caching.value, 1 if type == PageDirection.PAGE_READWRITE else 0)
        win32file.DeviceIoControl(self._file, SlashMemoryControl.IOCTL_MEM_SEEK.value, inreq, self._vptr, None)
        
    def read4(self, offset: np.uint16):
        if offset % 4 or offset >= 4093:
            raise InvalidParameter
        offset //= 4
        return cast(self._vptr, POINTER(c_uint))[offset]

    def write4(self, offset: np.uint16, value: np.uint32):
        if offset % 4 or offset >= 4093:
            raise InvalidParameter
        offset //= 4
        cast(self._vptr, POINTER(c_uint))[offset] = value

    def close(self):
        win32file.CloseHandle(self._file)
        if self._drv:
            WinMemDevice.uninstall_driver()
        self.__init__()

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()
        return False