<#
.SYNOPSIS
    Build a call graph for a given linker symbol.

.DESCRIPTION
    Cache the disassembly for a Memory.DMP file or a given image. Postprocess
    the disassembly to render a call stack, starting from a symbol.

.PARAMETER Symbol
    Specify the symbol, using a prefix as in "nt!KiSystemStartup"
    or an instruction with opcode "fa              cli".

.PARAMETER Down
    The symbol acts as a caller, all dependecies are callees. Without it,
    the default is "called".

.PARAMETER Depth
    Define the maximum depth of the tree. Default is 2 levels.

.PARAMETER Image
    Disassemble the image, if it is not found in the image database. It can be an
    .exe, .dll, .sys or a .dmp file. As an alternative, scan for a caption
    representing the OS edition in the existing database.

.PARAMETER Setup
    Text based guide that receives user input for internal configuration:
        kd.exe location, database path, symbol path, statistics, warning.

.PARAMETER List
    Shows the decompiled modules, either .DMP or .dll, .sys, .exe files.

.PARAMETER Migrate
    Copy internal files to a destination folder. Have kd.exe running in
    standalone mode with local symbols.

.PARAMETER Self
    Insert symbol in stop-rendering list.

.PARAMETER Display
    Show the functions' disassembly body. Use -NonInteractive to skip "Enter"
    keypress after each body.

.EXAMPLE
    Show all disassembled images. It can be a mixture of memory files, executables.

    .\UfSymbol.ps1 -List OS

    computer       os | basename                          image
    --------       -------------                          -----
    INHOUSE        dbgeng 10.0.26100.2454                 C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\dbgeng.dll
    INHOUSE        pci 10.0.19041.1                       C:\Windows\System32\drivers\pci.sys
    INHOUSE        Windows 10 Enterprise Evaluation 22000 D:\DataLake\2025-12-03\MEMORY.DMP
    DEPLOYMENT-092 Windows 10 Enterprise LTSC 2019 17763  C:\Windows\Memory.DMP
    INHOUSE        Windows 10 Pro 22631                   D:\DataLake\2025-01-28\MEMORY.DMP

    Use the "os" section as value for "-Caption" in subsequent launches.

.EXAMPLE
    Show the callees of nt!KiSystemStartup up to level 6.

    .\UfSymbol.ps1 -Symbol nt!KiSystemStartup -Caption "Windows 10 Enterprise Evaluation 22000" -Depth 6 -Down
    D:\scripts\78ef8fff-3c2f-435d-a44e-a2e896954b0b\78ef8fff-3c2f-435d-a44e-a2e896954b0b.disassembly
    nt!KiSystemStartup [8485]
    ├────────────────▷nt!KdInitSystem
    │                 │              nt!MmGetPagedPoolCommitPointer
    │                 ├─────────────▷nt!KdRegisterDebuggerDataBlock
    │                 │              │                             nt!KeAcquireSpinLockRaiseToDpc
    │                 │              │                             nt!KeReleaseSpinLockFromDpcLevel
    │                 │              └────────────────────────────▷nt!KiRemoveSystemWorkPriorityKick
    │                 │                                            └───────────────────────────────▷nt!EtwTraceKernelEvent
    │                 │                                                                                                   nt!EtwpLogKernelEvent
    │                 │                                                                             nt!_security_check_cookie
    │                 │              kdcom!KdInitialize
    │                 │              nt!KeInitializeDpc (nt!KdpTimeSlipDpcRoutine)
    │                 │              nt!KeInitializeTimerEx
    │                 │              nt!KeIsKernelCetEnabled
    │                 │              nt!RtlInitString

    8485 calls have been identified. KeInitializeDpc takes KdpTimeSlipDpcRoutine as argument.
    The Caption has a corresponding listing in 78ef8fff-3c2f-435d-a44e-a2e896954b0b.disassembly.

