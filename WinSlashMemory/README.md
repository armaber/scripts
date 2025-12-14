Windows SlashMem Python Subsystem
=

*On Linux, `/dev/mem` can be opened and read using python os primitives. On Windows, the gap is filled by this driver and user mode sample.*

Installation
-

* Download `Visual Studio 2022 Community` and the latest `Windows Driver Kit`. Open a development console,
navigate to the **driver** directory and type `msbuild`. By default, 64-bit Debug driver is generated.
* The build image must be signed with a self-signing certificate and the target system must allow such drivers.
See [driver signing during development](https://learn.microsoft.com/en-us/windows-hardware/drivers/develop/signing-a-driver-during-development-and-testing) and [provisioning a target computer](https://learn.microsoft.com/en-us/windows-hardware/drivers/gettingstarted/provision-a-target-computer-wdk-8-1).
    * A convenient shortcut is to generate a self-signed certificate, build the driver, install the public key on the target and use `bcdedit.exe /set testsigning on`.
    * The driver must be installed on Windows 10 *20H1 = 10.0.19041* or above.

Copy the `.sys` file to **python** folder, launch `py .\test.py` with elevated privileges.

Sample output
-

```powershell
    Copy-Item C:\WinSlashMemory\driver\x64\Debug\slash_memory.sys C:\WinSlashMemory\python
    py C:\WinSlashMemory\python\test.py f8000000
```

```text
    Installing "C:\WinSlashMemory\python\slash_memory.sys"
    Memory dump of f8000000
    ----------------------------------------
    000: 590f8086 20900106 06000006 00000000
    010: 00000000 00000000 00000000 00000000
    020: 00000000 00000000 00000000 07a31028
    030: 00000000 000000e0 00000000 00000000
    040: fed19001 00000000 fed10001 00000000
    050: 000001c1 00000039 cff00047 cd000127
    060: f8000005 00000000 fed18001 00000000
    070: fe000000 00000000 fe000c00 0000007f
    080: 11111110 00113111 0000001a 00000000
    090: 00000001 00000001 2df00001 00000001
    0a0: 00000001 00000001 2e000001 00000001
    0b0: ce000001 cd800001 cd000001 d0000001
    0c0: 00000000 00000000 00000000 00000000
    0d0: 00000000 00000000 00000000 00000000
    0e0: 01100009 62012061 940400c8 00040000
    0f0: 00000000 00090fc8 00000000 00000000
    Installing "C:\WinSlashMemory\python\slash_memory.sys"
    Memory dump of f8000000
    ----------------------------------------
    000: 590f8086 20900106 06000006 00000000
    010: 00000000 00000000 00000000 00000000
    020: 00000000 00000000 00000000 07a31028
    030: 00000000 000000e0 00000000 00000000
```