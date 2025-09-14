; Necessaries
ORIGIN equ 0x7C00
[org ORIGIN]

; Jump to the start point
jmp stage1_entry_16

; Constants
KERNEL_ADDRESS equ 0x200000
KERNEL_SECTORS equ 500

; General constants
SECTOR_SIZE equ 512
PAGE_SIZE   equ 4096

SIZE_RSDP equ 36 ; Bytes

; GDT selectors
SEG_CODE_R equ 0x10
SEG_CODE_P equ 0x08
SEG_DATA   equ 0x18

; Constants used throughout the bootloader
INFO_BOOT_DISK: db 0

INFO_DISK_SECTORS:   dw 0
INFO_DISK_HEADS:     dw 0
INFO_DISK_CYLINDERS: dw 0

; Address offsets from the tail end of the bootloader to load things the kernel may need
ADDR_STACK equ (ORIGIN + SECTOR_SIZE - 1) ; Base address of the stack

; Real mode GDT definition
GDT_start:
	dq 0x0000000000000000 ; Null
	dq 0x00CF9A000000FFFF ; Code protected mode
	dq 0x00009A000000FFFF ; Code real mode
	dq 0x00CF92000000FFFF ; Data

GDT_descriptor:
	dw GDT_end - GDT_start - 1       ; Limit (size - 1)
	dd GDT_start                     ; Base address
GDT_end:

; Bootloader entry
[bits 16]
stage1_entry_16:
	
	; Disable interrupts
	cli
	
	; Set up segment registers for real mode
	xor ax, ax
	mov ds, ax
	mov es, ax
	
	; Store the boot disk number
	mov [INFO_BOOT_DISK], dl
	
	; Set up the stack right after the bootloader
	xor ax, ax
	mov ss, ax
	mov sp, ADDR_STACK
	
	; Load the GDT
	lgdt [GDT_descriptor]
	
	; Give the disk loading function dummy values as we don't know the geometry yet
	mov word [INFO_DISK_SECTORS],   63   ; Likely sector count
	mov word [INFO_DISK_HEADS],     256  ; Likely head count
	mov word [INFO_DISK_CYLINDERS], 1024 ; Likely cylinder count
	
	; Check where we can load the second stage
	call e820_load_imm
	
	; Store the stage 2 address
	add eax, 0xF
	and eax, 0xFFFFFFF0
	shr eax, 4
	push ax
	
	; Load the second stage
	mov es, ax
	mov edi, (FILE_SIZE / SECTOR_SIZE) - 1 ; Sector count
	mov ax, 1 ; Sector index
	call disk_load ; Call the function
	
	; Jump to the second stage
	push 0
	retf

[bits 16]
um_enable:
	
	; Enable protected mode
	mov eax, cr0 ; Read current value
	or  eax, 1   ; Set the PE bit
	mov cr0, eax ; Write it back
	
	; Far jump into protected mode startup to flush the prefetch queue
	jmp SEG_CODE_R:um_enable_32

; Protected mode start routine
[bits 32]
um_enable_32:
	
	mov bx, SEG_DATA ; Select the data descriptor
	mov fs, bx
	
	; Disable protected mode
	mov eax, cr0 ; Read current value
	and eax, ~1  ; Unset the PE bit
	mov cr0, eax ; Write it back
	
	; Far jump to unreal startup to flush the prefetch queue
	jmp 0x00:um_enable_16

; Unreal mode start routine
[bits 16]
um_enable_16:
	
	retf

[bits 16]
pm_enable:
	
	; Enable protected mode
	mov eax, cr0 ; Read current value
	or  eax, 1   ; Set the PE bit
	mov cr0, eax ; Write it back
	
	; Far jump into protected mode startup to flush the prefetch queue
	jmp SEG_CODE_P:pm_enable_32

[bits 32]
pm_enable_32:
	
	jmp edx

; Loading sectors from disk
[bits 16]
disk_load:
	
	xor ch, ch
	mov cl, al
	inc cl
	xor dh, dh
	
disk_load_begin:
	
	; Setup our registers
	mov si, 3 ; Retry count
	xor bx, bx ; Offset of 0
	
