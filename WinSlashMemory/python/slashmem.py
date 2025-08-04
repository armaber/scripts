"""Proxy to SlashMemory driver, uses seek() to map IO memory to user mode"""
import os
import sys
from enum import Enum
import subprocess
from ctypes import Structure, c_uint, c_uint64, c_voidp, cast, POINTER, windll
import numpy as np
import win32file as wf
import winioctlcon
#pylint: disable = no-name-in-module
from pywintypes import error as winerror

if sys.platform != "win32":
    raise RuntimeError("Module available exclusively on Windows")

class PageCache(Enum):
    """direct map into WDK types"""
    PAGE_NOCACHE = 0
    PAGE_CACHE = 1
    PAGE_WRITECOMBINE = 2

class PageDirection(Enum):
    """direct map into WDK types"""
    PAGE_READWRITE = 4
    PAGE_READONLY = 2

class InvalidParameter(Exception):
    """quick placeholder"""

class SubprocessFailure(Exception):
    """quick placeholder"""

class SlashMemoryControl(Enum):
    """only 1 ioctl, can be extended"""
    IOCTL_MEM_SEEK = winioctlcon.CTL_CODE(32768 + winioctlcon.FILE_DEVICE_UNKNOWN,
                                          2048,
                                          winioctlcon.METHOD_BUFFERED,
                                          winioctlcon.FILE_ANY_ACCESS)

#pylint: disable=too-few-public-methods
class DeviceCommand(Structure):
    """packed structure from user to kernel mode"""
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
    _vptr: c_voidp
    _file: int
    _drv: bool
    @staticmethod
    def install_driver():
        """Call by itself to have it permanently installed."""
        if not windll.shell32.IsUserAnAdmin():
            raise OSError("SlashMemory driver installation requires elevated privileges.")
        drvpath = os.path.join(os.path.dirname(os.path.abspath(__file__)), "slash_memory.sys")
        print(f"Installing \"{drvpath}\"")
        rc = subprocess.call(["sc.exe", "create", "SlashMemory", "type=kernel",
                              "binPath=", drvpath],
                             stdout = subprocess.DEVNULL)
        if rc == 1073:
            rc = subprocess.call(["sc.exe", "delete", "SlashMemory"],
                                 stdout = subprocess.DEVNULL)
            if rc != 0:
                raise SubprocessFailure("Cannot delete SlashMemory")
            rc = subprocess.call(["sc.exe", "create", "SlashMemory", "type=kernel",
                                  "binPath=", drvpath],
                                 stdout = subprocess.DEVNULL)
        if rc != 0:
            raise SubprocessFailure("Failed to install SlashMemory driver")
        rc = subprocess.call(["sc.exe", "start", "SlashMemory"],
                             stdout = subprocess.DEVNULL)
        if rc != 0:
            raise SubprocessFailure("Failed to start SlashMemory")

    @staticmethod
    def uninstall_driver(test = False):
        """use sc.exe to uninstall, set test to True to if you are running with elevation"""
        if test:
            if not windll.shell32.IsUserAnAdmin():
                raise OSError("Driver uninstall requires elevated privileges.")
        rc = subprocess.call(["sc.exe", "stop", "SlashMemory"],
                             stdout = subprocess.DEVNULL)
        rc = subprocess.call(["sc.exe", "delete", "SlashMemory"],
                             stdout = subprocess.DEVNULL)
        if rc:
            raise SubprocessFailure("Cannot delete SlashMemory")

    def _default_values(self):
        self._file = wf.INVALID_HANDLE_VALUE
        self._vptr = c_voidp(0)
        self._drv = False

    def __init__(self):
        self._default_values()

    def open(self):
        """open communication with driver, install if failure"""
        try:
            self._file = wf.CreateFile(r"\\.\SlashMemory",
                                       wf.GENERIC_READ | wf.GENERIC_WRITE,
                                       wf.FILE_SHARE_READ | wf.FILE_SHARE_WRITE,
                                       None,
                                       wf.OPEN_EXISTING,
                                       wf.FILE_ATTRIBUTE_NORMAL,
                                       None)
        except winerror:
            WinMemDevice.install_driver()
            self._file = wf.CreateFile(r"\\.\SlashMemory",
                                       wf.GENERIC_READ | wf.GENERIC_WRITE,
                                       wf.FILE_SHARE_READ | wf.FILE_SHARE_WRITE,
                                       None,
                                       wf.OPEN_EXISTING,
                                       wf.FILE_ATTRIBUTE_NORMAL,
                                       None)
            self._drv = True
    def __enter__(self):
        self.open()
        return self

    def seek(self, pa: np.uint64, direction: PageDirection, caching: PageCache):
        """Go to physical address, map PAGE_SIZE internally"""
        inreq = DeviceCommand(pa,
                              caching.value,
                              1 if direction == PageDirection.PAGE_READWRITE else 0)
        wf.DeviceIoControl(self._file, SlashMemoryControl.IOCTL_MEM_SEEK.value, inreq, self._vptr)

    def read4(self, offset: np.uint16):
        """return mapped value"""
        if offset % 4 or offset >= 4093:
            raise InvalidParameter
        offset //= 4
        return cast(self._vptr, POINTER(c_uint))[int(offset)]

    def write4(self, offset: np.uint16, value: np.uint32):
        """set value into mapped pointer offset"""
        if offset % 4 or offset >= 4093:
            raise InvalidParameter
        offset //= 4
        cast(self._vptr, POINTER(c_uint))[int(offset)] = value

    def close(self):
        """if driver has been installed by us, then uninstall it"""
        wf.CloseHandle(self._file)
        if self._drv:
            WinMemDevice.uninstall_driver()
        self._default_values()

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()
        return False
