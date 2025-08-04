"""Simple POC for slashmem module"""
import sys
import numpy
from slashmem import WinMemDevice, PageDirection, PageCache

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

io_base = numpy.uint64(0xF8000000) # MCFG base on a system
if len(sys.argv) != 1:
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
