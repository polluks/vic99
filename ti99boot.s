; TI-99/4A Boot Screen for VIC-20 (3.5K unexpanded)
; cc65 assembler - VIA stable raster, two screens, beep
;
; Based on Marko Makela's stable raster technique using
; auxiliary VIA timer for cycle-exact synchronization.
; See: https://www.antimon.org/dl/c64/code/stable.txt
;
; Build:
;   ca65 -t vic20 -o ti99boot.o ti99boot.s
;   ld65 -t vic20 -o vic99.prg ti99boot.o

SCREEN  = $1E00
COLS    = 22

; VIC hardware
VSCR    = $900F       ; background/border color
RAST    = $9004       ; raster counter (upper 8 bits, changes per 2 lines)

; VIA 1 ($9110-$911F) - reference timer
VIA1_T1L  = $9114     ; Timer 1 counter low (read)
VIA1_T1CH = $9115     ; Timer 1 counter high (write starts timer)
VIA1_L2   = $9116     ; Timer 1 latch low
VIA1_H2   = $9117     ; Timer 1 latch high
VIA1_ACR  = $911B     ; Auxiliary Control Register
VIA1_IER  = $911E     ; Interrupt Enable Register
VIA1_IFR  = $911D     ; Interrupt Flag Register

; VIA 2 ($9120-$912F) - IRQ timer
VIA2_T1L  = $9124     ; Timer 1 counter low
VIA2_T1CH = $9125     ; Timer 1 counter high (write starts timer)
VIA2_L2   = $9126     ; Timer 1 latch low
VIA2_H2   = $9127     ; Timer 1 latch high
VIA2_ACR  = $912B     ; Auxiliary Control Register
VIA2_IER  = $912E     ; Interrupt Enable Register
VIA2_IFR  = $912D     ; Interrupt Flag Register
VIA2_PB   = $9120     ; Port B (keyboard columns)
VIA2_PA   = $9121     ; Port A (keyboard rows)
VIA2_DDRB = $9122     ; Data Direction Register B
VIA2_DDRA = $9123     ; Data Direction Register A

; IRQ vector
IRQV    = $0314
KERNAL_IRQ = $EABF

; Timer value: LINES * CYCLES_PER_LINE - 2
; PAL 6561-101: 312 lines * 71 cycles/line = 22152 - 2 = 22150
LINES        = 312
CYCLES_LINE  = 71
TIMER_VAL    = LINES * CYCLES_LINE - 2

; Screen codes
SC_A    = $01
SC_B    = $02
SC_C    = $03
SC_D    = $04
SC_E    = $05
SC_G    = $07
SC_H    = $08
SC_I    = $09
SC_K    = $0B
SC_M    = $0D
SC_N    = $0E
SC_O    = $0F
SC_P    = $10
SC_R    = $12
SC_S    = $13
SC_T    = $14
SC_U    = $15
SC_X    = $18
SC_Y    = $19
SC_SP   = $20
SC_1    = $31
SC_4    = $34
SC_7    = $37
SC_9    = $39
SC_DASH = $2D
SC_DOT  = $2E
SC_FSLH = $2F
SC_GT   = $3E
SC_RP   = $29
SC_CURS = $1C

; VIC colors
C_BLUE   = $06
C_LBLUE  = $0D
C_CYAN   = $03
C_GREEN  = $05
C_LGREEN = $0C
C_YELLOW = $07
C_ORANGE = $08
C_RED    = $02
C_LRED   = $09
C_PURPLE = $04

STRIPE_BASE   = 50
STRIPE_HEIGHT = 8
NUM_STRIPES   = 25

; Zero page temp
m = $FB

; Stripe color table
stripe_colors:
        .byte C_BLUE,C_BLUE
        .byte C_LBLUE,C_LBLUE
        .byte C_CYAN,C_CYAN
        .byte C_LGREEN,C_LGREEN
        .byte C_GREEN,C_GREEN
        .byte C_YELLOW,C_YELLOW
        .byte C_ORANGE,C_ORANGE
        .byte C_RED,C_RED
        .byte C_LRED,C_LRED
        .byte C_PURPLE,C_PURPLE
        .byte C_LBLUE
        .byte C_CYAN
        .byte C_GREEN
        .byte C_YELLOW
        .byte C_ORANGE

.exportzp __LOADADDR__: absolute = 1
.exportzp __EXEHDR__: absolute = 1

.segment "LOADADDR"
        .word $1001

.segment "EXEHDR"
        ; BASIC stub: 10 SYS 4109
        .word @next
        .word 10
        .byte $9e
        .byte "4109"
        .byte 0
@next:
        .word 0

.segment "STARTUP"

;----------------------------------------------
; Entry point
;----------------------------------------------
start:
        sei
        lda #$7f
        sta VIA2_IER
        sta VIA2_IFR
        sta VIA1_IER             ; disable NMIs (Restore key)

        ; Set background color
        lda #$0A
        sta VSCR

        ; Select TI-99/4A charset at $1C00
        ; Copy font data (1K) to $1C00
        ldx #$00
@copy:  lda font_data,x
        sta $1C00,x
        lda font_data+$100,x
        sta $1D00,x
        lda font_data+$200,x
        sta $1E00,x
        lda font_data+$300,x
        sta $1F00,x
        inx
        bne @copy

        ; $9005: bits 7-4 = screen ($1E00), bits 3-0 = charset ($1C00)
        lda #$FF
        sta $9005

        ; Clear screen
        ldx #$00
        lda #SC_SP
@clr:   sta SCREEN,x
        sta SCREEN+$100,x
        inx
        bne @clr

        ; Draw screen 1
        jsr draw_screen1

        ; Synchronize with screen
        jsr sync

        ; Set up VIA timers for stable raster
        lda #$40
        sta VIA1_ACR              ; Timer 1 free run
        sta VIA2_ACR

        lda #<TIMER_VAL
        ldx #>TIMER_VAL
        sta VIA1_L2
        sta VIA2_L2

        ; Delay to position correctly (article: ~77 cycles for PAL)
        ldy #7
        dey
        bne *-1
        nop
        nop

        stx VIA2_T1CH             ; start IRQ timer
        ldy #10
        dey
        bne *-1
        stx VIA1_T1CH             ; start reference timer

        ; Install IRQ handler
        lda #<irq
        sta IRQV
        lda #>irq
        sta IRQV+1

        ; Enable Timer 1 interrupt on VIA2
        lda #$c0
        sta VIA2_IER

        cli

        ; Beep
        jsr beep

        ; Wait for keypress
        lda #$ff
        sta VIA2_DDRB        ; columns = output
        lda #$00
        sta VIA2_DDRA        ; rows = input
@wait:  lda #$00
        sta VIA2_PB          ; select all columns
        lda VIA2_PA          ; read rows
        cmp #$ff             ; no key pressed?
        beq @wait            ; keep waiting

        ; Disable raster effect
        sei
        lda #$00
        sta VIA2_IER
        lda #<KERNAL_IRQ
        sta IRQV
        lda #>KERNAL_IRQ
        sta IRQV+1
        cli

        ; Set default color
        lda #$01
        sta VSCR

        ; Draw screen 2
        jsr draw_screen2

        ; Beep
        jsr beep

        ; Brief delay
        ldx #50
@wait1: lda #$fa
@wait2: cmp RAST
        bne @wait2
        dex
        bne @wait1

        ; Draw screen 3
        jsr draw_screen3

        ; Beep
        jsr beep

@halt:  jmp @halt

;----------------------------------------------
; Synchronize with screen (article technique)
;----------------------------------------------
sync:
        ldx #28
@0:     cpx RAST
        bne @0
        ldy #9
        bit $24
@1:     ldx RAST
        txa
        bit $24
        ldx #24
@2:     dex
        bne @2
        cmp RAST
        bcs @skip
        dey
        bne @1
@skip:  rts

;----------------------------------------------
; Stable raster IRQ handler
;----------------------------------------------
irq:
        ; ~38-45 cycles of IRQ overhead before we get here
        lda VIA1_T1L              ; read reference timer

        ; Delay to reach exact stable position (article technique)
        cmp #8
        bcc :+
        pha
        pla
        and #$07
:       cmp #4
        bcc :+
        bit $24
        and #$03
