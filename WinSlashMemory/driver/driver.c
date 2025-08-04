#include <ntddk.h>
#include <wdm.h>
#include "shared.h"

#define DRIVER_TAG 'eMlS' /* SlMe Slash Memory */
#define DEVICE_NAME L"\\Device\\SlashMemory"
#define USER_MODE_DEVICE_NAME L"\\DosDevices\\SlashMemory"

DRIVER_INITIALIZE DriverEntry;
DRIVER_DISPATCH SmDispatchCreate;
DRIVER_DISPATCH SmDispatchClose;
DRIVER_DISPATCH SmDispatchIoControl;
DRIVER_UNLOAD SmUnloadDriver;

#pragma alloc_text(INIT, DriverEntry)

typedef struct SM_FILE_CONTEXT
{
    PMDL Mdl;
    KEVENT Serialize;
    PVOID KernelMappedAddress;
    PVOID UserModeAddress;
} *PSM_FILE_CONTEXT;

NTSTATUS SmDispatchCreate(PDEVICE_OBJECT Device, PIRP Irp)
{
    PIO_STACK_LOCATION ioStack;
    PFILE_OBJECT fileObject;
    PSM_FILE_CONTEXT fileContext;
    NTSTATUS status = STATUS_INSUFFICIENT_RESOURCES;
    UNREFERENCED_PARAMETER(Device);

    Irp->IoStatus.Information = 0;
    ioStack = IoGetCurrentIrpStackLocation(Irp);
    fileObject = ioStack->FileObject;
    fileObject->FsContext = ExAllocatePool2(POOL_FLAG_NON_PAGED, sizeof(*fileContext), DRIVER_TAG);
    if (!fileObject->FsContext) {
        goto Exit;
    }
    fileContext = fileObject->FsContext;
    fileContext->Mdl = IoAllocateMdl(NULL, PAGE_SIZE, FALSE, TRUE, NULL);
    if (!fileContext->Mdl) {
        goto DeallocateContext;
    }
    KeInitializeEvent(&fileContext->Serialize, SynchronizationEvent, TRUE);
    status = STATUS_SUCCESS;
    goto Exit;

DeallocateContext:
    ExFreePoolWithTag(fileObject->FsContext, DRIVER_TAG);
Exit:
    Irp->IoStatus.Status = status;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return status;
}

NTSTATUS SmMapAddress(PSM_FILE_CONTEXT FileContext, ULONGLONG IoAddress, MEMORY_CACHING_TYPE CacheType, BOOLEAN Write)
{
    PVOID address;
    ULONG flags;
    NTSTATUS status;
    PHYSICAL_ADDRESS pa;
    PMDL mdl;
    
    pa.QuadPart = IoAddress;
    if (pa.LowPart & (PAGE_SIZE - 1)) {
        return STATUS_INVALID_PARAMETER;
    }
    mdl = FileContext->Mdl;
    flags = CacheType == MmNonCached? PAGE_NOCACHE:
            CacheType == MmWriteCombined? PAGE_WRITECOMBINE:
            MmCached;
    flags |= Write? PAGE_READWRITE: PAGE_READONLY;
    address = MmMapIoSpaceEx(pa, PAGE_SIZE, flags);
    if (!address) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Exit;
    }
    FileContext->KernelMappedAddress = address;
    MmInitializeMdl(mdl, address, PAGE_SIZE);
    MmBuildMdlForNonPagedPool(mdl);
    flags = NormalPagePriority | MdlMappingNoExecute;
    if (!Write) {
        flags |= MdlMappingNoWrite;
    }
    try {
        address = MmMapLockedPagesSpecifyCache(mdl, UserMode, CacheType, NULL, FALSE, flags);
        if (!address) {
            status = STATUS_INSUFFICIENT_RESOURCES;
            goto UnmapIo;
        }
    } except (EXCEPTION_EXECUTE_HANDLER) {
        status = GetExceptionCode();
        goto UnmapIo;
    }
    FileContext->UserModeAddress = address;
    return STATUS_SUCCESS;

UnmapIo:
    MmUnmapIoSpace(FileContext->KernelMappedAddress, PAGE_SIZE);
    FileContext->KernelMappedAddress = NULL;
Exit:
    return status;
}

VOID SmUnmapAddress(PSM_FILE_CONTEXT FileContext)
{
    PVOID address;

    address = FileContext->UserModeAddress;
    if (address) {
        MmUnmapLockedPages(address, FileContext->Mdl);
        FileContext->UserModeAddress = NULL;
        address = FileContext->KernelMappedAddress;
        MmUnmapIoSpace(address, PAGE_SIZE);
        FileContext->KernelMappedAddress = NULL;
    }
}

