bits 64
default rel

extern __imp_IoCreateDevice
extern __imp_IoCreateSymbolicLink

extern __imp_IoDeleteDevice
extern __imp_IoDeleteSymbolicLink

extern __imp_IoCompleteRequest

;extern __imp_RtlInitUnicodeString

; ============================================================
; DECLARE_UNICODE_STRING マクロ
; 引数1: 生成する構造体ラベルの名前
; 引数2: ターゲットとなる文字列（通常のASCII文字列で渡す）
; ============================================================
%macro DECLARE_UNICODE_STRING 2
    ; 1. プリプロセッサで文字列の長さを取得（文字数）
    %strlen %%str_len %2
    
    ; 2. バイト数に変換（1文字 = 2バイト）
    %%bytes_len       equ %%str_len * 2
    %%max_bytes_len   equ (%%str_len + 1) * 2  ; 終端ヌルを含めた最大サイズ

    section .rdata
    align 2
    ;; 文字列本体のバッファを一意のラベルで定義
    %%str_buf_label:
        dw __utf16__(%2), 0

    section .data
    align 16
    ;; 外部から参照される構造体のメインラベル
    %1:
        dw %%bytes_len          ; +0x00: Length (2バイト)
        dw %%max_bytes_len      ; +0x02: MaximumLength (2バイト)
        dd 0                    ; +0x04: x64アライメント用の4バイトパディング（必須）
        dq %%str_buf_label      ; +0x08: 文字列本体への8バイトポインタ
%endmacro

DECLARE_UNICODE_STRING DeviceName, "\Device\MyDrv"
DECLARE_UNICODE_STRING LinkName,   "\DosDevices\MyDrv"

; IoCreateDeviceが書き込むポインタ
section .data
align 8
	DeviceObject:	dq 0
	;__dummy_abs:	dq DriverEntry
	;DeviceName:	times 64 db 0
	;LinkName: times 64 db 0

;section .rdata
;align 64
; \\Device\\MyDrv
;DeviceNameBuf:  dw   '\','D','e','v','i','c','e','\','M','y','D','r','v',0
	;DeviceNameBuf:	dw word 26, word 26, dword 0, __utf16__("\Device\MyDrv"), 0
	;DeviceNameBuf:	dw __utf16__("\Device\MyDrv"), 0

; \\DosDevices\\MyDrv
;LinkNameBuf:	dw  '\','D','o','s','D','e','v','i','c','e','s','\','M','y','D','r','v',0
	;LinkNameBuf: dw word 34, word 34, dword 0, __utf16__("\DosDevices\MyDrv"), 0
	;LinkNameBuf: dw __utf16__("\DosDevices\MyDrv"), 0

IOCTL_READ_MSR:	equ 0x80002000
IOCTL_WRITE_MSR: equ 0x80002004

section .text

; ============================================================
; DriverUnload(PDRIVER_OBJECT DriverObject)
; rcx = DriverObject
; ============================================================
global DriverUnload
DriverUnload:
	sub	rsp, 58h

	; IoDeleteSymbolicLink(&LinkName)
	;lea		rcx,	[LinkNameBuf]
	;mov		dx,		word [rcx]
	;movzx	eax,	dx
	; RtlInitUnicodeString(&us, LinkNameBuf)
	;lea		rcx,	[rsp]		; UNICODE_STRING on stack
	;lea		rcx,	[LinkName]
	;lea		rdx,	[LinkNameBuf]
	;call			[__imp_RtlInitUnicodeString]
	;lea		rcx,	[rsp]
	lea		rcx,	[LinkName]
	call			[__imp_IoDeleteSymbolicLink]

	; IoDeleteDevice(DeviceObject)
	mov		rcx,	[DeviceObject]
	test	rcx,	rcx
	jz		.done
	call	[__imp_IoDeleteDevice]
	;mov		qword [DeviceObject], 0

.done:
	add	rsp, 58h
	ret

; ============================================================
; DispatchCreateClose(PDEVICE_OBJECT, PIRP)
; rcx = DeviceObject, rdx = Irp
; ============================================================
global DispatchCreateClose
DispatchCreateClose:
	sub	rsp, 28h
	; Irp->IoStatus.Status = STATUS_SUCCESS
	mov dword [rdx + 0x30], 0
	; Irp->IoStatus.Information = 0
	mov	qword [rdx + 0x38], 0
	; IoCompleteRequest(Irp, IO_NO_INCREMENT=0)
	mov	rcx, rdx
	xor	edx, edx
	call	[__imp_IoCompleteRequest]
	xor	eax, eax
	add	rsp, 28h
	ret

; ============================================================
; DispatchControl(PDEVICE_OBJECT, PIRP)
; rcx = DeviceObject, rdx = Irp
; ============================================================
global DispatchControl
DispatchControl:
	sub	rsp, 48h
	mov	[rsp + 30h], rdx		; IRP保存

	; CurrentStackLocation取得
	; Irp->Tail.Overlay.CurrentStackLocation
	mov	r8, [rdx + 0xB8]

	; IoControlCode取得
	; IO_STACK_LOCATION.Parameters.DeviceIoControl.IoControlCode
	mov	eax, [r8 + 0x18]

	; SystemBuffer取得
	; Irp->AssociatedIrp.SystemBuffer
	mov	r9, [rdx + 0x18]

	; 1. システムバッファのヌルチェック
	test r9, r9
	jz   .invalid_parameter

	; 2. バッファサイズのチェック (InputBufferLength: r8 + 0x10)
	; MSRアドレス(4B) + 値(8B) = 最低12バイト必要
	mov  r11d, [r8 + 0x10]
	cmp  r11d, 16
	jb   .buffer_too_small
	mov  r11d, [r8 + 0x08]      ; OutputBufferLength
    cmp  r11d, 16
    jb   .buffer_too_small

	mov ecx, [r9]

	cmp ecx, 0xC0010064

	jne .access_denied
	
	cmp	eax, IOCTL_READ_MSR
	je	.read_msr
	cmp	eax, IOCTL_WRITE_MSR
	je	.write_msr

