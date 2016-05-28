.include "m2560def.inc"

;MACROS
.macro swp
	mov r15, @1
	mov @1, @0
	mov @0, r15
.endmacro 

.macro do_lcd_command
	mov r15, temp
	ldi temp, @0
	rcall lcd_command
	rcall lcd_wait
	mov temp, r15
.endmacro

.macro do_lcd_data
	swp temp, @0
	rcall lcd_data
	rcall lcd_wait
	swp temp, @0
.endmacro

.macro do_lcd_datai
	mov r15, temp
	ldi temp, @0
	rcall lcd_data
	rcall lcd_wait
	mov temp, r15
.endmacro

.macro bin_to_dec_w
	ldi temp2, low(@0)
	ldi temp3, high(@0)
	rcall bin_to_dec_wf
.endmacro

.macro loadmem
	lds wl, @0
	lds wh, @0 + 1;
.endmacro 

.macro storemem
	sts @0, wl
	sts @0 + 1, wh;
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
.def temp4 = r21
.def wl = r24
.def wh = r25
.def state = r18
.def at = r19
.def temp3 = r20

;CONSTANTS
.set t=80
.set notstarted=0
.set inPot=2
.set inCountdown=1
.set infind=3
.set inenter=4
.set won=5
.set lost=6

.dseg
;VARIABLES
bounce0:	.byte 1;
bounce1:	.byte 1;
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

;MAIN
RESET:
	;INIT

	;initialise variables
	ldists bounce0, 0
	ldists bounce1, 0
	ldi state, 3;
	clr at;
	clr wl;
	clr wh;
	clr temp;
	clr temp2;

	;Lights
	ser temp
	out DDRC, temp
	clr temp
	out PORTC,temp

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

	do_lcd_datai '2'
	do_lcd_datai '1'
	do_lcd_datai '2'
	do_lcd_datai '1'
	do_lcd_command 0b00010100 ; increment to the right
	do_lcd_datai '1'
	do_lcd_datai '6'
	do_lcd_datai 's'
	do_lcd_datai '1'

	do_lcd_command 0b11000000

	do_lcd_datai 'S'
	do_lcd_datai 'a'
	do_lcd_datai 'f'
	do_lcd_datai 'e'
	do_lcd_command 0b00010100 ; increment to the right

	do_lcd_datai 'C'
	do_lcd_datai 'r'
	do_lcd_datai 'a'
	do_lcd_datai 'c'
	do_lcd_datai 'k'
	do_lcd_datai 'e'
	do_lcd_datai 'r'

	sei;

	notYetStarted:
		cpi at, incountdown
		brne notYetStarted
	
	;START GAME HERE
	rcall startingcountdown;

	cpi state, 0;
	breq end;
		rcall pot;
		rcall find;
		dec state;
	end:

	rcall enter;
	rjmp win;

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
	cpi at, notstarted
	brne generateRngSeed
		adiw wh:wl, 63
		adiw wh:wl, 63
		adiw wh:wl, 63
		adiw wh:wl, 63
		sbiw wh:wl, 1
	generateRngSeed:

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
	rjmp RESET;
	ret

pb1pressed:
	push temp
	cpi at, notStarted
	brne startGame
		inc at
		storemem seed
	startGame:
	cpi at, won
	brlo restartgame
		rjmp RESET;
	restartGame:
	pop temp
	ret

;GAME STATES
win:
	ldi at, won
	rjmp win

lose:
	ldi at, lost
	rjmp lose

startingcountdown:
	ret

find:
	ldi at, infind
	ret

pot:
	ldi at, inpot
	ret

enter:
	ldi at, inenter
	ret

displayw:
	push temp
	push temp2
	push temp3
	push wh
	push wl

	clr temp;
	do_lcd_command 0b00000001 ; clear display
	bin_to_dec_w 10000;
	bin_to_dec_w 1000;
	bin_to_dec_w 100;
	bin_to_dec_w 10;
	bin_to_dec_w 1;
	cpi temp, 0;
	brne dontprintzerot
		do_lcd_datai '0'
	dontprintzerot:

	pop wl
	pop wh
	pop temp3
	pop temp2
	pop temp
	ret;

bin_to_dec_wf:
	push temp4
	ldi temp4, '0'
	bintodecwloop:
		cp wl, temp2
		cpc wh, temp3
		brlo endbintodecwloop
		
		sub wl, temp2
		sbc wh, temp3
		inc temp4;
		ser temp;
		rjmp bintodecwloop;
	endbintodecwloop:
	cpi temp, 0
	breq dontprintbtdw;
		do_lcd_data temp4
	dontprintbtdw:
	pop temp4
	ret

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
