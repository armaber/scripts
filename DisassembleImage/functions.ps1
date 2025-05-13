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

$Inflight =  @"
    using System;
    using System.Text;
    using System.IO;
    using System.Collections.Generic;

    public class TrimKD
    {
        public static void HotPath(string source, int from, int to, string destination)
        {
            var istream = new StreamReader(source);
            var ostream = new StreamWriter(destination);

            while (! istream.EndOfStream && to > 0)
            {
                to -= from;
                while (from > 0)
                {
                    istream.ReadLine();
                    from --;
                }
                var str = istream.ReadLine();
                ostream.WriteLine(str);
                to --;
            }
            ostream.Close();
            istream.Close();
        }
    }

    public class TrimDisassembly
    {
        private const int TrimCutout = (int)100E+3;

        public static void HotPath(string delimiter, string path)
        {
            var body = new List<string>();
            var block = new StringBuilder();
            var istream = new StreamReader(path);
            string str;

            while (! istream.EndOfStream)
            {
                var line = istream.ReadLine();
                if (line.StartsWith(delimiter))
                {
                    str = block.ToString();
                    if (str.Length > TrimCutout &&
                        str.Contains("Flow analysis was incomplete, some code may be missing"))
                    {
                        block.Clear();
                    } else
                    {
                        body.Add(str);
                        block.Clear();
                        block.Append(line);
                        block.Append("\n");
                    }
                } else
                {
                    block.Append(line);
                    block.Append("\n");
                }
            }
            istream.Close();
            if (block.Length > 0)
            {
                str = block.ToString();
                if (! (str.Length > TrimCutout &&
                       str.Contains("Flow analysis was incomplete, some code may be missing")))
                {
                    body.Add(str);
                }
            }
            var ostream = new StreamWriter(path);
            foreach (var iter in body)
            {
                ostream.Write(iter);
            }
            ostream.Close();
        }
    }
"@;
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
    Add-Type -TypeDefinition $script:Inflight -Language CSharp;
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
        $to = @(Select-String "\.logclose`$" $kdlogfile).LineNumber[-1];
        $to --;
        [TrimKD]::HotPath($kdlogfile, $from, $to, $OutputFile);
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
                    (($gi.VersionInfo -split "`r`n" | Where-Object { $_ -like "ProductVersion:*" }) -split ":\s+")[-1];
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
    param([string]$Path)

    $delimiter = Select-String "(\d+: kd> )" $Path -List;
    if ($delimiter) {
        $delimiter = $delimiter.Matches.Value;
    } else {
        $delimiter = "0:000> ";
    }
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

    [TrimDisassembly]::HotPath($delimiter, $Path);
}

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

