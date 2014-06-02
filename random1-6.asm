;Electronic Dice
;---------------
;Program written by Scott Cannard
;
;for the electronic die
;designed by Scott Cannard and Nicholas Cannard (2/16/11)
;
;Uses common library definitions
;
;Last edited: February 20, 2011
;
;****************************************************
;* Notes:											*
;*													*
;*		Dedicated Register Allocation				*
;*		-----------------------------				*
;*		r10 : 0x00									*
;*		r11 : 0xFF									*
;*													*
;*		r15 : read input port						*
;*		r16 : temp loop counters					*
;*		r17 : comparison to a constant				*
;*		r18 : random value (1-6)					*
;*													*
;*		r24 : bits for LED display pattern			*
;*		r25 : error codes							*
;*													*
;*		r29 : delay outer loop						*
;*		r30 : delay inner loop(LOW)					*
;*		r31 : delay inner loop(HIGH)				*
;*													*
;*													*
;*		Error Codes									*
;*		-----------									*
;*		1 - random value out of range (x<1, x>6)	*
;*													*
;****************************************************
			

//Define symbols
.include "./tn2313def.inc"   ;include common library symbols
.def  rOFF		= r10
.def  rON		= r11
.def  rINPUT	= r15
.def  rCOUNTER	= r16
.def  rRANDOM	= r18
.def  rPATTERN  = r24
.def  rERRORS	= r25

//Define beginning of code segment and begin execution
.org 0x0000
rjmp INITIALIZE		;first rjmp statement initializes instruction pointer





INITIALIZE:
	//Start 16-bit timer
	ldi r21, 0b00000001
	out TCCR1B, r21

	//Initialize global constants
	.set  cInnerHIGH	= HIGH(59535)  ;inner loop setting: inner delay = 65536 - (innerHIGH|innerLOW)
	.set  cInnerLOW		=  LOW(59535)
	.set  cFlashON		=	      75	;X * (inner delay) cycles for LEDs to stay lit during startup flash
	.set  cFlashOFF		=		  25	;X * (inner delay) cycles for LEDs to be off during startup flash
	.set  cFlashDELAY	=		 255	;X * (inner delay) cycles to wait before repeating startup flash
	.set  cPickON		=		  30	;X * (inner delay) cycles for LEDs to stay lit during # selection
	.set  cPickOFF		=  		  15	;X * (inner delay) cycles for LEDs to be off during # selection
	.set  cFailONOFF	=  	  	 100	;X * (inner delay) cycles for error code on/off toggle
	.set  cRolls		=		  13	;number of times to "roll" the random numbers

	//Initialize dedicated registers
	clr  rERRORS		;error codes = 0
	ldi  r21, 0x00
	mov  rOFF, r21		;0b00000000 bit sequence (LEDs off)
	ldi  r21, 0xFF
	mov  rON, r21		;0b11111111 bit sequence (LEDs on)

	//Set up stack location and data port directions
	ldi  r21, RAMEND	;RAMEND = size of available memory
	out  SPL, r21		;assign stack pointer
	out  DDRB, rON		;set PortB data direction (0xFF = outputs)
	out  DDRD, rOFF		;set PortD data direction (0x00 = inputs)





STARTUP:
//Loop - flash all LEDs 3x,
//		 wait for flashDELAY,
//		 check for button press (escape from STARTUP)
//
//Break if - button gets pressed between flash sequences

	ldi  rCOUNTER, 3		;set up startup flash loop

	STARTUP_FLASH:
		out  PortB, rON			;turn on all LEDs
		ldi  r29, cFlashON		;wait for flashON delay
		rcall DELAY

		out  PortB, rOFF		;turn off all LEDs
		ldi  r29, cFlashOFF		;wait for flashOFF delay
		rcall DELAY

		dec  rCOUNTER			;decrement startup flash loop
		brne STARTUP_FLASH		;loop if counter didn't hit zero

	STARTUP_WAIT:
		ldi  r29, cFlashDELAY	;set up outer delay loop

		SW_OUTER:
		ldi  r31, cInnerHIGH		;set up inner delay loop
		ldi  r30, cInnerLOW

			SW_INNER:
			in   rINPUT, PIND
			sbrs rINPUT, 2			;if button is not pressed, skip
			rjmp STARTUP_END		;...else break to end (button was pressed)
			nop
			adiw r30, 1				;increment sw_inner loop
			brne SW_INNER			;loop if counter didn't hit zero

		dec  r29				;decrement sw_outer loop
		brne SW_OUTER			;loop if counter didn't hit zero

		rjmp STARTUP			;go back to top and flash again

	STARTUP_END:





//Escaped from STARTUP, select/display the first random number
rcall PICK_A_NUMBER





MAIN:
//Loop - evaluate error code,
//		 check for button press (PICK_A_NUMBER)
//
//Break if error code exists

	mov  r17, rERRORS		;check if error codes = 0
	cpi  r17, 0
	brne FAIL				;if not, break to end

	in   rINPUT, PIND
	sbrs rINPUT, 2			;if button is not pressed, skip
	rcall PICK_A_NUMBER		;...else select/display a new random number
	nop
	rjmp MAIN





FAIL:
//Loop - flash error code
//
//no break

	out  PortB, rERRORS
	ldi  r29, cFailONOFF
	rcall DELAY

	out  PortB, rOFF
	ldi  r29, cFailONOFF
	rcall DELAY

	rjmp FAIL





PICK_A_NUMBER:
//Countdown - loop cRolls times,
//			  poll 16-bit timer,
//			  modify count to get a 1-6 value,
//			  select LED pattern and display
//
//Set error code 1: "random" value out of range

	ldi  rCOUNTER, cRolls			;set up counter for # of times to flash random numbers
	
	PICK_FLASH:
		out  PortB, rOFF			;turn off all LEDs
		ldi  r29, cPickOFF
		rcall DELAY

	PICK_RANDOM:
		in   r30, TCNT1L			;get count from 16-bit timer
		in   r31, TCNT1H			;(low byte must be read from timer first)

	PICK_MOD:
		adiw r30, 6					;add 6 to 16-bit value,
		brcc PICK_MOD				;repeat if no overflow
		nop
		mov  rRANDOM, r30			;store overflow as random value  (0 <= x <= 5)
		inc  rRANDOM				;add 1  (1 <= x <= 6)

	PICK_CASE:
		PC_CMP1:	mov  r17, rRANDOM
					cpi  r17, 1						;random # == 1?
					brne PC_CMP2					;if no, try next comparison
					ldi  rPATTERN, 0b00001000		;if yes, set LED pattern for 1
					rjmp PICK_CASE_END				;escape

		PC_CMP2:	mov  r17, rRANDOM
					cpi  r17, 2						;random # == 2?
					brne PC_CMP3					;if no, try next comparison
					ldi  rPATTERN, 0b01000001		;if yes, set LED pattern for 2
					rjmp PICK_CASE_END				;escape

		PC_CMP3:	mov  r17, rRANDOM
					cpi  r17, 3						;random # == 3?
					brne PC_CMP4					;if no, try next comparison
					ldi  rPATTERN, 0b01001001		;if yes, set LED pattern for 3
					rjmp PICK_CASE_END				;escape

		PC_CMP4:	mov  r17, rRANDOM
					cpi  r17, 4						;random # == 4?
					brne PC_CMP5					;if no, try next comparison
					ldi  rPATTERN, 0b01100011		;if yes, set LED pattern for 4
					rjmp PICK_CASE_END				;escape

		PC_CMP5:	mov  r17, rRANDOM
					cpi  r17, 5						;random # == 5?
					brne PC_CMP6					;if no, try next comparison
					ldi  rPATTERN, 0b01101011		;if yes, set LED pattern for 5
					rjmp PICK_CASE_END				;escape

		PC_CMP6:	mov  r17, rRANDOM
					cpi  r17, 6						;random # == 6?
					brne PC_FAULT					;if no, try next comparison
					ldi  rPATTERN, 0b01110111		;if yes, set LED pattern for 6
					rjmp PICK_CASE_END				;escape

		PC_FAULT:	ldi  rERRORS, 0b00000001		;random value is out of range, set error code
					ret
	PICK_CASE_END:

		out  PortB, rPATTERN			;display selected LED pattern
		ldi  r29, cPickON
		rcall DELAY

	dec  rCOUNTER						;decrement loop counter
	brne PICK_FLASH						;loop if counter didn't hit zero

	ret





DELAY:
	DELAY_OUTER:
	ldi  r31, cInnerHIGH
	ldi  r30, cInnerLOW

		DELAY_INNER:
		adiw r30, 1
		brne DELAY_INNER

	dec  r29
	brne DELAY_OUTER

	ret
