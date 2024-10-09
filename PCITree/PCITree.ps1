<#
.SYNOPSIS
Display the PCI devices together with their BDF

.DESCRIPTION
Launch it without admin privileges. For each devnode display: BDF, DeviceID, Service, Caption, BARs, Driver Stack.

.PARAMETER AsHTML
Generate html file on the current directory. The layout is identical to AsVT.

.PARAMETER AsVT
Highlight BDF status, display the tree on the console using virtual terminal escape sequences.

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


function ImportNative
{
    $co = [System.CodeDom.Compiler.CompilerParameters]::new();
    $co.CompilerOptions += "/unsafe";

    Add-Type -CompilerParameters $co @"
        using System;
        using System.Runtime.InteropServices;

        [StructLayout(LayoutKind.Sequential)]
        unsafe public struct MEM_RESOURCE
        {
            public UInt32 MD_Count;
            public UInt32 MD_Type;
            public UInt64 MD_Alloc_Base;
            public UInt64 MD_Alloc_End;
            public fixed UInt32 Unused[11];
        };

        [StructLayout(LayoutKind.Sequential)]
        public struct SP_DEVINFO_DATA
        {
            public UInt32 cbSize;
            public Guid ClassGuid;
            public UInt32 DevInst;
            public IntPtr Reserved;
        };    

        public static class NativeMethod {
            [DllImport("ntdll.dll")]
                public static extern int
                    NtSetTimerResolution(int DesiredResolution,
                                         bool SetResolution,
                                         ref Int32 CurrentResolution);
            [DllImport("kernel32.dll")]
                public static extern int
                    GetLargePageMinimum();
            [DllImport("kernel32.dll")]
                public static extern bool
                    GetNumaHighestNodeNumber(ref Int32 HighestNodeNumber);

            [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
            public static extern IntPtr
                SetupDiGetClassDevs(IntPtr DeviceClasses,
                                    [MarshalAs(UnmanagedType.LPTStr)] string Enumerator,
                                    IntPtr Hwnd,
                                    UInt32 Flags);
            [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
            public static extern bool
                SetupDiEnumDeviceInfo(IntPtr DeviceInfoSet,
                                      UInt32 MemberIndex,
                                      ref SP_DEVINFO_DATA DeviceInfoData);
            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            public static extern UInt32
                CM_Get_DevNode_Status(ref UInt32 Status,
                                      ref UInt32 Problem,
                                      IntPtr DevInst,
                                      UInt32 Flags);
            [DllImport("cfgmgr32.dll", CharSet = CharSet.Unicode)]
            public static extern UInt32
                CM_Get_Device_ID(IntPtr DevInst,
                                 IntPtr Buffer,
                                 UInt32 Size,
                                 UInt32 Flags);
            [DllImport("setupapi.dll", CharSet = CharSet.Unicode)]
            public static extern bool
                SetupDiDestroyDeviceInfoList(IntPtr Device);

            [DllImport("cfgmgr32.dll")]
            public static extern UInt32
                CM_Get_First_Log_Conf(ref IntPtr Conf,
                                      IntPtr DevInst,
                                      UInt32 Flags);
            [DllImport("cfgmgr32.dll")]
            public static extern UInt32
                CM_Get_Next_Res_Des(ref IntPtr ResDes,
                                    IntPtr Previous,
                                    UInt32 ForResource,
                                    ref UInt32 ResourceID,
                                    UInt32 Flags);
            [DllImport("cfgmgr32.dll")]
            public static extern UInt32
                CM_Get_Res_Des_Data(IntPtr ResDes,
                                    ref MEM_RESOURCE Buffer,
                                    UInt32 BufferLen,
                                    UInt32 Flags);
            [DllImport("cfgmgr32.dll")]
            public static extern UInt32
                CM_Free_Res_Des_Handle(IntPtr ResDes);
            [DllImport("cfgmgr32.dll")]
            public static extern UInt32
                CM_Free_Log_Conf_Handle(IntPtr Conf);
        };

        public class DevnodeHR {
            public string BDF;
            public string DeviceID;
            public string MatchingID;
            public string Multiple;
            public string LinkMPS;
            public string ACS;
            public string Human;
            public string BARs;
            public string CompatibleID;
            public string NUMA;
            public string[] DriverStack;
        };
"@;
}

function GetPCIeBARs
{
    $DIGCF_ALLCLASSES = 4;
    $DIGCF_PRESENT = 2;
    $ResType_All = 0;
    $ALLOC_LOG_CONF = 2;
    $ResType_Mem = 1;
    $ResType_MemLarge = 7;

    [SP_DEVINFO_DATA]$data = New-Object SP_DEVINFO_DATA;
    [MEM_RESOURCE]$desc = New-Object MEM_RESOURCE;
    $p = "PCI";
    $x = [NativeMethod]::SetupDiGetClassDevs(0, $p, 0, $DIGCF_ALLCLASSES + $DIGCF_PRESENT);

    $data.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($data);
    [UInt32]$le = 512;
    [UInt32]$st = 0;
    [UInt32]$pb = 0;
    [UInt32]$sz = [System.Runtime.InteropServices.Marshal]::SizeOf($desc);
    $id = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(2 * $le);
    [IntPtr]$conf = 0;
    [IntPtr]$start = 0;
    [IntPtr]$res = 0;
    [UInt32]$rid = 0;

    [PSObject[]]$pe = & {

        for ($m = 0; [NativeMethod]::SetupDiEnumDeviceInfo($x, $m, [ref]$data); $m ++) {

            $c = [NativeMethod]::CM_Get_DevNode_Status([ref]$st, [ref]$pb, $data.DevInst, 0);
            if ($CR_NO_SUCH_VALUE, $CR_NO_SUCH_DEVINST -contains $c) {
                continue;
            }

            $le = 512;
            $c = [NativeMethod]::CM_Get_Device_ID($data.DevInst, $id, $le, 0);
            if ($c) {
                continue;
            }
            $di = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($id);
            $c = [NativeMethod]::CM_Get_First_Log_Conf([ref]$conf, $data.DevInst, $ALLOC_LOG_CONF);
            if ($c) {
                continue;
            }

            $start = $conf;
            $c = [NativeMethod]::CM_Get_Next_Res_Des([ref]$res, $conf, $ResType_All, [ref]$rid, 0);
            $bar = @();

            while ($c -eq 0) {
                $conf = $res;
                if ($ResType_MemLarge, $ResType_Mem -contains $rid) {
                    [NativeMethod]::CM_Get_Res_Des_Data($res, [ref]$desc, $sz, 0) | Out-Null;
                    if ($desc.MD_Alloc_End -le [UInt32]::MaxValue) {
                        $pad = 8;
                    } else {
                        $pad = 16;
                    }
                    $bar += "0x"+("{0:X}" -f $desc.MD_Alloc_Base).PadLeft($pad, '0') + "-0x" +
                            ("{0:X}" -f $desc.MD_Alloc_End).PadLeft($pad, '0');
                }
                $c = [NativeMethod]::CM_Get_Next_Res_Des([ref]$res, $conf, $ResType_All, [ref]$rid, 0);
                [NativeMethod]::CM_Free_Res_Des_Handle($conf) | Out-Null;
            }

            [NativeMethod]::CM_Free_Log_Conf_Handle($start) | Out-Null;

            if ($bar.Count) {
                [PSObject]@{
                    DeviceID = $di;
                    BAR = $bar;
                };
            }
        }
    };

    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($id);
    [NativeMethod]::SetupDiDestroyDeviceInfoList($x) | Out-Null;

    return $pe;
}

function PrintHeader([Switch]$AsHTML)
{
    $sys = Get-CimInstance Win32_ComputerSystem;
    $rs =  @(Get-CimInstance Win32_PhysicalMemory -Filter "ConfiguredClockSpeed != 0")[0].ConfiguredClockSpeed;
    $bios = Get-CimInstance Win32_BIOS;
    $cpu = @(Get-CimInstance Win32_Processor -Property Name, Caption, AddressWidth, NumberOfEnabledCore, NumberOfLogicalProcessors);

    [Int]$cr = 0;
    [NativeMethod]::NtSetTimerResolution(10000, $false, [ref]$cr) | Out-Null;
    $lp = [NativeMethod]::GetLargePageMinimum();
    [Int]$hn = 0;
    [NativeMethod]::GetNumaHighestNodeNumber([ref]$hn) | Out-Null;
    [String]$crs = "$cr";
    if (10e+6 % $cr) {
        $crs += " ~ ";
    } else {
        $crs += " = "
    }
    $crs += "" + [Int](10e+6 / $cr) + "Hz";
    $hvci = "off";
    if ((Get-ItemProperty "HKLM:\System\CurrentControlSet\Control\CI\State" HVCIEnabled -EA SilentlyContinue).HVCIEnabled) {
        $hvci = "on";
    }
    $cpu0 = $cpu[0];
    $box_line = $sys.Manufacturer+", "+$sys.Model+", "+("{0:F2}" -f ($sys.TotalPhysicalMemory/1GB))+"GB @${rs}MHz, Timer $crs, Large $lp, NUMA "+($hn+1)+", HVCI $hvci";
    $cpu_line = $cpu0.Name.Replace("@ ", "@")+", "+$cpu0.Caption+", "+$cpu0.AddressWidth+" bit, "+$cpu0.NumberOfEnabledCore+" cores, "+$cpu0.NumberOfLogicalProcessors+" threads";
    $cpu_line = "$($cpu.Count)S, $cpu_line";
    $bios_line = $bios.Manufacturer + ", " + $bios.Name + ", " + $bios.Version + ", SecureBoot ";
    $sb = [Int](Get-ItemProperty -EA SilentlyContinue HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State).UEFISecureBootEnabled;
    if ($sb) {
        $bios_line += "on";
    } else {
        $bios_line += "off";
    }

    if ($AsHTML) {
        return @"
        <table>
            <tr>
                <td class="wheader">BOX:</td><td>$box_line</td>
            </tr>
            <tr>
                <td>BIOS:</td><td class="wheader">$bios_line</td>
            </tr>
            <tr>
                <td class="wheader">CPU:</td><td>$cpu_line</td>
            </tr>
        </table>
"@;
    } else {
        "BOX: $box_line", "BIOS: $bios_line", "CPU: $cpu_line", "" | Write-Host;
    }
}

$script:ProblemNames = @(
    @{"CM_PROB_NOT_CONFIGURED" = 0x00000001},
    @{"CM_PROB_DEVLOADER_FAILED" = 0x00000002},
    @{"CM_PROB_OUT_OF_MEMORY" = 0x00000003},
    @{"CM_PROB_ENTRY_IS_WRONG_TYPE" = 0x00000004},
    @{"CM_PROB_LACKED_ARBITRATOR" = 0x00000005},
    @{"CM_PROB_BOOT_CONFIG_CONFLICT" = 0x00000006},
    @{"CM_PROB_FAILED_FILTER" = 0x00000007},
    @{"CM_PROB_DEVLOADER_NOT_FOUND" = 0x00000008},
    @{"CM_PROB_INVALID_DATA" = 0x00000009},
    @{"CM_PROB_FAILED_START" = 0x0000000A},
    @{"CM_PROB_LIAR" = 0x0000000B},
    @{"CM_PROB_NORMAL_CONFLICT" = 0x0000000C},
    @{"CM_PROB_NOT_VERIFIED" = 0x0000000D},
    @{"CM_PROB_NEED_RESTART" = 0x0000000E},
    @{"CM_PROB_REENUMERATION" = 0x0000000F},
    @{"CM_PROB_PARTIAL_LOG_CONF" = 0x00000010},
    @{"CM_PROB_UNKNOWN_RESOURCE" = 0x00000011},
    @{"CM_PROB_REINSTALL" = 0x00000012},
    @{"CM_PROB_REGISTRY" = 0x00000013},
    @{"CM_PROB_VXDLDR" = 0x00000014},
    @{"CM_PROB_WILL_BE_REMOVED" = 0x00000015},
    @{"CM_PROB_DISABLED" = 0x00000016},
    @{"CM_PROB_DEVLOADER_NOT_READY" = 0x00000017},
    @{"CM_PROB_DEVICE_NOT_THERE" = 0x00000018},
    @{"CM_PROB_MOVED" = 0x00000019},
    @{"CM_PROB_TOO_EARLY" = 0x0000001A},
    @{"CM_PROB_NO_VALID_LOG_CONF" = 0x0000001B},
    @{"CM_PROB_FAILED_INSTALL" = 0x0000001C},
    @{"CM_PROB_HARDWARE_DISABLED" = 0x0000001D},
    @{"CM_PROB_CANT_SHARE_IRQ" = 0x0000001E},
    @{"CM_PROB_FAILED_ADD" = 0x0000001F},
    @{"CM_PROB_DISABLED_SERVICE" = 0x00000020},
    @{"CM_PROB_TRANSLATION_FAILED" = 0x00000021},
    @{"CM_PROB_NO_SOFTCONFIG" = 0x00000022},
    @{"CM_PROB_BIOS_TABLE" = 0x00000023},
    @{"CM_PROB_IRQ_TRANSLATION_FAILED" = 0x00000024},
    @{"CM_PROB_FAILED_DRIVER_ENTRY" = 0x00000025},
    @{"CM_PROB_DRIVER_FAILED_PRIOR_UNLOAD" = 0x00000026},
    @{"CM_PROB_DRIVER_FAILED_LOAD" = 0x00000027},
    @{"CM_PROB_DRIVER_SERVICE_KEY_INVALID" = 0x00000028},
    @{"CM_PROB_LEGACY_SERVICE_NO_DEVICES" = 0x00000029},
    @{"CM_PROB_DUPLICATE_DEVICE" = 0x0000002A},
    @{"CM_PROB_FAILED_POST_START" = 0x0000002B},
    @{"CM_PROB_HALTED" = 0x0000002C},
    @{"CM_PROB_PHANTOM" = 0x0000002D},
    @{"CM_PROB_SYSTEM_SHUTDOWN" = 0x0000002E},
    @{"CM_PROB_HELD_FOR_EJECT" = 0x0000002F},
    @{"CM_PROB_DRIVER_BLOCKED" = 0x00000030},
    @{"CM_PROB_REGISTRY_TOO_LARGE" = 0x00000031},
    @{"CM_PROB_SETPROPERTIES_FAILED" = 0x00000032},
    @{"CM_PROB_WAITING_ON_DEPENDENCY" = 0x00000033},
    @{"CM_PROB_UNSIGNED_DRIVER" = 0x00000034},
    @{"CM_PROB_USED_BY_DEBUGGER" = 0x00000035},
    @{"CM_PROB_DEVICE_RESET" = 0x00000036},
    @{"CM_PROB_CONSOLE_LOCKED" = 0x00000037},
    @{"CM_PROB_NEED_CLASS_CONFIG" = 0x00000038},
    @{"CM_PROB_GUEST_ASSIGNMENT_FAILED" = 0x00000039}
);

function GetPCIeDevNodes
{
    [Int]$hn = 0;
    [NativeMethod]::GetNumaHighestNodeNumber([ref]$hn) | Out-Null;

    $ba = GetPCIeBARs;
    $filter = "ConfigManagerErrorCode != $($script:ProblemNames.CM_PROB_PHANTOM) AND " +
              "(DeviceID LIKE ""PCI\\%"" OR DeviceID LIKE ""ACPI\\PNP0A08\\%"")";
    $ap = Get-WmiObject Win32_PnPEntity -Filter $filter;
    $ret = $ap | Select-Object `
        @{ Name="BARs";
        Expression={ $id = $_.DeviceID; ($ba | Where-Object { $_.DeviceID -eq $id }).BAR; }
        },
        @{ Name="Service";
        Expression={ if ($_.Service) { $_.Service } else { $_.GetDeviceProperties("DEVPKEY_Device_DriverInfSection").deviceProperties.Data } }
        },
        @{ Name="Problem";
        Expression={ "{0:X}" -f [Int]$_.GetDeviceProperties("DEVPKEY_Device_ProblemCode").deviceProperties.Data }
        },
        @{ Name="ProblemStatus";
        Expression={
                $t = "{0:X}" -f $_.GetDeviceProperties("DEVPKEY_Device_ProblemStatus").deviceProperties.Data;
                if (-not $t) { "0"; } else { $t; }
            }
        },
        @{ Name="Status";
        Expression={ "{0:X}" -f [Int]$_.GetDeviceProperties("DEVPKEY_Device_DevNodeStatus").deviceProperties.Data }
        },
        @{ Name="HardwareID";
        Expression={ $_.HardwareID[0] }
        },
        @{ Name="BDF";
        Expression={
                [int64]$BusNo = $_.GetDeviceProperties("DEVPKEY_Device_BusNumber").deviceProperties.Data;
                $DevFn = $_.GetDeviceProperties("DEVPKEY_Device_Address").deviceProperties.Data;
                $FnNo = $DevFn -band 0x0000FFFF;
                $DevNo = $DevFn -shr 16;
                ($BusNo -shl 8) -bor ($DevNo -shl 3) -bor $FnNo;
            }
        },
        Caption,
        DeviceID,
        @{ Name="CompatibleID";
        Expression={ $_.CompatibleID[-1] }
        },
        @{ Name="Parent";
        Expression={ $_.GetDeviceProperties("DEVPKEY_Device_Parent").deviceProperties.Data }
        },
        @{ Name="ACPILocation";
        Expression={ @($_.GetDeviceProperties("DEVPKEY_Device_LocationPaths").deviceProperties.Data)[-1] }
        },
        @{ Name="InstalledOn";
        Expression={ $_.GetDeviceProperties("DEVPKEY_Device_InstallDate").deviceProperties.Data }
        },
        @{ Name="MatchingID";
        Expression={ $_.GetDeviceProperties("DEVPKEY_Device_MatchingDeviceId").deviceProperties.Data }
        },
        @{ Name="OSControlledNHPI"; #Native Hot Plug Interrupts are grated control by the firmware to the OS
        Expression={
                try {
                    if ($_.GetDeviceProperties("DEVPKEY_PciRootBus_PCIExpressNativeHotPlugControl").deviceProperties.Data) {
                        $true
                    } else {
                        $false
                    }
                } catch { $false }
            }
        },
        @{ Name="LinkWidth";
        Expression={ $_.GetDeviceProperties("DEVPKEY_PciDevice_CurrentLinkWidth").deviceProperties.Data }
        },
        @{ Name="LinkSpeed";
        Expression={ $_.GetDeviceProperties("DEVPKEY_PciDevice_CurrentLinkSpeed").deviceProperties.Data }
        },
        @{ Name="PayloadSize";
        Expression={ $_.GetDeviceProperties("DEVPKEY_PciDevice_CurrentPayloadSize").deviceProperties.Data }
        },
        @{ Name="DeviceType";
        Expression={ $_.GetDeviceProperties("DEVPKEY_PciDevice_DeviceType").deviceProperties.Data }
        #The value is unreliable. A Root Port is reported as DevProp_PciDevice_BridgeType_PciExpressTreatedAsPci.
        #The Root Complex is reported as DevProp_PciDevice_DeviceType_PciConventional.
        },
        @{ Name="ACSCapability";
        Expression={ $_.GetDeviceProperties("DEVPKEY_PciDevice_AcsCapabilityRegister").deviceProperties.Data }
        },
        @{ Name="NUMA";
        Expression={
                if ($hn) {
                    $nd = $_.GetDeviceProperties("DEVPKEY_Device_Numa_Node").deviceProperties.Data;
                    if (-not $nd) {
                        -2;
                    } else {
                        $nd;
                    }
                } else { -1; }
            }
        },
        @{ Name="DriverStack";
        Expression= { $_.GetDeviceProperties("DEVPKEY_Device_Stack").deviceProperties.Data }
        },
        @{ Name="Descendant"; Expression={ @() } },
        @{ Name="Displayed";
        Expression={
                $p = $ap.IndexOf($_) + 1;
                $v = $ap.Count;
                [Int]$c = $p * 100 / $v;
                Write-Progress -PercentComplete $c -Activity "Retrieve properties for devnode $p of $v" -Status "$c% completed" -Id 1;
                $false;
            }
        };
    $v = $ap.Count;
    Write-Progress -PercentComplete 100 -Activity "Retrieve properties for devnode $v of $v" -Status "100% completed" -Id 1 -Completed;
    
    return $ret;
}

function PCITree([ref][PSObject[]]$List)
{
    $List.Value = $List.Value | Sort-Object BDF;
    $acpi = @($List.Value | Where-Object { $_.DeviceID -like 'ACPI\PNP0A08\*' } | Sort-Object `
                @{ Expression={[Int]("0x"+($_.DeviceID -split '\\')[-1])} });
    $pci = $List.Value | Where-Object { $_.DeviceID -like 'PCI\*' };
    $List.Value = $acpi + $pci;

    for ($i = 0; $i -lt $List.Value.Count - 1; $i ++) {
        $x = $List.Value[$i];
        for ($j = $i + 1; $j -lt $List.Value.Count; $j ++) {
            $y = $List.Value[$j];
            if ($y.Parent -eq $x.DeviceID) {
                [PSObject[]]$x.Descendant += $y;
            }
        }
    }
}

function ConvertFromFileTime([String]$Tobe)
{
# FileTime string is "20190807125506.803492+180". +180 is converted to +03:00
# and resulting string formatted as yyyyMMddHHmmss.ffffffzzz.
    [Int]$to = ($Tobe -split "[+-]")[1];
    $o = "{0:00}:{1:00}" -f ($to/60), ($to%60);
    $m = [regex]::Replace($Tobe, "(?<sign>[+-])\d+", "`${sign}$o");
    return Get-Date ([DateTime]::ParseExact($m, "yyyyMMddHHmmss.ffffffzzz", $null, "AssumeLocal")) `
                -Format "u";
}

function PrintDevNode([DevnodeHR]$Entry, [String]$Code, [String]$Spaces, [Int]$Width)
{
    [Int]$max = 0;
    foreach ($k in ($Entry.PSObject.Properties | Select-Object -SkipLast 3)) {
        if ($k.Value.Length -gt $max) {
            $max = $k.Value.Length;
        }
    }
    if ($max -gt $Width) {
        $max = $Width;
    }
    if (-not $AsText) {
        $bdf = $Entry.BDF;
        switch ($Code) {
            "0" {
                $Entry.BDF = "$([char]0x1b)[42m$bdf$([char]0x1b)[0m";
                break;
            }
            "35" { #Network FDO controlled by Kernel Debugger
                $Entry.BDF = "$([char]0x1b)[42m$bdf$([char]0x1b)[0m";
                break;
            }
            "16" { #FDO disabled
                $Entry.BDF = "$([char]0x1b)[42m$bdf$([char]0x1b)[0m";
                break;
            }
            "1C" { #Driver package not installed
                $Entry.BDF = "$([char]0x1b)[42m$bdf$([char]0x1b)[0m";
                break;
            }
            default {
                #build a RED rectangle;
                $Entry.BDF = "$([char]0x1b)[41m$bdf$([char]0x1b)[0m";
            }
        }
    }
    foreach ($k in $Entry.PSObject.Properties) {
        if ($k.Name -eq "BARs") {
            continue;
        }
        if ($k.Value.Length -gt $Width) {
            #trim output as equal rectangles
            $v = $k.Value;
            $l = $v.Length;
            $nv = "";
            $b = 0;
            while ($l -gt $Width) {
                $nv += $v.Substring($b, $Width);
                $l -= $Width;
                $b += $Width;
                $nv += "`n$Spaces  ";
            }
            if ($l) {
                $nv += $v.Substring($b);
            }
            $k.Value = $nv;
        }
    }
    Write-Host ("$Spaces->"+$Entry.BDF),
               ("`n$Spaces  "+$Entry.DeviceID) -NoNewline;
    foreach ($k in "MatchingID", "Multiple", "LinkMPS", "ACS") {
        if ($Entry.$k) {
            Write-Host ("`n$Spaces  " + $Entry.$k) -NoNewline;    
        }
    }
    Write-Host ("`n$Spaces  " + $Entry.Human) -NoNewLine;
    if ($Entry.BARs) {
        $b = $Entry.BARs -split "`n";
        Write-Host ("`n$Spaces  BARs: "+$b[0]) -NoNewLine;
        for ($i = 1; $i -ne $b.Count; $i ++) {
            Write-Host ("`n$Spaces        "+$b[$i]) -NoNewLine;
        }
    }
    Write-Host "";

    $max += $Spaces.Length + 2;
    return $max;
}