.EXAMPLE
    Which functions clear the interrupt flag in ntoskrnl?

    .\UfSymbol.ps1 -Symbol "fa              cli" -Image "C:\Windows\System32\ntoskrnl.exe" -Depth 1
    fa              cli [1039]
                    nt!PpmSnapPerformanceAccumulation
                    nt!KeSetActualBasePriorityThread
                    nt!RtlpHpSegMgrCommitComplete
                    nt!EmpParseTargetRuleStringIndexList
                    nt!MiUnlockLoaderEntry
                    nt!KeQueryTotalCycleTimeThread
                    nt!KeSetPriorityAndQuantumProcess
                    nt!FsRtlCheckOplockEx2
                    nt!ExInterlockedRemoveHeadList
                    nt!EtwpFreeCompression
                    nt!PspUnlockProcessListExclusive
                    nt!HalpAcquireCmosSpinLock
                    nt!MiUnlockDynamicMemoryExclusive
                    nt!KiTimerExpirationDpc
                    nt!ExpDeleteTimer
                    nt!MiFlushStrongCodeDriverLoadFailures
                    nt!KeAbPostRelease

    To display the callers, increase -Depth.

.EXAMPLE
    .\UfSymbol.ps1 -Symbol "fa              cli" -Image "C:\Windows\System32\ntoskrnl.exe" -Depth 2
    D:\scripts\4bd0d042-76db-40e3-87dc-623510619a65\4bd0d042-76db-40e3-87dc-623510619a65.disassembly
    fa              cli [5206]
    ├─────────────────▷ntoskrnl!PpmSnapPerformanceAccumulation
    │                                                         ntoskrnl!PpmCheckSnapAllDeliveredPerformance
    │                                                         ntoskrnl!PpmPerfSnapDeliveredPerformance
    │                                                         ntoskrnl!PpmResetPerfTimes
    │                                                         ntoskrnl!PpmCapturePerformanceDistributionCallback
    │                                                         ntoskrnl!PpmGetThroughputInfoCallback
    ├─────────────────▷ntoskrnl!KeSetActualBasePriorityThread
    │                                                        ntoskrnl!SMKM_STORE<SM_TRAITS>::SmStWorkItemGet
    │                                                        ntoskrnl!IoApplyPriorityInfoThread
    │                                                        ntoskrnl!MiWakeModifiedPageWriter
    │                                                        ntoskrnl!SMKM_STORE<SM_TRAITS>::SmStWorker
    │                                                        ntoskrnl!MiFlushAllHintedStorePages
    │                                                        ntoskrnl!PopFxRemoveDevice
    │                                                        ntoskrnl!MiStoreUpdateMemoryConditions
    │                                                        ntoskrnl!PfpServiceMainThreadBoost
    │                                                        ntoskrnl!SmKmStoreHelperWorker
    │                                                        ntoskrnl!MiMappedPageWriter
    │                                                        ntoskrnl!PfpServiceMainThreadUnboost
    ...
    ├─────────────────▷ntoskrnl!KiReduceByEffectiveIdleSmtSet
    │                                                        ntoskrnl!KiTryLocalThreadSchedule
    │                                                        ntoskrnl!KiChooseTargetProcessor
    │                                                        ntoskrnl!KiSelectIdleProcessor
    ├─────────────────▷ntoskrnl!HalpBlkIdlePortRead
    │                                              ntoskrnl!HalpBlkIdleLoop
    │                  ntoskrnl!ZwAllocateUuids
    ├─────────────────▷ntoskrnl!ZwUnloadKeyEx
    │                                        ntoskrnl!PiDrvDbUnloadHive
    └─────────────────▷ntoskrnl!ZwRecoverResourceManager
                                                        ntoskrnl!CmpInitCmRM
                    ntoskrnl!ZwCloseObjectAuditAlarm

.EXAMPLE
    .\UfSymbol.ps1 -Self wcstok_s

    Make "wcstok_s" a stop symbol. The callees are not rendered.

