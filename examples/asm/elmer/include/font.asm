; ***************************************************************************
; ***************************************************************************
;
; font.asm
;
; Code for working with fonts.
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
; Include dependancies ...
;

		include "common.asm"		; Common helpers.

;
; If drop-shadow is on the RHS, then font data should be LHS justified.
; If drop-shadow is on the LHS, then font data should be RHS justified.
;

	.ifndef	FNT_SHADOW_LHS
FNT_SHADOW_LHS	=	0
	.endif

;
; Temporary 32-byte workspace at the bottom of the stack.
;

tmp_shadow_buf	equ	$2100			; Interleaved 16 + 1 lines.
tmp_normal_buf	equ	$2101			; Interleaved 16 lines.



; ***************************************************************************
; ***************************************************************************
;
; dropfnt8x8_sgx - Upload an 8x8 drop-shadowed font to the SGX VDC.
; dropfnt8x8_vdc - Upload an 8x8 drop-shadowed font to the PCE VDC.
;
; Args: _bp, Y = _farptr to font data (maps to MPR3).
; Args: _di = ptr to output address in VRAM.
; Args: _al = bitplane 2 value for the tile data ($00 or $FF).
; Args: _ah = bitplane 3 value for the tile data ($00 or $FF).
; Args: _bl = # of font glyphs to upload.
;
; N.B. The font is 1bpp, and the drop-shadow is generated by the CPU.
;
; When _al == $00 $FF $00 $FF
; When _ah == $00 $00 $FF $FF
;
; BKG pixels    0   4   8  12
; Shadow pixels 1   5   9  13
; Font pixels   2   6  10  14
;

		.procgroup			; Keep this code together!

	.if	SUPPORT_SGX
dropfnt8x8_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$F0			; Turn "clx" into a "beq".

		.endp
	.endif

dropfnt8x8_vdc	.proc

		clx				; Offset to PCE VDC.

		tma3				; Preserve MPR3.
		pha

		jsr	set_bp_to_mpr3		; Map memory block to MPR3.
		jsr	set_di_to_mawr		; Map _di to VRAM.

		; Generate shadowed glyph.

.tile_loop:	phx				; Preserve VDC/SGX offset.

		clx				; Create a drop-shadowed version
		stz	tmp_shadow_buf, x	; of the glyph.

	.if	FNT_SHADOW_LHS
.line_loop:	lda	[_bp]			; Drop-shadow on the LHS.
		sta	tmp_normal_buf, x	; Font data is RHS justified.
		asl	a
	.else
.line_loop:	lda	[_bp]			; Drop-shadow on the RHS.
		sta	tmp_normal_buf, x	; Font data is LHS justified.
		lsr	a
	.endif

	.if	0
		ora	[_bp]			; Composite font and shadow
		sta	tmp_shadow_buf + 2, x	; planes (wide shadow).
	.else
		sta	tmp_shadow_buf + 2, x	; Composite font and shadow
		ora	[_bp]			; planes (normal shadow).
	.endif

		ora	tmp_shadow_buf, x
		eor	tmp_normal_buf, x
		sta	tmp_shadow_buf, x

		inc	<_bp			; Increment ptr to font.
		bne	.next_line
		jsr	inc.h_bp_mpr3
.next_line:	inx
		inx
		cpx	#8 * 2			; 8 lines high per glyph.
		bne	.line_loop

		plx				; Restore VDC/SGX offset.

		; Upload glyph to VRAM.

.copy_tile:	cly
.plane01_loop:	lda	tmp_shadow_buf, y	; Write bitplane 0 data.
		sta	VDC_DL, x
		iny
		lda	tmp_shadow_buf, y	; Write bitplane 1 data.
		sta	VDC_DH, x
		iny
		cpy	#16
		bne	.plane01_loop

		ldy	#8			; A tile is 8 pixels high.
		lda	<_al			; Write bitplane 2 data.
		sta	VDC_DL, x
		lda	<_ah			; Write bitplane 3 data.
.plane23_loop:	sta	VDC_DH, x
		dey
		bne	.plane23_loop

.next_tile:	dec	<_bl			; Upload next glyph.
		bne	.tile_loop

.exit:		pla				; Restore MPR3.
		tam3

		leave				; All done, phew!

		.endp
		.endprocgroup



