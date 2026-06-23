using System;
using System.Text;
using System.Text.RegularExpressions;
using System.IO;
using System.Linq;
using System.Collections.Generic;

public class TrimKD
{
    public static void TrimLogFile(string source, string from, bool after, string to, string destination)
    {
        StreamReader istream = new(source);
        StreamWriter ostream = new(destination);
        string line;
        bool found = false;

        while (! istream.EndOfStream)
        {
            line = istream.ReadLine();
            if (line.StartsWith(to))
            {
                break;
            }
            if (found)
            {
                ostream.WriteLine(line);
                continue;
            }
            if (line.StartsWith(from))
            {
                found = true;
                if (! after)
                {
                    ostream.WriteLine(line);
                }
            }
        }
        ostream.Close();
        istream.Close();
    }
}

public class TrimDisassembly
{
    const uint FlowAnalysisLimit = (uint)100E+3;
    const string FlowAnalysisCookie = "Flow analysis was incomplete, some code may be missing";
    const string NoCodeCookie = "No code found, aborting";
    const string CouldntResolveCookie = "Couldn't resolve error at";
    const string SyntaxErrorCookie = "Syntax error at";

    static void LeftTrim(ref string str, Regex pattern)
    {
        str = pattern.Replace(str, "");
    }

    public static void TrimBodies(string delimiter, string path)
    {
        List<string> body = new();
        StringBuilder block = new();
        StreamReader istream = new(path);
        bool bypass;
        string str;
        StringBuilder sb = new();
        Regex pattern = new(@"^[a-z0-9]{8}(`[a-z0-9]{8})? ", RegexOptions.Compiled | RegexOptions.Multiline);

        while (!istream.EndOfStream)
        {
            var line = istream.ReadLine();
            if (line.StartsWith(delimiter))
            {
                str = block.ToString();
                bypass = str.Contains(NoCodeCookie) ||
                         str.Contains(CouldntResolveCookie) ||
                         str.Contains(SyntaxErrorCookie) ||
                         str.Length > FlowAnalysisLimit &&
                         str.Contains(FlowAnalysisCookie);
                if (!bypass)
                {
                    LeftTrim(ref str, pattern);
                    body.Add(str);
                }
                block.Clear();
            }
            block.Append(line);
            block.Append("\n");
        }
        istream.Close();
        if (block.Length > 0)
        {
            str = block.ToString();
            bypass = str.Contains(NoCodeCookie) ||
                     str.Contains(CouldntResolveCookie) ||
                     str.Contains(SyntaxErrorCookie) ||
                     str.Length > FlowAnalysisLimit &&
                     str.Contains(FlowAnalysisCookie);
            if (!bypass)
            {
                LeftTrim(ref str, pattern);
                body.Add(str);
            }
        }
        StreamWriter ostream = new(path);
        foreach (var iter in body)
        {
            ostream.Write(iter);
        }
        ostream.Close();
    }
}

public enum Expand
{
    None,
    Empty,
    ExpandMiddle,
    ExpandLast
}

public enum DrawHint
{
    HasDependency,
    Retpoline,
    AtEnd,
    StopDisassembly,
    BodyNotFound,
    ImportAddressTable,
    Indirect
}

public class Node
{
    public string Symbol = "";
    public string Address = "";
    public int Index;
    public Expand Expand;
    public DrawHint Hint;
    public System.Collections.Generic.List<Node> Dependency = new();

    private static int _GetDependencyCount(Node node)
    {
        var count = node.Dependency.Count;

        foreach (var dep in node.Dependency)
        {
            if (dep.Dependency.Count > 0)
            {
                count += _GetDependencyCount(dep);
            }
        }
        return count;
    }

    public int GetDependencyCount()
    {
        return Node._GetDependencyCount(this);
    }

}

enum SCSI_NOTIFICATION_TYPE
{
    RequestComplete,
    NextRequest,
    NextLuRequest,
    ResetDetected,
    _obsolete1,
    _obsolete2,
    RequestTimerCall,
    BusChangeDetected,
    WMIEvent,
    WMIReregister,
    LinkUp,
    LinkDown,
    QueryTickCount,
    BufferOverrunDetected,
    TraceNotification,
    GetExtendedFunctionTable,

    EnablePassiveInitialization = 0x1000,
    InitializeDpc,
    IssueDpc,
    AcquireSpinLock,
    ReleaseSpinLock,
    StateChangeDetectedCall,
    IoTargetRequestServiceTime,
    AsyncNotificationDetected,
    RequestDirectComplete,
    InitializeDpcWithContext,
    InitializeThreadedDpc,
    SetTargetProcessorDpc,
    MarkDeviceFailed,
    MarkDeviceFailedEx,
    TerminateSystemThread,
    NvmeofNotification,
    StorMQControllerStartInitialization
}

enum STORPORT_FUNCTION_CODE
{
    ExtFunctionAllocatePool,
    ExtFunctionFreePool,
    ExtFunctionAllocateMdl,
    ExtFunctionFreeMdl,
    ExtFunctionBuildMdlForNonPagedPool,
    ExtFunctionGetSystemAddress,
    ExtFunctionGetOriginalMdl,
    ExtFunctionCompleteServiceIrp,
    ExtFunctionGetDeviceObjects,
    ExtFunctionBuildScatterGatherList,
    ExtFunctionPutScatterGatherList,
    ExtFunctionAcquireMSISpinLock,
    ExtFunctionReleaseMSISpinLock,
    ExtFunctionGetMessageInterruptInformation,
    ExtFunctionInitializePerformanceOptimizations,
    ExtFunctionGetStartIoPerformanceParameters,
    ExtFunctionLogSystemEvent,
    ExtFunctionGetCurrentProcessorNumber,
    ExtFunctionGetActiveGroupCount,
    ExtFunctionGetGroupAffinity,
    ExtFunctionGetActiveNodeCount,
    ExtFunctionGetNodeAffinity,
    ExtFunctionGetHighestNodeNumber,
    ExtFunctionGetLogicalProcessorRelationship,
    ExtFunctionAllocateContiguousMemorySpecifyCacheNode,
    ExtFunctionFreeContiguousMemorySpecifyCache,
    ExtFunctionSetPowerSettingNotificationGuids,
    ExtFunctionInvokeAcpiMethod,
    ExtFunctionGetRequestInfo,
    ExtFunctionInitializeWorker,
    ExtFunctionQueueWorkItem,
    ExtFunctionFreeWorker,
    ExtFunctionInitializeTimer,
    ExtFunctionRequestTimer,
    ExtFunctionFreeTimer,
    ExtFunctionInitializeSListHead,
    ExtFunctionInterlockedFlushSList,
    ExtFunctionInterlockedPopEntrySList,
    ExtFunctionInterlockedPushEntrySList,
    ExtFunctionQueryDepthSList,
    ExtFunctionGetActivityId,
    ExtFunctionGetSystemPortNumber,
    ExtFunctionGetDataInBufferMdl,
    ExtFunctionGetDataInBufferSystemAddress,
    ExtFunctionGetDataInBufferScatterGatherList,
    ExtFunctionMarkDumpMemory,
    ExtFunctionSetUnitAttributes,
    ExtFunctionQueryPerformanceCounter,
    ExtFunctionInitializePoFxPower,
    ExtFunctionPoFxActivateComponent,
    ExtFunctionPoFxIdleComponent,
    ExtFunctionPoFxSetComponentLatency,
    ExtFunctionPoFxSetComponentResidency,
    ExtFunctionPoFxPowerControl,
    ExtFunctionFlushDataBufferMdl,
    ExtFunctionDeviceOperationAllowed,
    ExtFunctionGetProcessorIndexFromNumber,
    ExtFunctionPoFxSetIdleTimeout,
    ExtFunctionMiniportEtwEvent2,
    ExtFunctionMiniportEtwEvent4,
    ExtFunctionMiniportEtwEvent8,
    ExtFunctionCurrentOsInstallationUpgrade,
    ExtFunctionRegistryReadAdapterKey,
    ExtFunctionRegistryWriteAdapterKey,
    ExtFunctionSetAdapterBusType,
    ExtFunctionPoFxRegisterPerfStates,
    ExtFunctionPoFxSetPerfState,
    ExtFunctionGetD3ColdSupport,
    ExtFunctionInitializeRpmb,
    ExtFunctionAllocateHmb,
    ExtFunctionFreeHmb,
    ExtFunctionPropagateIrpExtension,
    ExtFunctionInterlockedInsertHeadList,
    ExtFunctionInterlockedInsertTailList,
    ExtFunctionInterlockedRemoveHeadList,
    ExtFunctionInitializeSpinlock,
    ExtFunctionGetPfns,
    ExtFunctionInitializeCryptoEngine,
    ExtFunctionGetRequestCryptoInfo,
    ExtFunctionMiniportTelemetry,
    ExtFunctionUpdateAdapterMaxIO,
    ExtFunctionDelayExecution,
    ExtFunctionAllocateDmaMemory,
    ExtFunctionFreeDmaMemory,
    ExtFunctionUpdateAdapterMaxIOInfo,
    ExtFunctionMiniportChannelEtwEvent2,
    ExtFunctionMiniportChannelEtwEvent4,
    ExtFunctionMiniportChannelEtwEvent8,
    ExtFunctionInitializeHighResolutionTimer,
    ExtFunctionRequestHighResolutionTimer,
    ExtFunctionCancelHighResolutionTimer,
    ExtFunctionFreeHighResolutionTimer,
    ExtFunctionGetCurrentProcessorIndex,
    ExtFunctionAcquireSpinLock,
    ExtFunctionGetProcessorCount,
    ExtFunctionCancelDpc,
    ExtFunctionMiniportTelemetryEx,
    ExtFunctionQueryConfiguration,
    ExtFunctionLogHardwareError,
    ExtFunctionInitializeEvent,
    ExtFunctionWaitForEvent,
    ExtFunctionSetEvent,
    ExtFunctionDeviceReset,
    ExtFunctionSetFeatureList,
    ExtFunctionCaptureLiveDump,
    ExtFunctionMiniportLogByteStream,
    ExtFunctionQueryDpcWatchdogInformation,
    ExtFunctionQueryTimerMinInterval,
    ExtFunctionMaskPciMsixEntry,
    ExtFunctionGetCurrentIrql,
    ExtFunctionCreateSystemThread,
    ExtFunctionSetPriorityThread,
    ExtFunctionSetSystemGroupAffinityThread,
    ExtFunctionRevertToUserGroupAffinityThread,
    ExtFunctionDeviceResetEx,
    ExtFunctionMiniportReportInternalData,
    ExtFunctionGetMessageInterruptIDFromProcessorIndex,
    ExtFunctionGetNodeAffinity2,
    ExtFunctionEnableRegistryKeyNotification,
    ExtFunctionPoFxRegisterPerfStatesEx,
    ExtFunctionReadRegistryKey,
    ExtFunctionGetDeviceBase2,
    ExtFunctionIsDriverHotSwapEnabled,
    ExtFunctionRegisterDriverProxy,
    ExtFunctionRegisterDriverProxyEndpoints,
    ExtFunctionGetDriverProxyEndpointWrapper,
    ExtFunctionNvmeIceIoStart,
    ExtFunctionNvmeIceIoComplete,
    ExtFunctionNvmeMiniportEvent,
    ExtFunctionNvmeMiniportTelemetry,
    ExtFunctionGetDriverProxyEndpointWrapperFromEndpoint,
    ExtFunctionSwapDriverProxyEndpoints,
    ExtFunctionStorMQAddController,
    ExtFunctionStorMQRemoveController,
    ExtFunctionNvmeIceIoStartEx,
    ExtFunctionQueryNvmeIceSupport,
    ExtFunctionQueueWorkItemToNode
}

