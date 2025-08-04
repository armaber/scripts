from slashmem import WinMemDevice, PageDirection, PageCache
import sys

def dump_memory(dev, base, size):
    print(f"Memory dump of {base:08x}\n{'-'*40}")
    for i in range(0, size, 4):
        r = dev.read4(i)
        if i % 16 == 0:
            print(f"{i:03x}: ", end = "")
        print(f"{r:08x} ", end = "")
        if i % 16 == 12:
            print()

if len(sys.argv) == 1:
    io_base = 0xF8000000 # MCFG base on a system
else:
    try:
        io_base = int(sys.argv[1])
    except:
        try:
            io_base = int(sys.argv[1], 16)
        except:
            raise

devmem = WinMemDevice()
devmem.open()
devmem.seek(io_base, PageDirection.PAGE_READONLY, PageCache.PAGE_NOCACHE)

dump_memory(devmem, io_base, 256)

devmem.close()

with WinMemDevice() as wm:
    # no open/close is necessary
    wm.seek(io_base, PageDirection.PAGE_READONLY, PageCache.PAGE_NOCACHE)
    dump_memory(wm, io_base, 64)