# tiny-mac-bootloader: Makefile
#  - build script to script the builds!

all: floppy.img
.PHONY: all run clean

run: floppy.img
	minivmac floppy.img

boot_block.o: boot_block.s
	m68k-unknown-elf-as -o boot_block.o boot_block.s -m68000

boot_block.bin: boot_block.o boot_block.ld
	m68k-unknown-elf-ld -T boot_block.ld boot_block.o -o boot_block.bin

floppy.img: boot_block.bin
	-rm filesystem.img
	mkdir -p fs-contents
	mke2fs -t ext3 -d fs-contents filesystem.img 8m
	cat boot_block.bin | head -c 1024 > floppy.img
	cat filesystem.img | tail -c +1025 >> floppy.img

clean:
	-rm floppy.img filesystem.img boot_block.o boot_block.bin
