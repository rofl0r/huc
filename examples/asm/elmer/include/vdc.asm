; ***************************************************************************
; ***************************************************************************
;
; vdc.asm
;
; Useful routines for operating the HuC6270 Video Display Controller.
;
; These should be located in permanently-accessible memory!
;
; Copyright John Brandwood 2021.
;
; Distributed under the Boost Software License, Version 1.0.
; (See accompanying file LICENSE_1_0.txt or copy at
;  http://www.boost.org/LICENSE_1_0.txt)
;
; ***************************************************************************
; ***************************************************************************

;
; Include dependancies ...
;

		include "common.asm"		; Common helpers.
		include "vce.asm"		; Useful VCE routines.

;
; Enable BG & SPR layers.
;

set_bgon:	lda	#$80			; Enable BG layer.
		bra	!+

set_spron:	lda	#$40			; Enable SPR layer.
		bra	!+

set_dspon:	lda	#$C0			; Enable BG & SPR layers.

!:		tsb	<vdc_crl		; These take effect when
	.if	SUPPORT_SGX			; the next VBLANK occurs.
		tsb	<sgx_crl
	.endif
		rts

;
; Disable BG & SPR layers.
;

set_bgoff:	lda	#$80			; Disable BG layer.
		bra	!+

set_sproff:	lda	#$40			; Disable SPR layer.
		bra	!+

set_dspoff:	lda	#$C0			; Disable BG & SPR layers.

!:		trb	<vdc_crl		; These take effect when
	.if	SUPPORT_SGX			; the next VBLANK occurs.
		trb	<sgx_crl
	.endif
		rts

;
;
;

		.procgroup			; These routines share code!

; ***************************************************************************
; ***************************************************************************
;
; clear_vram_sgx - Clear all of VRAM in the SGX VDC.
; clear_vram_vdc - Clear all of VRAM in the PCE VDC.
;
; Args: _ax = word value to write to the BAT.
; Args: _bl = hi-byte of size of BAT (# of words).
;

	.if	SUPPORT_SGX
clear_vram_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$E0			; Turn "clx" into a "cpx #".

		.endp
	.endif

clear_vram_vdc	.proc

		clx				; Offset to PCE VDC.

clear_vram_x:	bsr	clear_bat_x		; Clear the BAT.

		lda	#$80			; Xvert hi-byte of # words
		sec				; in screen to loop count.
		sbc	<_bl
		lsr	a

;		cly				; Clear the rest of VRAM.
.clr_loop:	pha
		stz	VDC_DL, x
.clr_pair:	stz	VDC_DH, x
		stz	VDC_DH, x
		dey
		bne	.clr_pair
		pla
		dec	a
		bne	.clr_loop

		leave				; All done, phew!

		.endp



; ***************************************************************************
; ***************************************************************************
;
; clear_bat_sgx - Clear the BAT in the SGX VDC.
; clear_bat_vdc - Clear the BAT in the PCE VDC.
;
; Args: _ax = word value to write to the BAT.
; Args: _bl = hi-byte of size of BAT (# of words).
;

	.if	SUPPORT_SGX
clear_bat_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$E0			; Turn "clx" into a "cpx #".

		.endp
	.endif

clear_bat_vdc	.proc

		clx				; Offset to PCE VDC.

		bsr	clear_bat_x		; Clear the BAT.

		leave				; All done, phew!

		.endp

		; Written as a subroutine because of "leave"!

clear_bat_x:	stz	<_di + 0		; Set VDC or SGX destination
		stz	<_di + 1		; address.
		jsr	set_di_to_mawr

		lda	<_bl			; Xvert hi-byte of # words
		lsr	a			; in screen to loop count.

		cly
.bat_loop:	pha
		lda	<_ax + 0
		sta	VDC_DL, x
		lda	<_ax + 1
.bat_pair:	sta	VDC_DH, x
		sta	VDC_DH, x
		dey
		bne	.bat_pair
		pla
		dec	a
		bne	.bat_loop

		rts

		.endprocgroup

;
;
;

		.procgroup			; These routines share code!

; ***************************************************************************
; ***************************************************************************
;
; set_mode_sgx - Set video hardware registers from a data table.
; set_mode_vdc - Set video hardware registers from a data table.
;
; Args: _si, _si_bank = _farptr to data table mapped into MPR3 & MPR4.
;

	.if	SUPPORT_SGX
set_mode_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$E0			; Turn "clx" into a "cpx #".

		.endp
	.endif

set_mode_vdc	.proc

		clx				; Offset to PCE VDC.

.set_mode_x:	tma3				; Preserve MPR3.
		pha
		tma4				; Preserve MPR4.
		pha

		jsr	set_si_to_mpr34		; Map data to MPR3 & MPR4.

		php				; Disable interrupts.
		sei

		cly				; Table size is < 256 bytes.

.loop:		lda	[_si], y		; Get the register #, +ve for
		beq	.done			; VDC, -128 for VCE.
		bpl	.set_vdc_reg

		; Set a VCE register.

.set_vce_reg:	iny

		lda	[_si], y		; Get lo-byte of register.
		iny
		sta	VCE_CR			; Set the VCE clock speed and
		bra	.loop			; artifact reduction.

		; Set a VDC register.

.set_vdc_reg:	iny
		sta	VDC_AR, x		; Set which VDC register.

		cmp	#VDC_CR			; CS if VDC_CR or higher.
		beq	.skip_cc
		clc				; CC if not VDC_CR.

.skip_cc:	lda	[_si], y		; Get lo-byte of register.
		iny
		bcc	.not_vdc_cr

	.if	SUPPORT_SGX
		cpx	#0			; Writing to the VDC or SGX?
		beq	.save_crl
		and	#$F7			; We only need 1 vblank IRQ!
	.endif

.save_crl:	sta	<vdc_crl, x		; Save VDC_CR shadow register.

.not_vdc_cr:	sta	VDC_DL, x		; Write to VDC.

		lda	[_si], y		; Get hi-byte of register.
		iny
		sta	VDC_DH, x
		bcc	.loop			; Next register, please!

		sta	<vdc_crh, x		; Save VDC_CR shadow register.

		bra	.loop			; Next register, please!

		; All registers set!

.done:		lda	<vdc_reg, x		; Restore previous VDC_AR from
		sta	VDC_AR, x		; the shadow variable.

		plp				; Restore interrupts.

		pla				; Restore MPR4.
		tam4
		pla				; Restore MPR3.
		tam3

		leave				; All done, phew!

		.endp

		.endprocgroup



; ***************************************************************************
; ***************************************************************************
;
; sgx_detect - Detect whether we're running on a SuperGrafx.
;
; Note that this corrupts VRAM address $7F7F in both the VDC and SGX.
;

	.if	SUPPORT_SGX
sgx_detect	.proc

		ldy	#$7F			; Use VRAM address $7F7F
		sty.h	<_di			; because it won't cause
		sty.l	<_di			; a screen glitch.

		jsr	sgx_di_to_mawr		; Write $007F to SGX VRAM.
		sty	SGX_DL
		stz	SGX_DH

		jsr	vdc_di_to_mawr		; Write $0000 to VDC VRAM.
		stz	VDC_DL
		stz	VDC_DH

		jsr	sgx_di_to_marr		; Check value in SGX VRAM.
		ldy	SGX_DL
		sty	sgx_detected

		jsr	sgx_di_to_mawr		; Write $0000 to SGX VRAM.
		stz	SGX_DL
		stz	SGX_DH

		leave				; All done, phew!

		.endp

	.ifndef	sgx_detected			; Could be defined in CORE.
		.bss
sgx_detected:	ds	1			; NZ if SuperGrafx detected.
		.code
	.endif

	.endif	SUPPORT_SGX



; ***************************************************************************
; ***************************************************************************
;
; init_256x224 - An example of initializing screen and VRAM.
;
; This can be used as-is, or copied to your own program and modified.
;

init_256x224	.proc

.BAT_SIZE	=	64 * 32
.SAT_ADDR	=	.BAT_SIZE		; SAT takes 16 tiles of VRAM.
.CHR_ZERO	=	.BAT_SIZE / 16		; 1st tile # after the BAT.
.CHR_0x10	=	.CHR_ZERO + 16		; 1st tile # after the SAT.
.CHR_0x20	=	.CHR_ZERO + 32		; ASCII ' ' CHR tile #.

		call	clear_vce		; Clear all palettes.

		lda.l	#.CHR_0x20		; Tile # of ' ' CHR.
		sta.l	<_ax
		lda.h	#.CHR_0x20
		sta.h	<_ax

		lda	#>.BAT_SIZE		; Size of BAT in words.
		sta	<_bl

		call	clear_vram_vdc		; Clear VRAM.
	.if	SUPPORT_SGX
		call	clear_vram_sgx
	.endif

		lda.l	#.mode_256x224		; Disable BKG & SPR layers but
		sta.l	<_si			; enable RCR & VBLANK IRQ.
		lda.h	#.mode_256x224
		sta.h	<_si
		lda	#^.mode_256x224
		sta	<_si_bank

	.if	SUPPORT_SGX
		call	sgx_detect		; Are we really on an SGX?
		beq	!+
		call	set_mode_sgx		; Set SGX 1st, with no VBL.
	.endif
!:		call	set_mode_vdc		; Set VDC 2nd, VBL allowed.

		call	wait_vsync		; Wait for the next VBLANK.

		leave				; All done, phew!

		; A standard 256x224 screen with overscan.

.mode_256x224:	db	$80			; VCE Control Register.
		db	VCE_CR_5MHz + 4		;   Video Clock + Artifact Reduction

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_64x32 + VDC_MWR_1CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_256
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_256
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0800
		dw	$0800
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

		.endp



; ***************************************************************************
; ***************************************************************************
;
; init_512x224 - An example of initializing screen and VRAM.
;
; This can be used as-is, or copied to your own program and modified.
;

init_512x224	.proc

.BAT_SIZE	=	64 * 32
.SAT_ADDR	=	.BAT_SIZE		; SAT takes 16 tiles of VRAM.
.CHR_ZERO	=	.BAT_SIZE / 16		; 1st tile # after the BAT.
.CHR_0x10	=	.CHR_ZERO + 16		; 1st tile # after the SAT.
.CHR_0x20	=	.CHR_ZERO + 32		; ASCII ' ' CHR tile #.

		call	clear_vce		; Clear all palettes.

		lda.l	#.CHR_0x20		; Tile # of ' ' CHR.
		sta.l	<_ax
		lda.h	#.CHR_0x20
		sta.h	<_ax

		lda	#>.BAT_SIZE		; Size of BAT in words.
		sta	<_bl

		call	clear_vram_vdc		; Clear VRAM.
	.if	SUPPORT_SGX
		call	clear_vram_sgx
	.endif

		lda.l	#.mode_512x224		; Disable BKG & SPR layers but
		sta.l	<_si			; enable RCR & VBLANK IRQ.
		lda.h	#.mode_512x224
		sta.h	<_si
		lda	#^.mode_512x224
		sta	<_si_bank

	.if	SUPPORT_SGX
		call	sgx_detect		; Are we really on an SGX?
		beq	!+
		call	set_mode_sgx		; Set SGX 1st, with no VBL.
	.endif
!:		call	set_mode_vdc		; Set VDC 2nd, VBL allowed.

		call	wait_vsync		; Wait for the next VBLANK.

		leave				; All done, phew!

		; A standard 512x224 screen with overscan.

.mode_512x224:	db	$80			; VCE Control Register.
		db	VCE_CR_10MHz + 4	;   Video Clock + Artifact Reduction

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_64x32 + VDC_MWR_2CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_512
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_512
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0800
		dw	$0800
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

		.endp



; ***************************************************************************
; ***************************************************************************
;
; mode_240x224 - Example 240x224 screen mode to copy to your own program.
; mode_256x224 - Example 256x224 screen mode to copy to your own program.
; mode_352x224 - Example 352x224 screen mode to copy to your own program.
; mode_512x224 - Example 512x224 screen mode to copy to your own program.
;
; See "pcengine.inc" for other common settings that can be used, and read the
; HuC6270 Video Display Controller manual to understand what the values mean,
; and how you might change them to create different special effects.
;

	.if	0

		; A reduced 240x224 screen to save VRAM.

mode_240x224:	db	$80			; VCE Control Register.
		db	VCE_CR_5MHz		; Video Clock

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_32x32 + VDC_MWR_1CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_240
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_240
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0400
		dw	$0400
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

		; A standard 256x224 screen with overscan.

mode_256x224:	db	$80			; VCE Control Register.
		db	VCE_CR_5MHz		; Video Clock

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_64x32 + VDC_MWR_1CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_256
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_256
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0800
		dw	$0800
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

		; A standard 352x224 screen with overscan.

mode_352x224:	db	$80			; VCE Control Register.
		db	VCE_CR_7MHz + 4		;   Video Clock + Artifact Reduction

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_64x32 + VDC_MWR_1CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_352
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_352
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0800
		dw	$0800
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

		; A standard 512x224 screen with overscan.

mode_512x224:	db	$80			; VCE Control Register.
		db	VCE_CR_10MHz + 4	;   Video Clock + Artifact Reduction

		db	VDC_MWR			; Memory-access Width Register
		dw	VDC_MWR_64x32 + VDC_MWR_2CYCLE
		db	VDC_HSR			; Horizontal Sync Register
		dw	VDC_HSR_512
		db	VDC_HDR			; Horizontal Display Register
		dw	VDC_HDR_512
		db	VDC_VPR			; Vertical Sync Register
		dw	VDC_VPR_224
		db	VDC_VDW			; Vertical Display Register
		dw	VDC_VDW_224
		db	VDC_VCR			; Vertical Display END position Register
		dw	VDC_VCR_224
		db	VDC_DCR			; DMA Control Register
		dw	$0010			;   Enable automatic VRAM->SATB
		db	VDC_DVSSR		; VRAM->SATB address $0800
		dw	$0800
		db	VDC_BXR			; Background X-Scroll Register
		dw	$0000
		db	VDC_BYR			; Background Y-Scroll Register
		dw	$0000
		db	VDC_RCR			; Raster Counter Register
		dw	$0000			;   Never occurs!
		db	VDC_CR			; Control Register
		dw	$000C			;   Enable VSYNC & RCR IRQ
		db	0

	.endif
