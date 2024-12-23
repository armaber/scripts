<#
.SYNOPSIS
Show native PCIe hot plug ACPI methods, ISRs

.DESCRIPTION
Use the script to process either the .DMP memory file or show the in-band kernel support
for PCIe hot plug.

CPU model, ACPI _OSC and CTL, IDT entries that manage hot plug with corresponding PDOs are
part of listing.

.PARAMETER Path
Specify the path to a memory file. It must end in .dmp.

.PARAMETER LocalKD
Use local kernel connection, within an elevated prompt. Provision the OS with
    bcdedit.exe /debug on
    bcdedit.exe /dbgsettings local
and disable SecureBoot in the firmware menu = BIOS.

.LINK
https://github.com/armaber/articles/blob/main/PCIeHP/notes.md
#>

[CmdletBinding(DefaultParameterSetName = "DMP")]
param(
    [Parameter(ParameterSetName = "DMP")]
    [String]$Path,
    [Parameter(ParameterSetName = "LKD")]
    [Switch]$LocalKD
);

$kd = "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\kd.exe";
$st = ".load jsprovider.dll; .scriptrun ""$PSScriptRoot\Detect_OSC.js""; q";

if ($PSCmdlet.ParameterSetName -eq "DMP") {
    if ($Path -notlike "*.dmp") {
        throw "The path must be a memory file";
    }
    $output = & $kd -c $st -kqm -z $Path;
} else {
    $output = & $kd -c $st -kqm -kl;
}
$output = $output -join "`n";
$parse = ([regex]::Matches($output, "JavaScript script successfully loaded.+(.*`n)+quit:").Value -split "`n");
$parse[1..($parse.Count-2)];