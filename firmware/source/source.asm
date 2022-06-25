; -------------------------------------
;  PS/2 Mouse to MSX Mouse Converter
; -------------------------------------
;
;  Author: Fernando Camussi (25-May-2020)
;  Based on "PS/2 Mouse to Amiga Mouse Converter" by Nevenko Baričević and
;  modified by sundance

;  This program is free software: you can redistribute it and/or modify
;  it under the terms of the GNU General Public License as published by
;  the Free Software Foundation, either version 3 of the License, or
;  (at your option) any later version.

;  This program is distributed in the hope that it will be useful,
;  but WITHOUT ANY WARRANTY; without even the implied warranty of
;  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;  GNU General Public License for more details.

;  You should have received a copy of the GNU General Public License
;  along with this program.  If not, see <http://www.gnu.org/licenses/>.


; ---------- includes -----------
    list p=16F84A
    include p16f84a.inc
; ----------- config ------------
    __config _RC_OSC  & _PWRTE_ON &  _WDT_OFF  & _CP_OFF
; -------------------------------


; ---------- registers definition -----------

byte    equ     0x0c        ; byte to receive or send
parity  equ     0x0d        ; parity bit is held here
parcnt  equ     0x0e        ; counter for calculating parity
roller  equ     0x0f        ; help for 8 data bits to byte conversion
pack1   equ     0x10        ; 1st byte of mouse data packet
pack2   equ     0x11        ; 2nd byte of mouse data packet
pack3   equ     0x12        ; 3rd byte of mouse data packet
delcnt  equ     0x13        ; delay counter
nibble  equ     0x14        ; nibble to be sent to MSX


; --------- main routine -----------

    org     0x0

main:
; set port direction
    bsf     STATUS,RP0      ; page 1
    movlw   0xFB            ; OUT ON RA2 FOR ERROR LED
    movwf   TRISA           ; port A, bit 0 and  1 is input
    movlw   b'00000001'     ; INPUT: RB0=strobe
    movwf   TRISB           ; OUTPUT: RB1-RB4,RB6-RB7
    bcf     STATUS,RP0      ; page 0
    clrf    PORTA           ; port A out pins to 0
    clrf    PORTB           ; port B out pins to 0

; set port out level
    clrf    byte
    clrf    parity
    clrf    parcnt
    clrf    roller
    clrf    pack1
    clrf    pack2
    clrf    pack3

check_mouse_init
    call    REC             ; receive byte from mouse
    call    INHIB           ; pull CLK low to inhibit furhter sending
    movf    byte,W
    xorlw   0xaa            ; if it's $AA mouse self test passed
    btfss   STATUS,Z
    goto    check_mouse_init
; check mouse id =00
    call    REL             ; release CLK (allow mouse to send)
    call    REC             ; receive byte from mouse
    call    INHIB
    movf    byte,W
    xorlw   0x00            ; mouse ID code should be $00
    btfss   STATUS,Z
    goto    check_mouse_init
; receive type of parity ?
    movlw   0xf4            ; "Enable Data Reporting" command to mouse
    movwf   byte
    call    NEWPAR          ; get parity for $F4
    call    REL             ; release CLK (allow mouse to send)
; wait
    call    DEL200            ;wait 200µs
; receive ack = fa
    call    SEND            ; send command to mouse
    call    REC             ; receive acknowledge ($FA) from mouse)
    call    INHIB
    movf    byte,W
    xorlw   0xfa
    btfss   STATUS,Z
    goto    check_mouse_init

start
; main loop
CHK:
; lecture trame de 3 octets
    call    REL
    call    REC             ; receive byte1 from mouse packet
    call    INHIB
    movf    byte,W
    movwf   pack1
    call    REL
    call    REC             ; receive byte2 from mouse packet
    call    INHIB
    movf    byte,W
    movwf   pack2
    call    REL
    call    REC             ; receive byte3 from mouse packet
    call    INHIB
    movf    byte,W
    movwf   pack3
    call    send_to_msx     ; send mouse data to msx
    goto    CHK             ; receive another packet

; --------------------------------------------------------

DEL200:
    movlw   .22
    movwf   delcnt
DEL2:
    decfsz  delcnt,f
    goto    DEL2
DEL10:
    nop                     ; delay 10us
    return

; --------- byte receiving subroutine -------------

REC:
    btfsc   PORTA,0         ; wait clock (start bit)
    goto    REC
RL1:
    btfss   PORTA,0
    goto    RL1
    call    RECBIT          ; receive 8 data bits
    call    RECBIT
    call    RECBIT
    call    RECBIT
    call    RECBIT
    call    RECBIT
    call    RECBIT
    call    RECBIT
RL2:
    btfsc   PORTA,0         ; receive parity bit
    goto    RL2
    btfsc   PORTA,1
    goto    RL3
    bcf     parity,0
RL4:
    call    wait_h
RL8:
    btfss   PORTA,0
    goto    RL8
    return
RL3:
    bsf     parity,0
    goto    RL4