enum KEBUGCHECKEX_FUNCTION_CODE
{
    APC_INDEX_MISMATCH = 0x00000001,
    DEVICE_QUEUE_NOT_BUSY = 0x00000002,
    INVALID_AFFINITY_SET = 0x00000003,
    INVALID_DATA_ACCESS_TRAP = 0x00000004,
    INVALID_PROCESS_ATTACH_ATTEMPT = 0x00000005,
    INVALID_PROCESS_DETACH_ATTEMPT = 0x00000006,
    INVALID_SOFTWARE_INTERRUPT = 0x00000007,
    IRQL_NOT_DISPATCH_LEVEL = 0x00000008,
    IRQL_NOT_GREATER_OR_EQUAL = 0x00000009,
    IRQL_NOT_LESS_OR_EQUAL = 0x0000000A,
    NO_EXCEPTION_HANDLING_SUPPORT = 0x0000000B,
    MAXIMUM_WAIT_OBJECTS_EXCEEDED = 0x0000000C,
    MUTEX_LEVEL_NUMBER_VIOLATION = 0x0000000D,
    NO_USER_MODE_CONTEXT = 0x0000000E,
    SPIN_LOCK_ALREADY_OWNED = 0x0000000F,
    SPIN_LOCK_NOT_OWNED = 0x00000010,
    THREAD_NOT_MUTEX_OWNER = 0x00000011,
    TRAP_CAUSE_UNKNOWN = 0x00000012,
    EMPTY_THREAD_REAPER_LIST = 0x00000013,
    CREATE_DELETE_LOCK_NOT_LOCKED = 0x00000014,
    LAST_CHANCE_CALLED_FROM_KMODE = 0x00000015,
    CID_HANDLE_CREATION = 0x00000016,
    CID_HANDLE_DELETION = 0x00000017,
    REFERENCE_BY_POINTER = 0x00000018,
    BAD_POOL_HEADER = 0x00000019,
    MEMORY_MANAGEMENT = 0x0000001A,
    PFN_SHARE_COUNT = 0x0000001B,
    PFN_REFERENCE_COUNT = 0x0000001C,
    NO_SPIN_LOCK_AVAILABLE = 0x0000001D,
    KMODE_EXCEPTION_NOT_HANDLED = 0x0000001E,
    SHARED_RESOURCE_CONV_ERROR = 0x0000001F,
    KERNEL_APC_PENDING_DURING_EXIT = 0x00000020,
    QUOTA_UNDERFLOW = 0x00000021,
    FILE_SYSTEM = 0x00000022,
    FAT_FILE_SYSTEM = 0x00000023,
    NTFS_FILE_SYSTEM = 0x00000024,
    NPFS_FILE_SYSTEM = 0x00000025,
    CDFS_FILE_SYSTEM = 0x00000026,
    RDR_FILE_SYSTEM = 0x00000027,
    CORRUPT_ACCESS_TOKEN = 0x00000028,
    SECURITY_SYSTEM = 0x00000029,
    INCONSISTENT_IRP = 0x0000002A,
    PANIC_STACK_SWITCH = 0x0000002B,
    PORT_DRIVER_INTERNAL = 0x0000002C,
    SCSI_DISK_DRIVER_INTERNAL = 0x0000002D,
    DATA_BUS_ERROR = 0x0000002E,
    INSTRUCTION_BUS_ERROR = 0x0000002F,
    SET_OF_INVALID_CONTEXT = 0x00000030,
    PHASE0_INITIALIZATION_FAILED = 0x00000031,
    PHASE1_INITIALIZATION_FAILED = 0x00000032,
    UNEXPECTED_INITIALIZATION_CALL = 0x00000033,
    CACHE_MANAGER = 0x00000034,
    NO_MORE_IRP_STACK_LOCATIONS = 0x00000035,
    DEVICE_REFERENCE_COUNT_NOT_ZERO = 0x00000036,
    FLOPPY_INTERNAL_ERROR = 0x00000037,
    SERIAL_DRIVER_INTERNAL = 0x00000038,
    SYSTEM_EXIT_OWNED_MUTEX = 0x00000039,
    SYSTEM_UNWIND_PREVIOUS_USER = 0x0000003A,
    SYSTEM_SERVICE_EXCEPTION = 0x0000003B,
    INTERRUPT_UNWIND_ATTEMPTED = 0x0000003C,
    INTERRUPT_EXCEPTION_NOT_HANDLED = 0x0000003D,
    MULTIPROCESSOR_CONFIGURATION_NOT_SUPPORTED = 0x0000003E,
    NO_MORE_SYSTEM_PTES = 0x0000003F,
    TARGET_MDL_TOO_SMALL = 0x00000040,
    MUST_SUCCEED_POOL_EMPTY = 0x00000041,
    ATDISK_DRIVER_INTERNAL = 0x00000042,
    NO_SUCH_PARTITION = 0x00000043,
    MULTIPLE_IRP_COMPLETE_REQUESTS = 0x00000044,
    INSUFFICIENT_SYSTEM_MAP_REGS = 0x00000045,
    DEREF_UNKNOWN_LOGON_SESSION = 0x00000046,
    REF_UNKNOWN_LOGON_SESSION = 0x00000047,
    CANCEL_STATE_IN_COMPLETED_IRP = 0x00000048,
    PAGE_FAULT_WITH_INTERRUPTS_OFF = 0x00000049,
    IRQL_GT_ZERO_AT_SYSTEM_SERVICE = 0x0000004A,
    STREAMS_INTERNAL_ERROR = 0x0000004B,
    FATAL_UNHANDLED_HARD_ERROR = 0x0000004C,
    NO_PAGES_AVAILABLE = 0x0000004D,
    PFN_LIST_CORRUPT = 0x0000004E,
    NDIS_INTERNAL_ERROR = 0x0000004F,
    PAGE_FAULT_IN_NONPAGED_AREA = 0x00000050,
    PAGE_FAULT_IN_NONPAGED_AREA_M = 0x10000050,
    REGISTRY_ERROR = 0x00000051,
    MAILSLOT_FILE_SYSTEM = 0x00000052,
    NO_BOOT_DEVICE = 0x00000053,
    LM_SERVER_INTERNAL_ERROR = 0x00000054,
    DATA_COHERENCY_EXCEPTION = 0x00000055,
    INSTRUCTION_COHERENCY_EXCEPTION = 0x00000056,
    XNS_INTERNAL_ERROR = 0x00000057,
    VOLMGRX_INTERNAL_ERROR = 0x00000058,
    PINBALL_FILE_SYSTEM = 0x00000059,
    CRITICAL_SERVICE_FAILED = 0x0000005A,
    SET_ENV_VAR_FAILED = 0x0000005B,
    HAL_INITIALIZATION_FAILED = 0x0000005C,
    UNSUPPORTED_PROCESSOR = 0x0000005D,
    OBJECT_INITIALIZATION_FAILED = 0x0000005E,
    SECURITY_INITIALIZATION_FAILED = 0x0000005F,
    PROCESS_INITIALIZATION_FAILED = 0x00000060,
    HAL1_INITIALIZATION_FAILED = 0x00000061,
    OBJECT1_INITIALIZATION_FAILED = 0x00000062,
    SECURITY1_INITIALIZATION_FAILED = 0x00000063,
    SYMBOLIC_INITIALIZATION_FAILED = 0x00000064,
    MEMORY1_INITIALIZATION_FAILED = 0x00000065,
    CACHE_INITIALIZATION_FAILED = 0x00000066,
    CONFIG_INITIALIZATION_FAILED = 0x00000067,
    FILE_INITIALIZATION_FAILED = 0x00000068,
    IO1_INITIALIZATION_FAILED = 0x00000069,
    LPC_INITIALIZATION_FAILED = 0x0000006A,
    PROCESS1_INITIALIZATION_FAILED = 0x0000006B,
    REFMON_INITIALIZATION_FAILED = 0x0000006C,
    SESSION1_INITIALIZATION_FAILED = 0x0000006D,
    BOOTPROC_INITIALIZATION_FAILED = 0x0000006E,
    VSL_INITIALIZATION_FAILED = 0x0000006F,
    SOFT_RESTART_FATAL_ERROR = 0x00000070,
    ASSIGN_DRIVE_LETTERS_FAILED = 0x00000072,
    CONFIG_LIST_FAILED = 0x00000073,
    BAD_SYSTEM_CONFIG_INFO = 0x00000074,
    CANNOT_WRITE_CONFIGURATION = 0x00000075,
    PROCESS_HAS_LOCKED_PAGES = 0x00000076,
    KERNEL_STACK_INPAGE_ERROR = 0x00000077,
    PHASE0_EXCEPTION = 0x00000078,
    MISMATCHED_HAL = 0x00000079,
    KERNEL_DATA_INPAGE_ERROR = 0x0000007A,
    INACCESSIBLE_BOOT_DEVICE = 0x0000007B,
    BUGCODE_NDIS_DRIVER = 0x0000007C,
    INSTALL_MORE_MEMORY = 0x0000007D,
    SYSTEM_THREAD_EXCEPTION_NOT_HANDLED = 0x0000007E,
    SYSTEM_THREAD_EXCEPTION_NOT_HANDLED_M = 0x1000007E,
    UNEXPECTED_KERNEL_MODE_TRAP = 0x0000007F,
    UNEXPECTED_KERNEL_MODE_TRAP_M = 0x1000007F,
    NMI_HARDWARE_FAILURE = 0x00000080,
    SPIN_LOCK_INIT_FAILURE = 0x00000081,
    DFS_FILE_SYSTEM = 0x00000082,
    OFS_FILE_SYSTEM = 0x00000083,
    RECOM_DRIVER = 0x00000084,
    SETUP_FAILURE = 0x00000085,
    AUDIT_FAILURE = 0x00000086,
    MBR_CHECKSUM_MISMATCH = 0x0000008B,
    KERNEL_MODE_EXCEPTION_NOT_HANDLED = 0x0000008E,
    KERNEL_MODE_EXCEPTION_NOT_HANDLED_M = 0x1000008E,
    PP0_INITIALIZATION_FAILED = 0x0000008F,
    PP1_INITIALIZATION_FAILED = 0x00000090,
    WIN32K_INIT_OR_RIT_FAILURE = 0x00000091,
    UP_DRIVER_ON_MP_SYSTEM = 0x00000092,
    INVALID_KERNEL_HANDLE = 0x00000093,
    KERNEL_STACK_LOCKED_AT_EXIT = 0x00000094,
    PNP_INTERNAL_ERROR = 0x00000095,
    INVALID_WORK_QUEUE_ITEM = 0x00000096,
    BOUND_IMAGE_UNSUPPORTED = 0x00000097,
    END_OF_NT_EVALUATION_PERIOD = 0x00000098,
    INVALID_REGION_OR_SEGMENT = 0x00000099,
    SYSTEM_LICENSE_VIOLATION = 0x0000009A,
    UDFS_FILE_SYSTEM = 0x0000009B,
    MACHINE_CHECK_EXCEPTION = 0x0000009C,
    USER_MODE_HEALTH_MONITOR = 0x0000009E,
    DRIVER_POWER_STATE_FAILURE = 0x0000009F,
    INTERNAL_POWER_ERROR = 0x000000A0,
    PCI_BUS_DRIVER_INTERNAL = 0x000000A1,
    MEMORY_IMAGE_CORRUPT = 0x000000A2,
    ACPI_DRIVER_INTERNAL = 0x000000A3,
    CNSS_FILE_SYSTEM_FILTER = 0x000000A4,
    ACPI_BIOS_ERROR = 0x000000A5,
    FP_EMULATION_ERROR = 0x000000A6,
    BAD_EXHANDLE = 0x000000A7,
    BOOTING_IN_SAFEMODE_MINIMAL = 0x000000A8,
    BOOTING_IN_SAFEMODE_NETWORK = 0x000000A9,
    BOOTING_IN_SAFEMODE_DSREPAIR = 0x000000AA,
    SESSION_HAS_VALID_POOL_ON_EXIT = 0x000000AB,
    HAL_MEMORY_ALLOCATION = 0x000000AC,
    VIDEO_DRIVER_DEBUG_REPORT_REQUEST = 0x400000AD,
    BGI_DETECTED_VIOLATION = 0x000000B1,
    VIDEO_DRIVER_INIT_FAILURE = 0x000000B4,
    BOOTLOG_LOADED = 0x000000B5,
    BOOTLOG_NOT_LOADED = 0x000000B6,
    BOOTLOG_ENABLED = 0x000000B7,
    ATTEMPTED_SWITCH_FROM_DPC = 0x000000B8,
    CHIPSET_DETECTED_ERROR = 0x000000B9,
    SESSION_HAS_VALID_VIEWS_ON_EXIT = 0x000000BA,
    NETWORK_BOOT_INITIALIZATION_FAILED = 0x000000BB,
    NETWORK_BOOT_DUPLICATE_ADDRESS = 0x000000BC,
    INVALID_HIBERNATED_STATE = 0x000000BD,
    ATTEMPTED_WRITE_TO_READONLY_MEMORY = 0x000000BE,
    MUTEX_ALREADY_OWNED = 0x000000BF,
    PCI_CONFIG_SPACE_ACCESS_FAILURE = 0x000000C0,
    SPECIAL_POOL_DETECTED_MEMORY_CORRUPTION = 0x000000C1,
    BAD_POOL_CALLER = 0x000000C2,
    SYSTEM_IMAGE_BAD_SIGNATURE = 0x000000C3,
    DRIVER_VERIFIER_DETECTED_VIOLATION = 0x000000C4,
    DRIVER_CORRUPTED_EXPOOL = 0x000000C5,
    DRIVER_CAUGHT_MODIFYING_FREED_POOL = 0x000000C6,
    TIMER_OR_DPC_INVALID = 0x000000C7,
    IRQL_UNEXPECTED_VALUE = 0x000000C8,
    DRIVER_VERIFIER_IOMANAGER_VIOLATION = 0x000000C9,
    PNP_DETECTED_FATAL_ERROR = 0x000000CA,
    DRIVER_LEFT_LOCKED_PAGES_IN_PROCESS = 0x000000CB,
    PAGE_FAULT_IN_FREED_SPECIAL_POOL = 0x000000CC,
    PAGE_FAULT_BEYOND_END_OF_ALLOCATION = 0x000000CD,
    DRIVER_UNLOADED_WITHOUT_CANCELLING_PENDING_OPERATIONS = 0x000000CE,
    TERMINAL_SERVER_DRIVER_MADE_INCORRECT_MEMORY_REFERENCE = 0x000000CF,
    DRIVER_CORRUPTED_MMPOOL = 0x000000D0,
    DRIVER_IRQL_NOT_LESS_OR_EQUAL = 0x000000D1,
    BUGCODE_ID_DRIVER = 0x000000D2,
    DRIVER_PORTION_MUST_BE_NONPAGED = 0x000000D3,
    SYSTEM_SCAN_AT_RAISED_IRQL_CAUGHT_IMPROPER_DRIVER_UNLOAD = 0x000000D4,
    DRIVER_PAGE_FAULT_IN_FREED_SPECIAL_POOL = 0x000000D5,
    DRIVER_PAGE_FAULT_BEYOND_END_OF_ALLOCATION = 0x000000D6,
    DRIVER_PAGE_FAULT_BEYOND_END_OF_ALLOCATION_M = 0x100000D6,
    DRIVER_UNMAPPING_INVALID_VIEW = 0x000000D7,
    DRIVER_USED_EXCESSIVE_PTES = 0x000000D8,
    LOCKED_PAGES_TRACKER_CORRUPTION = 0x000000D9,
    SYSTEM_PTE_MISUSE = 0x000000DA,
    DRIVER_CORRUPTED_SYSPTES = 0x000000DB,
    DRIVER_INVALID_STACK_ACCESS = 0x000000DC,
    POOL_CORRUPTION_IN_FILE_AREA = 0x000000DE,
    IMPERSONATING_WORKER_THREAD = 0x000000DF,
    ACPI_BIOS_FATAL_ERROR = 0x000000E0,
    WORKER_THREAD_RETURNED_AT_BAD_IRQL = 0x000000E1,
    MANUALLY_INITIATED_CRASH = 0x000000E2,
    RESOURCE_NOT_OWNED = 0x000000E3,
    WORKER_INVALID = 0x000000E4,
    POWER_FAILURE_SIMULATE = 0x000000E5,
    DRIVER_VERIFIER_DMA_VIOLATION = 0x000000E6,
    INVALID_FLOATING_POINT_STATE = 0x000000E7,
    INVALID_CANCEL_OF_FILE_OPEN = 0x000000E8,
    ACTIVE_EX_WORKER_THREAD_TERMINATION = 0x000000E9,
    SAVER_UNSPECIFIED = 0x0000F000,
    SAVER_BLANKSCREEN = 0x0000F002,
    SAVER_INPUT = 0x0000F003,
    SAVER_WATCHDOG = 0x0000F004,
    SAVER_STARTNOTVISIBLE = 0x0000F005,
    SAVER_NAVIGATIONMODEL = 0x0000F006,
    SAVER_OUTOFMEMORY = 0x0000F007,
    SAVER_GRAPHICS = 0x0000F008,
    SAVER_NAVSERVERTIMEOUT = 0x0000F009,
    SAVER_CHROMEPROCESSCRASH = 0x0000F00A,
    SAVER_NOTIFICATIONDISMISSAL = 0x0000F00B,
    SAVER_SPEECHDISMISSAL = 0x0000F00C,
    SAVER_CALLDISMISSAL = 0x0000F00D,
    SAVER_APPBARDISMISSAL = 0x0000F00E,
    SAVER_RILADAPTATIONCRASH = 0x0000F00F,
    SAVER_APPLISTUNREACHABLE = 0x0000F010,
    SAVER_REPORTNOTIFICATIONFAILURE = 0x0000F011,
    SAVER_UNEXPECTEDSHUTDOWN = 0x0000F012,
    SAVER_RPCFAILURE = 0x0000F013,
    SAVER_AUXILIARYFULLDUMP = 0x0000F014,
    SAVER_ACCOUNTPROVSVCINITFAILURE = 0x0000F015,
    SAVER_MTBFCOMMANDTIMEOUT = 0x00000315,
    SAVER_MTBFCOMMANDHANG = 0x0000F101,
    SAVER_MTBFPASSBUGCHECK = 0x0000F102,
    SAVER_MTBFIOERROR = 0x0000F103,
    SAVER_RENDERTHREADHANG = 0x0000F200,
    SAVER_RENDERMOBILEUIOOM = 0x0000F201,
    SAVER_DEVICEUPDATEUNSPECIFIED = 0x0000F300,
    SAVER_AUDIODRIVERHANG = 0x0000F400,
    SAVER_BATTERYPULLOUT = 0x0000F500,
    SAVER_MEDIACORETESTHANG = 0x0000F600,
    SAVER_RESOURCEMANAGEMENT = 0x0000F700,
    SAVER_CAPTURESERVICE = 0x0000F800,
    SAVER_WAITFORSHELLREADY = 0x0000F900,
    SAVER_NONRESPONSIVEPROCESS = 0x00000194,
    SAVER_SICKAPPLICATION = 0x00008866,
    THREAD_STUCK_IN_DEVICE_DRIVER = 0x000000EA,
    THREAD_STUCK_IN_DEVICE_DRIVER_M = 0x100000EA,
    DIRTY_MAPPED_PAGES_CONGESTION = 0x000000EB,
    SESSION_HAS_VALID_SPECIAL_POOL_ON_EXIT = 0x000000EC,
    UNMOUNTABLE_BOOT_VOLUME = 0x000000ED,
    CRITICAL_PROCESS_DIED = 0x000000EF,
    STORAGE_MINIPORT_ERROR = 0x000000F0,
    SCSI_VERIFIER_DETECTED_VIOLATION = 0x000000F1,
    HARDWARE_INTERRUPT_STORM = 0x000000F2,
    DISORDERLY_SHUTDOWN = 0x000000F3,
    CRITICAL_OBJECT_TERMINATION = 0x000000F4,
    FLTMGR_FILE_SYSTEM = 0x000000F5,
    PCI_VERIFIER_DETECTED_VIOLATION = 0x000000F6,
    DRIVER_OVERRAN_STACK_BUFFER = 0x000000F7,
    RAMDISK_BOOT_INITIALIZATION_FAILED = 0x000000F8,
    DRIVER_RETURNED_STATUS_REPARSE_FOR_VOLUME_OPEN = 0x000000F9,
    HTTP_DRIVER_CORRUPTED = 0x000000FA,
    RECURSIVE_MACHINE_CHECK = 0x000000FB,
    ATTEMPTED_EXECUTE_OF_NOEXECUTE_MEMORY = 0x000000FC,
    DIRTY_NOWRITE_PAGES_CONGESTION = 0x000000FD,
    BUGCODE_USB_DRIVER = 0x000000FE,
    BC_BLUETOOTH_VERIFIER_FAULT = 0x00000BFE,
    BC_BTHMINI_VERIFIER_FAULT = 0x00000BFF,
    RESERVE_QUEUE_OVERFLOW = 0x000000FF,
    LOADER_BLOCK_MISMATCH = 0x00000100,
    CLOCK_WATCHDOG_TIMEOUT = 0x00000101,
    DPC_WATCHDOG_TIMEOUT = 0x00000102,
    MUP_FILE_SYSTEM = 0x00000103,
    AGP_INVALID_ACCESS = 0x00000104,
    AGP_GART_CORRUPTION = 0x00000105,
    AGP_ILLEGALLY_REPROGRAMMED = 0x00000106,
    KERNEL_EXPAND_STACK_ACTIVE = 0x00000107,
    THIRD_PARTY_FILE_SYSTEM_FAILURE = 0x00000108,
    CRITICAL_STRUCTURE_CORRUPTION = 0x00000109,
    APP_TAGGING_INITIALIZATION_FAILED = 0x0000010A,
    DFSC_FILE_SYSTEM = 0x0000010B,
    FSRTL_EXTRA_CREATE_PARAMETER_VIOLATION = 0x0000010C,
    WDF_VIOLATION = 0x0000010D,
    VIDEO_MEMORY_MANAGEMENT_INTERNAL = 0x0000010E,
    DRIVER_INVALID_CRUNTIME_PARAMETER = 0x00000110,
    RECURSIVE_NMI = 0x00000111,
    MSRPC_STATE_VIOLATION = 0x00000112,
    VIDEO_DXGKRNL_FATAL_ERROR = 0x00000113,
    VIDEO_SHADOW_DRIVER_FATAL_ERROR = 0x00000114,
    AGP_INTERNAL = 0x00000115,
    VIDEO_TDR_FAILURE = 0x00000116,
    VIDEO_TDR_TIMEOUT_DETECTED = 0x00000117,
    NTHV_GUEST_ERROR = 0x00000118,
    VIDEO_SCHEDULER_INTERNAL_ERROR = 0x00000119,
    EM_INITIALIZATION_ERROR = 0x0000011A,
    DRIVER_RETURNED_HOLDING_CANCEL_LOCK = 0x0000011B,
    ATTEMPTED_WRITE_TO_CM_PROTECTED_STORAGE = 0x0000011C,
    EVENT_TRACING_FATAL_ERROR = 0x0000011D,
    TOO_MANY_RECURSIVE_FAULTS = 0x0000011E,
    INVALID_DRIVER_HANDLE = 0x0000011F,
    BITLOCKER_FATAL_ERROR = 0x00000120,
    DRIVER_VIOLATION = 0x00000121,
    WHEA_INTERNAL_ERROR = 0x00000122,
    CRYPTO_SELF_TEST_FAILURE = 0x00000123,
    WHEA_UNCORRECTABLE_ERROR = 0x00000124,
    NMR_INVALID_STATE = 0x00000125,
    NETIO_INVALID_POOL_CALLER = 0x00000126,
    PAGE_NOT_ZERO = 0x00000127,
    WORKER_THREAD_RETURNED_WITH_BAD_IO_PRIORITY = 0x00000128,
    WORKER_THREAD_RETURNED_WITH_BAD_PAGING_IO_PRIORITY = 0x00000129,
    MUI_NO_VALID_SYSTEM_LANGUAGE = 0x0000012A,
    FAULTY_HARDWARE_CORRUPTED_PAGE = 0x0000012B,
    EXFAT_FILE_SYSTEM = 0x0000012C,
    VOLSNAP_OVERLAPPED_TABLE_ACCESS = 0x0000012D,
    INVALID_MDL_RANGE = 0x0000012E,
    VHD_BOOT_INITIALIZATION_FAILED = 0x0000012F,
    DYNAMIC_ADD_PROCESSOR_MISMATCH = 0x00000130,
    INVALID_EXTENDED_PROCESSOR_STATE = 0x00000131,
    RESOURCE_OWNER_POINTER_INVALID = 0x00000132,
    DPC_WATCHDOG_VIOLATION = 0x00000133,
    DRIVE_EXTENDER = 0x00000134,
    REGISTRY_FILTER_DRIVER_EXCEPTION = 0x00000135,
    VHD_BOOT_HOST_VOLUME_NOT_ENOUGH_SPACE = 0x00000136,
    WIN32K_HANDLE_MANAGER = 0x00000137,
    GPIO_CONTROLLER_DRIVER_ERROR = 0x00000138,
    KERNEL_SECURITY_CHECK_FAILURE = 0x00000139,
    KERNEL_MODE_HEAP_CORRUPTION = 0x0000013A,
    PASSIVE_INTERRUPT_ERROR = 0x0000013B,
    INVALID_IO_BOOST_STATE = 0x0000013C,
    CRITICAL_INITIALIZATION_FAILURE = 0x0000013D,
    ERRATA_WORKAROUND_UNSUCCESSFUL = 0x0000013E,
    REGISTRY_CALLBACK_DRIVER_EXCEPTION = 0x0000013F,
    STORAGE_DEVICE_ABNORMALITY_DETECTED = 0x00000140,
    VIDEO_ENGINE_TIMEOUT_DETECTED = 0x00000141,
    VIDEO_TDR_APPLICATION_BLOCKED = 0x00000142,
    PROCESSOR_DRIVER_INTERNAL = 0x00000143,
    BUGCODE_USB3_DRIVER = 0x00000144,
    SECURE_BOOT_VIOLATION = 0x00000145,
    NDIS_NET_BUFFER_LIST_INFO_ILLEGALLY_TRANSFERRED = 0x00000146,
    ABNORMAL_RESET_DETECTED = 0x00000147,
    IO_OBJECT_INVALID = 0x00000148,
    REFS_FILE_SYSTEM = 0x00000149,
    KERNEL_WMI_INTERNAL = 0x0000014A,
    SOC_SUBSYSTEM_FAILURE = 0x0000014B,
    FATAL_ABNORMAL_RESET_ERROR = 0x0000014C,
    EXCEPTION_SCOPE_INVALID = 0x0000014D,
    SOC_CRITICAL_DEVICE_REMOVED = 0x0000014E,
    PDC_WATCHDOG_TIMEOUT = 0x0000014F,
    TCPIP_AOAC_NIC_ACTIVE_REFERENCE_LEAK = 0x00000150,
    UNSUPPORTED_INSTRUCTION_MODE = 0x00000151,
    INVALID_PUSH_LOCK_FLAGS = 0x00000152,
    KERNEL_LOCK_ENTRY_LEAKED_ON_THREAD_TERMINATION = 0x00000153,
    UNEXPECTED_STORE_EXCEPTION = 0x00000154,
    OS_DATA_TAMPERING = 0x00000155,
    WINSOCK_DETECTED_HUNG_CLOSESOCKET_LIVEDUMP = 0x00000156,
    KERNEL_THREAD_PRIORITY_FLOOR_VIOLATION = 0x00000157,
    ILLEGAL_IOMMU_PAGE_FAULT = 0x00000158,
    HAL_ILLEGAL_IOMMU_PAGE_FAULT = 0x00000159,
    SDBUS_INTERNAL_ERROR = 0x0000015A,
    WORKER_THREAD_RETURNED_WITH_SYSTEM_PAGE_PRIORITY_ACTIVE = 0x0000015B,
    PDC_WATCHDOG_TIMEOUT_LIVEDUMP = 0x0000015C,
    SOC_SUBSYSTEM_FAILURE_LIVEDUMP = 0x0000015D,
    BUGCODE_NDIS_DRIVER_LIVE_DUMP = 0x0000015E,
    CONNECTED_STANDBY_WATCHDOG_TIMEOUT_LIVEDUMP = 0x0000015F,
    WIN32K_ATOMIC_CHECK_FAILURE = 0x00000160,
    LIVE_SYSTEM_DUMP = 0x00000161,
    KERNEL_AUTO_BOOST_INVALID_LOCK_RELEASE = 0x00000162,
    WORKER_THREAD_TEST_CONDITION = 0x00000163,
    WIN32K_CRITICAL_FAILURE = 0x00000164,
    CLUSTER_CSV_STATUS_IO_TIMEOUT_LIVEDUMP = 0x00000165,
    CLUSTER_RESOURCE_CALL_TIMEOUT_LIVEDUMP = 0x00000166,
    CLUSTER_CSV_SNAPSHOT_DEVICE_INFO_TIMEOUT_LIVEDUMP = 0x00000167,
    CLUSTER_CSV_STATE_TRANSITION_TIMEOUT_LIVEDUMP = 0x00000168,
    CLUSTER_CSV_VOLUME_ARRIVAL_LIVEDUMP = 0x00000169,
    CLUSTER_CSV_VOLUME_REMOVAL_LIVEDUMP = 0x0000016A,
    CLUSTER_CSV_CLUSTER_WATCHDOG_LIVEDUMP = 0x0000016B,
    INVALID_RUNDOWN_PROTECTION_FLAGS = 0x0000016C,
    INVALID_SLOT_ALLOCATOR_FLAGS = 0x0000016D,
    ERESOURCE_INVALID_RELEASE = 0x0000016E,
    CLUSTER_CSV_STATE_TRANSITION_INTERVAL_TIMEOUT_LIVEDUMP = 0x0000016F,
    CLUSTER_CSV_CLUSSVC_DISCONNECT_WATCHDOG = 0x00000170,
    CRYPTO_LIBRARY_INTERNAL_ERROR = 0x00000171,
    SECURE_KERNEL_HIBERNATE_ERROR = 0x00000172,
    COREMSGCALL_INTERNAL_ERROR = 0x00000173,
    COREMSG_INTERNAL_ERROR = 0x00000174,
    PREVIOUS_FATAL_ABNORMAL_RESET_ERROR = 0x00000175,
    STORAGE_STACK_FATAL_ERROR = 0x00000176,
    ELAM_DRIVER_DETECTED_FATAL_ERROR = 0x00000178,
    CLUSTER_CLUSPORT_STATUS_IO_TIMEOUT_LIVEDUMP = 0x00000179,
    PROFILER_CONFIGURATION_ILLEGAL = 0x0000017B,
    PDC_LOCK_WATCHDOG_LIVEDUMP = 0x0000017C,
    PDC_UNEXPECTED_REVOCATION_LIVEDUMP = 0x0000017D,
    MICROCODE_REVISION_MISMATCH = 0x0000017E,
    HYPERGUARD_INITIALIZATION_FAILURE = 0x0000017F,
    WVR_LIVEDUMP_REPLICATION_IOCONTEXT_TIMEOUT = 0x00000180,
    WVR_LIVEDUMP_STATE_TRANSITION_TIMEOUT = 0x00000181,
    WVR_LIVEDUMP_RECOVERY_IOCONTEXT_TIMEOUT = 0x00000182,
    WVR_LIVEDUMP_APP_IO_TIMEOUT = 0x00000183,
    WVR_LIVEDUMP_MANUALLY_INITIATED = 0x00000184,
    WVR_LIVEDUMP_STATE_FAILURE = 0x00000185,
    WVR_LIVEDUMP_CRITICAL_ERROR = 0x00000186,
    VIDEO_DWMINIT_TIMEOUT_FALLBACK_BDD = 0x00000187,
    CLUSTER_CSVFS_LIVEDUMP = 0x00000188,
    BAD_OBJECT_HEADER = 0x00000189,
    SILO_CORRUPT = 0x0000018A,
    SECURE_KERNEL_ERROR = 0x0000018B,
    HYPERGUARD_VIOLATION = 0x0000018C,
    SECURE_FAULT_UNHANDLED = 0x0000018D,
    KERNEL_PARTITION_REFERENCE_VIOLATION = 0x0000018E,
    SYNTHETIC_EXCEPTION_UNHANDLED = 0x0000018F,
    WIN32K_CRITICAL_FAILURE_LIVEDUMP = 0x00000190,
    PF_DETECTED_CORRUPTION = 0x00000191,
    KERNEL_AUTO_BOOST_LOCK_ACQUISITION_WITH_RAISED_IRQL = 0x00000192,
    VIDEO_DXGKRNL_LIVEDUMP = 0x00000193,
    KERNEL_STORAGE_SLOT_IN_USE = 0x00000199,
    SMB_SERVER_LIVEDUMP = 0x00000195,
    LOADER_ROLLBACK_DETECTED = 0x00000196,
    WIN32K_SECURITY_FAILURE = 0x00000197,
    UFX_LIVEDUMP = 0x00000198,
    WORKER_THREAD_RETURNED_WHILE_ATTACHED_TO_SILO = 0x0000019A,
    TTM_FATAL_ERROR = 0x0000019B,
    WIN32K_POWER_WATCHDOG_TIMEOUT = 0x0000019C,
    CLUSTER_SVHDX_LIVEDUMP = 0x0000019D,
    BUGCODE_NETADAPTER_DRIVER = 0x0000019E,
    PDC_PRIVILEGE_CHECK_LIVEDUMP = 0x0000019F,
    TTM_WATCHDOG_TIMEOUT = 0x000001A0,
    WIN32K_CALLOUT_WATCHDOG_LIVEDUMP = 0x000001A1,
    WIN32K_CALLOUT_WATCHDOG_BUGCHECK = 0x000001A2,
    CALL_HAS_NOT_RETURNED_WATCHDOG_TIMEOUT_LIVEDUMP = 0x000001A3,
    DRIPS_SW_HW_DIVERGENCE_LIVEDUMP = 0x000001A4,
    USB_DRIPS_BLOCKER_SURPRISE_REMOVAL_LIVEDUMP = 0x000001A5,
    BLUETOOTH_ERROR_RECOVERY_LIVEDUMP = 0x000001A6,
    SMB_REDIRECTOR_LIVEDUMP = 0x000001A7,
    VIDEO_DXGKRNL_BLACK_SCREEN_LIVEDUMP = 0x000001A8,
    DIRECTED_FX_TRANSITION_LIVEDUMP = 0x000001A9,
    EXCEPTION_ON_INVALID_STACK = 0x000001AA,
    UNWIND_ON_INVALID_STACK = 0x000001AB,
    VIDEO_MINIPORT_FAILED_LIVEDUMP = 0x000001B0,
    VIDEO_MINIPORT_BLACK_SCREEN_LIVEDUMP = 0x000001B8,
    DRIVER_VERIFIER_DETECTED_VIOLATION_LIVEDUMP = 0x000001C4,
    IO_THREADPOOL_DEADLOCK_LIVEDUMP = 0x000001C5,
    FAST_ERESOURCE_PRECONDITION_VIOLATION = 0x000001C6,
    STORE_DATA_STRUCTURE_CORRUPTION = 0x000001C7,
    MANUALLY_INITIATED_POWER_BUTTON_HOLD = 0x000001C8,
    USER_MODE_HEALTH_MONITOR_LIVEDUMP = 0x000001C9,
    SYNTHETIC_WATCHDOG_TIMEOUT = 0x000001CA,
    INVALID_SILO_DETACH = 0x000001CB,
    EXRESOURCE_TIMEOUT_LIVEDUMP = 0x000001CC,
    INVALID_CALLBACK_STACK_ADDRESS = 0x000001CD,
    INVALID_KERNEL_STACK_ADDRESS = 0x000001CE,
    HARDWARE_WATCHDOG_TIMEOUT = 0x000001CF,
    ACPI_FIRMWARE_WATCHDOG_TIMEOUT = 0x000001D0,
    TELEMETRY_ASSERTS_LIVEDUMP = 0x000001D1,
    WORKER_THREAD_INVALID_STATE = 0x000001D2,
    WFP_INVALID_OPERATION = 0x000001D3,
    UCMUCSI_LIVEDUMP = 0x000001D4,
    DRIVER_PNP_WATCHDOG = 0x000001D5,
    WORKER_THREAD_RETURNED_WITH_NON_DEFAULT_WORKLOAD_CLASS = 0x000001D6,
    EFS_FATAL_ERROR = 0x000001D7,
    UCMUCSI_FAILURE = 0x000001D8,
    HAL_IOMMU_INTERNAL_ERROR = 0x000001D9,
    HAL_BLOCKED_PROCESSOR_INTERNAL_ERROR = 0x000001DA,
    IPI_WATCHDOG_TIMEOUT = 0x000001DB,
    DMA_COMMON_BUFFER_VECTOR_ERROR = 0x000001DC,
    BUGCODE_MBBADAPTER_DRIVER = 0x000001DD,
    BUGCODE_WIFIADAPTER_DRIVER = 0x000001DE,
    PROCESSOR_START_TIMEOUT = 0x000001DF,
    INVALID_ALTERNATE_SYSTEM_CALL_HANDLER_REGISTRATION = 0x000001E0,
    DEVICE_DIAGNOSTIC_LOG_LIVEDUMP = 0x000001E1,
    AZURE_DEVICE_FW_DUMP = 0x000001E2,
    BREAKAWAY_CABLE_TRANSITION = 0x000001E3,
    VIDEO_DXGKRNL_SYSMM_FATAL_ERROR = 0x000001E4,
    DRIVER_VERIFIER_TRACKING_LIVE_DUMP = 0x000001E5,
    CRASHDUMP_WATCHDOG_TIMEOUT = 0x000001E6,
    REGISTRY_LIVE_DUMP = 0x000001E7,
    INVALID_THREAD_AFFINITY_STATE = 0x000001E8,
    ILLEGAL_ATS_INITIALIZATION = 0x000001E9,
    SECURE_PCI_CONFIG_SPACE_ACCESS_VIOLATION = 0x000001EA,
    DAM_WATCHDOG_TIMEOUT = 0x000001EB,
    HANDLE_LIVE_DUMP = 0x000001EC,
    HANDLE_ERROR_ON_CRITICAL_THREAD = 0x000001ED,
    MPSDRV_QUERY_USER = 0x400001EE,
    VMBUS_LIVEDUMP = 0x400001EF,
    USB4_HARDWARE_VIOLATION = 0x000001F0,
    KASAN_ENLIGHTENMENT_VIOLATION = 0x000001F1,
    KASAN_ILLEGAL_ACCESS = 0x000001F2,
    IORING = 0x000001F3,
    MDL_CACHE = 0x000001F4,
    APPLICATION_HANG_KERNEL_LIVEDUMP = 0x000001F5,
    MISALIGNED_POINTER_PARAMETER = 0x000001F6,
    MSSECCORE_ASSERTION_FAILURE = 0x000001F7,
    INVALID_MINIMAL_PROCESS_STATE = 0x000001F8,
    PREVIOUS_MODE_MISMATCH = 0x000001F9,
    SMB_SRV_REQUEST_VALIDATION_FAILURE = 0x000001FA,
    IOMMU_INTERRUPT_REMAPPING_FAULT = 0x000001FB,
    WIN32K_CALLOUT_UNREGISTER_FAILED = 0x000001FC,
    HAL_SPE_INTERNAL_ERROR = 0x000001FD,
    SMB_CLIENT_REQUEST_VALIDATION_FAILURE = 0x000001FE,
    CPU_SCHEDULER_INTERNAL_ERROR = 0x00000200,
    PROCESS_TERMINATE_LIKELY_DEADLOCK = 0x00000201,
    UNEXPECTED_CODEPATH = 0x00000202,
    INVALID_EXTENSION_STATE = 0x00000203,
    STORAGE_DRIVER_LIVEDUMP = 0x00000207,
    XBOX_VMCTRL_CS_TIMEOUT = 0x00000356,
    XBOX_CORRUPTED_IMAGE = 0x00000357,
    XBOX_INVERTED_FUNCTION_TABLE_OVERFLOW = 0x00000358,
    XBOX_CORRUPTED_IMAGE_BASE = 0x00000359,
    XBOX_XDS_WATCHDOG_TIMEOUT = 0x0000035A,
    XBOX_SHUTDOWN_WATCHDOG_TIMEOUT = 0x0000035B,
    XBOX_CANNOT_MANAGE_PARTITION_MEMORY = 0x0000035D,
    XBOX_360_SYSTEM_CRASH = 0x00000360,
    XBOX_360_SYSTEM_CRASH_RESERVED = 0x00000420,
    XBOX_SECURITY_FAILUE = 0x00000421,
    KERNEL_CFG_INIT_FAILURE = 0x00000422,
    MANUALLY_INITIATED_POWER_BUTTON_HOLD_LIVE_DUMP = 0x000011C8,
    HYPERVISOR_ERROR = 0x00020001,
    XBOX_MANUALLY_INITIATED_CRASH = 0x00030006,
    MANUALLY_INITIATED_BLACKSCREEN_HOTKEY_LIVE_DUMP = 0x000021C8,
    WINLOGON_FATAL_ERROR = unchecked((int)0xC000021A),
    MANUALLY_INITIATED_CRASH1 = unchecked((int)0xDEADDEAD)
}

