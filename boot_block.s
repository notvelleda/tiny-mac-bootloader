/*
 * tiny-mac-bootloader: boot_block.s
 *  - the actual code of the bootloader, what makes it tick
 */

.equ boot_block_size, 1024 /* the size of this boot block */

/* various definitions for interfacing with the Mac ROM */
/*.equ BootDrive, 0x0210
.equ BtDskRfn, 0x0b34*/
.equ ScrnBase, 0x0824
.equ MemTop, 0x0108
.equ ROMBase, 0x02ae
.macro _SysError
    .short 0xa9c9
.endm
.macro _Read
    .short 0xa002
.endm
.macro _HideCursor
    .short 0xa852
.endm

.equ block_group_size, 32

.equ elf_magic, 0x7f454c46 /* ELF magic number */
.equ pt_load, 1 /* id of the loadable program header type */

/* list of error codes that are displayed if something goes wrong
 * these are displayed in a Sad Mac screen with the first 2 letters reading 0F and the last 4 being the error code itself
 */
.equ bad_magic_number, 0xe600
.equ no_such_file, 0xe601
.equ read_error, 0xe602

/* the boot block header, required for the Mac ROM to recognize that this device is bootable */
.globl begin
begin:

id:         .ascii  "LK"    /* boot block signature */
entry:      bra     start   /* entry point, the Mac ROM jumps here when the boot block has been loaded */
version:    .short  0x4418  /* boot block version number, only the high byte of this matters */
/* everything else doesn't seem to be required so it isn't here :3 */

/* the actual entry point */
start:
    movel %a7, %a0

    /* since the stack layout in the 64 KB ROM used in the Mac 128K/512K and the later 128 KB ROM used in the 512Ke/Plus/etc. is different,
     * the version number of the ROM needs to be checked */
    movel ROMBase, %a1 /* get the base address of the ROM since it may not be consistent */
    moveb 9(%a1), %d0 /* the ROM version number is the 9th byte in ROM */
    cmpb #0x69, %d0
    ble 1f /* if the ROM version is 0x69 (the 64 KB ROM's version) or less, a0 already points to the io parameter block and thus does not need to be modified */
    addql #4, %a0 /* add 4 to a0 so that it points to the same io parameter block used to read this boot block */
1:

    /*movew #1, 0x2c(%a0)*/ /* use offset-from-start positioning */
    /*movew (BtDskRfn), 0x18(%a0)
    movew (BootDrive), 0x16(%a0)*/

    lea io_params(%pc), %a1
    movel %a0, (%a1) /* save the io block address for easy access later */

    lea counter(%pc), %a1
    movel (ScrnBase), (%a1)

    /* read the superblock */
    lea after_fill(%pc), %a1
    movel #1, %d0
    bsr read_block

    /* check its magic number */
    cmpw #0x53ef, 56(%a1) /* s_magic */
    beq correct_magic_number
    movew #bad_magic_number, %d0
    _SysError

correct_magic_number:
    /* read fields from the superblock */
    movel 24(%a1), %d0 /* s_log_block_size */
    bsr reverse_word
    movel #1024, %d1
    lsl %d0, %d1
    lea block_size(%pc), %a2
    movel %d1, (%a2)

    movel 20(%a1), %d0 /* s_first_data_block */
    bsr reverse_word
    addql #1, %d0
    lea bg_table(%pc), %a2
    movel %d0, (%a2)

    movel 40(%a1), %d0 /* s_inodes_per_group */
    bsr reverse_word
    lea bg_inodes(%pc), %a2
    movel %d0, (%a2)

    movel 76(%a1), %d0 /* s_rev_level */
    bsr reverse_word
    cmpl #0, %d0
    beq calculate_load_address /* if the major revision is 0, inodes are fixed at 128 bytes */

    movew 88(%a1), %d0 /* s_inode_size */
    swap %d0
    clrw %d0
    bsr reverse_word
    lea inode_size(%pc), %a2
    movel %d0, (%a2)

calculate_load_address:
    /* calculate address to load kernel at before copying it into place */
    lea after_fill(%pc), %a3
    addl block_size(%pc), %a3

    /* load the kernel's command line */
    lea cmdline_name(%pc), %a4
    movew #cmdline_len, %d7
    bsr load_file

    movel %a3, -(%a7)

    /* load the kernel */
    lea kernel_name(%pc), %a4
    movew #kernel_len, %d7
    bsr load_file

    _HideCursor
    movew #0x2700, %sr /* disable interrupts */

    /* indicate that loading from disk has finished */
    lea counter_state(%pc), %a0
    moveb #0xff, (%a0)
    bsr increment_counter

    movel (%a7)+, %a3 /* restore kernel load address */

    /* check if the kernel is an ELF binary */
    movel (%a3), %d0
    cmpl #elf_magic, %d0
    beq load_elf

    movew #bad_magic_number, %d0
    _SysError

load_elf:
    /* it is, copy its segments into their proper addresses */
    movel 24(%a3), %a0 /* save entry point address for when invoke_kernel is called later */

    movel 28(%a3), %a1 /* get the offset of the program headers in the file */
    addl %a3, %a1 /* get the address of the program headers */

    movew 42(%a3), %d0 /* get the size of each individual program header */
    clrl %d1
    movew 44(%a3), %d1 /* get the number of program headers */

    bra 2f
load_program_header:
    /* make sure this program header is loadable */
    movel (%a1), %d2
    cmpl #pt_load, %d2
    bne next_program_header

    /* get the address of the segment's contents */
    movel 4(%a1), %a2
    addl %a3, %a2

    movel 8(%a1), %a4 /* get the address that the segment's data will be copied to */

    /* TODO: maybe speed these up? */

    /* copy this segment's data from the file */
    movel 16(%a1), %d2 /* get the size of the segment in the file */
    bra 1f
copy_segment_data:
    moveb (%a2)+, (%a4)+
    subql #1, %d2
1:  bne copy_segment_data

    /* clear out the rest of the segment's data */
    movel 20(%a1), %d3 /* get the size of the segment in memory */
    subl 16(%a1), %d3 /* get the number of bytes that'll have to be cleared */
    bra 1f
clear_segment:
    clrb (%a4)+
    subql #1, %d3
1:  bne clear_segment

next_program_header:
    bsr increment_counter

    /* advance to next program header */
    addw %d0, %a1
2:  dbra %d1, load_program_header

    /* all segments are in place now, kernel can be started */
invoke_kernel:
    /* add a special final state to the progress counter to show that control is leaving the bootloader, this can probably be removed to save space */
    lea counter_state(%pc), %a1
    moveb #0xcc, (%a1)
    bsr increment_counter

    /* move stack pointer to top of ram */
    movel (MemTop), %sp

    /* push address of command line arguments onto stack */
    lea after_fill(%pc), %a1
    addl block_size(%pc), %a1
    movel %a1, -(%sp)

    jsr (%a0)

halt:
    bra halt

/* increments the progress counter so the user knows something's happening */
increment_counter:
    moveml %a0/%d0, -(%a7)

    movel counter(%pc), %d0

    movel %d0, %a0
    moveb counter_state(%pc), (%a0)

    addql #1, %d0

    lea counter(%pc), %a0
    movel %d0, (%a0)

    moveml (%a7)+, %a0/%d0

    rts

/* loads a file into memory. address to load at is in a3, address of filename is in a4, length of filename is in d7. end address is returned in a3, block size is returned in d4 */
load_file:
    moveml %d0-%d3/%d5-%d7/%a0-%a2/%a4-%a6, -(%a7)

    movel %a3, -(%a7) /* save load address */

    /* read the inode for the root directory */
    lea after_fill(%pc), %a1
    movel #2, %d0
    bsr read_inode

    /* find the inode for the file */
    movel %a1, %a5
    addl block_size(%pc), %a5
    movel %a1, %a3
    movel %d7, %d3
    bsr find_directory_entry

    /* read the file inode */
    lea after_fill(%pc), %a1
    bsr read_inode

    /* calculate its size in filesystem blocks */
    bsr get_inode_block_size
    movel %d0, %d5

    movel (%a7)+, %a3 /* restore load address */

    /* get end address in memory */
    movel 4(%a1), %d0 /* i_size */
    bsr reverse_word
    addl %a3, %d0
    movel %d0, -(%a7)

    movel %a1, %a4
    clrl %d4
    bra 3f

2:  /* load the file into memory */
    movel %a3, %a1
    movel %a4, %a2
    movel %d4, %d0
    bsr read_inode_block
    bsr increment_counter

    addql #1, %d4
    addl block_size(%pc), %a3
3:  dbra %d5, 2b

    /* add null terminator */
    movel (%a7)+, %a0
    clrb (%a0)

    moveml (%a7)+, %d0-%d3/%d5-%d7/%a0-%a2/%a4-%a6
    rts

/* finds a directory entry matching the given name. address of directory inode to search is in a3, address of name is in a4, address of temporary buffer is in a5,
 * name length is in d3, returns inode number in d0 */
find_directory_entry:
    moveml %d1-%d7/%a0-%a6, -(%a7)

    clrl %d4

    /* calculate how many filesystem blocks are allocated for this inode */
    bsr get_inode_block_size
    movel %d0, %d7

    clrl %d0
    bra 7f

2:  /* loop thru blocks containing directory entries */
    moveml %d0/%d3, -(%a7)
    movel %a5, %a1
    movel %a3, %a2
    bsr read_inode_block
    moveml (%a7)+, %d0/%d3

    movel %a5, %a6
    clrl %d1

3:  /* look for matching directory entry */
    movel (%a6), %d6 /* inode */
    cmpl #0, %d6 /* skip unused directory entries marked with an inode of 0 */
    beq 6f

    moveb 6(%a6), %d4 /* name_len */
    cmpb %d4, %d3 /* check if name length matches */
    bne 6f

    movel %a4, -(%a7) /* save filename */
    lea 8(%a6), %a1
    bra 1f

4:  /* make sure the name matches exactly */
    cmpmb (%a4)+, (%a1)+
    bne 5f
1:  dbra %d4, 4b

    addql #4, %a7

    /* it does, return its inode number */
    movel %d6, %d0
    bsr reverse_word

    moveml (%a7)+, %d1-%d7/%a0-%a6
    rts

5:  movel (%a7)+, %a4 /* load filename */
6:  /* entry doesn't match, keep searching */
    movew 4(%a6), %d4 /* rec_len */
    rolw #8, %d4

    addl %d4, %d1 /* increment the directory entry address and counter */
    addl %d4, %a6

    cmpl block_size(%pc), %d1 /* loop if there are more directory entries in this block */
    bcs 3b

    /* couldn't find any matching entries in this block */
    addql #1, %d0 /* move on to the next block, loop if there are more blocks to be read */
7:  dbra %d7, 2b

    /* directory entry wasn't found, give up */
    movew #no_such_file, %d0
    _SysError

/* calculate the size in filesystem blocks for the given inode. address of inode is in a1, returns size in d0 */
get_inode_block_size:
    movel %d1, -(%a7)

    movel 4(%a1), %d0 /* i_size */
    bsr reverse_word
    movel block_size(%pc), %d1
    addl %d1, %d0
    subql #1, %d0 /* add block_size - 1 to the size field so that it'll round up */
    divu %d1, %d0
    swap %d0
    clrw %d0
    swap %d0

    movel (%a7)+, %d1
    rts

/* reads an inode from the filesystem. inode number is in d0, address to load blocks at is in a1, returns address of inode in a1 */
read_inode:
    moveml %d0-%d6, -(%a7)

    /* inode -= 1 */
    subql #1, %d0

    movel bg_inodes(%pc), %d1
    divu %d1, %d0
    /* block_group (d5) = inode / bg_inodes */
    movew %d0, %d5
    /* index = inode % bg_inodes */
    clrw %d0
    swap %d0

    /* index *= inode_size */
    movel inode_size(%pc), %d1
    mulu %d1, %d0

    /* calculate where the inode will be in the table */
    movel block_size(%pc), %d1
    divu %d1, %d0
    /* containing_block (d3) = index / block_size */
    movew %d0, %d3
    /* offset (d4) = index % block_size */
    clrw %d0
    swap %d0
    movel %d0, %d4

    /* block_group *= block_group_size */
    mulu #block_group_size, %d5

    /* calculate where the block group will be in the table */
    movel block_size(%pc), %d1
    divu %d1, %d5
    /* containing_block (d6) = index / block_size */
    movew %d5, %d6
    addl bg_table(%pc), %d6
    /* offset (d5) = index % block_size */
    clrw %d5
    swap %d5

    /* read the block containing the block group entry */
    movel %d6, %d0
    bsr read_block

    /* find and read the inode table */
    movel 8(%a1, %d5), %d0 /* bg_inode_table */
    bsr reverse_word
    /* containing_block (now in d0) += bg_inode_table */
    addl %d3, %d0

    /* read the inode */
    bsr read_block

    /* return the address it's loaded at */
    lea (%a1, %d4), %a1

    moveml (%a7)+, %d0-%d6
    rts

/* clears a block of memory. clobbers d0, a1, address to clear at is in a1 */
clear_block:
    movel block_size(%pc), %d0
    bra 2f
1:  clrb (%a1)+
2:  dbra %d0, 1b
    rts

/* reads a block from the given inode. clobbers a2, d0, d1, d2, d3. block index to read is in d0, address to read block at is in a1, inode address is in a2 */
read_inode_block:
    addl #40, %a2 /* i_block */

    /* handle initial 12 direct blocks */
    cmpl #12, %d0
    bcc 1f
    bra read_direct_block

1:  /* block number is at least 13, needs indirection */
    subl #12, %d0 /* subtract the initial 12 blocks count from the index */
    movel %d0, %d2 /* save block index */

    movel block_size(%pc), %d1
    lsrl #2, %d1 /* divide block size by 4 to get the number of 32 bit indices in indirect arrays */

    /* check if this block is single or double indirect */
    cmpl %d1, %d0
    bcs 2f

    /* read doubly indirect block */
    subl %d1, %d0 /* subtract the single indirect blocks count from the index */

    movel %d0, %d3 /* save index */

    movel 52(%a2), %d0 /* get the block number of the doubly indirect array */
    beq clear_block /* make sure it isn't zero */
    bsr reverse_word
    bsr read_block

    movel %d3, %d0 /* restore index */

    divu %d1, %d0

    swap %d0
    movew %d0, %d2 /* remainder of the division is the single indirect block index */

    clrw %d0
    swap %d0 /* get the quotient in d0 */
    lsll #2, %d0 /* multiply by 4 to get the offset in the array */
    movel (%a1, %d0), %d0 /* load the address of the singly indirect block array */
    bra read_single_indirect

2:  /* read singly indirect block */
    movel 48(%a2), %d0 /* get the block number of the indirect blocks */
read_single_indirect:
    beq clear_block /* make sure it isn't zero */
    bsr reverse_word
    bsr read_block /* read in the array */

    movel %a1, %a2 /* point read_direct_block at the address the block was read at instead of i_block */
    movel %d2, %d0 /* block index */
    /* fall thru to read_direct_block */

/* reads a direct block from the filesystem. clobbers d0. block index to read is in d0, address to read block at is in a1, address of block array is in a2 */
read_direct_block:
    lsll #2, %d0 /* mulu #4, %d0 */
    movel (%a2, %d0), %d0
    beq clear_block /* just clear the block if there's no data for it */
    bsr reverse_word
    /* fall thru to read_block */

/* reads a single block from the boot device. block number is in d0, address to read to is a1 */
read_block:
    moveml %a0/%d0-%d1, -(%a7) /* save clobbered registers */

    movel io_params(%pc), %a0
    movel block_size(%pc), %d1
    mulu %d1, %d0
    movel %a1, 0x20(%a0) /* where to write the newly read data */
    movel %d1, 0x24(%a0) /* how much data to read */
    movel %d0, 0x2e(%a0) /* offset in bytes */
    _Read
    bne 1f /* check for write errors */

    moveml (%a7)+, %a0/%d0-%d1
    rts

1:  movew #read_error, %d0
    _SysError

/* https://retrocomputing.stackexchange.com/a/15365
 * swaps the bytes in the word given in d0, converting little to big endian or vice versa
 */
reverse_word:
    rolw #8, %d0
    swap %d0
    rolw #8, %d0
    rts

/* assorted variables */
io_params:          .long 0             /* address of the boot device's io parameter block */
block_size:         .long 1024          /* filesystem block size in bytes */
inode_size:         .long 128           /* size of inode structures in the filesystem */
bg_table:           .long 0             /* address of the block group table */
bg_inodes:          .long 0             /* number of inodes per block group */
counter:            .long 0             /* address of the next byte in screen memory to fill for a basic progress indicator */
counter_state:      .byte 0             /* the value that'll be written to the address stored in `counter` */

/* names of the files that this bootloader loads */
kernel_name:        .ascii "kernel"     /* filename of the kernel */
.equ kernel_len,    6                   /* length of the filename of the kernel */
cmdline_name:       .ascii "cmdline"    /* filename of the kernel's command line arguments */
.equ cmdline_len,   7                   /* length of the filename of the command line arguments */

end:

.fill boot_block_size - (end - begin), 1, 0xbb
after_fill:
