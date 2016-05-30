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

.macro bin_to_dec_t
	ldi temp2, @0
	rcall bin_to_dec_f
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

.macro ldsdec
	lds temp, @0
	dec temp
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
.set t=30
.set notstarted=0
.set inPot=2
.set inCountdown=1
.set infind=3
.set inenter=4
.set won=5
.set lost=6
.set buzzer=0

.dseg
;VARIABLES
count:	.byte 1;
ocount:	.byte 1;
bounce: .byte 1;
fours:	.byte 1;
wadc:	.byte 1;
seed:	.byte 2;
vadc:	.byte 2;
potwin:	.byte 1;

.cseg

;VECTOR TABLE
.org 0
	jmp RESET
.org INT0addr
	jmp EXT_INT0
	jmp EXT_INT1
.org OVF1addr
	jmp timer1
.org OVF0addr
	jmp timer0
.org 0x3A
	jmp adcread
.org OVF4addr
	jmp timer4

;MAIN
RESET:
	;INIT

	;initialise variables
	ldists ocount, 10;
	ldists count, 0;
	ldists bounce, 0;
	ldists fours, 0;
	ldists wadc, 0;
	ldists vadc, 0;
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
	ldi temp, 3
	out DDRG, temp
	cbi PORTG, 0
	cbi PORTG, 1

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

	;random number generator
	clr temp
	out TCCR0A,temp
	ldi temp,3<<CS00
	out TCCR0B,temp
	ldi temp,1<<TOIE0
	sts TIMSK0,temp 

	;beeper
	sbi DDRB,buzzer

	clr temp
	sts TCCR1A,temp
	ldi temp,1<<CS10
	sts TCCR1B,temp
	rcall buzzeroff

	;countdown
	clr temp
	sts TCCR4A,temp
	ldi temp,2<<CS40
	sts TCCR4B,temp
	clr temp
	sts TIMSK4,temp

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

	mainloop:
		cpi state, 0;
		breq end;
			
		rcall pot;
		rcall find;
		dec state;
		rjmp mainloop
	end:
	rcall enter;
	rjmp win;

;INTERRUPTS
adcread:
	sei
	push temp
	in temp, SREG
	push temp
	lds wl, ADCL
	lds wh, ADCH
	ldists wadc, 0
	;rcall displayw
	pop temp
	out SREG, temp
	pop temp
	reti

;BUTTONS
EXT_INT0:
	rjmp RESET

EXT_INT1:
	push temp  ; save register  
 	in temp, SREG  ; save SREG  
 	push temp  
 	ldscpi bounce, 0
 	brne pb1isalreadycounting
 		ldists bounce, 1;
		ldi temp, 1<<TOIE0
		sts TIMSK0, temp
 	pb1isalreadycounting:
 	pop temp  ; restore SREG  
 	out SREG, temp  
 	pop temp  ; restore register   
 	reti 

pb1pressed:
	push temp  
	cpi at, notStarted
	brne startGame
		inc at
	startGame:
	cpi at, won
	brlo restartgame
		rjmp RESET;
	restartGame:
	pop temp  ; restore register
	ret

;TIMERS
losejump:
	clr temp
	sts TIMSK4, temp
	sei
	rjmp lose

timer4:
	push temp
	in temp, SREG
	push temp
	push temp2
	push temp3

	cpi at, inpot;
	brne notinpot_t4
		ldscpi potwin, 0;
		breq timer4notwin
			inc temp;
			sts potwin, temp;
		timer4notwin:
		ldscpi fours, t;
		brne full
			ldists fours, 0
			ldsdec count
			breq losejump
			do_lcd_command 0b11000000 + 11
			rcall displayt
			do_lcd_datai ' '
			rcall buzzeron
			rjmp endnotinpot_t4
		full:
			lds temp2, count
			lds temp3, ocount
			cp temp2, temp3

			breq quarter
				cpi temp, (t >> 2);
				rjmp half;
			quarter:
				cpi temp, (t >> 1);
			half:
			brne checkadc
				rcall buzzeroff
				rjmp endnotinpot_t4
			checkadc:
				andi temp, 3 ;POT FREQUENCY
				cpi temp, 0;
				brne endnotinpot_t4
				ldscpi wadc, 1
				breq endnotinpot_t4
					rcall startAdcRead

	notinpot_t4:
		ldscpi fours, t >> 1;
		brne endnotinpot_t4
			clr temp;
			sts TIMSK4, temp
			rcall buzzeroff

	endnotinpot_t4:
	ldsinc fours

	pop temp3
	pop temp2
	pop temp
	out SREG, temp
	pop temp
	reti

timer1:
	sei
	push temp
	in temp, SREG
	push temp
	in temp, PORTB
	andi temp, 1<<buzzer
	cpi temp, 0
	breq timer1clear
		cbi PORTB, buzzer
		rjmp timer1end
	timer1clear:
		sbi PORTB, buzzer
	timer1end:
	pop temp
	out SREG, temp
	pop temp
	reti

