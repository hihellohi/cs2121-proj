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

.macro shiftright
	ldi temp,@1
shifting:
	cpi temp,0
	breq done
		lsr @0
		dec temp
		rjmp shifting
	done:
.endmacro

.macro compNum
	lds temp,@0
	lds temp2,@1
	cp temp,temp2
	breq changeNum
		changeNum:
			lsr temp2
			inc temp2
			cp temp,temp2
			breq changeNum
			sts @1,temp2
			rjmp loopy
.endmacro

.macro printwtf
		push wl
		push wh
		clr wh
		mov wl,@0
		do_lcd_command 0b00010100 ; increment to the right
		rcall displayw
		pop wh
		pop wl
.endmacro

.macro convert_number
		mov temp4,wl; store row in temp4
		ldi temp3,4
		mul temp4,temp3; 4xrow
		mov temp4,r0
		mov temp3,wh
		add temp3, temp4;=(col+1)+4xrow
		sts keyButton,temp3 ;stores in data memory the correct one
.endmacro

;REGISTERS
.def temp = r16
.def temp2 = r17
.def temp4 = r21
.def wl = r24
.def wh = r25
.def roundsleft = r18
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
second:	.byte 1;
wadc:	.byte 1;
potwin:	.byte 1;
seed:		.byte 2;
RandNum:	.byte 3;
keyFlag:    .byte 1;
keyButton:  .byte 1;
keyFound:   .byte 1;
keyRandNum:	.byte 1
TempCounter:.byte 1
adcreading:	.byte 2

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
.org OVF5addr
	jmp timer5

;MAIN
RESET:
	;INIT

	;initialise variables
	ldists ocount, 10;
	ldists count, 0;
	ldists bounce, 0;
	ldists second, 0;
	ldists wadc, 0;
	ldists keyFlag,0
	ldists keyFound,0
	ldists keyRandNum,255
	ldists keyButton,255
	ldists TempCounter,0
	ldists adcreading,0
	ldi roundsleft, 3;
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

	sbi DDRA, 1
	cbi PORTA, 1

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

	;keyboard
	ldi temp,0xF0
	sts DDRL,temp ;0b11110000
	;motor
	ldi temp,1<<4
	out DDRE,temp
	
	;keyboard hold- one second
	clr temp
	sts TCCR5A,temp
	ldi temp,1<<CS50 ;find a good prescalar
	sts TCCR5B,temp
	clr temp
	;ldi temp,1<<TOIE5
	sts TIMSK5,temp ; starts the timer counter now

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

	ldi temp, 0x7F
	sts PORTL, temp
	lds temp2, ocount
	notYetStarted:

		lds temp, PINL
		andi temp, 0xF
		cpi temp, 0xF
		breq nobutton
			sbrs temp, 0
				ldi temp2, 20
			sbrs temp, 1
				ldi temp2, 15
			sbrs temp, 2
				ldi temp2, 10
			sbrs temp, 3
				ldi temp3, 5
		nobutton:
		cpi at, incountdown
		brne notYetStarted

	sts ocount, temp2
	clr temp
	sts PORTL, temp
	
	;START GAME HERE
	rcall startingcountdown;

	mainloop:
		cpi roundsleft, 0;
		breq end;
			
		rcall pot;
		rcall find;
		dec roundsleft;
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
	storemem adcreading
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

