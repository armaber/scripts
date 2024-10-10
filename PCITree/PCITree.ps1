<#
.SYNOPSIS
Display the PCI devices together with their BDF.

.DESCRIPTION
Launch it without admin privileges. For each devnode display: BDF, DeviceID,
Service, Caption, BARs, Driver Stack.

.PARAMETER AsHTML
Generate html file on the current directory. Each devnode shows relevant
properties, with additional information being displayed as a tooltip.

.PARAMETER AsVT
Highlight BDF status, display the tree using virtual terminal escape sequences.

.PARAMETER AsText
Suppress VT sequences.

.NOTES
AsVT, AsText parameters break the output if the window is resized.
In these cases, increase the console width.

AsHTML rendering:
- DeviceID is used as the largest width for the devnode rectangle. Some
devnodes have a Caption that surpass it in length, so a line break is
applied.
- hover on each entry to see what Status and Problem fields represent.

.LINK
https://github.com/armaber/articles/blob/main/PCITree/brief.md
#>

#Requires -PSEdition Desktop -Version 5

[CmdletBinding(DefaultParameterSetName = "HTML")]
param(
    [Parameter(ParameterSetName = "Text")]
    [Switch]$AsText,
    [Parameter(ParameterSetName = "VT")]
    [Switch]$AsVT,
    [Parameter(ParameterSetName = "HTML")]
    [Switch]$AsHTML);

. $PSScriptRoot\functions.ps1

ImportNative;

$devs = GetPCIeDevNodes;
PCITree ([ref]$devs);

if ($PSCmdlet.ParameterSetName -eq "HTML") {
    $ct = RenderHTML $devs;
    GenerateFileName ([ref]$ct);
} else {
    PrintHeader;
    DisplayConsole $devs;
}