timer0:
	;rngesus
	push temp
	in temp, SREG
	push temp
	push temp2
	clr temp2
	push wl
	push wh

	;generate rng
	cpi at, notstarted
	brne generateRngSeed
		loadmem seed
		subi wl, low(-36277)
		ldi temp, high(-36277)
		sbc wh, temp
		storemem seed
		rjmp generateRngSeedEnd

	generateRngSeed:
		inc temp2			
	generateRngSeedEnd:
	
	;debounce pb1
	ldscpi bounce, 0
 	breq pb0notcounting;
 		cpi temp, 4
 		brlo pb0IsStillCounting	
 			ldists bounce, 0
 			sbis PIND, 1
 			rcall pb1pressed
 			rjmp pb0notcounting
 		pb0IsStillCounting:
 			ldsinc bounce
			rjmp pb0endnotcounting
	pb0notcounting:
		inc temp2
	pb0endnotcounting:

	cpi temp2, 2
	brlo dontdisable
		;disable timer
		clr temp
		sts TIMSK0,temp	
	dontdisable:

	pop wh
	pop wl
	pop temp2
	pop temp
	out SREG, temp
	pop temp
	reti

;GAME STATES
win:
	ldi at, won
	rcall buzzeron
	do_lcd_command 0b00000001
	do_lcd_datai 'G'
	do_lcd_datai 'a'
	do_lcd_datai 'm'
	do_lcd_datai 'e'
	do_lcd_datai ' '
	do_lcd_datai 'c'
	do_lcd_datai 'o'
	do_lcd_datai 'm'
	do_lcd_datai 'p'
	do_lcd_datai 'l'
	do_lcd_datai 'e'
	do_lcd_datai 't'
	do_lcd_datai 'e'
	do_lcd_command 0b11000000
	do_lcd_datai 'Y'
	do_lcd_datai 'o'
	do_lcd_datai 'u'
	do_lcd_datai ' '
	do_lcd_datai 'W'
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai '!'
	rjmp finished

lose:
	ldi at, lost
	rcall buzzeron
	do_lcd_command 0b00000001
	do_lcd_datai 'G'
	do_lcd_datai 'a'
	do_lcd_datai 'm'
	do_lcd_datai 'e'
	do_lcd_datai ' '
	do_lcd_datai 'o'
	do_lcd_datai 'v'
	do_lcd_datai 'e'
	do_lcd_datai 'r'
	do_lcd_command 0b11000000
	do_lcd_datai 'Y'
	do_lcd_datai 'o'
	do_lcd_datai 'u'
	do_lcd_datai ' '
	do_lcd_datai 'L'
	do_lcd_datai 'o'
	do_lcd_datai 's'
	do_lcd_datai 'e'
	do_lcd_datai '!'

finished:
	rcall sleep_245ms
	rcall sleep_750ms
	rcall buzzeroff
halt:
	rjmp halt

startingcountdown:
	push temp
	ldi temp, '4'
	do_lcd_command 0b11000000
	do_lcd_datai 'S'
	do_lcd_datai 't'
	do_lcd_datai 'a'
	do_lcd_datai 'r'
	do_lcd_datai 't'
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai 'g'
	do_lcd_datai ' '
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai ' '
	do_lcd_datai ' '
	do_lcd_datai '.'
	do_lcd_datai '.'
	do_lcd_datai '.'
	countdownLoop:
		dec temp
		do_lcd_command 0b11000000 + 12
		do_lcd_data temp
		rcall buzzeron
		rcall sleep_245ms

		rcall buzzeroff
		rcall sleep_750ms
		cpi temp, '2'
		brsh countdownLoop
	pop temp
	ret

find:
	ldi at, infind
	ret

