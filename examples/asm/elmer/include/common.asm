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
; Overload this System Card variable for use by a far data pointer argument.
;

	.ifndef	_si_bank
_si_bank	=	_dh
_di_bank	=	_dh
_bp_bank	=	_dh
	.endif

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
; Map the _si data far-pointer into MPR3 (& MPR4).
;

xay_to_si_mpr34:bsr	xay_to_si_mpr3		; Remap ptr to MPR3.
		inc	a			; Put next bank into MPR4.
		tam4
		rts

xay_to_si_mpr3:	stx.l	<_si			; Remap ptr to MPR3.
;		say
		and.h	#$1F00
		ora.h	#$6000
		sta.h	<_si

		tya				; Put bank into MPR3.
		tam3
		rts



; ***************************************************************************
; ***************************************************************************
;
; Map the _si data far-pointer into MPR3 (& MPR4).
;

set_si_to_mpr34:bsr	set_si_to_mpr3		; Remap ptr to MPR3.
		inc	a			; Put next bank into MPR4.
		tam4
		rts

set_si_to_mpr3:	lda.h	<_si			; Remap ptr to MPR3.
		and.h	#$1F00
		ora.h	#$6000
		sta.h	<_si

		lda	<_si_bank		; Put bank into MPR3.
		tam3
		rts



; ***************************************************************************
; ***************************************************************************
;
; Increment the hi-byte of _si and change TMA3 if necessary.
;

inc.h_si_mpr3:	inc.h	<_si			; Increment hi-byte of _si.

		bpl	!+			; OK if within MPR0-MPR3.
		tst	#$7F, <_si + 1		; OK unless $80.
		bne	!+

		pha				; Increment the bank in MPR3,
		tma3				; usually when pointer moves
		inc	a			; from $7FFF -> $8000.
		tam3
		lda.h	#$6000
		sta.h	<_si
		pla
!:		rts



; ***************************************************************************
; ***************************************************************************
;
; Put the _si data pointer into the VDC's MARR register.
;

	.if	SUPPORT_SGX
set_si_to_sgx:	ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$E0			; Turn "clx" into a "cpx #".
	.endif

set_si_to_vdc:	clx				; Offset to PCE VDC.

set_si_to_vram:	lda	#VDC_MARR		; Set VDC or SGX destination
		sta	<vdc_reg, x		; address.

		sta	VDC_AR, x
		lda	<_si + 0
		sta	VDC_DL, x
		lda	<_si + 1
		sta	VDC_DH, x

		lda	#VDC_VRR		; Select the VRR data-read
		sta	<vdc_reg, x		; register.
		sta	VDC_AR, x
		rts



; ***************************************************************************
; ***************************************************************************
;
; Put the _di data pointer into the VDC's MAWR register.
;

	.if	SUPPORT_SGX
set_di_to_sgx:	ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$E0			; Turn "clx" into a "cpx #".
	.endif

set_di_to_vdc:	clx				; Offset to PCE VDC.

set_di_to_vram;	lda	#VDC_MAWR		; Set VDC or SGX destination
		stz	<vdc_reg, x		; address.

		stz	VDC_AR, x
		lda	<_di + 0
		sta	VDC_DL, x
		lda	<_di + 1
		sta	VDC_DH, x

		lda	#VDC_VWR		; Select the VWR data-write
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