.EXAMPLE
    .\UfSymbol.ps1 -Symbol nt!KiInitializeKernel -Image "D:\DataLake\2025-12-03\Memory.DMP" -Down

    File "D:\Datalake\2025-01-28\MEMORY.DMP" of 1194.36 Mb has been processed in 1195 seconds.
        > This warning shows the decompilation time for a file processed in the past, on a
          machine with same number of cores and CPU model.
    48243 functions disassembled in 1581 seconds
        > The memory file has been processed, the following files have been added to the database:
    D:\scripts\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81.disassembly
        > Full disassembly listing.

    D:\scripts\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81.meta
        > Memory file size, file hash, OS contained in the memory file - the target OS,
          local CPU model, number of cores.
    D:\scripts\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81\5aa22f4a-22d5-4b20-a2d2-41ca0a0a3f81.retpoline
        > Cache retpoline indirect calls.

    nt!KiInitializeKernel [131]
    ├───────────────────▷nt!PpmHvUseNativeAlgorithms+0xe
    │                                                   nt!KiDetectHardwareSpecControlFeatures
    │                                                   nt!KeBugCheckEx
    ├───────────────────▷nt!KiCheckMicrocode
    │                                       nt!_security_check_cookie
    │                                       nt!KeBugCheckEx
    │                                       nt!KeAttachProcess
    │                                       nt!KiInitializeThreadCycleTable
    │                                       nt!KiAcquirePrcbLocksForIsolationUnit
    │                                       nt!KiSetProcessorIdle
    │                                       nt!KiUpdateThreadPriority
    │                                       nt!KiReleasePrcbLocksForIsolationUnit
    │                                       nt!KiAddCpuToSystemCpuPartition
    │                                       nt!KiCreateCpuSetForProcessor
    │                                       nt!KeInitializeTimer2
    │                                       nt!KeInitializeDpc (nt!KiProcessPendingForegroundBoosts
    │                                                           nt!KiTriggerForegroundBoostDpc
    │                                                           nt!KiUpdateVpBackingThreadPriorityDpcRoutine)
    │                                       nt!KiAllocateHeteroConfigBuffer
    │                                       nt!KeAcquireSpinLockAtDpcLevel
    │                                       nt!RtlWriteAcquireTickLock
    │                                       nt!RtlWriteReleaseTickLock
    │                                       nt!KxReleaseSpinLock
    │                                       nt!KiRemoveSystemWorkPriorityKick
    │                    nt!memset
    ├───────────────────▷nt!KiSetPageAttributesTable
    │                                               nt!_security_check_cookie
    │                                               nt!KeFlushCurrentTbImmediately
    │                                               nt!KiRemoveSystemWorkPriorityKick
    ├───────────────────▷nt!KiInitializeTopologyStructures
    │                                                     nt!memset
    │                                                     nt!KeAddProcessorAffinityEx
    │                                                     nt!KeCountSetBitsAffinityEx
    │                                                     nt!KiAddProcessorToCoreControlBlock
    │                                                     nt!KeGetProcessorNode
    │                                                     nt!_security_check_cookie
    │                                                     nt!KeBugCheckEx
    ├───────────────────▷nt!KiSetCacheInformation
    │                                            nt!KiSetCacheInformationIntel
    │                                            nt!KeBugCheck
    │                                            nt!KiSetCacheInformationAmd
    ├───────────────────▷nt!PoInitializePrcb
    │                                       nt!memset
    │                                       nt!KeInitializeDpc
    │                                       nt!PpmHeteroHgsProcessorInit
    │                                       nt!PpmHeteroAmdProcessorInit
    │                                       nt!PpmHvUseNativeAlgorithms
    │                    nt!KeGetXSaveFeatureFlags
    ├───────────────────▷nt!HvlEnlightenProcessor
    │                                            nt!HvlpGetRegister64
    │                                            nt!MmGetPhysicalAddress
    │                                            nt!MmMapIoSpaceEx
    │                                            nt!guard_dispatch_icall (nt!HalPrivateDispatchTable+0x190=nt!HalpMapEarlyPages)
    │                                            nt!HvlpSetRegister64
    │                                            nt!HvlpSetupSchedulerAssist
    │                                            nt!HvlGetLpIndexFromProcessorIndex
    │                                            nt!HvlpGetLpcbByLpIndex
    │                                            nt!HvlSharedIsr
    │                                            nt!HvlpDiscoverTopologyLocal
    │                    nt!KiEnableXSave
    ├───────────────────▷nt!KiStartIdleThread
    │                                        nt!memset
    │                                        nt!KiInitializeContextThread
    │                                        nt!KiStartPrcbThread
    │                                        nt!KeInterlockedSetProcessorAffinityEx
    │                                        nt!KiInitializePriorityState
    ├───────────────────▷nt!KiStartPrcbThreads
    │                                         nt!KiStartPrcbThread
    ├───────────────────▷nt!HalpInitSystemPhase1
    │                                           nt!HalpInitSystemHelper
    │                    nt!KeBugCheck
    │                    nt!InitBootProcessor
    ├───────────────────▷nt!KiCompleteKernelInit
    │                                           nt!KeAttachProcess
    │                                           nt!KiInitializeThreadCycleTable
    │                                           nt!KiAcquirePrcbLocksForIsolationUnit
    │                                           nt!KiSetProcessorIdle
    │                                           nt!KiUpdateThreadPriority
    │                                           nt!KiReleasePrcbLocksForIsolationUnit
    │                                           nt!KiAddCpuToSystemCpuPartition
    │                                           nt!KiCreateCpuSetForProcessor
    │                                           nt!KeInitializeTimer2
    │                                           nt!KeInitializeDpc (nt!KiProcessPendingForegroundBoosts
    │                                                               nt!KiTriggerForegroundBoostDpc
    │                                                               nt!KiUpdateVpBackingThreadPriorityDpcRoutine)
    │                                           nt!KiAllocateHeteroConfigBuffer
    │                                           nt!KeBugCheckEx
    │                                           nt!KeAcquireSpinLockAtDpcLevel
    │                                           nt!RtlWriteAcquireTickLock
    │                                           nt!RtlWriteReleaseTickLock
    │                                           nt!KxReleaseSpinLock
    │                                           nt!KiRemoveSystemWorkPriorityKick
    │                    nt!KeYieldProcessorEx
    ├───────────────────▷nt!KeInitializeClockOtherProcessors
    │                                                       nt!KiGetClockTimerState
    │                                                       nt!guard_dispatch_icall (nt!HalPrivateDispatchTable+0x2f8=nt!HalpTimerClockStop
    │                                                                                nt!HalPrivateDispatchTable+0x2f0=nt!HalpTimerClockInitialize
    │                                                                                nt!HalPrivateDispatchTable+0x2e8=nt!HalpTimerClockActivate
    │                                                                                nt!HalPrivateDispatchTable+0x300=nt!HalpTimerClockArm)
    │                                                       nt!KiSetPendingTick
    │                                                       nt!KiRemoveSystemWorkPriorityKick
    │                    nt!_security_check_cookie
    ├───────────────────▷nt!HvlPhase0Initialize
    │                                          nt!HviIsAnyHypervisorPresent
    │                                          nt!HvlQueryConnection
    │                                          nt!HvlpTryConfigureInterface
    │                                          nt!HvlpSetupBootProcessorEarlyHypercallPages
    │                                          nt!HvlpDetermineEnlightenments
    │                                          nt!SC_DEVICE::GetStoragePropertyPost
    │                                          nt!strstr
    │                                          nt!HvlpPhase0Enlightenments
    │                                          nt!HvlpInitializeBootProcessor
    │                                          nt!HviGetHypervisorVersion
    │                    nt!KiDetectFpuLeakage
    ├───────────────────▷nt!KiConfigureInitialNodes
    │                                              nt!KiInitializeSchedulerSubNode
    │                                              nt!KiAllocateProcessorNumber
    │                                              nt!KiAssignProcessorNumberToPrcb
    ├───────────────────▷nt!KiConfigureProcessorBlock
    │                                                nt!KiGetSubNodeForGroup
    ├───────────────────▷nt!KeCompactServiceTable
    │                                            nt!KiLockServiceTable
    │                    nt!KiInitSystem
    ├───────────────────▷nt!HviGetHypervisorFeatures
    │                                               nt!HviIsHypervisorMicrosoftCompatible
    │                    nt!HvlEnableVsmCalls+0x25
    ├───────────────────▷nt!KiInitializeAndStartInitialThread
    │                                                        nt!memset
    │                                                        nt!KeInitThread
    │                                                        nt!KiStartIdleThread
    │                    nt!KiSetUserTbFlushPending
    └───────────────────▷nt!KiRemoveSystemWorkPriorityKick
                                                        nt!EtwTraceKernelEvent
                                                        nt!HvlpSetRegister64
                                                        nt!_security_check_cookie
                        nt!RtlInitKernelModeSpecialMachineFrameEntries
                        nt!KeGetTopologyIdForProcessor
                        nt!KeBugCheckEx