disk_load_int:
	
	mov al, 1 ; Load 1 sector at a time
	
	mov ah, 0x02 ; Read operation
	
	; Load the drive number
	mov dl, [INFO_BOOT_DISK]
	
	; Call the disk read interrupt
	int 0x13
	
	; If the carry is set, retry
	jc disk_load_retry
	
	dec edi
	jnz disk_load_next
	
	; Return to the caller
	ret

disk_load_retry:
	
	dec si
	jnz disk_load_int
	jmp stage1_err

disk_load_int_sec:
	
	; Restore the sector count
	mov cx, si
	
	; Reset SI
	mov si, 3 ; Reset the retry count
	
	; Jump to the loader
	jmp disk_load_int
	
disk_load_next:
	
	add bx, SECTOR_SIZE ; Offset 512 bytes
	jnc disk_load_next_cont ; If BX didn't wrap, proceed with CHS incrementation
	
	; Increment the segment; the offset is already at 0 so that doesn't need resetting
	mov bx, es
	add bx, 0x1000 ; Increment by 64KB (65536 bytes) (2^16)
	mov es, bx
	xor bx, bx
	
disk_load_next_cont:
	
	; Increment the sector
	mov si, cx
	inc si
	
	; If we're below the max sector, jump to the loader again
	cmp si, [gs:INFO_DISK_SECTORS]
	jbe disk_load_int_sec
	
	; Break down CL
	movzx bx, cl ; Use BX as scratch
	and bl, 0xC0 ; Mask out everything but high bits
	shl bx, 2    ; Shift up into high 8 bits of BX
	mov bl, dh   ; Move the low 8 bits of head into low 8 bits of BL
	inc bx       ; Increment BX
	push bx      ; Preserve BX for later usage
	
	; Rebuild CL
	mov dh, bl   ; Move low 8 bits of BX into high 8 bits of DX, which holds the low 8 bits of head count
	and bh, 0x03 ; Mask out all but low 2 bits
	shl bh, 6    ; Shift high bits to their respective location
	mov cl, bh   ; Restore head count in CL
	or  cl, 1    ; Reset sector count
	
	; Reset our variables
	mov si, 3 ; Reset the retry count
	
	; If we're below max head, jump to the loader again
	pop bx
	cmp bx, word [gs:INFO_DISK_HEADS]
	jb disk_load_int
	
	; Increment the cylinder
	mov cl, 1  ; Reset the sector
	xor dh, dh ; Reset the head
	inc ch     ; Increment the cylinder
	
	; If we're below the max cylinder, jump to the loader again
	cmp ch, [gs:INFO_DISK_CYLINDERS]
	jb disk_load_int
	
	; If we somehow, someway got here, just error
	jmp stage1_err

; Finding a location for the second bootloader stage
[bits 16]
e820_load_imm:
	
	xor ebx, ebx ; Continuation value of 0
	
	; Load the segment and offset selectors
	mov ax, (ORIGIN + stage1_entry_16)
	shr ax, 4
	mov es, ax
	xor di, di
	
e820_load_imm_next:
	
	xor eax, eax
	mov ax, 0xE820
	mov edx, 0x534D4150 ; SMAP
	mov ecx, 20         ; We load 20 bytes of info from E820
	
	int 0x15 ; Call the interrupt
	
	; Handle errors
	jc stage1_err
	cmp eax, 0x534D4150 ; Should still be SMAP
	jne stage1_err
	
	; Save EBX
	push ebx
	
	; Check if it's type 1 usable
	cmp dword [es:di + 16], 1
	jne e820_load_imm_test
	
	mov eax, [es:di + 0] ; Base
	mov ecx, [es:di + 8] ; Length
	
	; Get the end of region
	mov edx, eax
	add edx, ecx
	
e820_load_imm_loop:
	
	; If it's below the bootloader, continue
	cmp eax, (ORIGIN + SECTOR_SIZE + 4096)
	jbe e820_load_imm_chk
	
	; If it's outside of conventional memory, continue
	cmp eax, 0xA0000
	jae e820_load_imm_chk
	
	; If it can't hold the second stage, continue
	mov esi, edx
	sub esi, eax
	cmp esi, (FILE_SIZE - SECTOR_SIZE)
	jb e820_load_imm_chk
	
	; It's valid! We can return
	add sp, 4 ; Pop EBX
	ret
	
