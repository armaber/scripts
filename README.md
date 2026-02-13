Repository for lightweight scripts, mostly *PowerShell*, to query OS services.

* [IoDecode.ps1](./DecodeIoctl/IoDecode.ps1) shows the human readable IOCTL given a number. It keeps a local cache, in case the SDK is not installed. Otherwise, the header files are parsed.
* [UfSymbol.ps1](./DisassembleImage/UfSymbol.ps1) disassemble the Windows kernel or a *Memory.DMP* file to build a call tree.
* [GenerateEtl.ps1](./GenerateEtl/GenerateEtl.ps1) automate ETL provider configuration = start + stop, autostart, decode resulting file to interpret the traces.
* [PCITree.ps1](./PCITree/PCITree.ps1) view the PCI tree on UEFI systems, like Device Manager. Output rendered to console or as `.html` file, with a progress bar for large topologies.
* [WinSlashMemory.py](./WinSlashMemory/README.md) a python middleware + driver that maps any I/O *PAGE_SIZE* for read or write.