.EXAMPLE
    Display the implementation for nt!KeQueryTimeIncrement, nt!HviGetHypervisorFeatures

    .\UfSymbol.ps1 -Caption "Windows 10 Pro 22621" -Display nt!KeQueryTimeIncrement, nt!HviGetHypervisorFeatures
    │uf fffff802`0c4b7890
    │nt!KeQueryTimeIncrement:
    └─────────────────────────────────────────────────────────────────────────────────┐
     8b05be61a600    mov     eax,dword ptr [nt!KeMaximumIncrement (fffff802`0cf1da54)]│
     c3              ret                                                              │
                                                                                      │
    Enter to continue:

    │uf fffff802`0c571330
    │nt!HviGetHypervisorFeatures:
    └────────────────────────────────────────────────────────────────────────────────────────┐
     48895c2408      mov     qword ptr [rsp+8],rbx                                           │
     57              push    rdi                                                             │
     4883ec20        sub     rsp,20h                                                         │
     488bf9          mov     rdi,rcx                                                         │
     e88ef8ffff      call    nt!HviIsHypervisorMicrosoftCompatible (fffff802`0c570bd0)       │
     33c9            xor     ecx,ecx                                                         │
     84c0            test    al,al                                                           │
     0f859c201400    jne     nt!HviGetHypervisorFeatures+0x1420b8 (fffff802`0c6b33e8)  Branch│
                                                                                             │
     nt!HviGetHypervisorFeatures+0x1c:                                                       │
     48890f          mov     qword ptr [rdi],rcx                                             │
     48894f08        mov     qword ptr [rdi+8],rcx                                           │
                                                                                             │
     nt!HviGetHypervisorFeatures+0x23:                                                       │
     488b5c2430      mov     rbx,qword ptr [rsp+30h]                                         │
     4883c420        add     rsp,20h                                                         │
     5f              pop     rdi                                                             │
     c3              ret                                                                     │
                                                                                             │
     nt!HviGetHypervisorFeatures+0x1420b8:                                                   │
     b803000040      mov     eax,40000003h                                                   │
     0fa2            cpuid                                                                   │
     8907            mov     dword ptr [rdi],eax                                             │
     895f04          mov     dword ptr [rdi+4],ebx                                           │
     894f08          mov     dword ptr [rdi+8],ecx                                           │
     89570c          mov     dword ptr [rdi+0Ch],edx                                         │
     e954dfebff      jmp     nt!HviGetHypervisorFeatures+0x23 (fffff802`0c571353)  Branch    │
                                                                                             │

