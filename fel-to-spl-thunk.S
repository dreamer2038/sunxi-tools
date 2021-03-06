/*
 * Copyright © 2015 Siarhei Siamashka <siarhei.siamashka@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice (including the next
 * paragraph) shall be included in all copies or substantial portions of the
 * Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/*************************************************************************/
/* Usage instructions: "ruby -x fel-to-spl-thunk.S > fel-to-spl-thunk.h" */
/*************************************************************************/

#if 0 
#!/usr/bin/env ruby

def tool_exists(tool_name)
    `which #{tool_name} > /dev/null 2>&1`
    return $?.to_i == 0
end

toolchains = [
  "arm-none-eabi-",
  "arm-linux-gnueabihf-",
  "arm-none-linux-gnueabi-",
  "armv7a-hardfloat-linux-gnueabi-",
]

toolchain = toolchains.find { |toolchain| tool_exists("#{toolchain}gcc") }
abort "Can't find any ARM crosscompiler\n" unless toolchain

system("#{toolchain}gcc -o #{$PROGRAM_NAME}.o -c #{$PROGRAM_NAME}")
exit($?.to_i) if $?.to_i != 0

`#{toolchain}objdump -d #{$PROGRAM_NAME}.o`.each_line {|l|
    next unless l =~ /(\h+)\:\s+(\h+)\s+(\S+)\s+([^;]*)/
    printf("\t0x%s, /* %8s:    %-10s %-28s */\n", $2, $1, $3, $4.strip)
}

__END__
#endif

/*************************************************************************/

BUF1		.req	r0
BUF2		.req	r1
TMP1		.req	r2
TMP2		.req	r3
SWAPTBL		.req	r4
FULLSIZE	.req	r5
BUFSIZE		.req	r6
CHECKSUM	.req	r7

entry_point:
	b	setup_stack

stack_begin:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
stack_end:
	nop

	/* A function, which walks the table and swaps all buffers */
swap_all_buffers:
	adr	SWAPTBL,   swaptbl_start
swap_next_buffer:
	ldr	BUF1,      [SWAPTBL],  #4
	ldr	BUF2,      [SWAPTBL],  #4
	ldr	BUFSIZE,   [SWAPTBL],  #4
	cmp	BUFSIZE,   #0
	bxeq    lr
swap_next_word:
	ldr	TMP1,      [BUF1]
	ldr	TMP2,      [BUF2]
	subs	BUFSIZE,   BUFSIZE,    #4
	str	TMP1,      [BUF2],     #4
	str	TMP2,      [BUF1],     #4
	bne	swap_next_word
	b	swap_next_buffer

setup_stack: /* Save the original SP, LR and CPSR to stack */
	adr	BUF1,      stack_end
	str	sp,        [BUF1, #-4]!
	mov	sp,        BUF1
	mrs	TMP1,      cpsr
	push	{TMP1, lr}

	/* Disable IRQ and FIQ */
	orr	TMP1,      #0xc0
	msr	cpsr_c,    TMP1

	/* Check if the instructions or data cache is enabled */
	mrc	p15, 0, TMP1, c1, c0, 0
	movw	TMP2,      #((1 << 12) | (1 << 2))
	tst	TMP1,      TMP2
	bne	cache_is_unsupported

	bl	swap_all_buffers

verify_checksum:
	movw	CHECKSUM,  #0x6c39
	movt	CHECKSUM,  #0x5f0a
	mov	BUF1,      #0
	ldr     FULLSIZE,  [BUF1, #16]
check_next_word:
	ldr	TMP1,      [BUF1],   #4
	subs	FULLSIZE,  FULLSIZE, #4
	add	CHECKSUM,  CHECKSUM, TMP1
	bne	check_next_word

	mov	BUF1,      #0
	ldr	TMP1,      [BUF1, #12]
	subs	CHECKSUM,  CHECKSUM, TMP1, lsl #1
	bne	checksum_is_bad

	/* Change 'eGON.BT0' -> 'eGON.FEL' */
	mov	BUF1,      #0
	movw	TMP1,      (('F' << 8) + '.')
	movt	TMP1,      (('L' << 8) + 'E')
	str	TMP1,      [BUF1, #8]

	/* Call the SPL code */
	dsb
	isb
	blx	BUF1

	/* Return back to FEL */
	b	return_to_fel

cache_is_unsupported:
	/* Bail out if cache is enabled and change 'eGON.BT0' -> 'eGON.???' */
	mov	BUF1,      #0
	movw	TMP1,      (('?' << 8) + '.')
	movt	TMP1,      (('?' << 8) + '?')
	str	TMP1,      [BUF1, #8]
	b	return_to_fel

checksum_is_bad:
	/* The checksum test failed, so change 'eGON.BT0' -> 'eGON.BAD' */
	mov	BUF1,      #0
	movw	TMP1,      (('B' << 8) + '.')
	movt	TMP1,      (('D' << 8) + 'A')
	str	TMP1,      [BUF1, #8]

return_to_fel:
	bl	swap_all_buffers
	pop	{TMP1, lr}
	msr	cpsr_c,    TMP1 /* Restore the original CPSR */
	ldr     sp,        [sp]
	bx	lr

swaptbl_start:
