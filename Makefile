# tiny-mac-bootloader: Makefile
#  - build script to script the builds!

# set this to the prefix of your toolchain. crosstool-NG tends to use the m68k-unknown-elf- prefix so it's set as default here, but not all toolchains do
CROSS?=m68k-unknown-elf-

AS=$(CROSS)as
LD=$(CROSS)ld

FLOPPY_IMAGE_SIZE?=800k

all: boot_block.bin installer
.PHONY: all run clean

run: floppy.img
	minivmac floppy.img

boot_block.o: boot_block.s
	$(AS) -o boot_block.o boot_block.s -m68000

boot_block.bin: boot_block.o boot_block.ld
	$(LD) -T boot_block.ld boot_block.o -o boot_block.bin

floppy.img: boot_block.bin
	-rm filesystem.img
	mkdir -p fs-contents
	mke2fs -t ext3 -d fs-contents filesystem.img $(FLOPPY_IMAGE_SIZE)
	cat boot_block.bin | head -c 1024 > floppy.img
	cat filesystem.img | tail -c +1025 >> floppy.img

installer: installer.o
	$(CC) installer.o -o installer

clean:
	-rm floppy.img filesystem.img boot_block.o boot_block.bin installer.o