; ***************************************************************************
; ***************************************************************************
;
; dropfnt8x16_sgx - Upload an 8x16 drop-shadowed font to the SGX VDC.
; dropfnt8x16_vdc - Upload an 8x16 drop-shadowed font to the PCE VDC.
;
; Args: _bp, Y = _farptr to font data (maps to MPR3 & MPR4).
; Args: _di = ptr to output address in VRAM.
; Args: _al = bitplane 2 value for the tile data ($00 or $FF).
; Args: _ah = bitplane 3 value for the tile data ($00 or $FF).
; Args: _bl = # of font glyphs to upload.
;
; N.B. The font is 1bpp, and the drop-shadow is generated by the CPU.
;
; 12 = background
; 13 = shadow
; 14 = font
;
; 0 = trans
; 1 = shadow
; 2 = font

		.procgroup			; Keep this code together!

	.if	SUPPORT_SGX

dropfnt8x16_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$F0			; Turn "clx" into a "beq".

		.endp
	.endif

dropfnt8x16_vdc	.proc
		clx				; Offset to PCE VDC.

		tma3				; Preserve MPR3.
		pha

		jsr	set_bp_to_mpr3		; Map memory block to MPR3.
		jsr	set_di_to_mawr		; Map _di to VRAM.

		; Generate shadowed glyph.

.tile_loop:	phx				; Preserve VDC/SGX offset.

		clx				; Create a drop-shadowed version
		stz	tmp_shadow_buf, x	; of the glyph.

	.if	FNT_SHADOW_LHS
.line_loop:	lda	[_bp]			; Drop-shadow on the LHS.
		sta	tmp_normal_buf, x	; Font data is RHS justified.
		asl	a
	.else
.line_loop:	lda	[_bp]			; Drop-shadow on the RHS.
		sta	tmp_normal_buf, x	; Font data is LHS justified.
		lsr	a
	.endif

	.if	0
		ora	[_bp]			; Composite font and shadow
		sta	tmp_shadow_buf + 2, x	; planes (wide shadow).
	.else

		sta	tmp_shadow_buf + 2, x	; Composite font and shadow
		ora	[_bp]			; planes (normal shadow).
	.endif

		ora	tmp_shadow_buf, x
		eor	tmp_normal_buf, x
		sta	tmp_shadow_buf, x

		inc	<_bp			; Increment ptr to font.
		bne	.next_line
		jsr	inc.h_bp_mpr3
.next_line:	inx
		inx
		cpx	#16 * 2			; 16 lines high per glyph.
		bne	.line_loop

		plx				; Restore VDC/SGX offset.

		; Upload glyph to VRAM.

		cly
		bsr	.plane01_loop
		bsr	.fill_plane23

		ldy	#16
		bsr	.plane01_loop
		bsr	.fill_plane23

		dec	<_bl			; Upload next glyph.
		bne	.tile_loop

.exit:		pla				; Restore MPR3.
		tam3

		leave				; All done, phew!

.plane01_loop:	lda	tmp_shadow_buf, y	; Write bitplane 0 data.
		sta	VDC_DL, x
		iny
		lda	tmp_shadow_buf, y	; Write bitplane 1 data.
		sta	VDC_DH, x
		iny
		tya
		and	#$0F
		bne	.plane01_loop
		rts

.fill_plane23:	ldy	#8			; A tile is 8 pixels high.
		lda	<_al			; Write bitplane 2 data.
		sta	VDC_DL, x
		lda	<_ah			; Write bitplane 3 data.
.plane23_loop:	sta	VDC_DH, x
		dey
		bne	.plane23_loop
		rts

		.endp
		.endprocgroup



; ***************************************************************************
; ***************************************************************************
;
; dropfntbox_sgx - Upload an 8x8 drop-shadowed font to the SGX VDC.
; dropfntbox_vdc - Upload an 8x8 drop-shadowed font to the PCE VDC.
;
; The font data is 1bpp, and the drop-shadow is generated by the CPU.
;
; This version of the code uses an arrary of 1-bit-per-tile flags that is
; located just before the font itself to select which colors each tile is
; rendered in.
;
; The array of flags is little-endian, i.e. the 1st flag is bit 0 of byte 0.
;
; Args: _bp, Y = _farptr to font data (maps to MPR3 & MPR4).
; Args: _di = ptr to output address in VRAM.
; Args: _al = bitplane 2 value for the tile data ($00 or $FF).
; Args: _ah = bitplane 3 value for the tile data ($00 or $FF).
; Args: _bl = # of font glyphs to upload.
;
; When _al == $00 $FF $00 $FF
; When _ah == $00 $00 $FF $FF
;
; If the flag bit for the tile is 0 ...
;
; BKG pixels    0   4   8  12
; Shadow pixels 1   5   9  13
; Font pixels   2   6  10  14
;
; If the flag bit for the tile is 1 ...
;
; BKG pixels    4   0  12   8
; Shadow pixels 5   1  13   9
; Font pixels   6   2  14  10
;

		.procgroup			; Keep this code together!

	.if	SUPPORT_SGX
