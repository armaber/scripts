$MetaVersion = 1;
$KD = "";
$Database = $PSScriptRoot;
$Sympath = "";
$Statistics = $true;
#Print a warning if other files have been decompiled in 5 minutes or more.
$AdviseLimit = 300;
$UfSymbolProfile = "$PSScriptRoot\UfSymbol.json";
#When these functions are encountered, the disassembly stops.
$StopDisassembly = @(
    "!memset$",
    "!memcpy$",
    "!qsort$",
    "!RtlStringCchCopyA$",
    "!RtlStringCchCopyW$",
    "!RtlStringCchCatA$",
    "!RtlStringCchCatW$",
    "!RtlStringCchCatNA$",
    "!RtlStringCchCatNW$",
    "!RtlStringCbPrintfA$",
    "!RtlStringCbPrintfW$",
    "!RtlStringCchVPrintfA$",
    "!RtlStringCchVPrintfW$",
    "!vsnprintf$",
    "!strupr$",
    "!stricmp$",
    "!strtok_s$",
    "!atoi$",
    "!atoi64$",
    "!atol$",
    "!DbgPrintEx$",
    "!_security_check_cookie$",
    "!guard_dispatch_icall \(.+?\)$",
    "!KeWaitForSingleObject$",
    "!KeWaitForMultipleObjects$",
    "!ExAllocatePool2$",
    "!ExAllocatePool3$",
    "!ExAllocatePoolWithTag$",
    "!ExFreePoolWithTag$",
    "!ExAllocateFromNPagedLookasideList$",
    "!ExFreeToNPagedLookasideList$",
    "!ExAllocateFromPagedLookasideList$",
    "!ExFreeToPagedLookasideList$",
    "!ExAcquireSpinLockShared$",
    "!ExReleaseSpinLockShared$",
    "!ExAcquireSpinLockExclusiveAtDpcLevel$",
    "!ExReleaseSpinLockExclusiveFromDpcLevel$",
    "!IofCompleteRequest$",
    "!ObfReferenceObject$",
    "!ObfReferenceObjectWithTag$",
    "!ObfDereferenceObjectWithTag$",
    "!ObDereferenceObjectDeferDeleteWithTag$",
    "!KeAcquireSpinLockAtDpcLevel$",
    "!KeReleaseSpinLockFromDpcLevel$",
    "!KeAcquireQueuedSpinLock$",
    "!KeReleaseQueuedSpinLock$",
    "!KeAcquireSpinLockRaiseToDpc$",
    "!KeReleaseSpinLock$",
    "!KeTryToAcquireSpinLockAtDpcLevel$",
    "!ExAcquireFastMutexUnsafe$",
    "!ExReleaseFastMutexUnsafe$",
    "!KeAcquireMutex$",
    "!KeReleaseMutex$",
    "!KeInitializeDpc$",
    "!KeInsertQueueDpc$",
    "!KeSetTargetProcessorDpc$",
    "!KeSetTargetProcessorDpcEx$",
    "!KeInitializeEvent$",
    "!KeSetEvent$",
    "!KeResetEvent$",
    "!KeClearEvent$",
    "!KeInitializeTimer$",
    "!KeInitializeTimer2$",
    "!KeSetTimer$",
    "!KeInitializeTimerEx$",
    "!KeSetTimerEx$",
    "!KeCancelTimer$",
    "!KeStallExecutionProcessor$",
    "!KeQueryPerformanceCounter$",
    "!KeSynchronizeExecution$",
    "!KeYieldProcessorEx$",
    "!KeBugCheck$",
    "!KeBugCheck2$",
    "!KeBugCheckEx$",
    "!RtlRaiseException$",
    "!EtwpLogKernelEvent$",
    "!RtlInitUnicodeString$"
);

function TraceMemoryUsage
{
    ("$($MyInvocation.ScriptLineNumber): Working set {0:f2}" -f ((Get-Process -Id $PID).WorkingSet64/1Mb)) | Write-Host;
}

function TraceLine
{
    param($Content)

    ("{0:u} $Content at line $($MyInvocation.ScriptLineNumber)" -f [datetime]::now) | Write-Host;
}

function LoadScriptProfile
{
    if (Test-Path $script:UfSymbolProfile) {
        $json = Get-Content -Raw $script:UfSymbolProfile | ConvertFrom-Json;
        $script:KD = $json.kd;
        $script:Database = $json.database;
        $script:Sympath = "srv*${json.sympath}*https://msdl.microsoft.com/download/symbols";
        $script:Statistics = $json.statistics;
        $script:AdviseLimit = $json.advise;
        if ($json.knownuf) {
            $script:StopDisassembly = $json.knownuf;
        }
        return $true;
    }
    return $false;
}

function LoadDefaultValues
{
    if (LoadScriptProfile) {
        return;
    }
    $location = @(Get-Item "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\kd.exe",
                    "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\kd.exe" `
                    -ErrorAction SilentlyContinue)[0];
    if (-not $location) {
        throw @"
Install Debugging Tools for Windows:
    https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
    & winsdksetup.exe /features OptionId.WindowsDesktopDebuggers /quiet /ceip off
"@;
    }
    $script:KD = $location.FullName;
    $script:Database = $PSScriptRoot;
    if ($env:_NT_SYMBOL_PATH) {
        $script:Sympath = $env:_NT_SYMBOL_PATH;
    } else {
        $script:Sympath = "srv*${script:Database}\Symbols*https://msdl.microsoft.com/download/symbols";
    }
    $script:Statistics = $true;
}

function LoadHotPath
{
    Add-Type -Path $PSScriptRoot\HotPath.cs;
}

function GetLogicalCPUs
{
    return [int](Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum;
}

function ComputeFileHash
{
    param([string]$Path)

    return (Get-FileHash -Algorithm SHA512 $Path).Hash;
}

function GetDelimiter
{
    param([string]$Disassembly)

    $delimiter = Select-String "(\d+: kd> )" $Disassembly -List;
    if ($delimiter) {
        $delimiter = $delimiter.Matches.Value;
    } else {
        $delimiter = "0:000> ";
    }
    return $delimiter;
}

function RunKd
{
    param([string]$Commands,
          [string]$Path,
          [string]$OutputFile)

    $cmdfile = [guid]::NewGuid().ToString();
    $cmdfile = "${env:TEMP}\$cmdfile.kd";
    #If empty line is inserted, then the previous command is replayed.
    #Use regex to replace all occurrences, trim the end.
    $Commands = ($Commands -replace "(`r?`n)+", "`n").Trim();
    if ($OutputFile) {
        $kdlogfile = [guid]::NewGuid().ToString();
        $kdlogfile = "${env:TEMP}\$kdlogfile.kdout";
        @"
.logopen "$kdlogfile"
$Commands
.logclose
q
"@ | Set-Content $cmdfile;
    } else {
        $Commands, "q" | Set-Content $cmdfile;
    }

    if ($OutputFile) {
        & $script:KD -y "$script:Sympath" -cf $cmdfile -z $Path > $null;
        if ($LASTEXITCODE) {
            throw "kd failed with code $LASTEXITCODE";
        }
        $after = $false;
        $delimiter = GetDelimiter $kdlogfile;
        if ($Commands.Substring(0, $Commands.IndexOf("`n")) -like ".reload*") {
            $from = ($Commands -split "`n")[1];
            $from = $delimiter + $from;
        } else {
            $from = "Opened log file";
            $after = $true;
        }
        $to = "$delimiter.logclose";
        [TrimKD]::TrimLogFile($kdlogfile, $from, $after, $to, $OutputFile);
        Remove-Item $kdlogfile;
    } else {
        & $script:KD -y "$script:Sympath" -cf $cmdfile -z $Path;
        if ($LASTEXITCODE) {
            throw "kd failed with code $LASTEXITCODE";
        }
    }
    Remove-Item $cmdfile;
}

function LoadMeta
{
    param([string]$Path)

    $gi = Get-Item $Path;
    $fn = $gi.FullName;
    $hash = ComputeFileHash $fn;
    if ($gi.Extension -eq ".dmp") {
        $content = RunKd @"
.reload
dpu mrxsmb!SmbCeContext+10 L0n4
"@ $Path;
        [string[]]$list = & {
            $content | ForEach-Object {
                #32 bit is possible
                if ($_ -match "([0-9a-f]{8}(``[0-9a-f]{8})?\s+){2}""(?<part>.+)""`$") {
                    $Matches.part;
                }
            }
        };
        if (! $list.Count) {
            #mrxsmb is not present
            $list = "UnknownMachine", "UnknownOS";
        }
        return [psobject][ordered]@{
                    version = $script:MetaVersion;
                    computer = $list[0];
                    os = $list[1];
                    image = $fn;
                    hash = $hash;
                    module = [string[]]@();
                };
            }
            return [psobject][ordered]@{
                version = $script:MetaVersion;
                computer = $env:COMPUTERNAME;
                os = & {
                    $gi.BaseName + " " + (($gi.VersionInfo -split "`r`n" | Where-Object { $_ -like "ProductVersion:*" }) -split ":\s+")[-1];
                };
                image = $fn;
                hash = $hash;
                module = [string[]]@();
            };
}

function BuildRetpoline
{
    param([string]$Disassembly,
          [string]$Image,
          [string]$Path)

    if ($Image -notlike "*.dmp") {
        return;
    }
    $body = SplitDisassembly $Disassembly;
    $guard = $body.Where({
        $PSItem -match "call    \w+!guard_dispatch_icall";
    });
    if (! $guard) {
        return;
    }
    $dps = [System.Collections.Generic.List[string]]::new();
    $pattern = [regex]::new("mov\s+rax,qword ptr \[(?<key>\w+!\w+\+.+?)\s.+?\][\s\S]+?call\s+\w+!guard_dispatch_icall", "Compiled, CultureInvariant");
    foreach ($g in $guard) {
        foreach ($m in [regex]::Matches($g, $pattern)) {
            $key = $m.Groups["key"].Value;
            $dps.Add("dps $key L1");
        }
    }
    if (! $dps.Count) {
        return;
    }
    $dps = $dps | Select-Object -Unique;
    $content = RunKd @"
.reload
$($dps -join "`n")
"@ $Image;
    $result = [psobject]::new();
    $content = $content -join "`n";
    $pattern = [regex]::new("dps (?<orig>.+?) L1`n([0-9a-f]{8}(``[0-9a-f]{8})?\s+){2}(?<part>\w+!\w+?[:\w]*?)`n", "Compiled, CultureInvariant");
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $from = $m.Groups["orig"].Value;
        $to = $m.Groups["part"].Value;
        Add-Member -NotePropertyName $from -NotePropertyValue $to -InputObject $result;
    }
    $result | ConvertTo-Json | Set-Content "$Path.retpoline";
}

function Trim0000Cr
{
    param([string]$Disassembly)

    $delimiter = GetDelimiter $Disassembly;
    #Text sections that are not locked in memory resolve to huge
    #bodies due to paged out instructions
    #    0000            add     byte ptr [rax],al
    #    0000            add     byte ptr [rax],al
    #                     Length Line
    #                     ------ ----
    #                   24061378 uf nt!SeInitSystem
    #                   24059940 uf nt!SepVariableInitialization
    #                   23836910 uf nt!SepInitSystemDacls
    #                   23772382 uf nt!SepInitializationPhase0
    #                   23765588 uf nt!SepInitializeSingletonAt…
    #                   23735440 uf nt!SepInitializeAuthorizati…
    #                   23730646 uf nt!SeMakeSystemToken
    #                   23687006 uf nt!SeMakeAnonymousLogonToke…
    #                   23667832 uf nt!SeMakeAnonymousLogonToken
    #                   23647694 uf nt!SepInitializeWorkList
    #If bodies are larger than 100K and contain "Flow analysis",
    #then they will be excluded.
    #
    #Trimming is implemented in C#. The hotpath takes a long time
    #to be interpreted.

    [TrimDisassembly]::TrimBodies($delimiter, $Disassembly);
}

#Single in the sense that is called within a runspace.
function DisassembleSingle
{
    param([System.Collections.Generic.List[string]]$Functions,
          [int]$From,
          [int]$To,
          [string]$Image,
          [string]$OutputFile)

    RunKd @"
.reload
$(
$Functions[$From .. $To] -join "`n";
)
"@ $Image $OutputFile;
}