:       cmp #2
        bcs :+
        bcs :+
        lsr
:       ; Now exactly 82 cycles from IRQ start
        ; Change border/background color per stripe

        ldx m                     ; stripe index
        lda stripe_colors,x
        sta VSCR
        inx
        cpx #NUM_STRIPES
        bne :+
        ldx #0
:       stx m

        jmp KERNAL_IRQ

;----------------------------------------------
; Beep: VIC chip tone via voice 1
;----------------------------------------------
beep:
        lda #$22          ; ~1kHz (PAL: 1108878/(32*35))
        sta $900A         ; voice 1 frequency
        lda #$0f          ; max volume
        sta $900E
        ldy #100          ; ~200ms delay
@outer: ldx #0
@inner: dex
        bne @inner
        dey
        bne @outer
        lda #$00
        sta $900A         ; silence
        rts

;----------------------------------------------
; Draw screen 1: TI-99/4A title
;----------------------------------------------
draw_screen1:
        ; "TI-99/4A" centered, col 7, row 0
        ldy #7
        lda #SC_T
        sta SCREEN+0*COLS,y
        iny
        lda #SC_I
        sta SCREEN+0*COLS,y
        iny
        lda #SC_DASH
        sta SCREEN+0*COLS,y
        iny
        lda #SC_9
        sta SCREEN+0*COLS,y
        iny
        lda #SC_9
        sta SCREEN+0*COLS,y
        iny
        lda #SC_FSLH
        sta SCREEN+0*COLS,y
        iny
        lda #SC_4
        sta SCREEN+0*COLS,y
        iny
        lda #SC_A
        sta SCREEN+0*COLS,y

        ; "COPYRIGHT 1979 TEX" row 2, col 2
        ldy #2
        lda #SC_C
        sta SCREEN+2*COLS,y
        iny
        lda #SC_O
        sta SCREEN+2*COLS,y
        iny
        lda #SC_P
        sta SCREEN+2*COLS,y
        iny
        lda #SC_Y
        sta SCREEN+2*COLS,y
        iny
        lda #SC_R
        sta SCREEN+2*COLS,y
        iny
        lda #SC_I
        sta SCREEN+2*COLS,y
        iny
        lda #SC_G
        sta SCREEN+2*COLS,y
        iny
        lda #SC_H
        sta SCREEN+2*COLS,y
        iny
        lda #SC_T
        sta SCREEN+2*COLS,y
        iny
        lda #SC_SP
        sta SCREEN+2*COLS,y
        iny
        lda #SC_1
        sta SCREEN+2*COLS,y
        iny
        lda #SC_9
        sta SCREEN+2*COLS,y
        iny
        lda #SC_7
        sta SCREEN+2*COLS,y
        iny
        lda #SC_9
        sta SCREEN+2*COLS,y
        iny
        lda #SC_SP
        sta SCREEN+2*COLS,y
        iny
        lda #SC_T
        sta SCREEN+2*COLS,y
        iny
        lda #SC_E
        sta SCREEN+2*COLS,y
        iny
        lda #SC_X
        sta SCREEN+2*COLS,y

        ; "AS INSTRUMENTS" row 3, col 4
        ldy #4
        lda #SC_A
        sta SCREEN+3*COLS,y
        iny
        lda #SC_S
        sta SCREEN+3*COLS,y
        iny
        lda #SC_SP
        sta SCREEN+3*COLS,y
        iny
        lda #SC_I
        sta SCREEN+3*COLS,y
        iny
        lda #SC_N
        sta SCREEN+3*COLS,y
        iny
        lda #SC_S
        sta SCREEN+3*COLS,y
        iny
        lda #SC_T
        sta SCREEN+3*COLS,y
        iny
        lda #SC_R
        sta SCREEN+3*COLS,y
        iny
        lda #SC_U
        sta SCREEN+3*COLS,y
        iny
        lda #SC_M
        sta SCREEN+3*COLS,y
        iny
        lda #SC_E
        sta SCREEN+3*COLS,y
        iny
        lda #SC_N
        sta SCREEN+3*COLS,y
        iny
        lda #SC_T
        sta SCREEN+3*COLS,y
        iny
        lda #SC_S
        sta SCREEN+3*COLS,y

        ; "READY." row 5
        ldy #0
        lda #SC_R
        sta SCREEN+5*COLS,y
        iny
        lda #SC_E
        sta SCREEN+5*COLS,y
        iny
        lda #SC_A
        sta SCREEN+5*COLS,y
        iny
        lda #SC_D
        sta SCREEN+5*COLS,y
        iny
        lda #SC_Y
        sta SCREEN+5*COLS,y
        iny
        lda #SC_DOT
        sta SCREEN+5*COLS,y

        ; "PRESS ANY KEY TO BEGIN" row 7
        ldy #0
        ldx #0