timer5:
	push temp
	push temp2
	;push temp3
	;push temp4
	push wl
	push wh
	in temp,SREG
	push temp
	lds temp, keyRandNum
	lds temp2,keyButton
	cp temp, temp2
	brne wrongkey
		ldscpi keyFlag,1
		brne wrongkey ; it is not being held down
			ldi temp,1<<4
			out PORTE,temp;start RUNNING the motor
			lds temp2,TempCounter
			inc temp2
			cpi temp2, 244 ; 244 is one second, if it is, ->jump to finish :)
			brne continue
					ldists keyFound,1
					rjmp finish
			continue:
			sts TempCounter,temp2 ; if not one second yet -> jump to finish :)
			rjmp finish
	wrongkey:
	clr temp2
	sts TempCounter,temp2 ; resets the timer	
	clr temp ; may need to change this for the back lighting 
	out PORTE,temp ; stop the motor from running< when more things are added, it doesnt work anymore
	finish:
	pop temp
	out SREG,temp
	pop wh
	pop wl
	pop temp2
	pop temp
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
		ldscpi second, t;
		brne full
			ldists second, 0
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
		cpi at, won
		breq winningt4
			ldscpi second, t >> 1;
			brne endnotinpot_t4
				clr temp;
				sts TIMSK4, temp
				rcall buzzeroff
				rjmp endnotinpot_t4
		winningt4:
			lds temp, second
			andi temp, 15

			cpi temp, 0
			brne turnont4
				sbi PORTA, 1
				rjmp endnotinpot_t4
			turnont4:

			cpi temp, 8
			brne turnofft4
				cbi PORTA, 1
			turnofft4:
	endnotinpot_t4:
	ldsinc second

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
	breq generateRngSeed
	cpi at, inpot
	breq generateRngSeed
		inc temp2
		rjmp generateRngSeedEnd

	generateRngSeed:
			loadmem seed
		subi wl, low(-36277)
		ldi temp, high(-36277)
		sbc wh, temp
		storemem seed
			
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
	ldi temp, 1 << TOIE4
	sts TIMSK4, temp
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
	push wl
	push wh
	push temp
	push temp2
	push temp3
	push yh
	push yl
	cpi roundsleft,3 ; if not the first time going through, dont need to find the numbers
	brne next
		loadmem seed ; loads the random generator number
		mov temp2,wl
		andi temp2,0xF ; gets rid of the higher 4 bits
		sts RandNum,temp2
		do_lcd_command 0b00000001 ; clear display
		mov temp2,wl
		shiftright temp2,4
		mov wl,temp2
		sts RandNum+1,temp2
		mov temp2,wh
		andi temp2,0xF
		sts RandNum+2,temp2
		printwtf temp2

		;rcall differentnumber -something buggy about this as well

	
next:
	mov temp2,roundsleft
	ldi yl,low(RandNum)
	ldi yh,high(RandNum)
	loops:
		ld temp,y+ ; loop it until it is the correct number
		dec temp2
		cpi temp2,0
		brne loops
	
	sts keyRandNum,temp
	printwtf temp
	ldi temp,1<<TOIE5
	sts TIMSK5,temp ; starts the timer counter now
	input:
		rcall keyboard
		ldscpi keyFound,0 ; checks if the button is found
		breq input
	ser temp
	out PORTC,temp
	clr temp ;may not be the best place to put it but i shall SEE
	
	sts TIMSK5,temp ; turns the timer off
	ldists keyFound,0; resets the button back
	ldists keyRandNum,255
	ldists keyButton,245
	pop yl
	pop yh
	pop temp3
	pop temp2
	pop temp
	pop wh
	pop wl
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
	andi wh, 3
	mov temp4, wh
	mov temp3, wl

	;initialise countdown
	lds temp, ocount
	sts count, temp
	rcall displayt
	rcall buzzeron
	clr temp
	sts second, temp
	ldi temp, 1 << TOIE4
	sts TIMSK4, temp

	retrypot:
	rcall resetpottoz

	potloop:
		loadmem adcreading
		mov xl, temp3
		mov xh, temp4
		sub xl, wl
		sbc xh, wh
		brlo retrypot

		cpi xh, 0
		brne pot8lightoff

		;bottom 8 lights
		sbiw x, 1
		cpi xl, 48 << 1
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
		cpi xl, 32 << 1
		brsh pot9lightoff
			sbi PORTG, 0
			rjmp endpot9light
		pot9lightoff:
			cbi PORTG, 0
			rjmp pot10lightoff
		endpot9light:

		;last light
		cpi xl, 16 << 1
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
	ldists second, 0

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
		loadmem adcreading
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
	;do_lcd_command 0b00000001 ; clear display
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