.invalid_device_request:
	; 未対応IOCTL
	mov	eax, 0xC0000010		; STATUS_INVALID_DEVICE_REQUEST
	jmp	.complete

.invalid_parameter:
	mov  eax, 0xC000000D		; STATUS_INVALID_PARAMETER
	jmp  .complete

.buffer_too_small:
	mov  eax, 0xC0000023		; STATUS_BUFFER_TOO_SMALL
	jmp  .complete

.access_denied:
	mov  eax, 0xC0000022		; STATUS_ACCESS_DENIED
	jmp  .complete

.read_msr:
	; SystemBuffer = { UINT32 address, UINT32 pad, UINT64 value }
	;mov	ecx, [r9]			  ; MSRアドレス
	rdmsr						  ; edx:eax = MSR値
	shl	rdx, 32
	or	 rax, rdx
	mov	[r9 + 8], rax		  ; valueに書き戻す
	xor	eax, eax				; STATUS_SUCCESS
	jmp	.complete

.write_msr:
	;mov	ecx, [r9]			  ; MSRアドレス
	mov	rax, [r9 + 8]		  ; 書き込む値
	mov	rdx, rax
	shr	rdx, 32				; edx:eax に分割
	mov eax, eax
	wrmsr
	xor	eax, eax
	jmp	.complete

.complete:
	mov	r10, [rsp + 30h]		; IRP復元
	mov	[r10 + 0x30], eax	  ; IoStatus.Status
	mov	qword [r10 + 0x38], 16   ; IoStatus.Information = sizeof(Value)
	mov	rcx, r10
	xor	edx, edx
	call	[__imp_IoCompleteRequest]
	xor	eax, eax
	add	rsp, 48h
	ret

; ============================================================
; DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING)
; rcx = DriverObject
; ============================================================
global DriverEntry
DriverEntry:
	sub	rsp, 78h
	mov	[rsp + 60h], rcx		; DriverObject保存

	; MajorFunction登録
	;mov	rcx, [rsp + 60h]
	lea	rax, [DispatchCreateClose]
	mov	[rcx + 70h], rax	 ; IRP_MJ_CREATE
	mov	[rcx + 80h], rax	 ; IRP_MJ_CLOSE
	lea	rax, [DispatchControl]
	mov	[rcx + 0xE0], rax	 ; IRP_MJ_DEVICE_CONTROL
	
	lea		rax,		[DriverUnload]
	mov		[rcx + 68h],	rax	 ; DriverUnload

	;lea		rcx,	[DeviceName]
	;lea		rdx,	[DeviceNameBuf]
	;call			[__imp_RtlInitUnicodeString]
	
	;lea		rcx,	[LinkName]
	;lea		rdx,	[LinkNameBuf]
	;call			[__imp_RtlInitUnicodeString]

	; UNICODE_STRINGを[rsp+40h]に構築（スタック引数と分離）
	;lea	rax, [DeviceNameBuf]
	;mov	word [rsp + 40h], 26; Length = 13文字 × 2
	;mov	word [rsp + 42h], 26	; MaxLength
	;mov	dword [rsp + 44h], 0	; padding
	;mov	[rsp + 48h], rax		; Buffer

	; IoCreateDevice(DriverObject, 0, &DeviceName, 0x22, 0, 0, &DeviceObject)
	mov	rcx, [rsp + 60h]
	xor	edx, edx
	;lea	r8,  [rsp + 40h]		; &DeviceName（[rsp+40h]）
	lea r8, [DeviceName]
	mov	r9d, 0x22			  ; FILE_DEVICE_UNKNOWN
	mov	dword [rsp + 20h], 0	; DeviceCharacteristics（5番目）
	mov	dword [rsp + 28h], 0	; Exclusive=FALSE（6番目）
	lea	rax, [DeviceObject]
	mov	[rsp + 30h], rax		; &DeviceObject（7番目）
	;lea [rsp+30h], [DeviceObject]
	call	[__imp_IoCreateDevice]
	test	eax, eax
	js	 .fail

	; LinkName UNICODE_STRINGを[rsp+40h]に再利用
	;lea	rax, [LinkNameBuf]
	;mov	word [rsp + 40h], 34	; "\DosDevices\MyDrv" = 14文字 × 2
	;mov	word [rsp + 42h], 34
	;mov	dword [rsp + 44h], 0
	;mov	[rsp + 48h], rax

	; DeviceName UNICODE_STRINGを[rsp+50h]に構築
	;lea	rax, [DeviceNameBuf]
	;mov	word [rsp + 50h], 26
	;mov	word [rsp + 52h], 26
	;mov	dword [rsp + 54h], 0
	;mov	[rsp + 58h], rax

	; IoCreateSymbolicLink(&LinkName, &DeviceName)
	;lea	rcx, [rsp + 40h]
	;lea	rdx, [rsp + 50h]
	lea	rcx, [LinkName]
	lea	rdx, [DeviceName]
	call	[__imp_IoCreateSymbolicLink]
	test	eax, eax
	js	 .fail

	

	xor	eax, eax
	jmp	.done

.fail:
	mov	r11d, eax
	;lea rcx, [DeviceObject]
	mov	rcx, [DeviceObject]
	test	rcx, rcx

	jz .skip_delete
	call	[__imp_IoDeleteDevice]
	;mov		qword [DeviceObject], 0

.skip_delete:
	mov	eax, r11d

.done:
	add	rsp, 78h
	ret