#Create a runspace pool = thread pool, call DisassembleSingle and its internal dependencies.
function DisassembleParallel
{
    param([int]$Cores,
          [System.Collections.Generic.List[string]]$Functions,
          [string]$Image,
          [string]$Base)

    $instate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault();
    "KD", "Database", "Sympath", "PSScriptRoot" | ForEach-Object {
        $var = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new("$PSItem", (Invoke-Expression "`${script:$PSItem}"), $null);
        $instate.Variables.Add($var);
    }
    $var = [System.Management.Automation.Runspaces.SessionStateVariableEntry]::new("Functions", $Functions, $null);
    $instate.Variables.Add($var);
    $count = $Functions.Count;
    [int]$size = $count / $Cores;
    if (! $size) {
        $size = 1;
        $Cores = $count;
    }
    $pool = [runspacefactory]::CreateRunspacePool(1, $Cores, $instate, $Host);
    $pool.Open();
    $runspaces = [System.Collections.Generic.List[psobject]]::new();
    for ($i = 0; $i -lt $Cores; $i ++) {
        $from = $i * $size;
        $to = $from + $size - 1;
        if ($i -eq $Cores - 1) {
            $to =  $count - 1;
        }
        $space = [powershell]::Create();
        $script = @"
$(
"LoadHotPath", "RunKd", "DisassembleSingle", "GetDelimiter", "Trim0000Cr" | ForEach-Object {
    "function $PSItem {" + (Get-Content function:\$PSItem) + "}";
}
)

LoadHotPath;
DisassembleSingle `$Functions $from $to "$Image" "$Base-$i.txt";
Trim0000Cr "$Base-$i.txt";
"@;
        $space.AddScript($script) | Out-Null;
        $space.RunspacePool = $pool;
        $newrunspace = [psobject] @{
            runspace = $space;
            state = $space.BeginInvoke();
        };
        $runspaces.Add($newrunspace);
    }
    $runspaces | ForEach-Object {
        $PSItem.state.AsyncWaitHandle.WaitOne() | Out-Null;
        $PSItem.runspace.EndInvoke($PSItem.state);
        $PSItem.runspace.Dispose();
    }
    $pool.Close();
    $pool.Dispose();
    $disassembly = "$Base.disassembly";
    Move-Item "$Base-0.txt" $disassembly;
    $ostream = [System.IO.FileStream]::new($disassembly, "Append");
    for ($i = 1; $i -lt $Cores; $i ++) {
        $istream = [System.IO.FileStream]::new("$Base-$i.txt", "Open");
        $istream.CopyTo($ostream);
        $istream.Close();
        Remove-Item "$Base-$i.txt";
    }
    $ostream.Close();
    BuildRetpoline $disassembly $Image $Base;
}

#Call kd.exe, use reload /d /f to download the proper symbols,
#return the functions available in the .dmp or image.
function IdentifyFunctions
{
    param([string]$Path,
          [psobject]$Meta)

    $gi = Get-Item $Path;
    if ($gi.Extension -eq ".dmp") {
        $Meta.module = "nt", "pci", "acpi", "hal";
    } else {
        $Meta.module = @(, $gi.BaseName);
    }
    $content = RunKd @"
.reload /d /f
$($Meta.module | Foreach-Object {
"x /v /f $PSItem!*`n";
})
"@ $Path;
    $functions = [System.Collections.Generic.List[string]]::new();
    $content | Foreach-Object {
        if (($PSItem -notlike "*WPP_RECORDER*") -and
            ($PSItem -match "^(pub|prv) func "))
        {
            $functions.Add("uf " + ($PSItem -split "\s+")[2]);
        }
    }
    return $functions;
}

