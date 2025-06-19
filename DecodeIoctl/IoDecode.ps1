<#
.SYNOPSIS
    Decode IOCTLs issues by Windows applications or drivers

.PARAMETER IoctlCode
    The code to be parsed. Latest Windows SDK version is scanned for matching CTL_CODE,
    identifying the source macro. Currently, winioctl.h and ntddscsi.h are used.

.EXAMPLE
    .\IoDecode.ps1 0x00041018
    0x00041018 = CTL_CODE(FILE_DEVICE_CONTROLLER, 0x406, METHOD_BUFFERED, FILE_ANY_ACCESS)
    > Found match in "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared\ntddscsi.h"
      IOCTL_SCSI_GET_ADDRESS = CTL_CODE(IOCTL_SCSI_BASE, 0x0406, METHOD_BUFFERED, FILE_ANY_ACCESS)

    In this example, the runtime match identifies FILE_DEVICE_CONTROLLER as type. The header
    file uses IOCTL_SCSI_BASE as identical macro.

.EXAMPLE
    .\IoDecode.ps1 0x00070000
    0x00070000 = CTL_CODE(FILE_DEVICE_DISK, 0x0, METHOD_BUFFERED, FILE_ANY_ACCESS)
    > Found match in "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um\winioctl.h"
        IOCTL_DISK_GET_DRIVE_GEOMETRY = CTL_CODE(IOCTL_DISK_BASE, 0x0000, METHOD_BUFFERED, FILE_ANY_ACCESS)

    In this example, the macro is located in winioctl.h.

.EXAMPLE
    .\IoDecode.ps1 0x002D118C
    0x002D118C = CTL_CODE(FILE_DEVICE_MASS_STORAGE, 0x463, METHOD_BUFFERED, FILE_ANY_ACCESS)

    In this example, the headers do not define a corresponding macro.

.EXAMPLE
    .\IoDecode.ps1 0x004D0008
    0x004D0008 = CTL_CODE(0x4D<undocumented>, 0x2, METHOD_BUFFERED, FILE_ANY_ACCESS)

    In this example, the FILE_DEVICE macro has no match for 0x4D.
#>

param([int]$IoctlCode)

