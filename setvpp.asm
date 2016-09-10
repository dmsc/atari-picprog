;--------------------------------------------------------------------
;  Atari PIC programmer
;  Copyright (C) 2016 Daniel Serpell
;
;  This program is free software; you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 2 of the License, or
;  (at your option) any later version.
;
;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.
;
;  You should have received a copy of the GNU General Public License along
;  with this program.  If not, see <http://www.gnu.org/licenses/>
;
;
; Assemble with MADS
;

        org     $2800

restart:
        ; No interrupts
        sei

        lda #0
        sta $D40E
        sta $D400

        ; Show we are working
        lda #4*16+2
        sta $D01A


        ; Put VPP as output:
        lda     #56
        sta     54018
        lda     #2
        sta     54016
        lda     #60
        sta     54018

        ldx #0
        ldy #2

loopVpp:
        sta $D40A
        sty 54016

        sta $D40A
        stx 54016

        lda $D01F
        and #1
        bne loopVpp

        ; Port as inputs:
        lda     #56
        sta     54018
        lda     #0
        sta     54016
        lda     #60
        sta     54018


        ; END
        lda #0
        sta 54016
        lda #$40
        sta $D40E
        lda #34
        sta $D400
        cli

        rts