public class DisassemblyTransform
{
    public static string HexToAscii(string value)
    {
        string ret = "";

        Byte[] by = new Byte[1];
        for (int i = value.Length; i > 0; i -= 2) {
            int length = (i > 1)? 2: 1;
            string two = value.Substring(i - length, length);
            by[0] = Convert.ToByte(two, 16);
            try
            {
                ret += Encoding.ASCII.GetString(by);
            }
            catch(ArgumentException)
            {
                ret += $"0x{two}";
            }
        }
        ret = $"{value}\x2B8E'{ret}'";
        return ret;
    }
}


public class ParseDisassembly
{
    public class Unreliable
    {
        private bool Value;

        public Unreliable(bool init)
        {
            Value = init;
        }
        public static explicit operator bool(Unreliable source)
        {
            return source.Value;
        }
    }

    Node _tree;
    Regex _guardDispatchPattern;

    /*Some indirect enums can be unreliable:
        mov     r8,1h
        lea     ecx,[r8+5Ch]
        call    storport!StorPortExtendedFunction

      In this case, the STORPORT_FUNCTION_CODE enum matches
      improperly 0x5C=ExtFunctionGetCurrentProcessorIndex.

      This must be a warning.
    */
    public Unreliable IsUnreliable;
    const string FlowAnalysisCookie = "Flow analysis was incomplete, some code may be missing";

    private class IdentifyArgument
    {
        public string Target;
        public string SourceDisasm;
        public uint AboveLimit;
        public Regex CompiledPattern;
        public object RegisterValue;
        public bool Unreliable;
        public Func<string, string> Transform;
    }

    IdentifyArgument[] _indirectSourceBlock =
    {
        new(){
            Target = @"call    \w+!KeInitializeDpc",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 2
        },
        new(){
            Target = @"call    \w+!KeInitializeThreadedDpc",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 2
        },
        new(){
            Target = @"call    \w+!KeSynchronizeExecution",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!MmMapMdl",
            SourceDisasm = @"lea     r8,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!IoQueueWorkItem",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 10
        },
        new(){
            Target = @"call    \w+!IoQueueWorkItemEx",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 10
        },
        new()
        {
            Target = @"call    \w+!PoRequestPowerIrp",
            SourceDisasm = @"lea     r9,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 8
        },
        new(){
            Target = @"call    storport!StorPortNotification",
            SourceDisasm = @"mov     ecx,(?<solution>.+)h",
            AboveLimit = 8,
            RegisterValue = new SCSI_NOTIFICATION_TYPE()
        },
        new(){
            Target = @"call    storport!StorPortExtendedFunction",
            SourceDisasm = @"((mov     ecx,(?<solution>[0-9A-F]+)h)|(lea     ecx,\[r8\+(?<solution>[0-9A-F]+)h\]))",
            AboveLimit = 8,
            RegisterValue = new STORPORT_FUNCTION_CODE(),
            Unreliable = true
        },
        new(){
            Target = @"call    \w+!KeBugCheckEx",
            SourceDisasm = @"((mov     ecx,(?<solution>[0-9A-F]+)h)|(lea     ecx,\[r8\+(?<solution>[0-9A-F]+)h\]))",
            AboveLimit = 8,
            RegisterValue = new KEBUGCHECKEX_FUNCTION_CODE(),
            Unreliable = true
        },
        new(){
            Target = @"call    \w+!IoRegisterPlugPlayNotification",
            SourceDisasm = @"lea     rax,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]\n(.+?\n){0,2}[0-9a-f]+?\s+mov     qword ptr \[rsp\+20h\],rax",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!ExAllocatePoolWithTag",
            SourceDisasm = @"mov     r8d,(?<solution>.+)h",
            AboveLimit = 4,
            Transform = DisassemblyTransform.HexToAscii
        },
        new(){
            Target = @"call    \w+!ExAllocatePoolWithQuotaTag",
            SourceDisasm = @"mov     r8d,(?<solution>.+)h",
            AboveLimit = 4,
            Transform = DisassemblyTransform.HexToAscii
        },
        new(){
            Target = @"call    \w+!ExAllocatePoolWithTagPriority",
            SourceDisasm = @"mov     r8d,(?<solution>.+)h",
            AboveLimit = 4,
            Transform = DisassemblyTransform.HexToAscii
        },
        new(){
            Target = @"call    \w+!ExAllocatePool2",
            SourceDisasm = @"mov     r8d,(?<solution>.+)h",
            AboveLimit = 7,
            Transform = DisassemblyTransform.HexToAscii
        },
        new(){
            Target = @"call    \w+!ExAllocatePool3",
            SourceDisasm = @"mov     r8d,(?<solution>.+)h",
            AboveLimit = 8,
            Transform = DisassemblyTransform.HexToAscii
        },
        new(){
            Target = @"call    \w+!IoQueryInterface",
            SourceDisasm = @"lea     r8,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 7
        }
    };

    public void CreateTree(bool upcall, string delimiter, string path, string key, uint depth, string[] stopSymbols, Dictionary<string, string> retpoline)
    {
        StreamReader istream = new(path);
        var content = istream.ReadToEnd();
        istream.Close();
        List<string> body = content.Split(delimiter, StringSplitOptions.RemoveEmptyEntries).ToList();
        content = null;
        string address = "";
        Node tree = new();
        var level = LocateSectionByKeyFunction(key, body, ref address);
        tree.Symbol = key;
        tree.Index = level;
        if (level == -1)
        {
            var levels = LocateSectionByRandomKey(key, body);
            if (levels.Count == 0)
            {
                return;
            }
            InitializeIndirectRegex();
            foreach (var iter in levels)
            {
                Node dep = new();
                dep.Index = iter;
                GetSectionHeader(body[iter], ref dep.Symbol, ref dep.Address);
                if (upcall)
                {
                    LocateDependencyRecursiveUpcall(1, depth, ref dep, body);
                }
                else
                {
                    LocateDependencyRecursiveDowncall(1, depth, ref dep, body, stopSymbols, retpoline);
                }
                tree.Dependency.Add(dep);
            }
        }
        else
        {
            tree.Address = address;
            InitializeIndirectRegex();
            if (upcall)
            {
                LocateDependencyRecursiveUpcall(0, depth, ref tree, body);
            }
            else
            {
                LocateDependencyRecursiveDowncall(0, depth, ref tree, body, stopSymbols, retpoline);
            }
        }
        if (tree.Dependency.Count != 0)
        {
            AddExpand(tree.Dependency);
        }
        else
        {
            tree.Expand = Expand.None;
        }
        _tree = tree;
    }

    public Node GetTree()
    {
        return _tree;
    }

    private void InitializeIndirectRegex()
    {
        foreach (var iter in _indirectSourceBlock)
        {
            iter.CompiledPattern = new($"{iter.SourceDisasm}\\n(.*?\\n){{0,{iter.AboveLimit}}}[0-9a-f]+?\\s+{iter.Target}", RegexOptions.Compiled);
        }
    }

    private void GetSectionHeader(in string section, ref string symbol, ref string address)
    {
        string[] header = section.Split("\n", 3);

        address = header[0].Replace("uf ", "");
        symbol = header[1] == FlowAnalysisCookie ?
                 header[2].Substring(0, header[2].IndexOf("\n")) : header[1];
        symbol = symbol.Substring(0, symbol.Length - 1);
    }

    private List<int> LocateSectionsByUpcall(in List<string> body, Regex pattern)
    {
        List<int> result = new();

        for (int i = 0; i < body.Count; i++)
        {
            if (pattern.IsMatch(body[i]))
            {
                result.Add(i);
            }
        }
        if (result.Count == 0)
        {
            result.Add(-1);
        }

        return result;
    }

    private void AddExpand(List<Node> tree)
    {
        Node el = null;
        int i;

        for (i = 0; i < tree.Count; i++)
        {
            bool noArrow = (tree[i].Hint == DrawHint.BodyNotFound ||
                            tree[i].Hint == DrawHint.Retpoline ||
                            tree[i].Hint == DrawHint.AtEnd ||
                            tree[i].Hint == DrawHint.StopDisassembly ||
                            tree[i].Hint == DrawHint.ImportAddressTable ||
                            tree[i].Hint == DrawHint.Indirect);
            if (noArrow)
            {
                tree[i].Expand = Expand.None;
            }
            else
            {
                tree[i].Expand = Expand.ExpandLast;
                if (el != null)
                {
                    el.Expand = Expand.ExpandMiddle;
                }
                el = tree[i];
            }
            if (tree[i].Dependency.Count != 0)
            {
                AddExpand(tree[i].Dependency);
            }
        }
        for (i = tree.Count - 1; i >= 0 && tree[i].Expand == Expand.None; i--) ;
        for (i++; i < tree.Count; i++)
        {
            tree[i].Expand = Expand.Empty;
        }
    }