function DisassembleParallel
{
    param([int]$Cores,
          [System.Collections.Generic.List[string]]$Functions,
          [string]$Image,
          [string]$Base)

    $instate = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault();
    "KD", "Database", "Sympath", "Inflight" | ForEach-Object {
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
"LoadHotPath", "RunKd", "DisassembleSingle", "Trim0000Cr" | ForEach-Object {
    "function $PSItem {" + (Get-Content function:\$PSItem) + "}";
}
)

LoadHotPath;
DisassembleSingle `$Functions $from $to "$Image" "$Base-$i.txt";
Trim0000Cr "$Base-$i.txt";
"@;
        $space.AddScript($script) | Out-Null;
        $space.RunspacePool = $pool;
        $nr = [psobject] @{
            runspace = $space;
            state = $space.BeginInvoke();
        };
        $runspaces.Add($nr);
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
    BuildRetpoline $disassembly $Image $Base;
}

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
.reload
$($Meta.module | Foreach-Object {
"x /v /f $PSItem!*`n";
})
"@ $Path;
    $functions = [System.Collections.Generic.List[string]]::new();
    $content | Foreach-Object {
        if (($PSItem -notlike "*[??]*") -and
            ($PSItem -notlike "*WPP_RECORDER*") -and
            ($PSItem -notlike "*`$thunk`$*") -and
            ($PSItem -notlike "*!`$`$*") -and
            ($PSItem -match "^(pub|prv) func "))
        {
            $functions.Add("uf " + ($PSItem -split "\s+")[4]);
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

enum Expand {
    #There are no dependencies. There is a sibling that has dependencies
    None;
    #There are no dependencies for all the remaining siblings.
    Empty;
    #This node has dependencies. Sibling nodes have dependencies.
    ExpandMiddle;
    #This is the last node that has dependencies.
    ExpandLast;
};

class Node {
    [string]$Symbol;
    [string]$Disassembly;
    [Expand]$Expand;
    [Node[]]$Dependency;
};

function IdentifySymbol
{
    param([string]$Key,
          [System.Collections.Generic.List[string]]$Body)

    $level = $Body.Where( { $PSItem.Contains($Key) } );
    return $level;
}

function IdentifySections
{
    param([Node]$Node,
          [System.Collections.Generic.List[string]]$Body,
          [switch]$Callees)

    if ($Callees) {
        $symbol = [System.Collections.Generic.List[string]]::new();
        [regex]::Matches($Node.Disassembly, "call    (\w+!.+?)\s.+").ForEach( {
            $symbol.Add("uf $($PSItem.Groups[1].Value)");
        } );
        if (! $symbol.Count) {
            return $null;
        }
        $symbol = $symbol | Select-Object -Unique;
        $section = [System.Collections.Generic.List[string]]::new();
        foreach ($sym in $symbol) {
            $s = IdentifySymbol "$sym`n" $Body;
            if (! $s) {
                #We've found a callee that has no body due to trimming
                #or it belongs to a different module.
                foreach ($stop in $script:StopDisassembly) {
                    if ($sym -match $stop) {
                        $s = $PSItem;
                        break;
                    }
                }
                if (! $s) {
                    $s = "$sym (N/A)";
                }
            }
            $section.Add($s);
        }
    } else {
        $section = IdentifySymbol "call    $($Node.Symbol -replace ""uf\s+"","""") " $Body;
    }
    return $section;
}

function DecodeIndirectCall
{
    param([string]$Body,
          [psobject]$Json)

    $indirect = & {
        [regex]::Matches($iter.Disassembly, "mov\s+rax,qword ptr \[(\w+!.+?)\s.+?\][\s\S]+?call\s+\w+!guard_dispatch_icall") |
        ForEach-Object { $PSItem.Groups[1].Value } | Select-Object -Unique;
    };
    if (! $indirect) {
        return "N/A";
    }
    $translated = [System.Collections.Generic.List[string]]::new();
    foreach ($i in $indirect) {
        $r = $Json.$i;
        if ($r) {
            $translated.Add("$i=$r");
        } else {
            $translated.Add($i);
        }
    }
    return $translated -join ", ";
}
function IdentifyBodyRecursive
{
    param([int]$Current,
          [int]$Depth,
          [Node[]]$Level,
          [System.Collections.Generic.List[string]]$Body,
          [switch]$Callees,
          [psobject]$Json)

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
        $next = IdentifySections $iter $Body -Callees:$Callees;
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
                $iter.Dependency += $node;
                $node = $null;
            }
        }
        if ($iter.Dependency) {
            IdentifyBodyRecursive $Current $Depth $iter.Dependency $Body -Callees:$Callees -Json:$Json;
        }
    }
}

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

function PrintSymbol
{
    param([Node]$Node,
          [string]$Left)

    $multi = $Node.Symbol -split ", ";
    #$Left + $multi[0] + "[$($Node.Expand)]";
    $Left + $multi[0];
    $count = $multi.Count - 1;
    if ($count) {
        $pt = $multi[0].Split("(")[0].Length + 1;
        foreach ($m in $multi[1..$count]) {
            $Left + (" " * $pt) + $m;
        }
    }

}
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

function AddExpand
{
    param([Node[]]$Tree)

    $el = $null;
    foreach ($iter in $Tree) {
        if ($iter.Dependency) {
            $iter.Expand = [Expand]::ExpandLast;
            if ($el) {
                $el.Expand = [Expand]::ExpandMiddle;
            }
            $el = $iter;
        } else {
            $iter.Expand = [Expand]::None;
        }
        if ($iter.Dependency) {
            AddExpand $iter.Dependency;
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

    if (! $Tree) {
        "Symbol is not present in disassembly.";
        return;
    }
    $Tree.Symbol;

    if ($Tree.Dependency) {
        AddExpand $Tree.Dependency;
    } else {
        $Tree.Expand = [Expand]::None;
    }
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

    $delimiter = Select-String "(\d+: kd> )" $Path -List;
    if ($delimiter) {
        $delimiter = $delimiter.Matches.Value;
    } else {
        $delimiter = "0:000> ";
    }
    $content = Get-Content $Path -Raw;
    [System.Collections.Generic.List[string]]$body = $content.Split($delimiter);
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
    $section = IdentifySymbol "uf $Key`n" $body;
    if ($section) {
        $tree.Symbol = "uf $Key";
        $tree.Disassembly = $section;
        $section = IdentifySections $tree $body -Callees:$Callees;
    } else {
        $section = IdentifySymbol $Key $body;
        if (! $section) {
            return $null;
        }
        $tree.Symbol = $Key;
    }
    foreach ($r in $section) {
        $node = [Node]::new();
        if ($r -match ".+") {
            $node.Symbol = $Matches[0];
            if ($Callees -and ($node.Symbol -match "uf \w+!guard_dispatch_icall")) {
                $node.Disassembly = $tree.Disassembly;
            } else {
                $node.Disassembly = $r;
            }
        }
        $tree.Dependency += $node;
        $node = $null;
    }
    if (! $tree.Dependency) {
        return $tree;
    }
    IdentifyBodyRecursive 1 $Depth $tree.Dependency $body -Callees:$Callees -Json:$Json;
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
