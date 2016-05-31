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
RandNum:	.byte 3;
keyFlag:    .byte 1;
keyButton:  .byte 1;
keyFound:   .byte 1;
keyRandNum:	.byte 1
TempCounter:.byte 1

.cseg

;VECTOR TABLE
.org 0
	jmp RESET
.org INT0addr
	jmp EXT_INT0
	jmp EXT_INT1
.org OVF0addr
	jmp timer0
.org OVF5addr
	jmp timer5

;MAIN
RESET:
	;INIT

	;initialise variables
	ldists bounce0, 0
	ldists bounce1, 0
	ldists keyFlag,0
	ldists keyFound,0
	ldists keyRandNum,255
	ldists keyButton,255
	ldists TempCounter,0
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

	notYetStarted:
		cpi at, incountdown
		brne notYetStarted

	;rcall displayw
	
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
	
	rcall find
halt:
	rjmp halt
	

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


;FUNCTIONS
pb0pressed:
	rjmp RESET;
	ret

pb1pressed:
	push temp
	cpi at, notStarted
	brne startGame
		inc at
		;ldi at,3
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
	push wl
	push wh
	push temp
	push temp2
	push temp3
	push yh
	push yl
	cpi state,3 ; if not the first time going through, dont need to find the numbers
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
	mov temp2,state
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
	;do_lcd_command 0b00000001 ; clear display
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