$typeHash = [ordered]@{
    "FILE_DEVICE_BEEP"                 = 0x00000001;
    "FILE_DEVICE_CD_ROM"               = 0x00000002;
    "FILE_DEVICE_CD_ROM_FILE_SYSTEM"   = 0x00000003;
    "FILE_DEVICE_CONTROLLER"           = 0x00000004;
    "IOCTL_SCSI_BASE"                  = 0x00000004;
    "FILE_DEVICE_DATALINK"             = 0x00000005;
    "FILE_DEVICE_DFS"                  = 0x00000006;
    "FILE_DEVICE_DISK"                 = 0x00000007;
    "IOCTL_DISK_BASE"                  = 0x00000007;
    "FILE_DEVICE_DISK_FILE_SYSTEM"     = 0x00000008;
    "FILE_DEVICE_FILE_SYSTEM"          = 0x00000009;
    "FILE_DEVICE_INPORT_PORT"          = 0x0000000a;
    "FILE_DEVICE_KEYBOARD"             = 0x0000000b;
    "FILE_DEVICE_MAILSLOT"             = 0x0000000c;
    "FILE_DEVICE_MIDI_IN"              = 0x0000000d;
    "FILE_DEVICE_MIDI_OUT"             = 0x0000000e;
    "FILE_DEVICE_MOUSE"                = 0x0000000f;
    "FILE_DEVICE_MULTI_UNC_PROVIDER"   = 0x00000010;
    "FILE_DEVICE_NAMED_PIPE"           = 0x00000011;
    "FILE_DEVICE_NETWORK"              = 0x00000012;
    "FILE_DEVICE_NETWORK_BROWSER"      = 0x00000013;
    "FILE_DEVICE_NETWORK_FILE_SYSTEM"  = 0x00000014;
    "FILE_DEVICE_NULL"                 = 0x00000015;
    "FILE_DEVICE_PARALLEL_PORT"        = 0x00000016;
    "FILE_DEVICE_PHYSICAL_NETCARD"     = 0x00000017;
    "FILE_DEVICE_PRINTER"              = 0x00000018;
    "FILE_DEVICE_SCANNER"              = 0x00000019;
    "FILE_DEVICE_SERIAL_MOUSE_PORT"    = 0x0000001a;
    "FILE_DEVICE_SERIAL_PORT"          = 0x0000001b;
    "FILE_DEVICE_SCREEN"               = 0x0000001c;
    "FILE_DEVICE_SOUND"                = 0x0000001d;
    "FILE_DEVICE_STREAMS"              = 0x0000001e;
    "FILE_DEVICE_TAPE"                 = 0x0000001f;
    "FILE_DEVICE_TAPE_FILE_SYSTEM"     = 0x00000020;
    "FILE_DEVICE_TRANSPORT"            = 0x00000021;
    "FILE_DEVICE_UNKNOWN"              = 0x00000022;
    "FILE_DEVICE_VIDEO"                = 0x00000023;
    "FILE_DEVICE_VIRTUAL_DISK"         = 0x00000024;
    "FILE_DEVICE_WAVE_IN"              = 0x00000025;
    "FILE_DEVICE_WAVE_OUT"             = 0x00000026;
    "FILE_DEVICE_8042_PORT"            = 0x00000027;
    "FILE_DEVICE_NETWORK_REDIRECTOR"   = 0x00000028;
    "FILE_DEVICE_BATTERY"              = 0x00000029;
    "FILE_DEVICE_BUS_EXTENDER"         = 0x0000002a;
    "FILE_DEVICE_MODEM"                = 0x0000002b;
    "FILE_DEVICE_VDM"                  = 0x0000002c;
    "FILE_DEVICE_MASS_STORAGE"         = 0x0000002d;
    "IOCTL_STORAGE_BASE"               = 0x0000002d;
    "FILE_DEVICE_SMB"                  = 0x0000002e;
    "FILE_DEVICE_KS"                   = 0x0000002f;
    "FILE_DEVICE_CHANGER"              = 0x00000030;
    "FILE_DEVICE_SMARTCARD"            = 0x00000031;
    "FILE_DEVICE_ACPI"                 = 0x00000032;
    "FILE_DEVICE_DVD"                  = 0x00000033;
    "FILE_DEVICE_FULLSCREEN_VIDEO"     = 0x00000034;
    "FILE_DEVICE_DFS_FILE_SYSTEM"      = 0x00000035;
    "FILE_DEVICE_DFS_VOLUME"           = 0x00000036;
    "FILE_DEVICE_SERENUM"              = 0x00000037;
    "FILE_DEVICE_TERMSRV"              = 0x00000038;
    "FILE_DEVICE_KSEC"                 = 0x00000039;
    "FILE_DEVICE_FIPS"                 = 0x0000003A;
    "FILE_DEVICE_INFINIBAND"           = 0x0000003B;
    "FILE_DEVICE_VMBUS"                = 0x0000003E;
    "FILE_DEVICE_CRYPT_PROVIDER"       = 0x0000003F;
    "FILE_DEVICE_WPD"                  = 0x00000040;
    "FILE_DEVICE_BLUETOOTH"            = 0x00000041;
    "FILE_DEVICE_MT_COMPOSITE"         = 0x00000042;
    "FILE_DEVICE_MT_TRANSPORT"         = 0x00000043;
    "FILE_DEVICE_BIOMETRIC"            = 0x00000044;
    "FILE_DEVICE_PMI"                  = 0x00000045;
    "FILE_DEVICE_EHSTOR"               = 0x00000046;
    "FILE_DEVICE_DEVAPI"               = 0x00000047;
    "FILE_DEVICE_GPIO"                 = 0x00000048;
    "FILE_DEVICE_USBEX"                = 0x00000049;
    "FILE_DEVICE_CONSOLE"              = 0x00000050;
    "FILE_DEVICE_NFP"                  = 0x00000051;
    "FILE_DEVICE_SYSENV"               = 0x00000052;
    "FILE_DEVICE_VIRTUAL_BLOCK"        = 0x00000053;
    "FILE_DEVICE_POINT_OF_SERVICE"     = 0x00000054;
    "FILE_DEVICE_STORAGE_REPLICATION"  = 0x00000055;
    "FILE_DEVICE_TRUST_ENV"            = 0x00000056;
    "FILE_DEVICE_UCM"                  = 0x00000057;
    "FILE_DEVICE_UCMTCPCI"             = 0x00000058;
    "FILE_DEVICE_PERSISTENT_MEMORY"    = 0x00000059;
    "FILE_DEVICE_NVDIMM"               = 0x0000005a;
    "FILE_DEVICE_HOLOGRAPHIC"          = 0x0000005b;
    "FILE_DEVICE_SDFXHCI"              = 0x0000005c;
    "FILE_DEVICE_UCMUCSI"              = 0x0000005d;
    "FILE_DEVICE_PRM"                  = 0x0000005e;
    "FILE_DEVICE_EVENT_COLLECTOR"      = 0x0000005f;
    "FILE_DEVICE_USB4"                 = 0x00000060;
    "FILE_DEVICE_SOUNDWIRE"            = 0x00000061;
    "FILE_DEVICE_FABRIC_NVME"          = 0x00000062;
    "FILE_DEVICE_SVM"                  = 0x00000063;
    "FILE_DEVICE_HARDWARE_ACCELERATOR" = 0x00000064;
    "FILE_DEVICE_I3C"                  = 0x00000065;
};

$methodHash = @{
    "METHOD_BUFFERED"   = 0;
    "METHOD_IN_DIRECT"  = 1;
    "METHOD_OUT_DIRECT" = 2;
    "METHOD_NEITHER"    = 3;
};

$accessHash = @{
    "FILE_ANY_ACCESS"                      = 0;
    "FILE_READ_ACCESS"                     = 1;
    "FILE_WRITE_ACCESS"                    = 2;
    "FILE_READ_ACCESS | FILE_WRITE_ACCESS" = 3;
};

function UnpackIoctl
{
    param([int]$IoControl)

    $type = ($IoControl -shr 16) -band 0xFFFF;
    $access = ($IoControl -shr 14) -band 0x3;
    $fn = ($IoControl -shr 2) -band 0xFFF;
    $method = $IoControl -band 0x3;

    if ($type -in $typeHash.Values) {
        $typeStr = ($typeHash.GetEnumerator() | Where-Object { $_.Value -eq $type }).Key;
        if ($typeStr.Count -gt 1) {
            $typeStr = $typeStr[0];
        }
    } else {
        $typeStr = "0x{0:X}<undocumented>" -f $type;
    }
    if ($method -in $methodHash.Values) {
        $methodStr = ($methodHash.GetEnumerator() | Where-Object { $_.Value -eq $method }).Key;
    } else {
        $methodStr = "0x{0:X}" -f $method;
    }
    if ($access -in $accessHash.Values) {
        $accessStr = ($accessHash.GetEnumerator() | Where-Object { $_.Value -eq $access }).Key;
    } else {
        $accessStr = "0x{0:X}" -f $access;
    }
    $fnStr = "0x{0:X}" -f $fn;
    "0x{0:X8} = CTL_CODE($typeStr, $fnStr, $methodStr, $accessStr)" -f $IoControl;
}

function CTL_CODE
{
    param([int]$Type,
          [int]$Fn,
          [int]$Method,
          [int]$Access)
    
    return ($Type -shl 16) + ($Access -shl 14) + ($Fn -shl 2) + $Method;
}

function LatestCTL_CODE
{
    param([int]$IoControl)

    $windowsKit = "${env:ProgramFiles(x86)}\Windows Kits\10\Include";
    $version = [Version[]](Get-ChildItem -Path "$windowsKit\*.*" -ErrorAction SilentlyContinue).Name;
    if (-not $version) {
        return;
    }
    $latestVersion = ($version | Sort-Object -Descending -Top 1) -join ".";
    $keys = [string[]]$typeHash.Keys;
    $knownPaths = "$windowsKit\$latestVersion\um\winioctl.h",
                  "$windowsKit\$latestVersion\shared\ntddscsi.h";
    $ctl_codeTable = [psobject]::new();
    foreach ($ioctlPath in $knownPaths) {
        $ioctl = Get-Content $ioctlPath | Select-String $keys -AllMatches -SimpleMatch;
        $ioctl.Line | Where-Object {
            if ($_ -match "define (\w+)\s+CTL_CODE\((\w+, \d+, \w+, \w+( \| \w+)?)\)" -or
                $_ -match "define (\w+)\s+CTL_CODE\((\w+, 0x[0-9a-f]+, \w+, \w+( \| \w+)?)\)")
            {
                $ctl_codeTable | Add-Member -NotePropertyName $Matches[1] -NotePropertyValue $Matches[2];
            }
        };
        foreach ($ctlProperty in $ctl_codeTable.PSObject.Properties) {
            $values = $ctlProperty.Value -split ", ";
            $type = $values[0];
            $intType = $typeHash.$type;
            if ($null -eq $intType) {
                continue;
            }
            $intFn = [int]$values[1];
            $method = $values[2];
            $intMethod = $methodHash.$method;
            if ($null -eq $intMethod) {
                continue;
            }
            $access = $values[3];
            if ($access.Contains("|")) {
                $intAccess = 3;
            } elseif ($access -eq "FILE_SPECIAL_ACCESS") {
                $intAccess = 0;
            } elseif ($access -eq "FILE_READ_DATA") {
                $intAccess = 1;
            } elseif ($access -eq "FILE_WRITE_DATA") {
                $intAccess = 2;
            } else {
                $intAccess = $accessHash.$access;
            }
            $ctlValue = CTL_CODE $intType $intFn $intMethod $intAccess;
            if ($ctlValue -eq $IoControl) {
                "> Found match in ""$ioctlPath""";
                "  $($ctlProperty.Name) = CTL_CODE($($ctlProperty.Value))";
                return;
            }
        }
    }
}

UnpackIoctl $IoctlCode;
LatestCTL_CODE $IoctlCode;
