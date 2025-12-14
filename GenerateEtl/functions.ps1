
function ProviderToGuid
{
    param([string[]]$Name)

    $Name = $Name | Select-Object -Unique;

    $guidList = @();
    $humanReadable = $Name | Where-Object {
        try {
            $guidList += [string][guid]$PSItem;
        } catch {
            $PSItem;
        }
    }
    if ($humanReadable) {
        & logman.exe query providers | Select-String $humanReadable -SimpleMatch | Foreach-Object {
            if ($PSItem -match "\{(?<guid>.+)\}") {
                $guidList += $Matches["guid"];
            }
        }
    }
    return $guidList;
}

function PrepareCtlFile
{
    param(
        [string[]]$Provider,
        [string]$Path
    )

    $null | Set-Content $Path;
    $keywords = "0xFFFFFFFF";
    $level = "5";
    $content = $Provider | Foreach-Object {
        "$PSItem;$keywords;$level" | Add-Content $Path;
    }
}

function GetSessionName {
    param([switch]$Startup)

    $sessionName = "session";
    if ($Startup) {
        $sessionName = "StartupProvideEtl";
    }
    return $sessionName;
}

function GetCtlFile
{
    return "${env:TEMP}\57446b50-6b29-4b32-a118-a3a09d92aefb.ctl";
}

function GetSymChk
{
    return "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\symchk.exe";
}

function GetSymRoot
{
    if ($env:_NT_SYMBOL_PATH) {
        $interPath = (($env:_NT_SYMBOL_PATH -split "^srv\*")[1] -split "\*")[0];
    }
    if (-not $interPath) {
        $interPath = "C:\Symbols";
    }
    return $interPath;
}

function ConfigureAutologgerIndirect
{
    # RemoveStartupKeys is required to delete the registry keys.
    param(
        [string]$TraceLog,
        [string[]]$Provider,
        [string]$Session
    )

    $ctlFile = GetCtlFile;
    PrepareCtlFile $Provider $ctlFile;
    $sessionGuid = [string](New-Guid);
    & $TraceLog -addautologger $Session -sessionguid "#$sessionGuid" -guid $ctlFile;
}

function PopulateStartupKeys
{
    # Kept as alternative to ConfigureAutologgerIndirect:
    # - registry keys documented
    # - tracelog.exe -autologger considered safe
    param(
        [string]$Session,
        [string[]]$Provider
    )

    $baseKey = "HKLM:\System\CurrentControlSet\Control\WMI\Autologger";
    New-Item $baseKey -Name $Session | Out-Null;
    $baseKey += "\$Session";
    $autoGuid = [string](New-Guid);
    Set-ItemProperty $baseKey -Name Guid -Value "`{$autoGuid`}" -Type String;
    Set-ItemProperty $baseKey -Name Start -Value 1 -Type Dword;
    $Provider | Foreach-Object {
        if ($PSItem -notlike "{*}") {
            $braces = "`{$PSItem`}";
        } else {
            $braces = $PSItem;
        }

        New-Item $baseKey -Name $braces | Out-Null;
        Set-ItemProperty $baseKey\$braces -Name Enabled -Type Dword -Value 1;
        Set-ItemProperty $baseKey\$braces -Name EnableFlags -Type Dword -Value -1;
        Set-ItemProperty $baseKey\$braces -Name EnableLevel -Type Dword -Value 5;
    }
}

function RemoveStartupKeys
{
    param([string]$Session)

    $baseKey = "HKLM:\System\CurrentControlSet\Control\WMI\Autologger";
    Remove-Item $baseKey\$Session -Recurse;
}

function GetLatestBin
{
    param([string]$FileName)

    $version = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\$FileName" |
               ForEach-Object {
                    [version](Split-Path $PSItem.FullName.Replace("\x64\$FileName", "") -Leaf)
                } |
               Sort-Object -Top 1 -Descending;
    return "${env:ProgramFiles(x86)}\Windows Kits\10\bin\$version\x64\$FileName";
}

function GetTraceLog
{
    return GetLatestBin "tracelog.exe";
}

function IsAdmin
{
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent();
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id);
    $ad = [System.Security.Principal.WindowsBuiltInRole]::Administrator;
    return $pr.IsInRole($ad);
}

function EnableProvider
{
    param(
        [string[]]$Provider,
        [string]$TraceLog,
        [switch]$Startup
    )

    if (-not (IsAdmin)) {
        Write-Error "EnableProvider requires elevation";
        exit 1;
    }
    $ctlFile = GetCtlFile;
    $sessionName = GetSessionName -Startup:$Startup;
    if ($Startup) {
        # PopulateStartupKeys $sessionName $Provider;
        ConfigureAutologgerIndirect $TraceLog $Provider $sessionName;
    } else {
        if (! $TraceLog) {
            $TraceLog = GetTraceLog;
        }
        PrepareCtlFile $Provider $ctlFile;
        & $TraceLog -f "${env:TEMP}\$sessionName.etl" -start $sessionName -guid $ctlFile;
    }
}

function DisableProvider
{
    param(
        [string]$TraceLog,
        [switch]$Startup
    )

    if (-not (IsAdmin)) {
        Write-Error "DisableProvider requires elevation";
        exit 1;
    }
    $sessionName = GetSessionName -Startup:$Startup;
    if (! $TraceLog) {
        $TraceLog = GetTraceLog;
    }
    & $TraceLog -stop $sessionName;
    if ($Startup) {
        RemoveStartupKeys $sessionName;
    } 
    GetCtlFile | Remove-Item -ErrorAction SilentlyContinue;
}

function GetTraceFmt
{
    return GetLatestBin "tracefmt.exe";
}

function DecodeEtl
{
    param(
        [string]$TraceFmt,
        [string]$EtlFile,
        [string[]]$Image,
        [string]$SymChk,
        [string]$SymRoot
    )

    if (! $SymChk) {
        $SymChk = GetSymChk;
    }
    if (! $SymRoot) {
        $SymRoot = GetSymRoot;
    }
    $ig = @();
    $Image | ForEach-Object {
        & $SymChk $PSItem /su "srv*$SymRoot*https://msdl.microsoft.com/download/symbols";
        $ig += "-i", $PSItem;
    }
    if (! $TraceFmt) {
        $TraceFmt = GetTraceFmt;
    }
    & $TraceFmt $EtlFile $ig -r $SymRoot;
}
