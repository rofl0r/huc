; ***************************************************************************
; ***************************************************************************
;
; common.asm
;
; Small, generic, PCE subroutines that are commonly useful when developing.
;
; These should be located in permanently-accessible memory!
;
; Copyright John Brandwood 2021-2022.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************

;
; Useful variables.
;

	.ifndef	_temp
		.zp
_temp		ds	2			; For use within a subroutine.
		.code
	.endif



; ***************************************************************************
; ***************************************************************************
;
; Wait for the next VBLANK IRQ.
;

wait_vsync:	lda	irq_cnt			; System Card variable, changed
.loop:		cmp	irq_cnt			; every VBLANK interrupt.
		beq	.loop
		rts



; ***************************************************************************
; ***************************************************************************
;
; Delay for the next Y VBLANK IRQs.
;

wait_nvsync:	bsr	wait_vsync		; # of VBLANK IRQs to wait in
		dey				; the Y register.
		bne	wait_nvsync
		rts



; ***************************************************************************
; ***************************************************************************
;
; Map the _bp data far-pointer into MPR3 (& MPR4).
;
; Because the 16KB RAM region at $2000-$5FFF is composed of two separate
; banks, with the 2nd bank having no specific relation to the 1st, there
; is no way to deal with a bank-increment, so do not map that region.
;
; N.B. Library code relies on this preserving X!
;

set_bp_to_mpr3:	lda.h	<_bp			; Do not remap a ptr to RAM,
		cmp	#$60			; which is $2000-$5FFF.
		bcc	!+
		and	#$1F			; Remap ptr to MPR3.
		ora	#$60
		sta.h	<_bp
		tya				; Put bank into MPR3.
		tam3
!:		rts

set_bp_to_mpr34:lda.h	<_bp			; Do not remap a ptr to RAM,
		cmp	#$60			; which is $2000-$5FFF.
		bcc	!+
		and	#$1F			; Remap ptr to MPR3.
		ora	#$60
		sta.h	<_bp
		tya				; Put bank into MPR3.
		tam3
		inc	a			; Put next into MPR4.
		tam4
!:		rts



; ***************************************************************************
; ***************************************************************************
;
; Increment the hi-byte of _bp and change TMA3 if necessary.
;
; N.B. Library code relies on this preserving A,X,Y!
;

inc.h_bp_mpr3:	inc.h	<_bp			; Increment hi-byte of _bp.
		bpl	!+			; OK if within MPR0-MPR3.
		pha				; Increment the bank in MPR3,
		tma3				; usually when pointer moves
		inc	a			; from $7FFF -> $8000.
		tam3
		lda	#$60
		sta.h	<_bp
		pla
!:		rts



; ***************************************************************************
; ***************************************************************************
;
; Increment the hi-byte of _bp and change TMA3 and TMA4 if necessary.
;
; N.B. Library code relies on this preserving A,X,Y!
;

	.if	1				; Save memory, for now.

inc.h_bp_mpr34:	inc.h	<_bp			; Increment hi-byte of _bp.
		bpl	!+			; OK if within MPR0-MPR3.
		pha				; Increment the bank in MPR3,
		tma4				; usually when pointer moves
		tam3				; from $7FFF -> $8000.
		inc	a
		tam4
		lda	#$60
		sta.h	<_bp
		pla
!:		rts

	.endif



; ***************************************************************************
; ***************************************************************************
;
; Put the _di data pointer into the VDC's MARR or MAWR register.
;

	.if	SUPPORT_SGX
sgx_di_to_marr:	ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$F0			; Turn "clx" into a "beq".
	.endif

vdc_di_to_marr:	clx				; Offset to PCE VDC.

set_di_to_marr	lda	#VDC_MARR		; Set VDC or SGX destination
		sta	<vdc_reg, x		; address.
		sta	VDC_AR, x
		bra	!+

	.if	SUPPORT_SGX
sgx_di_to_mawr:	ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$F0			; Turn "clx" into a "beq".
	.endif

vdc_di_to_mawr:	clx				; Offset to PCE VDC.

set_di_to_mawr;	lda	#VDC_MAWR		; Set VDC or SGX destination
		stz	<vdc_reg, x		; address.
		stz	VDC_AR, x

!:		lda	<_di + 0
		sta	VDC_DL, x
		lda	<_di + 1
		sta	VDC_DH, x

		lda	#VDC_VWR		; Select the VRR/VWR data
		sta	<vdc_reg, x		; register.
		sta	VDC_AR, x
		rts



; ***************************************************************************
; ***************************************************************************
;
; Increment the hi-byte of _di and change TMA4 if necessary.
;

	.if	0				; Save memory, for now.

inc.h_di_mpr4:	inc.h	<_di			; Increment hi-byte of _di.

		bpl	!+			; OK if within MPR0-MPR3.
		tst	#$1F, <_di + 1		; OK unless $80,$A0,$C0,$E0.
		bne	!+
		bvs	!+			; OK unless $80,$A0.