function CombineHTML([DevnodeHR]$Node, [String]$Status, [String]$Problem, [String]$Subproblem, [Int]$Index, [Switch]$Expand, [String]$Grow, [Int]$Padding)
{
    if ($Node.BARs) {
        $Node.BARs = "BARs: " + ($Node.BARs -replace " ", ("`n" + " " * 16 + "<br/>" + "&nbsp;" * 6));
    }
    $CompatibleID = $Node.CompatibleID.Replace('\', '\\');
    $LinkAndMPS = $Node.LinkMPS;
    $ACS = $Node.ACS;
    $NUMA = $Node.NUMA;
    $DriverStack = $Node.DriverStack | ForEach-Object { $_.Replace('\', '\\')+"<br/>" };
    $html = @"

        <table>
            <tr>
                <td class="@HeaderColor@" onmouseover="ExtendedInfo(0x$Status, 0x$Problem, 0x$Subproblem, '$CompatibleID', $LinkAndMPS, $ACS, $NUMA, '$DriverStack')" onmouseout="ExtendedOut()">@BDF@</td>
            </tr>
            <tr>
                <td onmouseover="ExtendedInfo(0x$Status, 0x$Problem, 0x$Subproblem, '$CompatibleID', $LinkAndMPS, $ACS, $NUMA, '$DriverStack')" onmouseout="ExtendedOut()">
                    @DeviceID@
                    @MatchingID@
                    @Multiple@
                    @Human@
                    @BARs@
                </td>
            </tr>
"@;
    $max = "";
    foreach ($i in "DeviceID", "MatchingID") {
        if ($Node.$i.Length -gt $max.Length) {
            $max = $Node.$i;
        }
    }
    foreach ($i in @("DeviceID", "MatchingID", "Multiple", "Human")) {
        $t = $Node.$i;
        if ($t -and ($t.Length -lt $Padding)) {
            $t += "&nbsp;" * ($Padding - $t.Length);
        } elseif ($t.Length -gt $Padding -and $t -notlike "*<a href*") {
            for ($x = $t.Length - $t.Length % $Padding;
                    $x; $x -= $Padding) {
                $t = $t.Insert($x, "<br/>");
            }
        }
        if ($t -and $t.Substring($t.Length - "<br/>".Length) -ne "<br/>") {
            $t += "<br/>";
        }
        $html = $html.Replace("@$i@", $t);
    }
    $html = $html.Replace("@BDF@", $Node.BDF).Replace("@BARs@", $Node.BARs);
    $cl = @{ "0" = "td_online"; "16" = "td_offline"; "1C" = "td_notinstalled"; "35" = "td_online" };
    $cl.Keys | Where-Object { $_ -eq $Problem } | ForEach-Object {
        $html = $html.Replace("@HeaderColor@", $cl[$_]);
    }
    $html = $html.Replace("@HeaderColor@", "td_error");
    if ($Expand) {
        $Grow = $Grow.Replace("`n", "`n" + " "*16);
        $html += @"

            <tr>
                <td></td>
                <td id="FL$Index" onclick="Expand('FL$Index')" class="td_border">-</td>
            </tr>
            <tr>
                <td></td>
                <td></td>
                <td>
                    <span id="FL${Index}_sub" class="visible">                $Grow
                    </span>
                </td>
            </tr>
"@;
    }
    $html += "`n        </table>";
    return $html;
}

function RecursiveHTML([PSObject[]]$List, [ref][Int]$Index, [Int]$Padding)
{
    $grow = "";
    foreach ($i in $List) {
        if ($i.Displayed) {
            continue;
        }
        $partial = "";
        $dt = "";
        if ($i.InstalledOn) {
            $dt = (ConvertFromFileTime $i.InstalledOn) + " ";
        }
        if ($i.Service) {
            $dt += $i.Service + " ";
        }
        $pr = $i.Problem;
        $st = $i.Status;
        $ps = $i.ProblemStatus;
        $dt += "S=$st P="
        if ($pr -ne "0") {
            $al = $script:ProblemNames | Where-Object {
                $_.Values -eq [Int]"0x$pr";
            }
            if ($al) {
                $ah = ($al.Keys -replace "_", "-").ToLower();
                $dt += "<a href=""https://learn.microsoft.com/en-us/windows-hardware/drivers/install/$ah"" target=""_blank"">$pr</a>";
            } else {
                $dt += $pr;
            }
        } else {
            $dt += $pr;
        };
        $bdf = $i.BDF;
        $bdf = "$($bdf -shr 8):$(($bdf -shr 3) -band 0x1f).$($bdf -band 0x7)";

        switch ($pr) {
            "0" { $bdf += " online"; break; }
            "35" { $bdf += " online"; break; }
            "16" { $bdf += " offline"; break; }
            "1C" { $bdf += " not installed"; break; }
            default { $bdf += " error"; break; }
        }

        [int[]]$lm = @(0, 0, 0);
        if ($i.OSControlledNHPI) {
            $lm[0] = 1;
        }
        if ($i.LinkWidth) {
            $lm[1] = $i.LinkWidth;
        }
        if ($i.LinkSpeed) {
            $lm[1] = $lm[1] -bor ($i.LinkSpeed -shl 8);
        }
        if ($null -ne $i.PayloadSize) {
            $lm[1] = $lm[1] -bor (($i.PayloadSize+1) -shl 16);
        }
        $lm[2] = $i.DeviceType;
        #We pass the value to ExtendedInfo() js function. It remains unused.

        [DevnodeHR]$ow = New-Object DevnodeHR;
        $ow = @{
            BDF = $bdf;
            DeviceID = $i.DeviceID;
            MatchingID = $i.MatchingID;

            Multiple = $dt;
            LinkMPS = $lm -join ", ";
            Human = $i.Caption;
            BARs = $i.BARs;

            CompatibleID = $i.CompatibleID;
            ACS = [Int]$i.ACSCapability; #Can be $null, in which case it becomes 0
            NUMA = $i.NUMA;
            DriverStack = $i.DriverStack;
        };
        $exp = $false;
        if ($i.Descendant) {
            $exp = $true;
            $Index.Value ++;
        }

        $idx = $Index.Value;
        foreach ($j in $i.Descendant) {
            $partial += RecursiveHTML ([ref]$j) $Index $Padding;
            $j.Displayed = $true;
        }
        $i.Displayed = $true;
        $grow += CombineHTML $ow $st $pr $ps $idx -Expand:$exp $partial $Padding;
    }

    return $grow;
}

function RenderHTML([PSObject[]]$List)
{
    $big = @"
<!DOCTYPE html>
<html lang="en">
    <head>
        <title>
            PCI tree on ${env:COMPUTERNAME}
        </title>

        <style type="text/css">
            td {
                font-family: monospace;
                font-weight: bold;
                white-space: nowrap;
            }
            .wheader {
                background-color: black;
                color: white;
            }
            .td_border {
                border: 1px solid;
                border-spacing: 0px;
                background-color: gainsboro;
            }
            .td_online {
                border-width: 0px;
                border-spacing: 0px;
                background-color: aquamarine;
            }
            .td_offline {
                border-width: 0px;
                border-spacing: 0px;
                background-color: yellow;
            }
            .td_notinstalled {
                border-width: 0px;
                border-spacing: 0px;
                background-color: coral;
            }
            .td_error {
                border-width: 0px;
                border-spacing: 0px;
                background-color: red;
            }
            .visible {
                visibility: visible;
            }
            .expand {
                visibility: hidden;
                position: fixed;
                top: 10px;
                right: 10px;
                border: 1px solid black;
                font-family: monospace;
                background-color: white;
                padding: 4px;
            }
        </style>

        <script type="text/javascript">
            pciClassMap = "\n\
C 00  Unclassified device\n\
    00  Non-VGA unclassified device\n\
    01  VGA compatible unclassified device\n\
    05  Image coprocessor\n\
C 01  Mass storage controller\n\
    00  SCSI storage controller\n\
    01  IDE interface\n\
    02  Floppy disk controller\n\
    03  IPI bus controller\n\
    04  RAID bus controller\n\
    05  ATA controller\n\
    06  SATA controller\n\
    07  Serial Attached SCSI controller\n\
    08  Non-Volatile memory controller\n\
    80  Mass storage controller\n\
C 02  Network controller\n\
    00  Ethernet controller\n\
    01  Token ring network controller\n\
    02  FDDI network controller\n\
    03  ATM network controller\n\
    04  ISDN controller\n\
    05  WorldFip controller\n\
    06  PICMG controller\n\
    07  Infiniband controller\n\
    08  Fabric controller\n\
    80  Network controller\n\
C 03  Display controller\n\
    00  VGA compatible controller\n\
    01  XGA compatible controller\n\
    02  3D controller\n\
    80  Display controller\n\
C 04  Multimedia controller\n\
    00  Multimedia video controller\n\
    01  Multimedia audio controller\n\
    02  Computer telephony device\n\
    03  Audio device\n\
    80  Multimedia controller\n\
C 05  Memory controller\n\
    00  RAM memory\n\
    01  FLASH memory\n\
    80  Memory controller\n\
C 06  Bridge\n\
    00  Host bridge\n\
    01  ISA bridge\n\
    02  EISA bridge\n\
    03  MicroChannel bridge\n\
    04  PCI bridge\n\
    05  PCMCIA bridge\n\
    06  NuBus bridge\n\
    07  CardBus bridge\n\
    08  RACEway bridge\n\
    09  Semi-transparent PCI-to-PCI bridge\n\
    0a  InfiniBand to PCI host bridge\n\
    80  Bridge\n\
C 07  Communication controller\n\
    00  Serial controller\n\
    01  Parallel controller\n\
    02  Multiport serial controller\n\
    03  Modem\n\
    04  GPIB controller\n\
    05  Smard Card controller\n\
    80  Communication controller\n\
C 08  Generic system peripheral\n\
    00  PIC\n\
    01  DMA controller\n\
    02  Timer\n\
    03  RTC\n\
    04  PCI Hot-plug controller\n\
    05  SD Host controller\n\
    06  IOMMU\n\
    80  System peripheral\n\
    99  Timing Card\n\
C 09  Input device controller\n\
    00  Keyboard controller\n\
    01  Digitizer Pen\n\
    02  Mouse controller\n\
    03  Scanner controller\n\
    04  Gameport controller\n\
    80  Input device controller\n\
C 0a  Docking station\n\
    00  Generic Docking Station\n\
    80  Docking Station\n\
C 0b  Processor\n\
    00  386\n\
    01  486\n\
    02  Pentium\n\
    10  Alpha\n\
    20  Power PC\n\
    30  MIPS\n\
    40  Co-processor\n\
C 0c  Serial bus controller\n\
    00  FireWire (IEEE 1394)\n\
    01  ACCESS Bus\n\
    02  SSA\n\
    03  USB controller\n\
    04  Fibre Channel\n\
    05  SMBus\n\
    06  InfiniBand\n\
    07  IPMI Interface\n\
    08  SERCOS interface\n\
    09  CANBUS\n\
C 0d  Wireless controller\n\
    00  IRDA controller\n\
    01  Consumer IR controller\n\
    10  RF controller\n\
    11  Bluetooth\n\
    12  Broadband\n\
    20  802.1a controller\n\
    21  802.1b controller\n\
    80  Wireless controller\n\
C 0e  Intelligent controller\n\
    00  I2O\n\
C 0f  Satellite communications controller\n\
    01  Satellite TV controller\n\
    02  Satellite audio communication controller\n\
    03  Satellite voice communication controller\n\
    04  Satellite data communication controller\n\
C 10  Encryption controller\n\
    00  Network and computing encryption device\n\
    10  Entertainment encryption device\n\
    80  Encryption controller\n\
C 11  Signal processing controller\n\
    00  DPIO module\n\
    01  Performance counters\n\
    10  Communication synchronizer\n\
    20  Signal processing management\n\
    80  Signal processing controller\n\
C 12  Processing accelerators\n\
    00  Processing accelerators\n\
    01  AI Inference Accelerator\n\
C 13  Non-Essential Instrumentation\n\
C 40  Coprocessor\n\
C ff  Unassigned class";

            const statMap = new Map([
                ["DN_ROOT_ENUMERATED", 0x00000001],
                ["DN_DRIVER_LOADED", 0x00000002],
                ["DN_ENUM_LOADED", 0x00000004],
                ["DN_STARTED", 0x00000008],
                ["DN_MANUAL", 0x00000010],
                ["DN_NEED_TO_ENUM", 0x00000020],
                ["DN_DRIVER_BLOCKED", 0x00000040],
                ["DN_HARDWARE_ENUM", 0x00000080],
                ["DN_NEED_RESTART", 0x00000100],
                ["DN_CHILD_WITH_INVALID_ID", 0x00000200],
                ["DN_HAS_PROBLEM", 0x00000400],
                ["DN_FILTERED", 0x00000800],
                ["DN_LEGACY_DRIVER", 0x00001000],
                ["DN_DISABLEABLE", 0x00002000],
                ["DN_REMOVABLE", 0x00004000],
                ["DN_PRIVATE_PROBLEM", 0x00008000],
                ["DN_MF_PARENT", 0x00010000],
                ["DN_MF_CHILD", 0x00020000],
                ["DN_WILL_BE_REMOVED", 0x00040000],
                ["DN_NT_ENUMERATOR", 0x00800000],
                ["DN_NT_DRIVER", 0x01000000]
            ]);
            const probMap = new Map([
                ["CM_PROB_NOT_CONFIGURED", 0x00000001],
                ["CM_PROB_DEVLOADER_FAILED", 0x00000002],
                ["CM_PROB_OUT_OF_MEMORY", 0x00000003],
                ["CM_PROB_ENTRY_IS_WRONG_TYPE", 0x00000004],
                ["CM_PROB_LACKED_ARBITRATOR", 0x00000005],
                ["CM_PROB_BOOT_CONFIG_CONFLICT", 0x00000006],
                ["CM_PROB_FAILED_FILTER", 0x00000007],
                ["CM_PROB_DEVLOADER_NOT_FOUND", 0x00000008],
                ["CM_PROB_INVALID_DATA", 0x00000009],
                ["CM_PROB_FAILED_START", 0x0000000A],
                ["CM_PROB_LIAR", 0x0000000B],
                ["CM_PROB_NORMAL_CONFLICT", 0x0000000C],
                ["CM_PROB_NOT_VERIFIED", 0x0000000D],
                ["CM_PROB_NEED_RESTART", 0x0000000E],
                ["CM_PROB_REENUMERATION", 0x0000000F],
                ["CM_PROB_PARTIAL_LOG_CONF", 0x00000010],
                ["CM_PROB_UNKNOWN_RESOURCE", 0x00000011],
                ["CM_PROB_REINSTALL", 0x00000012],
                ["CM_PROB_REGISTRY", 0x00000013],
                ["CM_PROB_VXDLDR", 0x00000014],
                ["CM_PROB_WILL_BE_REMOVED", 0x00000015],
                ["CM_PROB_DISABLED", 0x00000016],
                ["CM_PROB_DEVLOADER_NOT_READY", 0x00000017],
                ["CM_PROB_DEVICE_NOT_THERE", 0x00000018],
                ["CM_PROB_MOVED", 0x00000019],
                ["CM_PROB_TOO_EARLY", 0x0000001A],
                ["CM_PROB_NO_VALID_LOG_CONF", 0x0000001B],
                ["CM_PROB_FAILED_INSTALL", 0x0000001C],
                ["CM_PROB_HARDWARE_DISABLED", 0x0000001D],
                ["CM_PROB_CANT_SHARE_IRQ", 0x0000001E],
                ["CM_PROB_FAILED_ADD", 0x0000001F],
                ["CM_PROB_DISABLED_SERVICE", 0x00000020],
                ["CM_PROB_TRANSLATION_FAILED", 0x00000021],
                ["CM_PROB_NO_SOFTCONFIG", 0x00000022],
                ["CM_PROB_BIOS_TABLE", 0x00000023],
                ["CM_PROB_IRQ_TRANSLATION_FAILED", 0x00000024],
                ["CM_PROB_FAILED_DRIVER_ENTRY", 0x00000025],
                ["CM_PROB_DRIVER_FAILED_PRIOR_UNLOAD", 0x00000026],
                ["CM_PROB_DRIVER_FAILED_LOAD", 0x00000027],
                ["CM_PROB_DRIVER_SERVICE_KEY_INVALID", 0x00000028],
                ["CM_PROB_LEGACY_SERVICE_NO_DEVICES", 0x00000029],
                ["CM_PROB_DUPLICATE_DEVICE", 0x0000002A],
                ["CM_PROB_FAILED_POST_START", 0x0000002B],
                ["CM_PROB_HALTED", 0x0000002C],
                ["CM_PROB_PHANTOM", 0x0000002D],
                ["CM_PROB_SYSTEM_SHUTDOWN", 0x0000002E],
                ["CM_PROB_HELD_FOR_EJECT", 0x0000002F],
                ["CM_PROB_DRIVER_BLOCKED", 0x00000030],
                ["CM_PROB_REGISTRY_TOO_LARGE", 0x00000031],
                ["CM_PROB_SETPROPERTIES_FAILED", 0x00000032],
                ["CM_PROB_WAITING_ON_DEPENDENCY", 0x00000033],
                ["CM_PROB_UNSIGNED_DRIVER", 0x00000034],
                ["CM_PROB_USED_BY_DEBUGGER", 0x00000035],
                ["CM_PROB_DEVICE_RESET", 0x00000036],
                ["CM_PROB_CONSOLE_LOCKED", 0x00000037],
                ["CM_PROB_NEED_CLASS_CONFIG", 0x00000038],
                ["CM_PROB_GUEST_ASSIGNMENT_FAILED", 0x00000039]
            ]);
            const subprobMap = new Map([
                ["STATUS_PNP_RESTART_ENUMERATION", 0xC00002CE],
                ["STATUS_PNP_REBOOT_REQUIRED", 0xC00002D2],
                ["STATUS_PNP_NO_COMPAT_DRIVERS", 0xC0000490],
                ["STATUS_PNP_DRIVER_PACKAGE_NOT_FOUND", 0xC0000491],
                ["STATUS_PNP_DRIVER_CONFIGURATION_NOT_FOUND", 0xC0000492],
                ["STATUS_PNP_DRIVER_CONFIGURATION_INCOMPLETE", 0xC0000493],
                ["STATUS_PNP_FUNCTION_DRIVER_REQUIRED", 0xC0000494],
                ["STATUS_PNP_DEVICE_CONFIGURATION_PENDING", 0xC0000495],
                ["STATUS_PNP_BAD_MPS_TABLE", 0xC0040035],
                ["STATUS_PNP_TRANSLATION_FAILED", 0xC0040036],
                ["STATUS_PNP_IRQ_TRANSLATION_FAILED", 0xC0040037],
                ["STATUS_PNP_INVALID_ID", 0xC0040038],
                ["STATUS_INVALID_IMAGE_HASH", 0xC0000428],
                ["STATUS_INVALID_DEVICE_REQUEST", 0xC0000010],
                ["STATUS_UNSUCCESSFUL", 0xC0000001],
                ["STATUS_DRIVER_ENTRYPOINT_NOT_FOUND", 0xC0000263]
            ]);
            function Expand(myId)
            {
                elem = document.getElementById(myId);
                child = document.getElementById(myId+"_sub");
                if (elem.innerText == "+") {
                    elem.innerText = "-";
                    if (child) {
                        child.style.visibility = "visible";
                    }
                } else {
                    elem.innerText = "+";
                    if (child) {
                        child.style.visibility = "collapse";
                    }
                }
            }

            function ExtendedInfo(statusCode, problemCode, subproblemCode, classCode, osNHPI, infoLinkMPS, typeDevice, capACS, numaNode, driverStack)
            {
                elem = document.getElementById("extendedPanel");

                y = ["PciConventional", "PciX", "PciExpressEndpoint", "PciExpressLegacyEndpoint",
                     "PciExpressRootComplexIntegratedEndpoint", "PciExpressTreatedAsPci",
                     "BridgePciConventional", "BridgePciX", "BridgePciExpressRootPort",
                     "BridgePciExpressUpstreamSwitchPort", "BridgePciExpressDownstreamSwitchPort",
                     "BridgePciExpressToPciXBridge", "BridgePciXToExpressBridge",
                     "BridgePciExpressTreatedAsPci", "BridgePciExpressEventCollector"][typeDevice];
                /*Don't display this entry*/
                eit = "";
                beg = "Status " + statusCode.toString(16).toUpperCase() + " = ";
                eiw = "".padStart(beg.length*6, "&nbsp;");
                for (let [key, value] of statMap) {
                    if (value & statusCode) {
                        if (eit == "") {
                            eit = key;
                        } else {
                            eit += "|<br/>" + eiw + key;
                        }
                    }
                }
                x = beg + eit;
                if (problemCode) {
                    eit = "";
                    beg = "Problem " + problemCode.toString(16).toUpperCase() + " = ";
                    for (let [key, value] of probMap) {
                        if (value == problemCode) {
                            eit = key;
                            break;
                        }
                    }
                    x += "<br/>" + beg + eit;
                    eit = "";
                    for (let [key, value] of subprobMap) {
                        if (value == subproblemCode) {
                            eit = key;
                            break;
                        }
                    }
                    eiw = "".padStart("Problem ".length*6, "&nbsp;");
                    if (eit == "") {
                        x += "<br/>" + eiw + subproblemCode.toString(16).toUpperCase();
                    } else {
                        x += "<br/>" + eiw + eit;
                    }
                }
                pciClassIndex = -1;
                if (classCode && classCode.match(/^PCI\\CC_[0-9A-F]{4}/i)) {
                    pciClass = classCode.substring(7, 9).toLowerCase();
                    pciSubClass = classCode.substring(9).toLowerCase();
                    classCode = "Class " + classCode.toUpperCase();
                    let pciClassHuman, pciClassIndex, pciSubClassHuman;
                    try {
                        pciClassMatch = pciClassMap.match("\nC " + pciClass + " +(.+) *");
                        pciClassIndex = pciClassMatch.index;
                        pciClassHuman = pciClassMatch[1].trim();
                    } catch {
                        pciClassHuman = "Unknown class";
                        pciSubClassHuman = "";
                    }
                    if (pciClassIndex != -1) {
                        try{
                            pciClassRest = pciClassMap.substring(pciClassIndex + pciClassHuman.length);
                            pciSubClassMatch = pciClassRest.match("\n {4}" + pciSubClass + " +(.+) *");
                            pciClassTest = pciClassRest.match("\nC [0-9a-f]{2} ");
                            if (pciClassTest.index < pciSubClassMatch.index) {
                                throw "We passed the subclass index";
                            }
                            pciSubClassHuman = pciSubClassMatch[1].trim();
                        } catch {
                            pciSubClassHuman = "Unknown subclass";
                        }
                    }
                    eiw = "".padStart((classCode.length+3)*6, "&nbsp;");
                    x += "<br/>" + classCode + " = " + pciClassHuman + ",";
                    x += "<br/>" + eiw + pciSubClassHuman;
                }
                if (osNHPI || infoLinkMPS || capACS || numaNode >= 0) {
                    x += "<br/>";
                }
                if (numaNode >= 0) {
                    x += "<br/>NUMA Node " + numaNode;
                }
                if (osNHPI) {
                    x += "<br/>OS native hot-plug interrupts granted by firmware";
                }
                if (infoLinkMPS) {
                    linkWidth = infoLinkMPS & 0xFF;
                    linkSpeed = (infoLinkMPS >> 8) & 0xFF;
                    currentPS = (infoLinkMPS >> 16) & 0xFF;
                    if (linkWidth) {
                        x += "<br/>Link capabilities = x" + linkWidth + ", Gen" + linkSpeed;
                    }
                    if (currentPS) {
                        x += "<br/>Maximum payload size = " + (128 << (currentPS-1));
                    }
                }
                if (capACS) {
                    z = "ACS capability " + capACS.toString(16).toUpperCase() + " = ";
                    eiw = "".padStart(z.length*6, "&nbsp;");
                    u = "";
                    if (capACS & 1) {
                        u += "<br/>" + eiw + "SourceValidation|";
                    }
                    if (capACS & 2) {
                        u += "<br/>" + eiw + "TranslationBlocking|";
                    }
                    if (capACS & 4) {
                        u += "<br/>" + eiw + "RequestRedirect|";
                    }
                    if (capACS & 8) {
                        u += "<br/>" + eiw + "CompletionRedirect|";
                    }
                    if (capACS & 0x10) {
                        u += "<br/>" + eiw + "UpstreamForwarding|";
                    }
                    if (capACS & 0x20) {
                        u += "<br/>" + eiw + "EgressControl|";
                    }
                    if (capACS & 0x40) {
                        u += "<br/>" + eiw + "DirectTranslation|";
                    }
                    u = u.substring(("<br/>" + eiw).length, u.length-1);
                    x += "<br/>" + z + u;
                }
                if (driverStack) {
                    x += "<br/><br/>"+driverStack;
                }
                if (elem.innerHTML != x) {
                    elem.innerHTML = x;
                }
                elem.style.visibility = "visible";
            }

            function ExtendedOut()
            {
                elem = document.getElementById("extendedPanel");
                elem.style.visibility = "hidden";
            }
        </script>

    </head>
    <body>
        <span id="extendedPanel" class="expand"></span>

"@;

    $idx = 0;
    $mp = 0;
    $List | ForEach-Object {
        foreach ($k in @("DeviceID", "MatchingID")) {
            if ($mp -lt $_.$k.Length) {
                $mp = $_.$k.Length;
            }
        }
        $dt = "";
        if ($_.InstalledOn) {
            $dt = (ConvertFromFileTime $_.InstalledOn) + " ";
        }
        if ($_.Service) {
            $dt += $_.Service + " ";
        }
        $dt += "S=" + $_.Status + " P=" + $_.Problem;
        if ($dt.Length -gt $mp) {
            $mp = $dt.Length;
        }
    }
    $ct = RecursiveHTML $List ([ref]$idx) $mp;
    $hd = PrintHeader -AsHTML;
    $big += $hd + $ct + "`n    </body>`n</html>`n";

    return $big;
}

function GenerateFileName
{
    param([ref]$Content);

    $fn = ".\"+(New-Guid).ToString().ToUpper().Replace("-","_")+".html";
    Set-Content $fn -Value $Content.Value;
    $fn;
}

function DisplayConsole([PSObject[]]$List, [Int]$Padding = 0, [Int]$Width = 0)
{
    if (-not $Width) {
        $List | ForEach-Object {
            foreach ($k in "DeviceID", "MatchingID") {
                if ($Width -lt $_.$k.Length) {
                    $Width = $_.$k.Length;
                }
            }
        }
    }
    foreach ($i in $List) {
        if ($i.Displayed) {
            continue;
        }
        $spaces = " "*$Padding;
        $dt = "";
        if ($i.InstalledOn) {
            $dt = (ConvertFromFileTime $i.InstalledOn) + " ";
        }
        if ($i.Service) {
            $dt += $i.Service + " ";
        }
        $pr = $i.Problem;
        $dt += "S=" + $i.Status + " P=$pr";
        if ($pr -ne "0") {
            $dt += "/" + $i.ProblemStatus;
        }
        if (-1, -2 -notcontains $i.NUMA) {
            $dt += " N=" + $i.NUMA;
        }
        $bdf = $i.BDF;
        $bdf = "$($bdf -shr 8):$(($bdf -shr 3) -band 0x1f).$($bdf -band 0x7)";

        switch ($pr) {
            "0" { $bdf += " online"; break; }
            "35" { $bdf += " online"; break; }
            "16" { $bdf += " offline"; break; }
            "1C" { $bdf += " not installed"; break; }
            default { $bdf += " error"; break; }
        }
        $lm = "";
        if ($i.OSControlledNHPI) {
            $lm = "OS native hot-plug interrupts, ";
        }
        if ($i.LinkWidth) {
            $lm += "Link capabilities W=x"+$i.LinkWidth+" S=Gen"+$i.LinkSpeed+", ";
        }
        if ($null -ne $i.PayloadSize) {
            $lm += "MPS="+(128 -shl $i.PayloadSize);
        }
        if ($lm[-2] -eq ",") {
            $lm = $lm.Substring(0, $lm.Length-3);
        }

        $acs = $i.ACSCapability;
        $acstr = "";
        if ($acs) {
            $acstr = "ACS capability $acs = ";
            if ($acs -band 1) {
                $acstr += "SV | ";
            }
            if ($acs -band 2) {
                $acstr += "TB | ";
            }
            if ($acs -band 4) {
                $acstr += "RR | ";
            }
            if ($acs -band 8) {
                $acstr += "CR | ";
            }
            if ($acs -band 0x10) {
                $acstr += "UF | ";
            }
            if ($acs -band 0x20) {
                $acstr += "EC | ";
            }
            if ($acs -band 0x40) {
                $acstr += "DT | ";
            }
            $acstr = $acstr.Substring(0, $acstr.Length-4);
        }

        [DevnodeHR]$ow = New-Object DevnodeHR;
        $ow = @{
            BDF = $bdf;
            DeviceID = $i.DeviceID;
            MatchingID = $i.MatchingID;
            Multiple = $dt;
            LinkMPS = $lm;
            ACS = $acstr;
            Human = $i.Caption;
            BARs = $i.BARs -join "`n";
            NUMA = $null;
        };
        $max = PrintDevNode $ow $pr $spaces $Width;
        $i.Displayed = $true;
        foreach ($j in $i.Descendant) {
            DisplayConsole ([ref]$j) $max;
        }
    }
}

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
