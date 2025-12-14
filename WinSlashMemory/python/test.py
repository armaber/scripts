"""Simple POC for slashmem module"""
import sys
import ctypes
from slashmem import WinMemDevice, PageDirection, PageCache

class McfgTable(ctypes.Structure): # pylint: disable=too-few-public-methods
    """MCFG layout as defined in PCI firmware specification"""
    _pack_ = 1
    _fields_ = [
        ("Padding", ctypes.c_byte * 44),
        ("BaseAddress", ctypes.c_uint64),
        ("PciSegment", ctypes.c_uint16),
        ("StartBus", ctypes.c_uint8),
        ("EndBus", ctypes.c_uint8),
        ("Reserved", ctypes.c_uint32)
    ]

def locate_mcfg():
    """Call GetSystemFirmwareTable with 'ACPI', 'MCFG' and return the header
       Accessing MCFG can lead to undefined consequences.
       https://community.osr.com/t/how-acpi-and-pcie-are-linked-together/44758/8"""
    while True:
        answer = input("MCFG access can lead to undefined behavior. Are you sure? y/N:")
        answer = answer.strip().lower()
        if answer == 'y':
            break
        if answer in ['', 'n']:
            return None
    kernel32 = ctypes.WinDLL("kernel32", use_last_error = True)
    get_firmware = kernel32.GetSystemFirmwareTable
    get_firmware.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
    get_firmware.restype = ctypes.c_uint32
    _acpi = int.from_bytes(b'ACPI')
    _mcfg = int.from_bytes(b'MCFG', "little")
    ret = get_firmware(_acpi, _mcfg, None, 0)
    buffer = ctypes.create_string_buffer(ret)
    ret = get_firmware(_acpi, _mcfg, ctypes.byref(buffer), ret)
    header = McfgTable.from_buffer(buffer)
    return header

def dump_memory(dev, base, size):
    """print 4 dwords per line"""
    print(f"Memory dump of {base:08x}\n{'-'*40}")
    for i in range(0, size, 4):
        r = dev.read4(i)
        if i % 16 == 0:
            print(f"{i:03x}: ", end = "")
        print(f"{r:08x} ", end = "")
        if i % 16 == 12:
            print()

if len(sys.argv) == 1:
    print("""Usage: test.py <IoAddress>""")
    sys.exit(0)
else:
    try:
        io_base = int(sys.argv[1])
    except ValueError:
        try:
            io_base = int(sys.argv[1], 16)
        except ValueError as v:
            raise v

devmem = WinMemDevice()
devmem.open()
devmem.seek(io_base, PageDirection.PAGE_READONLY, PageCache.PAGE_NOCACHE)

dump_memory(devmem, io_base, 256)

devmem.close()

with WinMemDevice() as wm:
    # no open/close is necessary
    wm.seek(io_base, PageDirection.PAGE_READONLY, PageCache.PAGE_NOCACHE)
    dump_memory(wm, io_base, 64)