keyboard:
	push wh; number of columns
	push wl; number of rows
	push temp; cmask
	push temp2;rmask
	push temp3
	push temp4
	clr wh
	clr wl
	clr temp
	clr temp2
	clr temp3
	clr temp4



	start:
		ldi temp,0b11101111 ;temp=cmask
		clr wh			; number of columns
	col_loop:
		cpi wh,4
		breq finish1
		sts PORTL,temp ;port L 0b11101111
		ldi temp3,0xFF ; random number
	delay: 
		dec temp3
		brne delay
		lds temp4,PINL;	0b0000111
		mov temp3, temp4
		andi temp3,0xF;0b00001111
		cpi temp3,0xF
		breq next_col
		ldi wl, 0 ; number of rows
		ldi temp2,1
			row_loop:
				cpi temp2, 0x10
				breq next_col
				and temp3,temp2
				cpi temp3, 0 ; number is found
				mov temp3, temp4
				brne not_found
					rcall debounce
					rjmp finish1
				not_found:
				lsl temp2; rmask
				inc wl
				rjmp row_loop
		next_col:
		lsl temp
		inc temp
		inc wh ; increment number of columns
		jmp col_loop
		finish1:
	pop temp4
	pop temp3
	pop temp2
	pop temp
	pop wl
	pop wh
	ret

	debounce:
		push temp2
		push temp3
		push temp4
		push wl
		push wh
		rcall sleep_5ms ; 
		rcall sleep_5ms
		clr temp3
		clr temp4
		lds temp4,PINL;
		and temp4, temp2; lds temp4 with rmask 
		cpi temp4, 0;
		brne finish_2 ; may see where if it's just a random low
		push temp ; using it part of the macro, dont want to ruin it
		ldists keyFlag,1
		pop temp
		convert_number ; stores it into temp3
		printwtf temp3
		nobounce:
			lds temp4,PINL;0b10001000
			and temp4, temp2; still loops it until it is high again
			cpi temp4, 0;
			breq nobounce
		ldists keyFlag,0
		rcall sleep_5ms
		rcall sleep_5ms
		finish_2:
		pop wh
		pop wl
		pop temp4
		pop temp3
		pop temp2
		ret

differentnumber:
push temp
push temp2
loopy:
	compNum RandNum,RandNum+1
	compNum RandNum,RandNum+2
	compNum RandNum+1,RandNum+2
pop temp2
pop temp
ret

printwtf1:
		push wl
		push wh
		clr wh
		do_lcd_command 0b00010100 ; increment to the right
		rcall displayw
		pop wh
		pop wl
		ret


	/*
convert:
	rcall sleep_5ms
	rcall sleep_5ms
	lds temp4,PINL
	and temp4, temp2;
	cpi temp4, 0;
	brne main
	nobounce:
		;out PORTC,cmask
		lds temp4,PINL
		and temp4, temp2;
		cpi temp4, 0;
		breq nobounce
	rcall sleep_5ms
	rcall sleep_5ms

	cpi wh, 3;
	breq symbol;
	cpi row, 3
	breq zasdf;
	e:
	mov temp,row;
	add temp,row;
	add temp,row;
	add temp,col;
	inc temp;
	back:
	rjmp number

zasdf:
	cpi col,2;
	breq mainerino;
	cpi col,0;
	breq asterisk;
	clr temp
	rjmp back

asterisk:
	clr acc;
	clr temp3
	rcall display
	rjmp main

symbol:
	cpi row,0;
	breq addition
	cpi row,1;
	breq subtraction
	cpi row,2;
	breq multiplication
	cpi row,3;
	breq division
	*/
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
