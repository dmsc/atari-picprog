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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; OS and hardware equates
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
count   equ     $82     ; count of words to skip/write
ptr     equ     $86     ; misc pointer
picadr  equ     $88     ; address being programmed in PIC
tmp     equ     $8a     ; temporary
sbuf    equ     $f3     ; buffer to write in showMsg

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        org     $2800

        ; --------------------------------------------------------------
        ;  Main entry point, shows init message and waits for a console
        ;  key press.
        ;
restart:
        showMsg "$9B 'Press START to program PIC,' $9B 'SELECT returns to DOS' $9B $9B"

readConsol:
        lda CONSOL
        lsr
        bcc startPressed
        lsr
        bcs readConsol

        ; Exit to DOS
        jmp ($0A)

startPressed:
        jmp programPIC



        ; --------------------------------------------------------------
        ;  Error reading device ID
        ;

deviceIdError:
        ; Ends programming and shows error
        jsr stopProgramming

        showMsg   "'ERROR invalid device ID.' $9b 'Detected $'"
        showHex16 ioword
        showMsg   "', expected $'"
        showHex16 PS_deviceID

        jmp exitWithAddr

        ; --------------------------------------------------------------
        ;  Main program - programs the PIC!!
        ;
programPIC:

        ; Start programming mode
        jsr enableProgramming

        ; --------------------------------------------------------------
        ; Check if device ID is correct:
        ;

        ; Read the device id (location $06 of configuration area)

        ; LOAD CONFIGURATION
        lda #0
        jsr command
        lda #0
        sta ioword
        sta ioword+1
        jsr write14

        ; Increment 6 times
        lda #6
        jsr incAddressMult

        ; Read value
        jsr readProgramWord

        ; Verify
        lda ioword
        and PS_deviceMask
        cmp PS_deviceID
        bne deviceIdError
        lda ioword+1
        and PS_deviceMask+1
        cmp PS_deviceID+1
        bne deviceIdError

        ; --------------------------------------------------------------
        ; Now proceed to do a bulk erase of the chip
        ;
        ; NOTE: Technically, per datasheet, we should read and store the value
        ;       of any CALIBRATION words, and we should verify that they hold
        ;       the same value after a builk-erase operation.
        ;       We don't need to preserve the values, so we simply read many
        ;       locations and don't store it's values.
        ;
        ; Repeat 6 times, from address $06 to $0A.
        jsr incAddress
        jsr readProgramWord
        jsr incAddress
        jsr readProgramWord
        jsr incAddress
        jsr readProgramWord
        jsr incAddress
        jsr readProgramWord

        ; BULK ERASE
        lda #9
        jsr command

        ; WAIT TERA (max 8ms - 124 lines)
        ldx #62
        jsr delayVddOn

        ; --------------------------------------------------------------
        ; Reset programmer to start a new programming cycle
        ;
        jsr resetProgramming


        ; --------------------------------------------------------------
        ; Start programming script - reads from picdata
        ;
        lda #<PS_scriptStart
        sta ptr
        lda #>PS_scriptStart
        sta ptr+1


readScriptCmd:
        ; See if we are at end:
        lda ptr
        cmp PS_scriptEnd
        lda ptr+1
        sbc PS_scriptEnd+1
        beq okProgramming

        ; Process one command from the script:
        ldy #0
        lda (ptr),y
        beq specialCmd

        ; Write program memory words
        sta count

writeOneWord:
        iny
        sty COLBK
        lda (ptr),y
        sta ioword
        iny
        lda (ptr),y
        sta ioword+1

        jsr programWord
        dec count
        bne writeOneWord

        iny
        ; Increment script pointer and continue
incScriptPtr:
        clc
        tya
        adc ptr
        sta ptr
        bcc readScriptCmd
        inc ptr+1
        bne readScriptCmd
        jmp okProgramming

        ; Process special commands
specialCmd:
        iny
        lda (ptr),y
        beq loadConfigCmd

        ; Increment address by "count"
        jsr incAddressMult
        ldy #2
        bne incScriptPtr

loadConfigCmd:
        ; LOAD CONFIGURATION
        lda #$80
        sta picadr+1
        lda #0
        sta picadr
        jsr command
        lda #0
        sta ioword
        sta ioword+1
        jsr write14
        ldy #2
        bne incScriptPtr

        ; Terminates OK the programming
okProgramming:
        jsr stopProgramming
        showMsg   "'PIC programmed successfully.' $9B"
        jmp restart


exitWithAddr:
        showMsg   "$9B 'Writing address $'"
        showHex16 picadr
        showChar  #$9B
        jmp restart



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows a string to screen
.macro showMsg
        ift :0 > 1
         .error "error, only one argument supported"
        eif
        jsr showMsgJsr
        .by :1
        .by 0
