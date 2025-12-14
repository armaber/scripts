<#
.SYNOPSIS
    Activate WPP traces using logman.exe, TraceLog.exe. Analyze with TraceFmt.exe and SymChk.exe.

.DESCRIPTION
    Install WDK to obtain the TraceLog, TraceFmt and SymChk tools. Pass the provider list either
    by name or by GUID, enable the traces at system startup.

.PARAMETER Provider
    List of providers supplied by name or by GUID

.PARAMETER Startup
    Enable logging at system startup.

.PARAMETER TraceLog
    Specify a different path for tracelog.exe tool, instead of the latest version located in
    default "$env:ProgramFiles(x86)" subdirectory.

.PARAMETER Decode
    Specify the etl file to process.

.PARAMETER Image
    Specify the binary files that must match the .pdb to .tmf files.

.PARAMETER SymRoot
    Specify the root directory where versioned symbols are stored. Default to
        1. parsing the $env:_NT_SYMBOL_PATH
        2. if absent, use "C:\Symbols"

.PARAMETER TraceFmt
    Specify a different path for tracefmt.exe tool, instead of the latest version located in
    default "$env:ProgramFiles(x86)" subdirectory.

.EXAMPLE
    $pciGuid = '{47711976-08c7-44ef-8fa2-082da6a30a30}';
         .\GenerateEtl.ps1 -Provider $pciGuid -TraceLog C:\tracelog.exe -Startup

    This command activates PCI traces at system startup. It creates a "StartupGenerateEtl"
    autologger.

.EXAMPLE
    .\GenerateEtl.ps1 -Disable -TraceLog C:\tracelog.exe -Startup

    The command stops the StartupGenerateEtl session, saves the .etl file in
        C:\WINDOWS\system32\Logfiles\WMI\StartupGenerateEtl.etl

.EXAMPLE
    $pciSys = 'C:\Windows\System32\drivers\pci.sys';
         $etlFile = 'C:\WINDOWS\system32\Logfiles\WMI\StartupGenerateEtl.etl';
         .\GenerateEtl.ps1 -Decode $etlFile -SymRoot D:\Symbols -Image $pciSys;

    Extract the human-readable messages from the .etl file. The output is placed in
    .\FmtFile.txt, .\FmtSum.txt.
#>
[CmdletBinding(DefaultParameterSetName = "Enable")]
param(
    [Parameter(ParameterSetName = "Enable")]
    [Alias("Source")]
    [string[]]$Provider,
    [Parameter(ParameterSetName = "Enable")]
    [Parameter(ParameterSetName = "Disable")]
    [string]$TraceLog,
    [Parameter(ParameterSetName = "Enable")]
    [Parameter(ParameterSetName = "Disable")]
    [switch]$Startup,
    [Parameter(ParameterSetName = "Disable")]
    [switch]$Disable,
    [Parameter(ParameterSetName = "Decode")]
    [string]$TraceFmt,
    [Parameter(ParameterSetName = "Decode")]
    [Alias("EtlFile")]
    [string]$Decode,
    [Parameter(ParameterSetName = "Decode")]
    [string[]]$Image,
    [Parameter(ParameterSetName = "Decode")]
    $SymChk,
    [Parameter(ParameterSetName = "Decode")]
    [string]$SymRoot
)

. $PSScriptRoot\functions.ps1;

switch ($PSCmdLet.ParameterSetName)
{
    "Enable" {
        $guidList = ProviderToGuid $Provider;
        EnableProvider $guidList $TraceLog -Startup:$Startup;
    }
    "Disable" {
        DisableProvider $TraceLog -Startup:$Startup;
    }
    "Decode" {
        DecodeEtl -TraceFmt:$TraceFmt $Decode $Image -SymChk:$SymChk -SymRoot:$SymRoot;
    }
}
