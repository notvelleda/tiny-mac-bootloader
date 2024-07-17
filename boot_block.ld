/*
 * tiny-mac-bootloader: boot_block.ld
 *  - linker script to produce the raw boot block image
 */

OUTPUT_FORMAT("binary")
ENTRY(begin)

phys = 0x200000; /* this address probably doesn't matter since everything should ideally be position-independent */

SECTIONS {
    .text phys : AT(phys) {
        *(.text)
    }
}