e820_load_imm_chk:
	
	; If EAX exceeds EDX, we've maxxed out this search
	cmp eax, edx
	ja e820_load_imm_test
	
	add eax, 1024
	
	jmp e820_load_imm_loop
	
e820_load_imm_test:
	
	; Check the continuation value
	pop ebx
	test ebx, ebx
	jnz e820_load_imm_next
	
	; No usable memory was found; error
	jmp stage1_err

; Error function in case something went wrong
stage1_err:
	mov ah, 0x0E
	mov al, 'E'
	int 0x10
	jmp $

; Pad up to the partition table
times 0x1BE - ($ - $$) db 0

; Provide a blank / dummy first partition
db 0x00             ; Non-bootable
db 0x00, 0x00, 0x00 ; CHS Start
db 0x0C             ; Filesystem (FAT32 CHS)
db 0xFF, 0xFF, 0xFF ; CHS End
dd 2048             ; LBA Start
dd 2000             ; LBA Sectors

; Three empty partitions
times 16 db 0
times 16 db 0
times 16 db 0

; Pad to 512 bytes (since the bootloader must be within 1 sector) and mark the end with AA55 so this is recognized as a bootloader
times ((SECTOR_SIZE - 2) - ($ - $$)) db 0
dw 0xAA55

; Stage 2; loaded by stage 1
[bits 16]

; Jump to entry point
jmp stage2_entry_16

; Constants
ADDR_BASE:     dd 0 ; Base pointer to kernel info
ADDR_BASE_OFF: dd 0 ; To track the current offset from the base

SIZE_RSDP equ 36 ; Bytes

ADDR_INFO:
	ADDR_OFF_E820: dd 0
	ADDR_OFF_FB:   dd 0
	ADDR_OFF_RSDP: dd 0

; Helpers for PIC
%macro movr 2
	mov %1, cs
	shl %1, 4
	add %1, ($$ + %2) - SECTOR_SIZE
%endmacro

; Bootloader messages
msg_e820:
	db 'Obtained E820 memory map.', 0
msg_geom:
	db 'Obtained disk geometry.', 0
msg_a20:
	db 'Enabled A20 line.', 0
msg_krnl:
	db 'Loaded kernel into memory.', 0
msg_video:
	db 'Entering video mode.', 0
msg_enter:
	db 'Entering kernel.', 0
msg_rsdp:
	db 'RSDP pointer safely stored.', 0

; Print functions for null-terminated strings
print:
	mov ah, 0x0E
	mov al, [esi]
	cmp al, 0
	je print_ret
	xor bh, bh
	int 0x10
	inc esi
	jmp print
print_ret:
    mov al, 0x0D ; CR
    int 0x10
    mov al, 0x0A ; LF
    int 0x10
	ret

; Error function in case something went wrong
err:
	mov ah, 0x0E
	mov al, 'E'
	xor bh, bh
	int 0x10
err_loop:
	cli
	hlt
	jmp err_loop

; Loading sectors from disk
[bits 16]
disk_load_32:
	
	; Get the track count
	xor edx, edx ; Zero out the top dividend
	movzx esi, word [gs:INFO_DISK_SECTORS]
	div esi
	inc edx ; Increment the remainder because sectors are 1-based
	mov ecx, edx ; Save sector index
	
	; Calculate the cylinder count
	xor edx, edx ; Zero out the top dividend
	movzx esi, word [gs:INFO_DISK_HEADS]
	div esi
	
	mov dh, dl ; Head index; move it into the high part of DX
	mov ch, al ; Cylinder index; only take the low 8 bits
	
	; We do need to do a little math on the CHS registers before proceeding
	; Bits 0-5 of CL are the sector index and bits 6-7 are the high bits of the cylinder index
	
	; Encode high bits of cylinder index into the sector index
	mov bl, ah   ; Move high bits of cylinder into BL temporarily
	and bl, 0x03 ; Mask out all but the high bits of cylinder
	shl bl, 6    ; Shift to high 6th and 7th bit
	and cl, 0x3F ; Clear 6th and 7th bit of DL for safety
	or  cl, bl   ; Add the high bits onto DL
	
disk_load_32_begin:
	
	; Set ES segment
	movr esi, reserved_sector
	shr esi, 4
	mov es, esi
	
	; Setup our registers
	mov si, 3 ; Retry count
	
