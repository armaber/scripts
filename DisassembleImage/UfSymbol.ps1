<#
.SYNOPSIS
    Build a call graph for a given linker symbol.

.DESCRIPTION
    Within a Memory.DMP collection, transform the raw file in complete functions
    disassembly, using "kd.exe". The function body is queried, all callers or
    callees are rendered in a .html file.

.PARAMETER Symbol
    Specify the symbol, with or without module prefix.
        eg: KeTimeIncrement, nt!Kd_PCI_Mask
.PARAMETER Down
    The symbol acts as a caller, all dependecies are callees. Without it,
    the default is "called".
.PARAMETER Depth
    Define the maximum depth of the tree. Default is 2 levels.
.PARAMETER AsText
    Show the dependencies in the console. Default is a visual graph rendered
    in SVG.
.PARAMETER Image
    Disassemble the image, if it is not found in the image database. It can
    be an .exe or a .dmp file. Optionally, scan for a caption representing
    the OS edition in the existing database.

.EXAMPLE
    Get-ChildItem -Recurse -File "*.meta" | % { Get-Content $_ | ConvertFrom-Json } |
    Format-Table computer, os, image, @{ N = "duration"; E = {[string]$_.stats.duration + " s"} }

    computer   os                          image                            duration
    --------   --                          -----                            --------
    InfraNo1   10.0.19041.5737             C:\Windows\System32\ntoskrnl.exe 4140 s
    InfraNo2   10.0.26100.3775             C:\Windows\System32\ntoskrnl.exe 229 s
    Deploy1    Windows 10 Pro 22631        C:\Windows\MEMORY.DMP            157 s
    Deploy2    Windows 10 Enterprise 18363 C:\Windows\MEMORY.DMP            143 s

    See all disassembled images. Use the "os" section as value for "-Caption" and reuse.

.EXAMPLE
    .\UfSymbol.ps1 -Symbol nt!KeQueryTimeIncrement -Caption "Windows 10 Pro 22631"

.EXAMPLE
    .\UfSymbol.ps1 -Symbol IoGetIommuInterface -Image "C:\Windows\System32\ntoskrnl.exe"  

.NOTES
    PowerShell Core is mandatory: optimizations from Desktop 5.1 edition are substantial.
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
      [switch]$AsText,
      [Parameter(ParameterSetName = "Process")]
      [Alias("Caption")]
      [string]$Image,
      [Parameter(ParameterSetName = "Setup")]
      [switch]$Setup
)

$ErrorActionPreference = 'Break';

. $PSScriptRoot\functions.ps1;

switch ($PSCmdLet.ParameterSetName)
{
    "Process"
    { 
        QuerySymbol $Symbol -Down:$Down $Depth -AsText:$AsText $Image;
        break;
    }
    "Setup" { Setup; break; }
}