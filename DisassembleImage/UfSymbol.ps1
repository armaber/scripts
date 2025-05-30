<#
.SYNOPSIS
    Build a call graph for a given linker symbol.

.DESCRIPTION
    Within a Memory.DMP collection, transform the raw file in complete functions
    disassembly, using "kd.exe". The function body is queried, all callers or
    callees are rendered in text mode.

.PARAMETER Symbol
    Specify the symbol, with module prefix. eg: ntoskrnl!KeTimeIncrement, nt!Kd_PCI_Mask
.PARAMETER Down
    The symbol acts as a caller, all dependecies are callees. Without it,
    the default is "called".
.PARAMETER Depth
    Define the maximum depth of the tree. Default is 2 levels.
.PARAMETER Image
    Disassemble the image, if it is not found in the image database. It can be an
    .exe, .dll, .sys or a .dmp file. As an alternative, scan for a caption
    representing the OS edition in the existing database.
.PARAMETER Setup
    Text based guide that receives user input for internal configuration:
        kd.exe location, database path, symbol path, statistics, warning.
.PARAMETER List
    Shows the decompiled modules, either .DMP or .dll, .sys, .exe files.
.PARAMETER Migrate
    Copy internal files to a destination folder. Have kd.exe running in
    standalone mode with local symbols.
.PARAMETER Self
    Insert symbol in stop-rendering list.

.EXAMPLE
    .\UfSymbol.ps1 -List OS

    computer       os | basename                         image
    --------       -------------                         -----
    INHOUSE        dbgeng 10.0.26100.2454                C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbgeng.dll
    INHOUSE        pci 10.0.19041.1                      C:\Windows\System32\drivers\pci.sys
    DEPLOYMENT-092 Windows 10 Enterprise LTSC 2019 17763 C:\Windows\Memory.DMP
    INHOUSE        Windows 10 Pro 22631                  D:\DataLake\2025-01-28\MEMORY.DMP

    See all disassembled images. Use the "os" section as value for "-Caption" and reuse.

.EXAMPLE
    .\UfSymbol.ps1 -Symbol nt!KeQueryTimeIncrement -Caption "Windows 10 Pro 22631"

.EXAMPLE
    .\UfSymbol.ps1 -Symbol ntoskrnl!IoGetIommuInterface -Image "C:\Windows\System32\ntoskrnl.exe"

.EXAMPLE
    .\UfSymbol.ps1 -Self wcstok_s
    wcstok_s callees are not rendered.

.NOTES
    PowerShell Core is mandatory: optimizations since Desktop 5.1 are substantial.
    Hotpaths are implemented as inline assemblies.

.LINK
    https://github.com/armaber/articles/blob/main/HDUF/brief.md
#>

#requires -PSEdition Core

[CmdletBinding(DefaultParameterSetName = "Process")]
param(
      [Parameter(ParameterSetName = "Process")]
      [string]$Symbol,
      [Parameter(ParameterSetName = "Process")]
      [switch]$Down,
      [Parameter(ParameterSetName = "Process")]
      [int]$Depth = 2,
      [Parameter(ParameterSetName = "Process")]
      [Alias("Caption")]
      [string]$Image,
      [Parameter(ParameterSetName = "Setup")]
      [switch]$Setup,
      [Parameter(ParameterSetName = "List")]
      [ValidateSet("OS", "Complete")]
      [string]$List,
      [Parameter(ParameterSetName = "Migrate")]
      [Alias("USB")]
      [string]$Migrate,
      [Parameter(ParameterSetName = "Self")]
      [string]$Self
)

$ErrorActionPreference = 'Break';

. $PSScriptRoot\functions.ps1;

switch ($PSCmdLet.ParameterSetName)
{
    "Process"
    {
        QuerySymbol $Symbol -Down:$Down $Depth $Image;
    }
    "Setup" { ConfigureInteractive; }
    "List" { ListMetaFiles $List; }
    "Migrate" { MigrateFiles $Migrate; }
    "Self" { SelfInsert $Self }
}