.NOTES
    PowerShell Core is mandatory: optimizations since Desktop 5.1 are substantial.

.LINK
    https://github.com/armaber/articles/blob/main/HDUF/brief.md
#>

#requires -PSEdition Core

[CmdletBinding(DefaultParameterSetName = "Process")]
param(
      [Parameter(ParameterSetName = "Process")]
      [string]$Symbol,
      [Parameter(ParameterSetName = "Process")]
      [switch]$Down,
      [Parameter(ParameterSetName = "Process")]
      [int]$Depth = 2,
      [Parameter(ParameterSetName = "Process")]
      [Parameter(ParameterSetName = "Display")]
      [Alias("Caption")]
      [string]$Image,
      [Parameter(ParameterSetName = "Setup")]
      [switch]$Setup,
      [Parameter(ParameterSetName = "List")]
      [ValidateSet("OS", "Complete")]
      [string]$List,
      [Parameter(ParameterSetName = "Migrate")]
      [Alias("USB")]
      [string]$Migrate,
      [Parameter(ParameterSetName = "Self")]
      [string]$Self,
      [Parameter(ParameterSetName = "Display")]
      [string[]]$Display,
      [Parameter(ParameterSetName = "Display")]
      [switch]$NonInteractive
)

$ErrorActionPreference = 'Break';

. $PSScriptRoot\functions.ps1;

switch ($PSCmdLet.ParameterSetName)
{
    "Process"
    {
        QuerySymbol $Symbol -Down:$Down $Depth $Image;
    }
    "Setup" { ConfigureInteractive; }
    "List" { ListMetaFiles $List; }
    "Migrate" { MigrateFiles $Migrate; }
    "Self" { SelfInsert $Self }
    "Display" { DisplayFunctions $Image $Display -NonInteractive:$NonInteractive }
}