disk_load_32_int:
	
	mov al, 1 ; Load 1 sector at a time
	
	xor bx, bx ; Offset of 0
	
	mov ah, 0x02 ; Read operation
	
	; Load the drive number
	mov dl, [gs:INFO_BOOT_DISK]
	
	; Call the disk read interrupt
	int 0x13
	
	; If the carry is set, retry
	jc disk_load_32_retry
	
	jmp disk_load_32_next
	
disk_load_32_retry:
	
	dec si
	jnz disk_load_32_int
	jmp err

disk_load_32_int_sec:
	
	; Restore the sector count
	mov cx, si
	
	mov si, 3 ; Reset the retry count
	
	; Jump to the loader
	jmp disk_load_32_int
	
disk_load_32_next:
	
	; Save EAX as we're using it as scratch
	push eax
	
	mov esi, (SECTOR_SIZE / 4) ; ESI is counter
	xor ebx, ebx ; Offset of 0
	
disk_load_32_copy:
	
	; Copy 4 bytes
	mov eax, [es:bx]
	mov [fs:ebp], eax
	
	; Increment and continue
	add ebp, 4
	add bx,  4
	dec esi
	jnz disk_load_32_copy
	
	; Restore EAX
	pop eax
	
	; Check for return
	dec edi
	jnz disk_load_32_next_cont
	
	; Return to the caller
	ret
	
disk_load_32_next_cont:
	
	; Increment the sector
	mov si, cx
	inc si
	
	; If we're below the max sector, jump to the loader again
	cmp si, [gs:INFO_DISK_SECTORS]
	jbe disk_load_32_int_sec
	
	; Break down CL
	movzx bx, cl ; Use BX as scratch
	and bl, 0xC0 ; Mask out everything but high bits
	shl bx, 2    ; Shift up into high 8 bits of BX
	mov bl, dh   ; Move the low 8 bits of head into low 8 bits of BL
	inc bx       ; Increment BX
	push bx      ; Preserve BX for later usage
	
	; Rebuild CL
	mov dh, bl   ; Move low 8 bits of BX into high 8 bits of DX, which holds the low 8 bits of head count
	and bh, 0x03 ; Mask out all but low 2 bits
	shl bh, 6    ; Shift high bits to their respective location
	mov cl, bh   ; Restore head count in CL
	or  cl, 1    ; Reset sector count
	
	; Reset our variables
	mov si, 3 ; Reset the retry count
	
	; If we're below max head, jump to the loader again
	pop bx
	cmp bx, word [gs:INFO_DISK_HEADS]
	jb disk_load_32_int
	
	; Increment the cylinder
	mov cl, 1  ; Reset the sector
	xor dh, dh ; Reset the head
	inc ch     ; Increment the cylinder
	
	; If we're below the max cylinder, jump to the loader again
	cmp ch, [gs:INFO_DISK_CYLINDERS]
	jb disk_load_32_int
	
	; If we somehow, someway got here, just error
	jmp err

; Disk query function
[bits 16]
disk_query:
	
    mov ah, 0x08
    mov dl, [gs:INFO_BOOT_DISK]
    int 0x13
    jc err
	
	; Decode the cylinder count
	mov bl, ch
	mov bh, cl
	and bh, 0xC0 ; Mask out everything except the rightmost / highest bits in BH
	shr bh, 6 ; Because registers are reversed we shift right to put the hi bits into the low bits. It's on the left in memory but the right in the register. Ask Intel, IDK why it's this way
	
	; Decode the sector count
	movzx ax, cl
	and ax, 0x3F ; Mask out all but the rightmost bits of AX to get the sector count
	
	; Get the head count
    movzx dx, dh
	
	; Increment cylinder and head count as they are 0-based
    inc bx
    inc dx
	
	; Store the sector, head, and cylinder counts
    mov [gs:INFO_DISK_SECTORS], ax
    mov [gs:INFO_DISK_HEADS], dx
    mov [gs:INFO_DISK_CYLINDERS], bx
	
	; Return to the caller
    ret

; Enabling the A20 line
[bits 16]
a20_enable:
	
	in al, 0x92
	or al, 2
	out 0x92, al
	mov si, 1000
	