pot:
	push temp
	push wl
	push wh
	push xl
	push xh
	push temp2
	push temp3
	push temp4
	ldi at, inpot

	do_lcd_command 0b11000000
	do_lcd_datai 'R'
	do_lcd_datai 'e'
	do_lcd_datai 'm'
	do_lcd_datai 'a'
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai 'g'
	do_lcd_datai ':'
	do_lcd_datai ' '
	
	;choose number
	loadmem seed
	mov temp, wh
	lsr temp
	lsr temp
	mov temp2, state
	lsl temp2
	inc temp2
	mul temp, state
	add r0, wl
	add r1, wh
	andi wh, 3
	;ldi wh, high(500)
	;ldi wl, low(500)
	mov temp4, wh
	mov temp3, wl

	;initialise countdown
	lds temp, ocount
	sts count, temp
	rcall displayt
	rcall buzzeron
	clr temp
	sts fours, temp
	ldi temp, 1 << TOIE4
	sts TIMSK4, temp

	retrypot:
	rcall resetpottoz

	potloop:
		mov xl, temp3
		mov xh, temp4
		sub xl, wl
		sbc xh, wh
		brlo retrypot

		cpi xh, 0
		brne pot8lightoff

		;bottom 8 lights
		sbiw x, 1
		cpi xl, 48
		brsh pot8lightoff
			ser temp
			out PORTC, temp
			rjmp endpot8light
		pot8lightoff:
			clr temp
			out PORTC, temp
			rjmp pot9lightoff
		endpot8light:

		;9th light
		cpi xl, 32
		brsh pot9lightoff
			sbi PORTG, 0
			rjmp endpot9light
		pot9lightoff:
			cbi PORTG, 0
			rjmp pot10lightoff
		endpot9light:

		;last light
		cpi xl, 16
		brsh pot10lightoff
			sbi PORTG, 1

			ldscpi potwin, 0
			brne potwinalreadystarted
				inc temp;
				sts potwin, temp
			potwinalreadystarted:

			cpi temp, t+1
			brsh potfin
			rjmp endpot10light
		pot10lightoff:
			cbi PORTG, 1
			ldists potwin, 0
		endpot10light:

	rjmp potloop;

	potfin:
	clr temp
	out PORTC, temp
	cbi PORTG, 0
	cbi PORTG, 1

	rcall buzzeron
	ldists fours, 0

	ldi at, infind
		
	pop temp4
	pop temp3
	pop temp2
	pop xh
	pop xl
	pop wh
	pop wl
	pop temp
	ret

enter:
	ldi at, inenter
	ret

;FUNCTIONS

resetpottoz:
	push temp

	clr temp
	out PORTC, temp
	cbi PORTG, 1
	cbi PORTG, 0

	cli
	do_lcd_command 0b00000010 
	do_lcd_datai 'R'
	do_lcd_datai 'e'
	do_lcd_datai 's'
	do_lcd_datai 'e'
	do_lcd_datai 't'
	do_lcd_datai ' '
	do_lcd_datai 'P'
	do_lcd_datai 'O'
	do_lcd_datai 'T'
	do_lcd_datai ' '
	do_lcd_datai 't'
	do_lcd_datai 'o'
	do_lcd_datai ' '
	do_lcd_datai '0'
	sei

	resetpottozloop:
		cpi wl, 0;
		brne resetpottozloop
		cpi wh, 0;
		brne resetpottozloop

	cli
	do_lcd_command 0b00000010 
	do_lcd_datai 'F'
	do_lcd_datai 'i'
	do_lcd_datai 'n'
	do_lcd_datai 'd'
	do_lcd_datai ' '
	do_lcd_datai 'P'
	do_lcd_datai 'O'
	do_lcd_datai 'T'
	do_lcd_datai ' '
	do_lcd_datai 'P'
	do_lcd_datai 'o'
	do_lcd_datai 's'
	do_lcd_datai ' '
	do_lcd_datai ' '
	sei

	pop temp
	ret

startAdcRead:
	push temp
	ldists wadc, 1
	ldi temp, (3 << REFS0) | (0 << ADLAR) | (0 << MUX0);
	sts ADMUX, temp
	ldi temp, (1 << MUX5)
	sts ADCSRB, temp
	ldi temp,  (1 << ADEN) | (1 << ADSC) | (1 << ADIE) | (5 << ADPS0);
	sts ADCSRA, temp
	pop temp
	ret

buzzeron:
	push temp
	ldi temp, 1 << TOIE1
	sts TIMSK1, temp
	pop temp
	ret

buzzeroff:
	push temp
	clr temp
	sts TIMSK1, temp
	cbi PORTB, buzzer
	pop temp
	ret

displayt:
	push temp
	push temp2
	push temp3

	lds temp3, count;
	clr temp;
	bin_to_dec_t 10;
	bin_to_dec_t 1;
	cpi temp, 0;
	brne dontprintzerot
		do_lcd_datai '0'
	dontprintzerot:

	pop temp3
	pop temp2
	pop temp
	ret;

bin_to_dec_f:
	push temp4
	ldi temp4, '0'
	bintodecloop:
		cp temp3, temp2
		brlo endbintodecloop
			
		sub temp3, temp2
		inc temp4;
		ser temp;
		rjmp bintodecloop;
	endbintodecloop:

	cpi temp, 0
	breq dontprintbtd;
		do_lcd_data temp4
	dontprintbtd:
	pop temp4
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
	brne dontprintzerow
		do_lcd_datai '0'
	dontprintzerow:

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

sleep_245ms:
	push temp;
	ldi temp, -49;
	delayloop_250ms:
		rcall sleep_5ms
		inc temp;
		brne delayloop_250ms
	pop temp
	ret

sleep_750ms:
	rcall sleep_245ms
	rcall sleep_245ms
	rcall sleep_245ms
	rcall sleep_5ms
	rcall sleep_5ms
	rcall sleep_5ms
	ret