; ---------- bit receiving subroutine ------------

RECBIT:
    btfsc   PORTA,0
    goto    RECBIT
    movf    PORTA,W
    movwf   roller
    rrf     roller,f
    rrf     roller,f
    rrf     byte,f
RL5:
    btfss   PORTA,0
    goto    RL5
    return

; ---------- subroutines -----------------

INHIB:
    call    CLKLO           ; inhibit mouse sending (CLK low)
    call    DEL200
    return
REL:                        ; allow mouse to send data
CLKHI:
    bsf     STATUS,RP0      ; CLK high
    bsf     TRISA,0
    bcf     STATUS,RP0
    return
CLKLO:
    bsf     STATUS,RP0      ; CLK low
    bcf     TRISA,0
    bcf     STATUS,RP0
    bcf     PORTA,0
    return

DATLO:
    bsf     STATUS,RP0      ; DATA low
    bcf     TRISA,1
    bcf     STATUS,RP0
    bcf     PORTA,1
    return
DATHI:
    bsf     STATUS,RP0      ; DATA high
    bsf     TRISA,1
    bcf     STATUS,RP0
    return

send_bit
    rrf     byte,f          ; send data bit
    btfsc   STATUS,C
    goto    DHIGH
    call    DATLO
    goto    wait_h
DHIGH:
    call    DATHI
wait_h:
    btfss   PORTA,0
    goto    wait_h
wait_l:
    btfsc   PORTA,0
    goto    wait_l
    return

; ------------- send to mouse --------------

SEND:
    call    INHIB           ; CLK low
    call    DEL10
    call    DATLO           ; DATA low
    call    DEL10
    call    REL             ; CLK high
SL1:
    btfsc   PORTA,0         ; wait for CLK
    goto    SL1
    call    send_bit
    call    send_bit
    call    send_bit
    call    send_bit
    call    send_bit
    call    send_bit
    call    send_bit
    call    send_bit
    call    SNDPAR          ; send parity bit
    call    wait_h
    call    DATHI           ; release bus
    call    wait_h
SL7:
    btfss   PORTA,0
    goto    SL7
SL8:
    btfss   PORTA,1
    goto    SL8
    return

; -------------- subroutines --------------

SNDPAR:
    btfsc   parity,0        ; send parity bit
    goto    DATHI
    goto    DATLO

NEWPAR:                     ; calculate parity bit
    clrf    parcnt
    btfsc   byte,0
    incf    parcnt,f
    btfsc   byte,1
    incf    parcnt,f
    btfsc   byte,2
    incf    parcnt,f
    btfsc   byte,3
    incf    parcnt,f
    btfsc   byte,4
    incf    parcnt,f
    btfsc   byte,5
    incf    parcnt,f
    btfsc   byte,6
    incf    parcnt,f
    btfsc   byte,7
    incf    parcnt,f
    bcf     parity,0
    btfss   parcnt,0
    bsf     parity,0
    return

; --------------- conversion to MSX --------------

send_to_msx:
; set mouse buttons
    btfss   pack1,0         ; left button
    bsf     PORTB,6
    btfsc   pack1,0
    bcf     PORTB,6
    btfss   pack1,1         ; right button
    bsf     PORTB,7
    btfsc   pack1,1
    bcf     PORTB,7
; opposite of x coordinate
    movf    pack2,W
    sublw   .0
    movwf   pack2
; send x and y in 4 nibbles
strobe0
    btfss   PORTB,0
    goto    strobe0         ; wait for 1 in RB0 (strobe)
    movf    pack2,W
    movwf   nibble
    swapf   nibble,F
    call    put_nibble
strobe1
    btfsc   PORTB,0
    goto    strobe1         ; wait for 0 in RB0
    movf    pack2,W
    movwf   nibble
    call    put_nibble
strobe2
    btfss   PORTB,0
    goto    strobe2         ; wait for 1 in RB0
    movf    pack3,W
    movwf   nibble
    swapf   nibble,F
    call    put_nibble
strobe3
    btfsc   PORTB,0
    goto    strobe3         ; wait for 0 in RB0
    movf    pack3,W
    movwf   nibble
    call    put_nibble
; wait and clear direction bits
    call    delay_strb
    movlw   b'11100001'
    andwf   PORTB,F
    return

delay_strb:
    movlw   .12
    movwf   delcnt
delstrb:
    decfsz  delcnt,f
    goto    delstrb
    return

put_nibble:
    btfss   nibble,0        ; bit 0
    bcf     PORTB,1
    btfsc   nibble,0
    bsf     PORTB,1
    btfss   nibble,1        ; bit 1
    bcf     PORTB,2
    btfsc   nibble,1
    bsf     PORTB,2
    btfss   nibble,2        ; bit 2
    bcf     PORTB,3
    btfsc   nibble,2
    bsf     PORTB,3
    btfss   nibble,3        ; bit 3
    bcf     PORTB,4
    btfsc   nibble,3
    bsf     PORTB,4
    return

    end