    private void LocateDependencyRecursiveUpcall(uint current, uint depth, ref Node node, in List<string> body)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        current++;
        Regex pattern = new($"call    {node.Symbol} \\({node.Address}\\)");
        var idx = LocateSectionsByUpcall(body, pattern);
        if (idx[0] == -1)
        {
            node.Hint = DrawHint.BodyNotFound;
            return;
        }
        foreach (var iter in idx)
        {
            Node dep = new();

            dep.Index = iter;
            GetSectionHeader(body[iter], ref dep.Symbol, ref dep.Address);
            dep.Hint = DrawHint.HasDependency;
            node.Dependency.Add(dep);
            LocateDependencyRecursiveUpcall(current, depth, ref dep, body);
        }
    }

    private void LocateDependencyRecursiveDowncall(uint current, uint depth, ref Node node, in List<string> body, in string[] stopSymbols, in Dictionary<string, string> retpoline)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        IdentifyArgument indirect = new();
        current++;
        var idx = node.Index;
        List<string> deplist = new();
        if (_guardDispatchPattern == null)
        {
            _guardDispatchPattern = new(@"(call    (?<partial>(qword ptr \[\w+!((_imp_|_?guard_dispatch_icall).*)\])|(\w+!.*)))|(jmp     (?<partial>qword ptr \[\w+!_imp_.*\]))", RegexOptions.Compiled);
        }
        var match = _guardDispatchPattern.Match(body[idx]);
        while (match.Success)
        {
            var part = match.Groups["partial"].Value;
            deplist.Add(part);
            match = match.NextMatch();
        }
        deplist = deplist.Distinct().ToList();
        if (deplist.Count == 0)
        {
            node.Hint = DrawHint.BodyNotFound;
            return;
        }
        foreach (var iter in deplist)
        {
            Node dep = new();

            var func = iter.Substring(0, iter.LastIndexOf(" (")).Replace("qword ptr [", "");
            dep.Symbol = func;
            // Some compilers use _guard_dispatch_icall, others without first underscore.
            if (func.Contains("guard_dispatch_icall"))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.Retpoline;
                if (retpoline.Count > 0)
                {
                    var repstr = GetRetpolineTarget(body[idx], retpoline);
                    dep.Symbol = $"{dep.Symbol} ({repstr})";
                }
            }
            else if (MatchCallIndirect($"call    {iter}", ref indirect))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.Indirect;
                var indstr = GetIndirectSource(body[idx], indirect);
                if (indstr != "")
                {
                    dep.Symbol = $"{dep.Symbol} ({indstr})";
                    if (indirect.Unreliable)
                    {
                        IsUnreliable = new(true);
                    }
                }
            }
            else if (iter.Contains("qword ptr ["))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.ImportAddressTable;
            }
            else
            {
                foreach (var stop in stopSymbols)
                {
                    if (Regex.IsMatch(func, stop))
                    {
                        dep.Index = -1;
                        dep.Hint = DrawHint.StopDisassembly;
                        break;
                    }
                }
            }
            if (dep.Index == -1)
            {
                node.Dependency.Add(dep);
                continue;
            }
            var address = iter.Substring(iter.LastIndexOf(" (") + 2).Replace(")", "");
            dep.Address = address;
            dep.Index = LocateSectionByAddress(address, body, ref func);
            if (dep.Index == -1)
            {
                dep.Hint = DrawHint.BodyNotFound;
                node.Dependency.Add(dep);
                continue;
            }
            dep.Symbol = func;
            dep.Hint = DrawHint.HasDependency;
            LocateDependencyRecursiveDowncall(current, depth, ref dep, body, stopSymbols, retpoline);
            node.Dependency.Add(dep);
        }
    }

    private bool MatchCallIndirect(string call, ref IdentifyArgument arg)
    {
        foreach (var iter in _indirectSourceBlock)
        {
            if (Regex.IsMatch(call, iter.Target))
            {
                arg = iter;
                return true;
            }
        }

        return false;
    }

    private string GetIndirectSource(in string section, in IdentifyArgument arg)
    {
        List<string> result = new();
        var match = arg.CompiledPattern.Match(section);
        while (match.Success)
        {
            var str = match.Groups["solution"].Value;
            match = match.NextMatch();
            if (arg.RegisterValue != null)
            {
                Type type = arg.RegisterValue.GetType();
                try
                {
                    int reg = Convert.ToInt32(str, 16);
                    if (Enum.IsDefined(type, reg))
                    {
                        var value = Enum.ToObject(type, reg);
                        str = $"0x{str}={value}";
                    }
                    else
                    {
                        str = $"0x{str}";
                    }
                }
                finally { }
            }
            else if (arg.Transform != null) {
                str = arg.Transform(str);
            }
            if (!result.Contains(str))
            {
                result.Add(str);
            }
        }

        return string.Join(",", result);
    }

    private string GetRetpolineTarget(in string section, in Dictionary<string, string> retpoline)
    {
        List<string> source = new();
        var match = Regex.Match(section, @"mov     rax,qword ptr \[(\w+!.+?)\s.+?\][\s\S]+?call\s+\w+!_?guard_dispatch_icall");
        while (match.Success)
        {
            source.Add(match.Groups[1].Value);
            match = match.NextMatch();
        }
        if (source.Count == 0)
        {
            return "N/A";
        }
        source = source.Distinct().ToList();
        List<string> target = new();
        foreach (var iter in source)
        {
            try
            {
                if (retpoline != null)
                {
                    target.Add($"{iter}={retpoline[iter]}");
                }
                else
                {
                    target.Add(iter);
                }
            }
            catch (KeyNotFoundException)
            {
                target.Add(iter);
            }
        }

        return string.Join(",", target);
    }

    private int LocateSectionByKeyFunction(string key, in List<string> body, ref string address)
    {
        for (int i = 0; i < body.Count; i++)
        {
            var header = body[i].Split("\n", 3);
            if (header[1] == FlowAnalysisCookie)
            {
                header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
            }
            if (header[1] == $"{key}:")
            {
                address = header[0].Replace("uf ", "");
                return i;
            }
        }

        return -1;
    }

    private List<int> LocateSectionByRandomKey(string key, in List<string> body)
    {
        List<int> result = new();

        for (int i = 0; i < body.Count; i++)
        {
            if (body[i].Contains(key))
            {
                result.Add(i);
            }
        }

        return result;
    }

    private int LocateSectionByAddress(string address, in List<string> body, ref string name)
    {
        for (int i = 0; i < body.Count; i++)
        {
            var header = body[i].Split("\n", 3);
            if (header[0] == $"uf {address}")
            {
                if (header[1] == FlowAnalysisCookie)
                {
                    header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
                }
                name = header[1];
                name = name.Substring(0, name.Length - 1);
                return i;
            }
        }

        return -1;
    }

}