dropfntbox_sgx	.proc

		ldx	#SGX_VDC_OFFSET		; Offset to SGX VDC.
		db	$F0			; Turn "clx" into a "beq".

		.endp
	.endif

dropfntbox_vdc	.proc

		clx				; Offset to PCE VDC.

		tma3				; Preserve MPR3.
		pha
		tma4				; Preserve MPR4.
		pha

		jsr	set_bp_to_mpr34		; Map font data to MPR3 & MPR4.
		jsr	set_di_to_mawr		; Map _di to VRAM.

		lda.l	<_bp			; Set _di to point to the flag
		sta.l	<_di			; data at the beginning of the
		lda.h	<_bp			; font data.
		sta.h	<_di
		stz	<_temp			; Initialize flag buffer.

		ldy	#256 / 8		; Max bytes to skip.

		lda	<_bl			; 256 tiles in font?
		beq	.skip_flags
		clc				; Round up to next byte.
		adc	#7
		bcs	.skip_flags

		lsr	a			; Calculate #bytes of flags.
		lsr	a
		lsr	a
		tay

.skip_flags:	tya				; Move font pointer passed the
		clc				; flag data.
		adc.l	<_bp
		sta.l	<_bp
		bcc	.tile_loop
		inc.h	<_bp

		; Generate shadowed glyph.

.tile_loop:	phx				; Preserve VDC/SGX offset.

		clc
		ror	<_temp
		bne	.tile_type

		lda	[_di]
		sec
		ror	a
		sta	<_temp
		inc.l	<_di
		bne	.tile_type
		inc.h	<_di

.tile_type:	clv				; Clr V flag for normal tiles.
		bcc	.make_tile
		bit	#$40			; Set V flag for box tiles.

.make_tile:	clx				; Create a drop-shadowed version
		stz	tmp_shadow_buf, x	; of the glyph.

	.if	FNT_SHADOW_LHS
.line_loop:	lda	[_bp]			; Drop-shadow on the LHS.
		sta	tmp_normal_buf, x	; Font data is RHS justified.
		asl	a
	.else
.line_loop:	lda	[_bp]			; Drop-shadow on the RHS.
		sta	tmp_normal_buf, x	; Font data is LHS justified.
		lsr	a
	.endif

		sta	tmp_shadow_buf + 2, x	; Composite font and shadow
		ora	[_bp]			; planes (with narrow shadow).
		bvc	.is_narrow
		sta	tmp_shadow_buf + 2, x	; Wide shadow for box tiles.

.is_narrow:	ora	tmp_shadow_buf, x
		eor	tmp_normal_buf, x
		sta	tmp_shadow_buf, x

		inc.l	<_bp			; Increment ptr to font.
		bne	.next_line
		inc.h	<_bp
.next_line:	inx
		inx
		cpx	#8 * 2			; 8 lines high per glyph.
		bne	.line_loop

		plx				; Restore VDC/SGX offset.

		; Upload glyph to VRAM.

.copy_tile:	cly
.plane01_loop:	lda	tmp_shadow_buf, y	; Write bitplane 0 data.
		sta	VDC_DL, x
		iny
		lda	tmp_shadow_buf, y	; Write bitplane 1 data.
		sta	VDC_DH, x
		iny
		cpy	#16
		bne	.plane01_loop

		ldy	#8			; A tile is 8 pixels high.
		lda	<_al			; Write bitplane 2 data.
		bvc	.plane2
		eor	#$FF			; Flip plane 2 for box tiles.
.plane2:	sta	VDC_DL, x
		lda	<_ah			; Write bitplane 3 data.
.plane23_loop:	sta	VDC_DH, x
		dey
		bne	.plane23_loop

.next_tile:	dec	<_bl			; Upload next glyph.
		bne	.tile_loop

.exit:		pla				; Restore MPR4.
		tam4
		pla				; Restore MPR3.
		tam3

		leave				; All done, phew!

		.endp
		.endprocgroup