;		tst	#$20, <_di + 1		; OK unless $A0.
;		beq	!+			; This test is overkill!

		pha				; Increment the bank in MPR4,
		tma4				; usually when pointer moves
		inc	a			; from $9FFF -> $A000.
		tam4
		lda.h	#$8000
		sta.h	<_di
		pla
!:		rts
	.endif



; ***************************************************************************
; ***************************************************************************
;
; Far-call a function in another bank.
;
; This is compatible with PCEAS's "-newproc" procedure calls, but avoids
; generating a 10-byte procedure trampoline.
;
; To use this ...
;
;  jsr far_call
;  tst #bank( myfunc ), myfunc - 1
;
; The "TST" instruction itself is skipped and NOT executed after the call,
; it only exists to make things easier to read in a listing/debugger.
;
; The called .PROC routine must exit with "jmp leave_proc" and not "rts".
;
; leave_proc:	pla
;		tam6
;		tya
;		rts
;
; N.B. This costs 32 bytes, and takes 82 cycles vs 18 for the trampoline
;      code (when you exclude preserving YA in zero-page).
;
; N.B. This is NOT re-entrant, and must NOT be used in an IRQ handler if
;      _temp is not saved and restored!
;
; N.B. This was written as an excerise, and I wouldn't recommend using it!
;

	.if	0

far_call:	sta.l	<_bp			; Preserve YA registers as
		sty.h	<_bp			; an address parameter.

		pla				; Get return address.
		sta.l	<_temp
		clc				; Skip the far_call()
		adc	#4			; address parameter.
		tay
		pla
		sta.h	<_temp
		adc	#0
		pha				; Put return address.
		phy

		tma6				; Preserve MPR6.
		pha

		ldy	#4			; Push far_call() addr.
		lda	[_temp], y
		pha
		dey
		lda	[_temp], y
		pha

		dey				; Read far_call() bank.
		lda	[_temp], y
		tam6

		rts				; Jump to routine.

	.endif



; ***************************************************************************
; ***************************************************************************
;
; Far-call a function in another bank.
;
; This is compatible with PCEAS's "-newproc" procedure calls, but avoids
; generating a 10-byte procedure trampoline.
;
; To use this ...
;
;  brk
;  tst #bank( myfunc ), myfunc - 1
;
; The "TST" instruction itself is skipped and NOT executed after the call,
; it only exists to make things easier to read in a listing/debugger.
;
; The called .PROC routine must exit with "jmp leave_proc" and not "rts".
;
; leave_proc:	pla
;		tam6
;		tya
;		rts
;
; N.B. This costs 45 bytes, and takes 103 cycles (or 84 on HuCARD) vs 18 for
;      the trampoline code (when you exclude preserving YA in zero-page).
;
; N.B. This is NOT re-entrant, and must NOT be used in an IRQ handler if
;      _temp is not saved and restored!
;
; N.B. This was written as an excerise, and I wouldn't recommend using it!
;

	.if	0

irq2_handler:	phx				; Preserve X register
		tsx				;
		tst	#$10, $2102, x		; Is the B flag set?
		beq	.got_irq2		;
		plx				; Restore X register.

		; Handle interrupt as BRK.

.got_brk:	plp				; Restore interrupt flag.

		sta.l	<_bp			; Preserve YA registers as
		sty.h	<_bp			; an address parameter.

		pla				; Get return address lo-byte.
		sta.l	<_temp
		clc				; Skip the far_call()
		adc	#2			; address parameter.
		tay

		pla				; Get return address hi-byte.
		sta.h	<_temp
		adc	#0
		pha				; Put updated return address.
		phy

		tma6				; Preserve MPR6.
		pha

		ldy	#2			; Push far_call() addr.
		lda	[_temp], y
		pha
		dey
		lda	[_temp], y
		pha

		lda	[_temp]			; Read far_call() bank.
		tam6

		rts				; Jump to routine.

		; Handle interrupt as IRQ2.

.got_irq2:	plx				; Process as an interrupt.
		; ...

	.endif



; ***************************************************************************
; ***************************************************************************
;
; Far-call a function in another bank.
;
; This is a potential alternative procedure call trampoline that uses only 10
; bytes of common memory per bank of procedures, instead of 10 bytes for each
; individual procedure call, BUT it uses the X register as a procedure-index,
; and it needs a table of addresses at the end of every procedure bank.
;
; To use this ...
;
;  ldx #procedure-index
;  jsr far_call_nn
;
; The called .PROC routine must exit with "jmp leave_proc" and not "rts".
;
; leave_proc:	pla
;		tam6
;		tya
;		rts
;
; N.B. This costs 21 cycles vs 18 for the .newproc trampoline code (when you
;      exclude preserving YA in zero-page).
;
; N.B. This was written as an excerise, and definitely not for HuC!
;

	.if	0

far_call_nn:
;		sta.l	<_bp			; 4 Preserve YA registers as
;		sty.h	<_bp			; 4 an address parameter.

		tma6				; 4 Preserve MPR6.
		pha				; 3

		lda	#bank_number		; 2
		tam6				; 5
		jmp	[$DF00, x]		; 7

	.endif					; 21