function Setup
{
    Set-Variable -Name LowerLimit -Option Constant -Value 400mb;

    $disk = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType = 3" -Property DeviceID, FreeSpace);
    if ($disk.Count -eq 1) {
        Write-Host "Only drive ${disk.DeviceID} is available. No other disk can be selected.";
        return;
    }
    $candidate = $disk | Where-Object { $_.FreeSpace -gt $LowerLimit }
    if (-not $candidate) {
        Write-Host "Default dissasembly path cannot be recommended. Each partition availalbe has less than $($LowerLimit/1mb) MB free space.";
        return;
    }
    if ($candidate.Count -ne 1) {
        $e = Get-PnpDevice -Class 'DiskDrive' | Select-Object DeviceID;
        $e = $e | Get-PnpDeviceProperty DEVPKEY_Device_Parent;
        $e = $e.Data | Get-PnpDeviceProperty DEVPKEY_PciDevice_CurrentLinkSpeed, DEVPKEY_PciDevice_CurrentLinkWidth;
    }
}

#Look in all .meta, take the one that has the Operating System matching
#the caption and return the path.
function LocateDisassembly
{
    param([string]$Caption,
          [string]$Image)

    $location = $script:Database;
    if (-not $location) {
        return $null;
    }
    if ($Image) {
        $hash = ComputeFileHash $Image;
    }
    foreach ($iter in @(Get-ChildItem -Path $location -Recurse -Include "*.meta" -File)) {
        $fn = $iter.FullName;
        $json = Get-Content $fn | ConvertFrom-Json;
        if ($Caption) {
            if (($json.os -eq $Caption) -and ($script:MetaVersion -eq $json.version)) {
                return $fn -replace ".meta`$", ".disassembly";
            }
        }
        if ($Image) {
            if ($json.hash -eq $hash -and $script:MetaVersion -eq $json.version) {
                return $fn -replace ".meta`$", ".disassembly";
            }
        }
    }
    return $null;
}

#Execute DisassembleSingle on each logical processor.
function BuildDisassembly
{
    param([System.Collections.Generic.List[string]]$Functions,
          [string]$Image,
          [string]$Base)

    $cores = GetLogicalCPUs;
    $cores --;
    if (-not $cores) {
        throw "At least 1 core is required";
    }
    DisassembleParallel $cores $Functions $Image $Base;
}

#Used in rendering, called by parent ahead of printing the descendant.
#.Expand is computed in a different pass.
function DrawDescendantLine
{
    param([Node]$Node,
          [int]$Padding)

    $tright = "$([char]0x251C)";
    $corner = "$([char]0x2514)";
    $vertical = "$([char]0x2502)";
    $horizontal = "$([char]0x2500)";
    $arrow = "$([char]0x25B7)";
    if ($Node.Expand -eq [Expand]::ExpandMiddle) {
        $line = $tright + $horizontal * ($Padding - 2) + $arrow;
    } elseif ($Node.Expand -eq [Expand]::ExpandLast) {
        $line = $corner + $horizontal * ($Padding - 2) + $arrow;
    } elseif ($Node.Expand -eq [Expand]::None) {
        $line = $vertical + " " * ($Padding - 1);
    } else {
        $line = " " * $Padding;
    }
    return $line;
}

function DrawNextLine
{
    param([Node]$Node,
          [int]$Padding)

    $vertical = "$([char]0x2502)";
    if ($Node.Expand -in [Expand]::ExpandMiddle, [Expand]::None) {
        $line = $vertical + " " * ($Padding - 1);
    } elseif ($Node.Expand -eq [Expand]::ExpandLast) {
        $line = " " * $Padding;
    } else {
        $line = "";
    }
    return $line;
}

function PrintRetpoline
{
    param([Node]$Node,
          [string]$Left)

    $multi = $Node.Symbol -split ",";
    $first = $multi[0];
    #$Left + $first + " [$($Node.Expand)]";
    $Left + $first;
    $count = $multi.Count - 1;
    if ($count) {
        $pt = $multi[0].Split("(")[0].Length + 1;
        foreach ($m in $multi[1..$count]) {
            $Left + (" " * $pt) + $m;
        }
    }
}

function PrintIndirect
{
    param([Node]$Node,
          [string]$Left)

    PrintRetpoline $Node $Left;
}

function PrintIAT
{
    param([Node]$Node,
          [string]$Left)

    $impglyph = "$([char]0x27DC)";
    $Left + $impglyph + $Node.Symbol;
}

#.Hint tells what kind of node is being drawn. It happens in PowerShell,
#as opposed to HotPath.cs to give ample space for adjustments.
function PrintSymbol
{
    param([Node]$Node,
          [string]$Left)

    switch ($Node.Hint) {
        ([DrawHint]::Retpoline) {
            PrintRetpoline $Node $Left;
        }
        ([DrawHint]::Indirect) {
            PrintIndirect $Node $Left;
        }
        ([DrawHint]::ImportAddressTable) {
            PrintIAT $Node $Left;
        }
        default {
            $Left + $Node.Symbol;
        }
    }
}

#Draw lines and print symbol for each node.
function DisplayTreeRecursive
{
    param([Node]$Node,
          [string]$Line)

    $padding = $Node.Symbol.Length;
    foreach ($desc in $Node.Dependency) {
        $prev = $Line;
        $inner = DrawDescendantLine $desc $padding;
        PrintSymbol $desc ($Line + $inner);
        if ($desc.Dependency) {
            $Line += DrawNextLine $desc $padding;
            DisplayTreeRecursive $desc $Line;
            $Line = $prev;
        }
    }
}

#Display the root symbols as supplied in CLI, show the cumulated number
#of dependencies in [].
function DisplayTree
{
    param([Node]$Tree)

    if (! $Tree) {
        "Symbol is not present in disassembly.";
        return;
    }
    "$($Tree.Symbol) [$([ParseDisassembly]::GetTreeCumulatedDependecies($Tree))]";

    $padding = $Tree.Symbol.Length;
    [string]$line = "";
    foreach ($desc in $Tree.Dependency) {
        $prev = $line;
        $inner = DrawDescendantLine $desc $padding;
        PrintSymbol $desc ($line + $inner);
        if ($desc.Dependency) {
            $line += DrawNextLine $desc $padding;
            DisplayTreeRecursive $desc $line;
            $line = $prev;
        }
    }
}

function SplitDisassembly
{
    param([string]$Path)

    $delimiter = GetDelimiter $Path;
    $content = Get-Content $Path -Raw;
    [System.Collections.Generic.List[string]]$body = $content.Split($delimiter);
    $body.RemoveAt(0);
    $content = $null;

    return $body;
}

#Split the disassembly file into independent bodies, locate the 1st body
#containing the user symbol. From that root body, parse all dependent bodies
#up to $Depth level. All this happens in the hotpath, a JIT assembly.
function ParseDisassembly
{
    param([string]$Disassembly,
          [string]$Key,
          [int]$Depth,
          [switch]$Callees)

    $json = $Disassembly -replace "disassembly`$", "retpoline";
    $retpoline = [System.Collections.Generic.Dictionary[string, string]]::new();
    if (Test-Path $json -PathType Leaf) {
        $json = Get-Content -Raw $json -ErrorAction SilentlyContinue | ConvertFrom-Json;
        foreach ($iter in $json.PSObject.Properties) {
            $retpoline[$iter.Name] = $iter.Value;
        }
    }
    $delimiter = GetDelimiter $Disassembly;
    $tree = [ParseDisassembly]::CreateTree(($Callees -eq $false), $delimiter, $Disassembly, $Key, $Depth, $script:StopDisassembly, $retpoline);
    return $tree;
}