a20_enable_loop:
	
	dec si
	jz a20_enable_kb
	in al, 0x92
	test al, 2
	jz a20_enable_loop
	jmp a20_enable_ret
	
a20_enable_kb:
	
    call a20_enable_kb_wait_in
    mov al, 0xAD
    out 0x64, al
	
    call a20_enable_kb_wait_in
    mov al, 0xD0
    out 0x64, al
	
    call a20_enable_kb_wait_out
    in al, 0x60
    push ax
	
    call a20_enable_kb_wait_in
    mov al, 0xD1
    out 0x64, al
	
    call a20_enable_kb_wait_in
    pop ax
    or al, 2
    out 0x60, al
	
    call a20_enable_kb_wait_in
    mov al, 0xAE
    out 0x64, al
	
	jmp a20_enable_ret
	
a20_enable_kb_wait_in:
	
    in al, 0x64
    test al, 2
    jnz a20_enable_kb_wait_in
    ret

a20_enable_kb_wait_out:
	
    in al, 0x64
    test al, 1
    jz a20_enable_kb_wait_out
    ret
	
a20_enable_ret:
	
	ret

; Getting available framebuffer resolutions and choosing one
[bits 16]
fb_load:
	
	; Get the absolute address
	movr ebx, ADDR_BASE
	mov eax, [ebx]
	movr ebx, ADDR_BASE_OFF
	add eax, [ebx]
	
	; Save this address
	movr ebx, ADDR_OFF_FB
	mov [ebx], eax
	
	; Load the segment and offset selectors
	mov eax, [ebx]
	push eax
	shr eax, 4
	mov es, eax
	pop eax
	and eax, 0xF
	mov di, ax
	
	; Select our VESA mode
	mov si, 0x11B
	push si
	
	; Enable VESA
	mov ax, 0x4F02
	mov bx, si
	or  bx, 0x4000 ; Linear framebuffer
	int 0x10
	pop si
	
	; If the load failed, fall back to VGA
	cmp ax, 0x004F
	jne fb_load_vga
	
	; Our VESA mode is supported
	jmp fb_load_vesa
	
fb_load_vga:
	
	; Select our VGA mode
	mov si, 0x13 ; 320x200 mode with 256 colors
	
	; Enable VGA
	mov ax, si
	int 10h
	
	; Load VGA mode info
	mov dword [es:di], 1 ; Mode 1 is VGA
	
	mov word [es:di + 4], 320      ; X res
	mov word [es:di + 6], 200      ; Y res
	mov word [es:di + 8], (0xA0000 >> 4) ; BAR
	
	; Return to the caller
	jmp fb_load_ret
	
fb_load_vesa:
	
	; Mark the mode as 0 for VESA
	mov dword [es:di], 0
	add di, 4
	
	; Load this VESA resolution's information into memory
	mov ax, 4F01h
	mov cx, si
	int 0x10
	
	; Return to the caller
	jmp fb_load_ret
	
fb_load_ret:
	
	; Add to the base offset
	movr ebx, ADDR_BASE_OFF
	add dword [ebx], 260
	
	; Return to the caller
	ret

; Finding a location for the kernel info
[bits 16]
e820_load_info:
	
	xor ebx, ebx ; Continuation value of 0
	
	; Load the segment and offset selectors
	mov ax, (ORIGIN + stage1_entry_16)
	shr ax, 4
	mov es, ax
	xor di, di
	
e820_load_info_next:
	
	xor eax, eax
	mov ax, 0xE820
	mov edx, 0x534D4150 ; SMAP
	mov ecx, 20         ; Only request 20 bytes
	
	int 0x15 ; Call the interrupt
	
	; Handle errors
	jc err
	cmp eax, 0x534D4150 ; Should still be SMAP
	jne err
	
	; Save EBX
	push ebx
	
	; Check if it's type 1 usable
	cmp dword [es:di + 16], 1
	jne e820_load_info_test
	
	mov eax, [es:di + 0] ; Base
	mov ecx, [es:di + 8] ; Length
	
	; Get the end of region
	mov edx, eax
	add edx, ecx
	
e820_load_info_loop:
	
	; If it's below the bootloader, continue
	cmp eax, (ORIGIN + SECTOR_SIZE + 4096)
	jbe e820_load_info_chk
	
	; If it overlaps with this stage, continue
	mov esi, cs
	
	shl esi, 4
	cmp edx, esi
	jb  e820_load_info_skip
	
	add esi, (FILE_SIZE - SECTOR_SIZE)
	cmp eax, esi
	ja  e820_load_info_skip
	
	; It's within range of the second stage; skip
	jmp e820_load_info_chk
	
e820_load_info_skip:
	
	; We accept a minimum size of 4 kilobytes
	mov esi, edx
	sub esi, eax
	cmp esi, 4096
	jb e820_load_info_chk
	
	; It's valid! We can return
	add sp, 4 ; Pop EBX
	movr ebx, ADDR_BASE
	mov [ebx], eax
	ret
	
e820_load_info_chk:
	
	; If EAX exceeds EDX, we've maxxed out this search
	cmp eax, edx
	ja e820_load_info_test
	
	add eax, 1024
	
	jmp e820_load_info_loop
	
e820_load_info_test:
	
	; Check the continuation value
	pop ebx
	test ebx, ebx
	jnz e820_load_info_next
	
	; No usable memory was found; error
	jmp err

; E820 memory map obtainment
[bits 16]
e820_load:
	
	; Calculate the current offset
	movr ebx, ADDR_BASE
	mov eax, [ebx]
	movr ebx, ADDR_BASE_OFF
	add eax, [ebx]
	
	; Save this address
	movr ebx, ADDR_OFF_E820
	mov [ebx], eax
	
	; Load the segment and offset selectors
	add eax, 2 ; First 2 bytes reserved for E820 count
	push eax
	shr eax, 4
	mov es, eax
	pop eax
	and eax, 0xF
	mov di, ax
	
	xor esi, esi ; Counter starts at 0
	xor ebx, ebx ; Continuation value of 0
	
e820_load_next:
	
	xor eax, eax
	mov ax, 0xE820
	mov edx, 0x534D4150 ; SMAP
	mov ecx, 24         ; We load 24 bytes of info from E820
	
	int 0x15 ; Call the interrupt
	
	; Handle errors
	jc err
	cmp eax, 0x534D4150 ; Should still be SMAP
	jne err
	
	inc esi ; Add one to the counter
	add di, 24 ; Move to next buffer slot
	test ebx, ebx
	jnz e820_load_next
	
	; Save ESI to the first 2 bytes relative to the ADDR_OFF_E820 address
	movr ebx, ADDR_OFF_E820
	mov [ebx], esi
	
	; Shift the base address offset by the E820 count times 24
	mov eax, esi
	shl esi, 4
	shl eax, 3
	add esi, eax
	
	; Add this offset to the base offset for the next function
	movr ebx, ADDR_BASE_OFF
	add [ebx], esi
	
	; Return to the caller
	ret

; Locating and saving the RSDP
[bits 16]
rsdp_copy:
	
	; Zero out the pointer to the RSDP
	movr ebx, ADDR_OFF_RSDP
	mov dword [ebx], 0
	
	; Save our segment registers
	push es
	push ds
	
	; Get the EBDA from 0x040E
	mov ax, 0x40
	mov ds, ax
	mov si, 0x0E
	
	; Load the EBDA segment into DS
	mov ax, [ds:si]
	
	; Check to see if it's valid; if null, skip straight to BIOS scan
	test ax, ax
	jz rdsp_copy_loop_bios_start
	
	mov ds, ax
	xor si, si
	
rsdp_copy_loop_ebda:
	
	; Check for the signature
	cmp dword [ds:si + 0], 'RSD '
	jne rsdp_copy_loop_ebda_next
	cmp dword [ds:si + 4], 'PTR '
	jne rsdp_copy_loop_ebda_next
	
	; Jump to the save routine
	jmp rsdp_copy_save
	
rsdp_copy_loop_ebda_next:
	
	; Increment SI and see if we've exited the EBDA
	add si, 16
	cmp si, 1024
	jae rdsp_copy_loop_bios_start
	jmp rsdp_copy_loop_ebda
	
rdsp_copy_loop_bios_start:
	
	; Start at the BIOS area
	mov ax, (0xE0000 >> 4)
	mov ds, ax
	xor si, si
	
	mov ax, 2 ; We can only increment DS twice before overflowing the BIOS area and giving up
	