.endm
.proc showMsgJsr
        ; Get message address from stack
        pla
        sta sbuf
        pla
        sta sbuf+1
        bne msgLoopStart ; Assume that the message is never in page 0

msgLoop:
        showChar @

msgLoopStart:
        ; Increment pointer
        inw sbuf
        ; Read character, end if 0
        ldy #0
        lda (sbuf), y
        bne msgLoop

        lda sbuf+1
        pha
        lda sbuf
        pha
        rts
.endp

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows a 16 bit hex number in A:X
showHex16 .proc ( .word xa ) .reg
        pha
        txa
        jsr showHex
        pla

        ; fall through

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows an 8 bit hex number in A
showHex:
        pha
        lsr
        lsr
        lsr
        lsr
        tay
        showChar "hexTab,y"

        pla
        and #15
        tax
        lda hexTab,x

.endp
        ; fall through

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Shows a character to screen, in X
showChar .proc ( .byte x ) .reg
        lda ICPUTB+1
        pha
        lda ICPUTB
        pha
        txa
        ldx #$00
        rts
.endp

hexTab:
        .by "0123456789ABCDEF"


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Delay X lines with VDD on
delayVddOn:
        lda #2    ; 0->CLK  1->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #0    ; 0->CLK  1->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne delayVddOn
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Delay X lines with VDD off
delayVddOff:
        lda #6    ; 0->CLK  0->VDD  1->VPP  0->DATA
        sta WSYNC
        sta PORTA
        lda #4    ; 0->CLK  0->VDD  0->VPP  0->DATA
        sta WSYNC
        sta PORTA
        dex
        bne delayVddOff
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Multiple increment address by "A"
incAddressMult:
        sta count
doIncAd:
        jsr incAddress
        dec count
        bne doIncAd
        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Stop programming mode:
;;;   - enable IRQ, NMI and DMA.
;;;   - set joystick port to input (this drives all outputs HIGH)
;;;
stopProgramming:

        ; turn of VDD
        lda #15   ; 1->CLK  0->VDD  1->VPP  1->DATA
        sta PORTA

        ; Put all 4 lines as input:
        lda #56
        sta PACTL
        lda #0
        sta PORTA
        lda #60
        sta PACTL

        lda #$40
        sta NMIEN
        lda #34
        sta DMACTL
        cli

        rts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Start programming mode:
;;;   - disable IRQ, NMI and DMA.
;;;   - set joystick port (PIA PORTA) to output
;;;   - rises VPP
;;;
enableProgramming:

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
        jsr delayVddOff

        ; Fall through to reset programing

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Reset PIC by toggling VDD on -> off ->on
;;;  This is not in the specs, they do a full VPP off and on again but we
;;;  don't control VPP fast enough to do that.
resetProgramming:

        ; Reset pic address counter
        lda #0
        sta picadr
        sta picadr+1

        ; Power DOWN the PIC
        ; With VPP full on, turn off VDD for 32 cycles
        ldx #32
        jsr delayVddOff

        ; Power UP the PIC
        ; With VPP full on, turn on VDD for 32 cycles
        ldx #32
        jmp delayVddOn

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Writes a program memory location and verifies the value
;;;  See figure 3-16 in DS40001204J (PIC12F6XX/16F6XX Memory Programming Specification).
;;;
;;;  Input: ioword: 16byte value to write
programWord:

        ; Save current word
        lda ioword
        sta tmp
        lda ioword+1
        sta tmp+1

        ; LOAD DATA FOR PROGRAM MEMORY
        lda #2
        jsr command
        lda tmp
        sta ioword
        lda tmp+1
        sta ioword+1
        jsr write14

        ; BEGIN PROGRAMMING
        lda #8
        jsr command

        ; WAIT TPROG1 (3ms - 47 lines)
        ldx #24
        jsr delayVddOn

        ; READ FROM PROGRAM MEMORY
        jsr readProgramWord

        ; DATA CORRECT?
        lda ioword
        cmp tmp
        bne verifyError
        lda ioword+1
        cmp tmp+1
        bne verifyError

        ; INCREMENT ADDRESS and returns
        jmp incAddress

verifyError:
        ; Ends programming and shows error
        jsr stopProgramming

        ; Show byte to write and byte written
        showMsg "'ERROR at memory verify' $9B 'Wrote $'"
        showHex16 tmp
        showMsg "' and read $'"
        showHex16 ioword

        jmp exitWithAddr


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;  Increments memory location
incAddress:

        ; Increment our internar pointer
        inc picadr
        bne noincpa
        inc picadr+1
noincpa:

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


; -------------------------------------------------------------
; The program script is appended by the script generator
        org     $2c00

programScript:

PS_deviceId:
        .ds     2
PS_deviceMask:
        .ds     2
PS_scriptEnd:
        .ds     2
PS_scriptStart:

;        ICL     "picdata.asm"