@press: lda press_text,x
        sta SCREEN+7*COLS,y
        iny
        inx
        cpx #(press_end - press_text)
        bne @press
        rts

press_text:
        .byte SC_P,SC_R,SC_E,SC_S,SC_S,SC_SP
        .byte SC_A,SC_N,SC_Y,SC_SP
        .byte SC_K,SC_E,SC_Y,SC_SP
        .byte SC_T,SC_O,SC_SP
        .byte SC_B,SC_E,SC_G,SC_I,SC_N
press_end:

;----------------------------------------------
; Draw screen 2: ROM menu
;----------------------------------------------
draw_screen2:
        ldx #$00
        lda #SC_SP
@clr:   sta SCREEN,x
        sta SCREEN+$100,x
        inx
        bne @clr

        ; "TI-99/4A" centered, col 7, row 0
        ldy #7
        lda #SC_T
        sta SCREEN+0*COLS,y
        iny
        lda #SC_I
        sta SCREEN+0*COLS,y
        iny
        lda #SC_DASH
        sta SCREEN+0*COLS,y
        iny
        lda #SC_9
        sta SCREEN+0*COLS,y
        iny
        lda #SC_9
        sta SCREEN+0*COLS,y
        iny
        lda #SC_FSLH
        sta SCREEN+0*COLS,y
        iny
        lda #SC_4
        sta SCREEN+0*COLS,y
        iny
        lda #SC_A
        sta SCREEN+0*COLS,y

        ; "1) TI BASIC" row 2
        ldy #0
        lda #SC_1
        sta SCREEN+2*COLS,y
        iny
        lda #SC_RP
        sta SCREEN+2*COLS,y
        iny
        lda #SC_SP
        sta SCREEN+2*COLS,y
        iny
        lda #SC_T
        sta SCREEN+2*COLS,y
        iny
        lda #SC_I
        sta SCREEN+2*COLS,y
        iny
        lda #SC_SP
        sta SCREEN+2*COLS,y
        iny
        lda #SC_B
        sta SCREEN+2*COLS,y
        iny
        lda #SC_A
        sta SCREEN+2*COLS,y
        iny
        lda #SC_S
        sta SCREEN+2*COLS,y
        iny
        lda #SC_I
        sta SCREEN+2*COLS,y
        iny
        lda #SC_C
        sta SCREEN+2*COLS,y

        ; ">" prompt row 7
        lda #SC_GT
        sta SCREEN+7*COLS+0
        rts

;----------------------------------------------
; Draw screen 3: READY only + cursor
;----------------------------------------------
draw_screen3:
        ldx #$00
        lda #SC_SP
@clr:   sta SCREEN,x
        sta SCREEN+$100,x
        inx
        bne @clr

        ; "READY." row 5
        ldy #0
        lda #SC_R
        sta SCREEN+5*COLS,y
        iny
        lda #SC_E
        sta SCREEN+5*COLS,y
        iny
        lda #SC_A
        sta SCREEN+5*COLS,y
        iny
        lda #SC_D
        sta SCREEN+5*COLS,y
        iny
        lda #SC_Y
        sta SCREEN+5*COLS,y
        iny
        lda #SC_DOT
        sta SCREEN+5*COLS,y

        ; ">_" prompt row 7 with cursor
        lda #SC_GT
        sta SCREEN+7*COLS+0
        lda #SC_CURS
        sta SCREEN+7*COLS+1
        rts

;----------------------------------------------
; TI-99/4A character set (copied to $1C00 at startup)
;----------------------------------------------
font_data:
        .incbin "ti99font.bin"