NTSTATUS SmDispatchClose(PDEVICE_OBJECT Device, PIRP Irp)
{
    PIO_STACK_LOCATION ioStack;
    PFILE_OBJECT fileObject;
    PSM_FILE_CONTEXT fileContext;
    UNREFERENCED_PARAMETER(Device);

    ioStack = IoGetCurrentIrpStackLocation(Irp);
    fileObject = ioStack->FileObject;
    fileContext = fileObject->FsContext;
    SmUnmapAddress(fileContext);
    IoFreeMdl(fileContext->Mdl);
    ExFreePoolWithTag(fileContext, DRIVER_TAG);
    Irp->IoStatus.Information = 0;
    Irp->IoStatus.Status = STATUS_SUCCESS;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

NTSTATUS SmDispatchIoControl(PDEVICE_OBJECT Device, PIRP Irp)
{
    PIO_STACK_LOCATION ioStack;
    PFILE_OBJECT fileObject;
    PSM_FILE_CONTEXT fileContext;
    PVOID inputBuffer;
    PINPUT_MEM_SEEK ioSeek;
    ULONG inputLength, outputLength;
    NTSTATUS status = STATUS_INVALID_PARAMETER;
    UNREFERENCED_PARAMETER(Device);
    
    Irp->IoStatus.Information = 0;
    inputBuffer = Irp->AssociatedIrp.SystemBuffer;
    ioStack = IoGetCurrentIrpStackLocation(Irp);
    inputLength = ioStack->Parameters.DeviceIoControl.InputBufferLength;
    outputLength = ioStack->Parameters.DeviceIoControl.OutputBufferLength;
    fileObject = ioStack->FileObject;
    switch (ioStack->Parameters.DeviceIoControl.IoControlCode)
    {
        case IOCTL_MEM_SEEK:
            if (inputLength < sizeof(*ioSeek)) {
                status = STATUS_BUFFER_TOO_SMALL;
                break;
            }
            if (outputLength < sizeof(PVOID)) {
                status = STATUS_BUFFER_TOO_SMALL;
                break;
            }
            ioSeek = (PINPUT_MEM_SEEK)inputBuffer;
            fileContext = fileObject->FsContext;
            KeWaitForSingleObject(&fileContext->Serialize, Executive, KernelMode, FALSE, NULL);
            SmUnmapAddress(fileContext);
            status = SmMapAddress(fileContext, ioSeek->IoAddress, ioSeek->CacheType, ioSeek->Write);
            KeSetEvent(&fileContext->Serialize, 0, FALSE);
            if (!NT_SUCCESS(status)) {
                break;
            }
            RtlCopyMemory(inputBuffer, &fileContext->UserModeAddress, sizeof(PVOID));
            Irp->IoStatus.Information = sizeof(PVOID);
            status = STATUS_SUCCESS;
        break;
    }
    
    Irp->IoStatus.Status = status;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return status;
}

VOID SmUnloadDriver(PDRIVER_OBJECT Driver)
{
    UNICODE_STRING userModeVisibleName;
    PDEVICE_OBJECT deviceObject;

    RtlInitUnicodeString(&userModeVisibleName, USER_MODE_DEVICE_NAME);
    IoDeleteSymbolicLink(&userModeVisibleName);
    deviceObject = Driver->DeviceObject;
    IoDeleteDevice(deviceObject);
}

NTSTATUS DriverEntry(PDRIVER_OBJECT Driver, PUNICODE_STRING Registry)
{
    UNICODE_STRING deviceName;
    UNICODE_STRING userModeVisibleName;
    PDEVICE_OBJECT deviceObject;
    NTSTATUS status;
    UNREFERENCED_PARAMETER(Registry);

    RtlInitUnicodeString(&deviceName, DEVICE_NAME);
    RtlInitUnicodeString(&userModeVisibleName, USER_MODE_DEVICE_NAME);
    Driver->MajorFunction[IRP_MJ_CREATE] = SmDispatchCreate;
    Driver->MajorFunction[IRP_MJ_CLOSE] = SmDispatchClose;
    Driver->MajorFunction[IRP_MJ_DEVICE_CONTROL] = SmDispatchIoControl;
    Driver->DriverUnload = SmUnloadDriver;
    status = IoCreateDevice(Driver, 0, &deviceName, FILE_DEVICE_UNKNOWN, 0, FALSE, &deviceObject);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = IoCreateSymbolicLink(&userModeVisibleName, &deviceName);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(deviceObject);
        return status;
    }
    deviceObject->Flags &= ~DO_DEVICE_INITIALIZING;

    return STATUS_SUCCESS;
}