#When disassembling a large .DMP file, it is useful to have a notice
#about the duration. If it takes more than 5 minutes, based on other
#files that have been previously decompiled, then show the largest
#time previously spent.
function AdviseDuration {
    param ([string]$Image)

    $me = [psobject][ordered]@{
        inproc = $env:COMPUTERNAME;
        cpus = (GetLogicalCPUs) - 1;
        model = (Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" ProcessorNameString).ProcessorNameString;
        size = [int64](Get-Item $Image).Length;
    }
    $closest = [psobject]::new();
    Get-ChildItem -Path $script:Database -Recurse -Include "*.meta" |
    ForEach-Object {
        $json = Get-Content $PSItem -Raw | ConvertFrom-Json;
        if ($script:AdviseLimit -ne 0 -and
            $json.stats.cpus -eq $me.cpus -and
            $json.stats.size -le $me.size -and
            $script:AdviseLimit -lt $json.stats.duration) {
            if ($json.stats.duration -gt $closest.stats.duration) {
                $closest = $json;
            }
        }
    }
    if ($closest.stats.duration) {
        if ($closest.stats.inproc -eq $me.inproc) {
            ("File ""$($closest.image)"" of {0:F2} Mb has been processed in $($closest.stats.duration) seconds." -f ($closest.stats.size/1Mb)) | Write-Host;
        } else {
            ("File ""$($closest.image)"" of {0:F2} Mb has been processed in $($closest.stats.duration) seconds on system $($closest.stats.inproc)." -f $closest.stats.size/1Mb) | Write-Host;
        }
    }
}

#Helper file representing the disassembly origin.
function StoreMeta
{
    param([psobject]$Meta,
          [int]$Seconds,
          [string]$Base)

    $end = [datetime]::now;
    if ($script:Statistics) {
        $Meta.stats = [psobject][ordered]@{
            inproc = $env:COMPUTERNAME;
            cpus = (GetLogicalCPUs) - 1;
            model = (Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" ProcessorNameString).ProcessorNameString;
            duration = [int]$Seconds;
            size = [int64](Get-Item $file).Length;
        }
    }
    $Meta | ConvertTo-Json | Set-Content "$Base.meta";
}

#Helper
function CreateDatabaseEntry
{
    $unique = [guid]::NewGuid().ToString();
    $where = "${script:Database}\$unique";
    New-Item -ItemType Directory $where | Out-Null;
    return "$where\$unique";
}

#Helper
function ConsoleOverwrite
{
    param([string] $Content)

    $count = [Console]::CursorLeft;
    [Console]::CursorLeft = 0;
    " " * $count | Write-Host -NoNewLine;
    [Console]::CursorLeft = 0;
    Write-Host $Content -NoNewLine;
}

#Called by main in UfSymbol.ps1.
function QuerySymbol
{
    param([string]$Symbol,
          [switch]$Down,
          [int]$Depth,
          [string]$Suggestion)

    LoadDefaultValues;
    LoadHotPath;
    $file = $null;
    if (! (Test-Path $Suggestion)) {
        $file = LocateDisassembly -Caption $Suggestion;
    }
    if (! $file -and (Test-Path $Suggestion)) {
        $file = LocateDisassembly -Image $Suggestion;
        if (-not $file) {
            $begin = [datetime]::now;
            $file = $Suggestion;
            AdviseDuration $file;
            $meta = LoadMeta $file;
            $seed = CreateDatabaseEntry;
            ConsoleOverwrite "Downloading symbols, retrieving functions";
            $functions = IdentifyFunctions $file $meta;
            ConsoleOverwrite "Please wait while $($functions.Count) functions are being disassembled";
            BuildDisassembly $functions $file $seed;
            [int]$seconds = ([datetime]::now).Subtract($begin).TotalSeconds;
            ConsoleOverwrite "$($functions.Count) functions disassembled in $seconds seconds`n";
            StoreMeta $meta $seconds $seed;
            "$seed.disassembly", "$seed.meta";
            if (Test-Path "$seed.retpoline") {
                "$seed.retpoline";
            }
            $file = "$seed.disassembly";
        }
    }
    if ($file -and ! $seed) {
        $file;
    }
    $tree = ParseDisassembly $file $Symbol $Depth -Callees:$Down;
    DisplayTree $tree;
}

function ConfigureInteractive
{
    @"

The script requires kd.exe to be installed. Database = collection of disassembly folders
can be placed on a different partition with fast read access.

A timing limit is used to compare previous disassembly processes. If more than ${script:AdviseLimit} seconds
are forecasted for disassembly, then the closest match is printed as a hint.

Statistics can be turned off: .meta file stores the computer where disassembly took place,
the CPU model, disassembly duration and file size.

The configuration does not specify a stop disassembly table. Use the knownuf array to
specify functions that are prevented from processing.

The configuration is placed in "${script:UFSymbolProfile}" file.
It can be edited at will.

"@;

    if (Test-Path $script:UfSymbolProfile) {
        @"

"${script:UFSymbolProfile}" is present.
"@;
        return;
    }
    "1/5) Testing for kd.exe presence";
    $kd = @(Get-Item "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\kd.exe",
            "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\kd.exe" `
            -ErrorAction SilentlyContinue)[0];
    if ($kd) {
        "     kd found at ""$($kd.FullName)""";
        $kd = $kd.FullName;
    } else {
        @"

Install Debugging Tools for Windows:
    https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
    & winsdksetup.exe /features OptionId.WindowsDesktopDebuggers /quiet /ceip off
"@;
        return;
    }
    @"
2/5) Specify the symbols path. This is a folder where the .pdb files are placed before the
     one-time disassembly.
"@;

    do {
        $sp = Read-Host "     Enter path";
        if (Test-Path $sp -PathType Container) {
            $sp = (Get-Item $sp).FullName;
            break;
        }
        "     Path does not represent a folder";
    } while ($true);

    "3/5) Specify the base folder = database where all disassemblies are placed";
    do {
        $db = Read-Host "     Enter path";
        if (Test-Path $db -PathType Container) {
            $db = (Get-Item $db).FullName;
            break;
        }
        "     Path does not represent a folder";
    } while ($true);

    @"
4/5) Specify advise limit in seconds; default is ${script:AdviseLimit}. A comparison
     is printed if the disssasembly is forecasted to outlast this setting.
"@;
    do {
        $al = Read-Host "     Enter seconds";
        if ($al.Trim() -eq "") {
            $al = $script:AdviseLimit;
        }
        try {
            $al = [System.Convert]::ToDecimal($al);
        } catch {
            "     Invalid value";
            continue;
        }
        if ($al -gt 0) {
            $al = [int]$al;
            break;
        }
    } while ($true);

    "5/5) Turn on/off disassembly statistics; default is ${script:Statistics}"
    do {
        $st = Read-Host "     Turn off statistics?[y/N]";
        if (! $st) {
            $st = "N";
        }
    } while ($st -notin "Y", "N");
    if ($st -eq "N") {
        $st = $true;
    } else {
        $st = $false;
    }
    $json = [psobject][ordered] @{
        kd = $kd;
        sympath = $sp;
        database = $db;
        advise = $al;
        statistics = $st;
        knownuf = @();
    };
    $json | ConvertTo-Json | Set-Content $script:UfSymbolProfile;
    @"

Configuration completed.
"@;
    & notepad.exe "${script:UfSymbolProfile}";
}

function ListMetaFiles
{
    param($List)

    LoadDefaultValues;
    $ascending = "$([char]0x2191)";
    if ($List -eq "OS") {
        Get-ChildItem -Recurse -Include "*.meta" -Path $script:Database | 
        Foreach-Object { 
            Get-Content $PSItem | ConvertFrom-Json 
        } | Sort-Object os |
        Format-Table -AutoSize computer, @{ N = "os | basename $ascending"; E = { $PSItem.os; } }, image;
        return;
    }
    Get-ChildItem -Recurse -Include "*.meta" -Path $script:Database | 
    Foreach-Object { 
        Get-Content $PSItem | ConvertFrom-Json 
    } | Sort-Object -Property @{ E = { [int]$PSItem.stats.duration } } |
    Format-Table -AutoSize computer, @{ N = "os | basename"; E = { $PSItem.os; } }, 
                           image, 
                           @{ N = "GB"; E = {
                                if ($null -eq $PSItem.stats.size) {
                                    "";
                                } else {
                                    [decimal]$size = $PSItem.stats.size;
                                    $size /= 1e+9;
                                    if ($size -lt 1e-3) {
                                        "{0:F6}" -f $size;
                                    } elseif ($size -lt 1) {
                                        "{0:F3}" -f $size;
                                    } else {
                                        "{0:F2}" -f $size;
                                    }
                                }
                            } },
                           @{ N = "duration $ascending";
                              E = { [string]$duration = $PSItem.stats.duration;
                                 ("" -eq $duration) ? "": $duration + " s"; } },
                           @{ N = "cpu"; E = { [string]$PSItem.stats.model; } },
                           @{ N = "cores"; E = { [string]$PSItem.stats.cpus } };
}
