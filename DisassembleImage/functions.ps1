$KD = "";
$Database = "";
$Sympath = "";
$MetaVersion = 1;
$Statistics = $true;
#Print a warning if other files have been decompiled in 5 minutes or more.
$TestDuration = 300;
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
function LoadScriptProfile
{
    if (Test-Path $script:UfSymbolProfile) {
        $json = Get-Content -Raw $script:UfSymbolProfile | ConvertFrom-Json;
        $script:KD = $json.kd;
        $script:Database = $json.database;
        $script:Sympath = $json.sympath;
        $script:Statistics = $json.statistics;
        $script:StopDisassembly = $json.knownuf;
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

function GetLogicalCPUs
{
    return [int](Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum;
}

function ComputeFileHash
{
    param([string]$Path)

    return (Get-FileHash -Algorithm SHA512 $Path).Hash;
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
    $Commands = ($Commands -replace ("(`r?`n)+", "`n")).Trim();
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
        if (($Commands -split "`r?`n")[0] -like ".reload*") {
            $from = ($Commands -split "`r?`n")[1];
            #from can be "uf nt!NtQueryBootOptions$filt$0", where Select-String will stop at 1st $,
            #representing the end of line
            $from2 = [regex]::Escape($from);
            $from = @(Select-String "$from2`$" $kdlogfile).LineNumber[0];
            $from --;
        } else {
            $from = @(Select-String "Opened log file" $kdlogfile).LineNumber[0];
        }
        $to = @(Select-String ".logclose`$" $kdlogfile).LineNumber[-1];
        #ReadCount accelerates huge files with M lines.
        (Get-Content $kdlogfile -ReadCount $to -First $to)[$from .. ($to - 2)] | Add-Content $OutputFile;
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
                    (($gi.VersionInfo -split "`r`n" | Where-Object { $_ -like "ProductVersion:*" }) -split ":\s+")[-1];
                };
                image = $fn;
                hash = $hash;
                module = [string[]]@();
            };
}

function DisassembleSingle
{
    param($Functions,
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

function BuildRetpoline
{
    param([string]$Disassembly,
          [string]$Image,
          [string]$Path)

    if ($Image -notlike "*.dmp") {
        return;
    }
    $body = SplitDisassembly $Disassembly;
    $fbs = $body | Where-Object {
        $PSItem -match "call    \w+!guard_dispatch_icall";
    }
    if (! $fbs) {
        return;
    }
    $dps = [System.Collections.Generic.List[string]]::new();
    $pattern = [regex]::new("mov\s+rax,qword ptr \[(?<key>\w+!\w+\+.+?)\s.+?\][\s\S]+?call\s+\w+!guard_dispatch_icall", "Compiled, CultureInvariant");
    for ($i = 0; $i -lt $fbs.Count; $i ++) {
        $fb = $fbs[$i];
        foreach ($m in [regex]::Matches($fb, $pattern)) {
            $key = $m.Groups["key"].Value;
            $dps.Add("dps $Key L1");
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
    $pattern = [regex]::new("dps (?<orig>.+?) L1`n([0-9a-f]{8}(``[0-9a-f]{8})?\s+){2}(?<part>\w+!\w+)", "Compiled, CultureInvariant");
    foreach ($m in [regex]::Matches($content, $pattern)) {
        $from = $m.Groups["orig"].Value;
        $to = $m.Groups["part"].Value;
        Add-Member -NotePropertyName $from -NotePropertyValue $to -InputObject $result;
    }
    $result | ConvertTo-Json | Set-Content $Path;
}

function DisassembleParallel
{
    param([int]$Cores,
          [string[]]$Functions,
          [string]$Image,
          [string]$Base)

    $instate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault();
    "KD", "Database", "Sympath" | ForEach-Object {
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
    $runspaces = @();
    for ($i = 0; $i -lt $Cores; $i ++) {
        $from = $i * $size;
        $to = $from + $size - 1;
        if ($i -eq $Cores - 1) {
            $to =  $count - 1;
        }
        $space = [powershell]::Create();
        $script = @"
$(
"RunKd", "DisassembleSingle" | ForEach-Object {
    "function $PSItem {" + (Get-Content function:\$PSItem) + "}";
}
)
DisassembleSingle `$Functions $from $to "$Image" "$Base-$i.txt";
"@;
        $space.AddScript($script) | Out-Null;
        $space.RunspacePool = $pool;
        $runspaces += [psobject] @{
            runspace = $space;
            state = $space.BeginInvoke();
        };
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
    $os = [System.IO.FileStream]::new($disassembly, "Append");
    for ($i = 1; $i -lt $Cores; $i ++) {
        $is = [System.IO.FileStream]::new("$Base-$i.txt", "Open");
        $is.CopyTo($os);
        $is.Close();
        Remove-Item "$Base-$i.txt";
    }
    $os.Close();
    #Add this delimiter to facilitate regex. It is not in use, because -split
    #gives better performance.
    "0: kd> uf null!EOI" | Add-Content $disassembly;
    (Get-Content $disassembly -Raw).Replace("`r", "") | Set-Content $disassembly;
    BuildRetpoline $disassembly $Image "$Base.retpoline";
}

function IdentifyFunctions
{
    param([string]$Path,
          $Meta)

    $gi = Get-Item $Path;
    if ($gi.Extension -eq ".dmp") {
        $Meta.module = "nt", "pci", "acpi", "hal";
    } else {
        $Meta.module = @(, $gi.BaseName);
    }
    $content = RunKd @"
.reload
$($Meta.module | Foreach-Object {
"x /v /f $PSItem!*`n";
})
"@ $Path;
    $functions = @();
    $content | Foreach-Object {
        if (($PSItem -notlike "*[??]*") -and
            ($PSItem -notlike "*WPP_RECORDER*") -and
            ($PSItem -notlike "*`$thunk`$*") -and
            ($PSItem -notlike "*!`$`$*") -and
            ($PSItem -match "^(pub|prv) func "))
        {
            $functions += "uf " + ($PSItem -split "\s+")[4];
        }
    }
    #There may be duplicate functions at different addresses.
    #0:000> x /v /f /n ntoskrnl!IopVerifierExAllocatePoolWithQuota
    #prv func   00000001`4021f5e0  2b7 ntoskrnl!IopVerifierExAllocatePoolWithQuota (void)
    #prv func   00000001`405074fc   6f ntoskrnl!IopVerifierExAllocatePoolWithQuota (void)
    #Take only one. It is possible to uf by address "uf 00000001`4021f5e0".
    $functions = $functions | Sort-Object -Unique;
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

#Look in all .meta, take the one that has the Operating System matching the caption
#and return the path.
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

function BuildDisassembly
{
    param([string[]]$Functions,
          [string]$Image,
          [string]$Base)

    $cores = GetLogicalCPUs;
    $cores --;
    if (-not $cores) {
        throw "At least 1 core is required";
    }
    DisassembleParallel $cores $Functions $Image $Base;
}

enum Expand {
    None;
    Empty;
    ExpandMiddle;
    ExpandLast;
};

class Node {
    [string]$Symbol;
    [string]$Disassembly;
    [Expand]$Expand;
    [Node[]]$Descendants;
};

function IdentifySymbol
{
    param([string]$Key,
          [string[]]$Body)

    $level = @($Body | Where-Object { $PSItem.Contains($Key) });
    return $level;
}

function IdentifyBodies
{
    param([Node]$Block,
          [string[]]$Body,
          [switch]$Callees)

    if ($Callees) {
        $fns = @();
        [regex]::Matches($Block.Disassembly, "call    (\w+!.+?)\s.+") | ForEach-Object {
            $fns += "uf $($PSItem.Groups[1].Value)";
        }
        if (! $fns) {
            return $null;
        }
        $fns = $fns | Select-Object -Unique;
        $fbs = @();
        $fns | ForEach-Object {
            $fbs += IdentifySymbol "$PSItem`n" $Body;
        }
    } else {
        $fbs = IdentifySymbol "call    $($Block.Symbol -replace ""uf\s+"","""") " $Body;
    }
    return $fbs;
}

function DecodeIndirectCall
{
    param([string]$Body,
          $Json)
    
    $indirect = & {
        [regex]::Matches($iter.Disassembly, "mov\s+rax,qword ptr \[(\w+!.+?)\s.+?\][\s\S]+?call\s+\w+!guard_dispatch_icall") |
        ForEach-Object { $PSItem.Groups[1].Value } | Select-Object -Unique;
    };
    if (! $indirect) {
        return "N/A";
    }
    $translated = @();
    foreach ($i in $indirect) {
        $r = $Json.$i;
        if ($r) {
            $translated += "$i=$r";
        } else {
            $translated += $i;
        }
    }
    return $translated -join ", ";
}
function IdentifyBodyRecursive
{
    param([int]$Current,
          [int]$Depth,
          [Node[]]$Level,
          [string[]]$Body,
          [switch]$Callees,
          $Json)

    if ($Callees) {
        foreach ($iter in $Level) {
            if ($iter.Symbol -match "uf \w+!guard_dispatch_icall") {
                $indirect = DecodeIndirectCall $iter.Disassembly $Json;
                $iter.Symbol += " ($indirect)";
            }
        }
    }
    if ($Current -ge $Depth) {
        return;
    }
    $Current ++;
    foreach ($iter in $Level) {
        $skip = $false;
        foreach ($stop in $script:StopDisassembly) {
            if ($iter.Symbol -match $stop) {
                #("-"*80), "Symbol = $($iter.Symbol)" | Write-Host;
                $skip = $true;
                break;
            }
        }
        if ($skip) {
            continue;
        }
        $next = IdentifyBodies $iter $Body -Callees:$Callees;
        if (! $next) {
            continue;
        }
        $next | ForEach-Object {
            if ($PSItem -match ".+") {
                $node = [Node]::new();
                $node.Symbol = $Matches[0];
                if ($Callees -and ($node.Symbol -match "uf \w+!guard_dispatch_icall")) {
                    $node.Disassembly = $iter.Disassembly;
                } else {
                    $node.Disassembly = $PSItem;
                }
                $iter.Descendants += $node;
                $node = $null;
            }
        }
        if ($iter.Descendants) {
            IdentifyBodyRecursive $Current $Depth $iter.Descendants $Body -Callees:$Callees -Json:$Json;
        }
    }
}

function DisplayTreeRecursive
{
    param([Node]$Node,
          [string]$Line)

    $padding = $Node.Symbol.Length;
    foreach ($desc in $Node.Descendants) {
        $pline = $Line;
        if ($desc.Expand -eq [Expand]::ExpandMiddle) {
            $cline = "$([char]0x251C)" + ("$([char]0x2500)" * ($padding - 2)) + "$([char]0x25B7)";
        } elseif ($desc.Expand -eq [Expand]::ExpandLast) {
            $cline = "$([char]0x2514)" + ("$([char]0x2500)" * ($padding - 2)) + "$([char]0x25B7)";
        } elseif ($desc.Expand -eq [Expand]::None) {
            $cline = "$([char]0x2502)" + (" " * ($padding - 1));
        } else {
            $cline = " " * $padding;
        }
        $multi = @($desc.Symbol -split ", ");
        #$Line + $cline + $multi[0] + "[$($desc.Expand)]";
        $Line + $cline + $multi[0];
        $count = $multi.Count - 1;
        if ($count) {
            $pt = ($multi[0] -split "\(")[0].Length + 1;
            foreach ($m in $multi[1..$count]) {
                $Line + $cline + (" " * $pt) + $m;
            }
        }
        if ($desc.Expand -in [Expand]::ExpandMiddle, [Expand]::None) {
            $Line += "$([char]0x2502)" + (" " * ($padding - 1));
        } elseif ($desc.Expand -eq [Expand]::ExpandLast) {
            $Line += " " * $padding;
        }
        if ($desc.Descendants) {
            DisplayTreeRecursive $desc $Line;
        }
        $Line = $pline;
    }
}

function AddExpand
{
    param([Node[]]$Tree)

    $el = $null;
    foreach ($iter in $Tree) {
        if ($iter.Descendants) {
            $iter.Expand = [Expand]::ExpandLast;
            if ($el) {
                $el.Expand = [Expand]::ExpandMiddle;
            }
            $el = $iter;
        } else {
            $iter.Expand = [Expand]::None;
        }
        if ($iter.Descendants) {
            AddExpand $iter.Descendants;
        }
    }
    $i = $Tree.Count - 1;
    while ($Tree[$i].Expand -eq [Expand]::None) {
        if ($i -ge 0) {
            $i --;
        } else {
            break;
        }
    }
    for ($i ++; $i -lt $Tree.Count; $i ++) {
        $Tree[$i].Expand = [Expand]::Empty;
    }
}
function DisplayTree
{
    param([Node]$Tree)

    Write-Host -ForegroundColor Black -BackgroundColor White $Tree.Symbol -NoNewline;
    Write-Host;

    if ($Tree.Descendants) {
        AddExpand $Tree.Descendants;
    } else {
        $Tree.Expand = [Expand]::None;
    }
    $padding = $Tree.Symbol.Length;
    [string]$line = "";
    foreach ($desc in $Tree.Descendants) {
        $pline = $line;
        if ($desc.Expand -eq [Expand]::ExpandMiddle) {
            $cline = "$([char]0x251C)" + ("$([char]0x2500)" * ($padding - 2)) + "$([char]0x25B7)";
        } elseif ($desc.Expand -eq [Expand]::ExpandLast) {
            $cline = "$([char]0x2514)" + ("$([char]0x2500)" * ($padding - 2)) + "$([char]0x25B7)";
        } elseif ($desc.Expand -eq [Expand]::None) {
            $cline = "$([char]0x2502)" + (" " * ($padding - 1));
        } else {
            $cline = " " * $padding;
        }
        $multi = @($desc.Symbol -split ", ");
        #$line + $cline + $multi[0] + "[$($desc.Expand)]";
        $line + $cline + $multi[0];
        $count = $multi.Count - 1;
        if ($count) {
            $pt = ($multi[0] -split "\(")[0].Length + 1;
            foreach ($m in $multi[1..$count]) {
                $line + $cline + (" " * $pt) + $m;
            }
        }
        if ($desc.Expand -in [Expand]::ExpandMiddle, [Expand]::None) {
            $line += "$([char]0x2502)" + (" " * ($padding - 1));
        } elseif ($desc.Expand -eq [Expand]::ExpandLast) {
            $line += " " * $padding;
        }
        if ($desc.Descendants) {
            DisplayTreeRecursive $desc $line;
        }
        $line = $pline;
    }
}

function SplitDisassembly
{
    param([string]$Image)

    if (Select-String -Quiet "^\d+:\d+> " $Disassembly) {
        $kdprompt = "\d+:\d+> ";
    } else {
        $kdprompt = "\d+: kd> "
    }
    $content = Get-Content -Raw $Disassembly;
    $body = $content -split $kdprompt;
    $content = $null;
    return $body;
}
function ParseDisassembly
{
    param([string]$Disassembly,
          [string]$Key,
          [int]$Depth,
          [switch]$Callees)
    
    $body = SplitDisassembly $Disassembly;
    $json = $Disassembly -replace "disassembly`$", "retpoline";
    $json = Get-Content -Raw $json -ErrorAction SilentlyContinue | ConvertFrom-Json;
    $tree = [Node]::new();
    $fbs = IdentifySymbol "uf $Key`n" $body;
    if ($fbs) {
        $tree.Symbol = "uf $Key";
        $tree.Disassembly = $fbs;
        $fbs = IdentifyBodies $tree $body -Callees:$Callees;
    } else {
        $fbs = IdentifySymbol $Key $body;
        if (! $fbs) {
            return $null;
        }
        $tree.Symbol = $Key;
    }
    foreach ($fnb in $fbs) {
        $node = [Node]::new();
        if ($fnb -match ".+") {
            $node.Symbol = $Matches[0];
            if ($Callees -and ($node.Symbol -match "uf \w+!guard_dispatch_icall")) {
                $node.Disassembly = $tree.Disassembly;
            } else {
                $node.Disassembly = $fnb;
            }
        }
        $tree.Descendants += $node;
        $node = $null;
    }
    if (! $tree.Descendants) {
        return $tree;
    }
    IdentifyBodyRecursive 1 $Depth $tree.Descendants $body -Callees:$Callees -Json:$Json;
    return $tree;
}

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
        if ($script:TestDuration -ne 0 -and
            $json.stats.cpus -eq $me.cpus -and
            $json.stats.size -le $me.size -and
            $script:TestDuration -lt $json.stats.duration) {
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

function StoreMeta
{
    param([psobject]$Meta,
          [datetime]$Begin,
          [string]$Base)

    $end = [datetime]::now;
    if ($script:Statistics) {
        $Meta.stats = [psobject][ordered]@{
            inproc = $env:COMPUTERNAME;
            cpus = (GetLogicalCPUs) - 1;
            model = (Get-ItemProperty "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" ProcessorNameString).ProcessorNameString;
            duration = [int]$end.Subtract($Begin).TotalSeconds;
            size = [int64](Get-Item $file).Length;
        }
    }
    $Meta | ConvertTo-Json | Set-Content "$Base.meta";
}

function CreateDatabaseEntry
{
    $unique = [guid]::NewGuid().ToString();
    $where = "${script:Database}\$unique";
    New-Item -ItemType Directory $where | Out-Null;
    return "$where\$unique";
}

#TODO  Need a validate parms before launching the main script
#      Benefit: an easy error will surface early, instead of
#      waiting for minutes and then crashing.
function QuerySymbol
{
    param([string]$Symbol,
          [switch]$Down,
          [int]$Depth,
          [switch]$AsText,
          [string]$Suggestion)

    LoadDefaultValues;
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
            $functions = IdentifyFunctions $file $meta;
            BuildDisassembly $functions $file $seed;
            StoreMeta $meta $begin $seed;
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