rsdp_copy_loop_bios:
	
	; Check for the signature
	cmp dword [ds:si + 0], 'RSD '
	jne rsdp_copy_loop_bios_next
	cmp dword [ds:si + 4], 'PTR '
	jne rsdp_copy_loop_bios_next
	
	; Jump to the save routine
	jmp rsdp_copy_save
	
rsdp_copy_loop_bios_next:
	
	; Increment SI and see if it carries
	add si, 16
	jc rsdp_copy_loop_bios_hit
	jmp rsdp_copy_loop_bios
	
rsdp_copy_loop_bios_hit:
	
	; If AX hits zero, we failed to find the RSDP
	dec ax ; Decrement AX
	jz rsdp_copy_ret
	
	; Increment DS
	mov bx, ds
	add bx, 4096 ; Increment by 64KB
	mov ds, bx
	
	jmp rsdp_copy_loop_bios
	
rsdp_copy_save:
	
	; Save the 36 bytes
	movr eax, disk_query ; Repurpose the memory that holds "disk_query" for our RSDP copy
	shr eax, 4
	mov es, eax
	xor di, di ; Offset of 0
	mov cx, SIZE_RSDP ; Save 36 bytes
	cld
	rep movsb
	
	; Save ES to ECX
	mov ecx, es
	shl ecx, 4
	
	; Reset the segment registers
	pop ds
	pop es
	
	; Tell the kernel that its RSDP is at the address of "disk_query"
	movr ebx, ADDR_OFF_RSDP
	mov [ebx], ecx
	
	; Return to the caller
	ret
	
rsdp_copy_ret:
	
	; Reset the segment registers
	pop ds
	pop es
	
	; Return to the caller
	ret

; Stage 2 real mode entry
[bits 16]
stage2_entry_16:
	
	; GS is used as a segment register for accesing first stage info
	xor ax, ax
	mov gs, ax
	
	; Get the disk geometry
	call disk_query
	
	movr esi, msg_geom
	call print
	
	; Enable the A20 line
	call a20_enable
	
	movr esi, msg_a20
	call print
	
	; Find a location to store info for kernel
	call e820_load_info
	
	; Load the E820 memory map
	call e820_load
	
	movr esi, msg_e820
	call print
	
	; Copy the RSDP somewhere safe
	call rsdp_copy
	
	movr esi, msg_rsdp
	call print
	
	; Enter unreal mode
	call 0x00:um_enable
	
	; Load the kernel into memory
	mov ebp, KERNEL_ADDRESS
	mov edi, KERNEL_SECTORS ; Sector count
	mov eax, (FILE_SIZE / SECTOR_SIZE) ; Sector index
	call disk_load_32 ; Call the function
	
	movr esi, msg_krnl
	call print
	
	; Enable a linear framebuffer
	movr esi, msg_video
	call print
	
	call fb_load
	
	; Move the base address of our information into some registers
	movr ecx, ADDR_INFO
	
	; Tell the first stage where to jump to
	movr edx, stage2_entry_32
	
	; Enable protected mode
	jmp 0x00:pm_enable

; Stage 2 protected mode entry
[bits 32]
stage2_entry_32:
	
	; Set up data segment selectors
	mov ax, SEG_DATA
	mov ds, ax
	mov es, ax
	mov fs, ax
	mov gs, ax
	mov ss, ax
	
	; Setup the stack pointer
	mov esp, ADDR_STACK
	mov ebp, esp
	
	; Ensure write protection is enabled
	mov eax, cr0
	or  eax, (1 << 16) ; WP
	mov cr0, eax
	
	; Disable FPU emulation
	mov eax, cr0
	and eax, ~(1 << 2)
	mov cr0, eax
	
	; Enable SSE and SSE exceptions
	mov eax, cr4
	or  eax, (1 << 9) | (1 << 10)
	mov cr4, eax
	
	; Reset the FPU to defaults
	fninit
	
	; Jump to kernel
	mov eax, KERNEL_ADDRESS
	jmp eax

; Pad up to the nearest sector
times (2560 - ($ - $$)) db 0

; Reserve a sector for loading sectors
reserved_sector:
times SECTOR_SIZE db 0

; The file size used for calculating how many sectors the bootloader occupies
FILE_SIZE equ ($ - $$)