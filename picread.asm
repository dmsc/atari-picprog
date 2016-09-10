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

; OS and hardware equates
SAVMSC  equ     $58

ICCMD   equ     $0342
ICBUFA  equ     $0344
ICPUTB  equ     $0346
ICBUFL  equ     $0348
COLBK   equ     $D01A
CONSOL  equ     $D01F
PORTA   equ     $D300
PACTL   equ     $D302
DMACTL  equ     $D400
WSYNC   equ     $D40A
NMIEN   equ     $D40E
CIOV    equ     $E456

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Program variables

ioword  equ     $80     ; input/output word
scr     equ     $82
count   equ     $84
ptr1    equ     $86
picadr  equ     $88

        org     $2800

restart:

        lda #0
        sta picadr
        sta picadr+1

readMore:
        ; Init screen pointer
        lda SAVMSC
        sta scr
        lda SAVMSC+1
        sta scr+1

        ; No interrupts
        sei

        lda #0
        sta NMIEN
        sta DMACTL

        ; Show we are working
        lda #4*16+2
        sta COLBK


        ; Put all 4 lines as outputs:
        lda #56
        sta PACTL
        lda #15
        sta PORTA
        lda #60
        sta PACTL


        ; Start by lowering all to 0, wait voltages to drop
        lda #4    ; 0->CLK  0->VDD  0->VPP  0->DATA
        sta PORTA
        jsr delayBig
        jsr delayBig
        jsr delayBig
        jsr delayBig

        ; Now, rises VPP for 256 cycles
        ldx #0
loopVpp:
        lda #6    ; 0->CLK  0->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #4    ; 0->CLK  0->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne loopVpp

        ; With VPP full on, turn on VDD for 64 cycles
        ldx #64
loopVdd:
        lda #2    ; 0->CLK  1->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #0    ; 0->CLK  1->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne loopVdd

        ; We should be in programming mode now, try reading data
        lda #<useridMsg
        ldx #>useridMsg
        jsr showMsg

        ; LOAD CONFIGURATION, so we can read configuration space
        lda #0
        jsr command
        lda #0
        sta ioword
        sta ioword+1
        jsr write14

        ; READ FROM PROGRAM MEMORY $2000 to $2003 (User ID locations)
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow

        ; Increment 2 times to go to device ID
        jsr incAddress
        jsr incAddress

        lda #<devidMsg
        ldx #>devidMsg
        jsr showMsg

        ; READ FROM PROGRAM MEMORY $2006 (Device ID location)
        jsr readAndShow


        lda #<configMsg
        ldx #>configMsg
        jsr showMsg

        ; READ FROM PROGRAM MEMORY $2007-$200A (Config and calibration locations)
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow

        ; Shows "program memory from-to" message:
        lda #<progMsg
        ldx #>progMsg
        jsr showMsg

        ; Power DOWN the PIC (to reset the programming mode)
        ; With VPP full on, turn off VDD for 32 cycles
        ldx #32
loopVdd1:
        lda #6    ; 0->CLK  0->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #4    ; 0->CLK  0->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne loopVdd1

        ; Shows starting - ending addresses to read from program memory:
        lda picadr+1
        jsr showHex
        lda picadr
        jsr showHex
        lda #13         ; '-'
        jsr showChar
        clc
        lda picadr
        adc #132
        pha
        lda picadr+1
        adc #0
        jsr showHex
        pla
        jsr showHex

        ; advances to next line
        lda #<plineMsg
        ldx #>plineMsg
        jsr showMsg

        ; Advance the read address to the correct position
        lda picadr
        eor #255
        sta count
        lda picadr+1
        eor #255
        sta count+1

advance:
        inc count
        bne noincAdv
        inc count+1
        beq endAdvance

noincAdv:
        jsr incAddress

        jmp advance

endAdvance:
        lda #19
        sta count

        ; Power UP the PIC (to reset the programming mode)
        ; With VPP full on, turn on VDD for 32 cycles
        ldx #32
loopVdd2:
        lda #2    ; 0->CLK  1->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #0    ; 0->CLK  1->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne loopVdd2

readMem:
        lda picadr+1
        jsr showHex
        lda picadr
        jsr showHex
        lda #26         ; ':'
        jsr showChar

        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow
        jsr readAndShow

        clc
        lda picadr
        adc #7
        sta picadr
        bcc ok1
        inc picadr+1
ok1:

        dec count
        bne readMem

        ; END - turn of VDD
        lda #4    ; 0->CLK  0->VDD  0->VPP  0->DATA
        sta PORTA

        lda #<helpMsg
        ldx #>helpMsg
        jsr showMsg

        lda #$40
        sta NMIEN
        lda #34
        sta DMACTL
        cli

