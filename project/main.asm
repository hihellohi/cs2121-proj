.include "m2560def.inc"

;MACROS
.macro do_lcd_command
	ldi temp, @0
	rcall lcd_command
	rcall lcd_wait
.endmacro

.macro do_lcd_data
	ldi temp, @0
	rcall lcd_data
	rcall lcd_wait
.endmacro

.macro loadmem
	lds r23, @0
	lds r24, @0 + 1;
.endmacro 

.macro storemem
	sds @0, r23
	sds @0 + 1,r24;
.endmacro 

.macro ldscpi
	lds temp, @0
	cpi temp, @1
.endmacro

.macro ldists
	ldi temp, @1
	sts @0, temp
.endmacro

.macro ldsinc
	lds temp, @0
	inc temp
	sts @0, temp
.endmacro

;REGISTERS
.def temp = r16
.def temp2 = r17
.def wl = r24
.def wh = r25

;CONSTANTS
.set t=80

.dseg
;VARIABLES
bounce0:	.byte 1;
bounce1:	.byte 1;
rng:		.byte 1;
seed:		.byte 2;

.cseg

;VECTOR TABLE
.org 0
	jmp RESET
.org INT0addr
	jmp EXT_INT0
	jmp EXT_INT1
.org OVF0addr
	jmp timer0

;INTERRUPTS
EXT_INT0:  
	push temp  ; save register  
	in temp, SREG  ; save SREG  
	push temp  
	ldscpi bounce0, 0
	brne pb0isalreadycounting
		ldists bounce0, 1;
	pb0isalreadycounting:
	pop temp  ; restore SREG  
	out SREG, temp  
	pop temp  ; restore register   
	reti 

EXT_INT1:  
	push temp  ; save register  
	in temp, SREG  ; save SREG  
	push temp  
	ldscpi bounce1, 0
	brne pb1isalreadycounting
		ldists bounce1, 1;
	pb1isalreadycounting:
	pop temp  ; restore SREG  
	out SREG, temp  
	pop temp  ; restore register   
	reti 

timer0:
	;timer to debounce pb0 and pb1
	push temp
	in temp, SREG
	push temp
	
	;generate rng
	ldscpi rng, 1;
	brne nomorerng
		adiw r25:r24, 1
	nomorerng:

	;debounce pb0
	ldscpi bounce0, 0
	breq debouncePb1;
		cpi temp, t
		brlo pb0IsStillCounting	
			ldists bounce0, 0
			sbis PIND, 0
			rcall pb0pressed
			rjmp debouncePb1
		pb0IsStillCounting:
			ldsinc bounce0
	
	debouncePb1:
	ldscpi bounce1, 0
	breq timer0epilouge;
		cpi temp, t
		brlo pb1IsStillCounting	
			ldists bounce1, 0
			sbis PIND, 1
			rcall pb1pressed
			rjmp timer0epilouge
		pb1IsStillCounting:
			ldsinc bounce1

	timer0epilouge:
	pop temp
	out SREG, temp
	pop temp
	reti

;FUNCTIONS
pb0pressed:
	ret

pb1pressed:
	ret

;MAIN
RESET:
	;INIT

	ldists rng, 1 ;enable rng

	;stack pointer
	ldi temp, low(RAMEND)
	out SPL, temp
	ldi temp, high(RAMEND)
	out SPH, temp
	
	;push buttons
	ldi temp, (2 << ISC00|2 << ISC10) ; set INT0 as falling-edge 
	sts EICRA, temp ; edge triggered interrupt  
	in temp, EIMSK  ; enable INT0 and INT1 
	ori temp, (1<<INT0|1<<INT1)  
	out EIMSK, temp 
	cbi DDRD,0
	cbi DDRD,1

	;push button debouncer
	clr temp
	out TCCR0A,temp
	ldi temp,2
	out TCCR0B,temp
	ldi temp,1<<TOIE0
	sts TIMSK0,temp 

	;lcd
	ser temp
	out DDRF, temp
	out DDRA, temp
	clr temp
	out PORTF, temp
	out PORTA, temp
	
	do_lcd_command 0b00111000 ; 2x5x7
	rcall sleep_5ms
	do_lcd_command 0b00111000 ; 2x5x7
	rcall sleep_1ms
	do_lcd_command 0b00111000 ; 2x5x7
	do_lcd_command 0b00111000 ; 2x5x7
	do_lcd_command 0b00001000 ; display off?
	do_lcd_command 0b00000001 ; clear display
	do_lcd_command 0b00000110 ; increment, no display shift
	do_lcd_command 0b00001100 ; Cursor on, no bar, no blink

	do_lcd_data '2'
	do_lcd_data '1'
	do_lcd_data '2'
	do_lcd_data '1'
	do_lcd_command 0b00010100 ; increment to the right
	do_lcd_data '1'
	do_lcd_data '6'
	do_lcd_data 's'
	do_lcd_data '1'

	do_lcd_command 0b11000000

	do_lcd_data 'S'
	do_lcd_data 'a'
	do_lcd_data 'f'
	do_lcd_data 'e'
	do_lcd_command 0b00010100 ; increment to the right

	do_lcd_data 'C'
	do_lcd_data 'r'
	do_lcd_data 'a'
	do_lcd_data 'c'
	do_lcd_data 'k'
	do_lcd_data 'e'
	do_lcd_data 'r'
	

halt:
	rjmp halt

;LCD CODE
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.macro lcd_set
	sbi PORTA, @0
.endmacro
.macro lcd_clr
	cbi PORTA, @0
.endmacro

;
; Send a command to the LCD (temp)
;

lcd_command:
	out PORTF, temp
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	ret

lcd_data:
	out PORTF, temp
	lcd_set LCD_RS
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	lcd_clr LCD_RS
	ret

lcd_wait:
	push temp
	clr temp
	out DDRF, temp
	out PORTF, temp
	lcd_set LCD_RW
lcd_wait_loop:
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	in temp, PINF
	lcd_clr LCD_E
	sbrc temp, 7
	rjmp lcd_wait_loop
	lcd_clr LCD_RW
	ser temp
	out DDRF, temp
	pop temp
	ret

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

sleep_1ms:
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
delayloop_1ms:
	sbiw r25:r24, 1
	brne delayloop_1ms
	pop r25
	pop r24
	ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret
