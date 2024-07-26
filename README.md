# tiny-mac-bootloader

tiny-mac-bootloader is a tiny, simple, single-stage bootloader designed to load kernel binaries on early 68k Macs.

It was developed in order to easily load kernels for [uclinux-mac-plus](https://github.com/notvelleda/uclinux-mac-plus), a scrapped Linux 6.1 port, and [cenix](https://github.com/notvelleda/cenix)
without requiring the use of a Mac OS application, however it can be used to load any kernel so long as it's a valid ELF file.

Being a single-stage bootloader on the 68k Mac platform, its code is restricted to just 1024 bytes in size, so things like sanity checks and validation have had to be mostly or entirely removed.
If the filesystem that the bootloader is installed to is valid (i.e. not corrupted) and the kernel image is a valid big-endian ELF file for the 68k architecture it should work just fine, though.

## Building

In order to build tiny-mac-bootloader you'll need Make (either BSD or GNU Make works) and a 68k toolchain with at least `as` and `ld`
([crosstool-NG](https://crosstool-ng.github.io/) is a good option for building one if you don't already have one on hand).

The contents of the boot block can be built with the following command:
```sh
make boot_block.bin
```

If your toolchain isn't in your shell's `PATH` or if your toolchain's prefix (the bit that comes before `as` or `ld`) is something other than `m68k-unknown-elf-`,
you'll need to specify it when building the boot block like so:
```sh
make CROSS=<insert prefix here> boot_block.bin
```

In order to build the installer tool you'll need Make as before and a valid C toolchain for whatever platform you're going to run the installer on.

The installer tool can be built with the following command:
```sh
make installer
```

## Installation

Installation of tiny-mac-bootloader differs based on whether you're installing it to a floppy disk (or really any disk image on Mini vMac) or a SCSI hard disk.
The Mac Hard Disk 20 has not been tested as of yet, so compatibility and installation steps are unknown.

### Floppy Disk/Mini vMac Disk Image Installation

Installing to a floppy disk or a disk image for Mini vMac is incredibly simple, and can be done in two steps:

1. First, the disk or disk image must be formatted as ext2 or ext3.
   This can be done on a modern Linux system with a command like one of the following, however this should be easy to do on any OS with ext2/3 support:
   
   ```sh
   mke2fs -t ext2 /path/to/device/or/image
   mke2fs -t ext3 /path/to/device/or/image
   ```
3. Once the disk is formatted, the first 1024 bytes of it must be overwritten with the contents of the boot block.
   This can be done with something like `dd` using a command like the following, however there are probably plenty of other ways to do the same thing:
   
   ```sh
   dd if=boot_block.bin of=/path/to/device/or/image conv=notrunc
   ```
   It's important that this be done after the formatting step, as at least on Linux `mke2fs` likes to overwrite the first 1024 bytes,
   which is where tiny-mac-bootloader lives, so if these steps were to be done in reverse order the resulting disk would not be bootable.

At this point, the disk or disk image should be ready to boot in the machine, emulated or otherwise, of your choice!

### SCSI Hard Disk Installation

Unfortunately, installing to a hard disk is significantly more complicated than installing to a floppy disk.

If the hard disk is already bootable or if you have a disk image that's already bootable,
you can simply follow the above steps for installing to a floppy disk on the existing Mac OS or otherwise bootable partition.

If the disk isn't already bootable or isn't partitioned, the included installer tool can format it to a bootable state and install tiny-mac-bootloader on it.
You can do this with a command like the following:
```sh
./installer -b boot_block.bin -d scsi_hdd_driver.bin -s /path/to/device/or/image
```
Please note that this installer tool is still very experimental and subject to change, and it currently doesn't support making multiple partitions yet.
Additionally, as it writes the boot block image immediately after creating the partition table, there's the possibility that formatting the partition will overwrite the boot block image.
If this occurs, the installer tool can simply be run again since the layout of the partition table only depends on the provided driver binary and the size of the disk.

## Usage

Using tiny-mac-bootloader is incredibly simple: all it requires is the kernel image and a file containing the kernel's arguments to be placed in the root directory of the filesystem it's installed to.

The kernel should be named "kernel" (without the quotes) and the arguments file should be named "cmdline",
however the names of these files can be changed by editing [boot_block.s](boot_block.s) as long as there's space in the boot block to store them.

While booting, tiny-mac-bootloader will show its progress by slowly filling the screen white, moving from left to right then top to bottom.
Once the kernel has finished loading files, it will start filling the screen black briefly before starting the kernel.

### Error Codes

If something goes wrong in the boot process, a Sad Mac screen will be triggered.

A list of all current error codes and their explanations are shown below:

| Code     | Meaning                                                                                                                            |
|----------|------------------------------------------------------------------------------------------------------------------------------------|
| `0FE600` | The filesystem in the partition that tiny-mac-bootloader is installed to has a bad magic number, or is otherwise not ext2 or ext3. |
| `0FE601` | Either the kernel or the kernel arguments file couldn't be located.                                                                |
| `0FE602` | An error occured while reading from disk.                                                                                          |

If a Sad Mac screen is shown but its error code doesn't match one of the ones in this list, something probably went very wrong and if the error is reproducible it should be filed as a bug report.

### ABI

The interface that tiny-mac-bootloader provides to kernels is quite simple: When the kernel starts execution, the stack pointer will be located close to the end of RAM,
and the kernel's entry point will be called with the pointer to the arguments loaded from the arguments file as an argument in accordance with the 68k C ABI.

Additionally, interrupts will be disabled and the cursor will be hidden at the time the kernel is started.

## Compatibility

The following machines have had tiny-mac-bootloader tested and confirmed working so far.
An asterisk (*) following a machine name indicates that it has only been tested in an emulator, and thus its compatibility can't be completely guaranteed.

The absence of a machine from this list doesn't necessarily mean that it's incompatible, just that its compatibility is unknown, and as such could either work perfectly or not work at all.
If you've tested tiny-mac-bootloader on a machine not on this list and can confirm it to fully work, or have confirmed it to work on real hardware where it had only been tested on an emulator before,
please open an issue or a pull request so the list can be updated.

- Macintosh 128K*
- Macintosh Plus