endLoop:
        lda CONSOL
        lsr
        bcc doRestart
        lsr
        bcs endLoop

        jmp readMore

doRestart:
        jmp restart

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows a string to screen
showMsg:
        sta ptr1
        stx ptr1+1
        ldy #0
loopMsg:
        lda (ptr1),y
        cmp #219
        beq noMsg
        sta (scr),y
        iny
        bne loopMsg
noMsg:
        tya
        clc
        adc scr
        sta scr
        bcc ret
        inc scr+1
ret:
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows a character to screen
showChar:
        ldy #0
        sta (scr),y
        inc scr
        bne ret
        inc scr+1
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows an 8 bit hex number
showHex:
        ldy #0
        pha
        lsr
        lsr
        lsr
        lsr
        tax
        lda hexTab,x
        sta (scr),y
        iny
        pla
        and #15
        tax
        lda hexTab,x
        sta (scr),y
        lda scr
        clc
        adc #2
        sta scr
        bcc ret
        inc scr+1
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows an 16 bit hex number in "ioword"
showHex16:
        lda ioword+1
        jsr showHex
        lda ioword
        jmp showHex

hexTab:
        .db 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 33, 34, 35, 36, 37, 38

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Reads a program memory location and shows in the screen
readAndShow:

        ; READ FROM PROGRAM MEMORY
        jsr readProgramWord
        jsr showHex16

        lda #0
        jsr showChar

        ; Fall through to "increment address"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Increments memory location
incAddress:

        ; INCREMENT ADDRESS
        lda #6

        ; Fall through to "send command"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Sends command (in A) to the PIC
command:
        ; Push command, 6 bits, LSB first
        sta ioword
        ldx #6

commandLoop:
        lda #5
        lsr ioword
        rol       ; 1->CLK  1->VDD  1->VPP  C->DATA
        sta WSYNC
        sta PORTA ; 1->CLK  1->VDD  1->VPP  C->DATA

        and #$F5  ; 0->CLK  1->VDD  0->VPP  C->DATA
        sta WSYNC
        sta PORTA

        dex
        bne commandLoop

        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Reads a program memory location
readProgramWord:
        ; READ FROM PROGRAM MEMORY
        lda #4
        jsr command
        ; fall through

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Reads 14 bits from the chip, including a start and stop bit
read14:
        ; Read data, 14 bits, LSB first
        lda #0
        sta ioword
        sta ioword+1

        ; Put DATA as input
        sta WSYNC
        lda #56
        sta PACTL
        lda #14
        sta PORTA
        lda #60
        sta PACTL


        ldx #16
rDataLoop:
        lda #10     ; 1->CLK  1->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA

        lda #0      ; 0->CLK  1->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda PORTA   ; Read DATA to C
        lsr
        ror ioword+1
        ror ioword

        dex
        bne rDataLoop

        ; Put DATA as output
        sta WSYNC
        lda #56
        sta PACTL
        lda #15
        sta PORTA
        lda #60
        sta PACTL

        ; Wait one cycle...
        lda #2    ; 0->CLK  1->VDD  1->VPP 0->DATA
        sta WSYNC
        sta PORTA

        lda ioword+1
        lsr
        and #$3F
        sta ioword+1
        ror ioword

        lda #0    ; 0->CLK  1->VDD  0->VPP 0->DATA
        sta WSYNC
        sta PORTA

        rts

write14:
        ; Write data, 14 bits, LSB first

        ; Always send a "0" start bit
        asl ioword
        rol ioword+1
        sta WSYNC

        ldx #16
wDataLoop:
        lda #5
        lsr ioword+1
        ror ioword
        rol        ; 1->CLK  1->VDD  1->VPP  C->DATA
        sta WSYNC
        sta PORTA  ; 1->CLK  1->VDD  1->VPP  C->DATA

        and #$F5   ; 0->CLK  1->VDD  0->VPP  C->DATA
        sta WSYNC
        sta PORTA

        dex
        bne wDataLoop

        ; Wait one cycle...
        lda #2    ; 0->CLK  1->VDD  1->VPP 0->DATA
        sta WSYNC
        sta PORTA

        lda #0    ; 0->CLK  1->VDD  0->VPP 0->DATA
        sta WSYNC
        sta PORTA

        rts

delayBig:
        ldx #0
delayLoop:
        stx WSYNC
        inx
        bne delayLoop
        rts


useridMsg:      .sb 'User ID words: ', $9b
devidMsg:       .sb '         Device ID: ',$9b
configMsg:      .sb '                    Config/calibr: ',$9b
progMsg:        .sb '     Program memory from-to: ',$9b
plineMsg:       .sb '       ', $9b
helpMsg:        .sb +$80, '  '
                .sb 'SELECT'
                .sb +$80, ' to continue, '
                .sb 'START'
                .sb +$80, ' to restart  ', $9b
