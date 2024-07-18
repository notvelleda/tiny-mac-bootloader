#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

const char *usage = "usage: %s [-bdehs] <device>\n";
const char *options =
    "\n"
    "options:\n"
    " -b <boot block>    specifies the boot block image that should be written to the drive\n"
    " -d <driver file>   specifies the driver that should be used\n"
    " -e <driver file>   extracts the driver from the device\n"
    " -f                 forces installation, assumes \"yes\" for all safety prompts\n"
    " -h                 displays this help message\n"
    " -s                 single partition mode: create one large partition on the drive and install the bootloader to it\n";

/*
 * Apple Partition Map/Apple Driver Map definitions from https://ftp.netbsd.org/pub/NetBSD/NetBSD-current/src/sys/sys/bootblock.h
 */

/*
 *	Driver Descriptor Map, from Inside Macintosh: Devices, SCSI Manager
 *	pp 12-13.  The driver descriptor map always resides on physical block 0.
 */
struct apple_drvr_descriptor {
    uint32_t	desc_block;	/* first block of driver */
    uint16_t	desc_size;	/* driver size in blocks */
    uint16_t	desc_type;	/* system type */
} __attribute__((packed));

/*
 *	system types; Apple reserves 0-15
 */
#define	APPLE_DRVR_TYPE_MACINTOSH	1

#define	APPLE_DRVR_MAP_MAGIC		0x4552
#define	APPLE_DRVR_MAP_MAX_DESCRIPTORS	61

struct apple_drvr_map {
    uint16_t	sb_sig;			/* map signature */
    uint16_t	sb_block_size;	/* block size of device */
    uint32_t	sb_blk_count;	/* number of blocks on device */
    uint16_t	sb_dev_type;	/* (used internally by ROM) */
    uint16_t	sb_dev_id;		/* (used internally by ROM) */
    uint32_t	sb_data;		/* (used internally by ROM) */
    uint16_t	sb_drvr_count;	/* number of driver descriptors */
    struct apple_drvr_descriptor sb_dd[APPLE_DRVR_MAP_MAX_DESCRIPTORS];
    uint16_t	pad[3];
} __attribute__((packed));

/*
 *	Partition map structure from Inside Macintosh: Devices, SCSI Manager
 *	pp. 13-14.  The partition map always begins on physical block 1.
 *
 *	With the exception of block 0, all blocks on the disk must belong to
 *	exactly one partition.  The partition map itself belongs to a partition
 *	of type `APPLE_PARTITION_MAP', and is not limited in size by anything
 *	other than available disk space.  The partition map is not necessarily
 *	the first partition listed.
 */
#define	APPLE_PART_MAP_ENTRY_MAGIC	0x504d

struct apple_part_map_entry {
    uint16_t	pm_sig;				/* partition signature */
    uint16_t	pm_sig_pad;			/* (reserved) */
    uint32_t	pm_map_blk_cnt;		/* number of blocks in partition map */
    uint32_t	pm_py_part_start;	/* first physical block of partition */
    uint32_t	pm_part_blk_cnt;	/* number of blocks in partition */
    uint8_t		pm_part_name[32];	/* partition name */
    uint8_t		pm_part_type[32];	/* partition type */
    uint32_t	pm_lg_data_start;	/* first logical block of data area */
    uint32_t	pm_data_cnt;		/* number of blocks in data area */
    uint32_t	pm_part_status;		/* partition status information */
/*
 * Partition Status Information from Apple Tech Note 1189
 */
#define	APPLE_PS_VALID			0x00000001	/* Entry is valid */
#define	APPLE_PS_ALLOCATED		0x00000002	/* Entry is allocated */
#define	APPLE_PS_IN_USE			0x00000004	/* Entry in use */
#define	APPLE_PS_BOOT_INFO		0x00000008	/* Entry contains boot info */
#define	APPLE_PS_READABLE		0x00000010	/* Entry is readable */
#define	APPLE_PS_WRITABLE		0x00000020	/* Entry is writable */
#define	APPLE_PS_BOOT_CODE_PIC	0x00000040	/* Boot code has position independent code */
#define	APPLE_PS_CC_DRVR		0x00000100	/* Partition contains chain-compatible driver */
#define	APPLE_PS_RL_DRVR		0x00000200	/* Partition contains real driver */
#define	APPLE_PS_CH_DRVR		0x00000400	/* Partition contains chain driver */
#define	APPLE_PS_AUTO_MOUNT		0x40000000	/* Mount automatically at startup */
#define	APPLE_PS_STARTUP		0x80000000	/* Is the startup partition */
    uint32_t	pm_lg_boot_start;	/* first logical block of boot code */
    uint32_t	pm_boot_size;		/* size of boot code, in bytes */
    uint32_t	pm_boot_load;		/* boot code load address */
    uint32_t	pm_boot_load2;		/* (reserved) */
    uint32_t	pm_boot_entry;		/* boot code entry point */
    uint32_t	pm_boot_entry2;		/* (reserved) */
    uint32_t	pm_boot_cksum;		/* boot code checksum */
    int8_t		pm_processor[16];	/* processor type (e.g. "68020") */
    uint8_t		reserved[376];		/* pad to end of block */
};

#define	APPLE_PART_TYPE_DRIVER			"Apple_Driver"
#define	APPLE_PART_TYPE_DRIVER43		"Apple_Driver43"
#define	APPLE_PART_TYPE_DRIVERATA		"Apple_Driver_ATA"
#define	APPLE_PART_TYPE_DRIVERIOKIT		"Apple_Driver_IOKit"
#define	APPLE_PART_TYPE_FWDRIVER		"Apple_FWDriver"
#define	APPLE_PART_TYPE_FREE			"Apple_Free"
#define	APPLE_PART_TYPE_MAC				"Apple_HFS"
#define	APPLE_PART_TYPE_PATCHES			"Apple_Patches"
#define	APPLE_PART_TYPE_PARTMAP			"Apple_partition_map"
#define	APPLE_PART_TYPE_SCRATCH			"Apple_Scratch"
#define	APPLE_PART_TYPE_UNIX			"Apple_UNIX_SVR2"

int32_t big_to_native_endian_32(int32_t value) {
    uint8_t *p = (uint8_t *) &value;
    int32_t res = 0;

    for (int i = 0; i < sizeof(int32_t); i ++)
        res = (res << 8) + p[i];
    return res;
}

int16_t big_to_native_endian_16(int16_t value) {
    uint8_t *p = (uint8_t *) &value;
    int16_t res = 0;

    for (int i = 0; i < sizeof(int16_t); i ++)
        res = (res << 8) + p[i];
    return res;
}

int32_t native_to_big_endian_32(int32_t value) {
    int32_t res = 0;
    uint8_t *p = (uint8_t *) &res;

    for (int i = sizeof(int32_t) - 1; i >= 0; i --) {
        p[i] = value & 0xff;
        value >>= 8;
    }
    return res;
}

int16_t native_to_big_endian_16(int16_t value) {
    int16_t res = 0;
    uint8_t *p = (uint8_t *) &res;
    int i;

    for (i = sizeof(int16_t) - 1; i >= 0; i --) {
        p[i] = value & 0xff;
        value >>= 8;
    }
    return res;
}

void *checked_malloc(size_t size) {
    void *result = malloc(size);
    if (result == NULL) {
        fprintf(stderr, "failed to allocate memory\n");
        exit(1);
    }
    return result;
}

/*
 * extracts the drivers from a formatted device and dumps them into a file
 *
 * the dump is in the following format:
 *  block size in bytes (2 bytes, big endian)
 *  reserved data from partition map header (376 bytes)
 *  any number of drivers in the following format:
 *   driver type (2 bytes, big endian)
 *   driver size in blocks (2 bytes, big endian)
 *   driver data of that same length
 */
void extract_driver(FILE *device, const char *filename) {
    FILE *output = fopen(filename, "wb");

    if (output == NULL) {
        perror("failed to open output file");
        exit(1);
    }

    void *driver_map_block = checked_malloc(512);

    fseek(device, 0, SEEK_SET);
    if (fread(driver_map_block, 512, 1, device) != 1) {
device_read_failed:
        fprintf(stderr, "failed to read from device file\n");
free_and_exit:
        free(driver_map_block);
        fclose(output);
        exit(1);
    }

    struct apple_drvr_map *driver_map = (struct apple_drvr_map *) driver_map_block;

    if (big_to_native_endian_16(driver_map->sb_sig) != APPLE_DRVR_MAP_MAGIC) {
        fprintf(stderr, "invalid driver map magic number\n");
        goto free_and_exit;
    }

    if (fwrite(&driver_map->sb_block_size, sizeof(driver_map->sb_block_size), 1, output) != 1) {
output_write_failed:
        fprintf(stderr, "failed to write to output file\n");
        goto free_and_exit;
    }

    struct apple_part_map_entry *partition_header = checked_malloc(sizeof(struct apple_part_map_entry));

    if (fread(partition_header, sizeof(struct apple_part_map_entry), 1, device) != 1) {
        fprintf(stderr, "failed to read partition map header from device\n");
        free((void *) partition_header);
        goto free_and_exit;
    }

    if (fwrite(partition_header->reserved, sizeof(partition_header->reserved), 1, output) != 1) {
        free((void *) partition_header);
        goto output_write_failed;
    }

    free((void *) partition_header);

    uint16_t block_size = big_to_native_endian_16(driver_map->sb_block_size);
    uint16_t num_descriptors = big_to_native_endian_16(driver_map->sb_drvr_count);

    void *buffer = checked_malloc(block_size);

    for (int i = 0; i < num_descriptors; i ++) {
        struct apple_drvr_descriptor *descriptor = &driver_map->sb_dd[i];

        if (
            fwrite(&descriptor->desc_type, sizeof(descriptor->desc_type), 1, output) != 1
            || fwrite(&descriptor->desc_size, sizeof(descriptor->desc_size), 1, output) != 1
        ) {
            free(buffer);
            goto output_write_failed;
        }

        fseek(device, big_to_native_endian_32(descriptor->desc_block) * block_size, SEEK_SET);

        uint16_t size_blocks = big_to_native_endian_16(descriptor->desc_size);
        for (int j = 0; j < size_blocks; j ++) {
            if (fread(buffer, block_size, 1, device) != 1) {
                free(buffer);
                goto device_read_failed;
            }
            if (fwrite(buffer, block_size, 1, output) != 1) {
                free(buffer);
                goto output_write_failed;
            }
        }
    }

    free(buffer);
    free(driver_map_block);
    fclose(output);

    printf("dumped drivers to %s\n", filename);
}

int main(int argc, char **argv) {
    char c;
    char *boot_block_path = NULL;
    char *driver_path = NULL;
    char *extract_path = NULL;
    bool single_partition_mode = false;
    bool force = false;

    opterr = 0;
    while ((c = getopt(argc, argv, "b:d:e:fhs")) != -1)
        switch (c) {
        case 'b':
            boot_block_path = optarg;
            break;
        case 'd':
            driver_path = optarg;
            break;
        case 'e':
            extract_path = optarg;
            break;
        case 'f':
            force = true;
            break;
        case 'h':
            printf(usage, argv[0]);
            printf(options);
            return 0;
        case 's':
            single_partition_mode = true;
            break;
        case '?':
            fprintf(stderr, "unknown option -%c\n", optopt);
            return 1;
        }

    if (optind >= argc) {
        fprintf(stderr, usage, argv[0]);
        return 1;
    }

    if (!single_partition_mode && extract_path == NULL) {
        fprintf(stderr, "please specify either -s or -e\n");
        return 1;
    }

    FILE *device;

    if (single_partition_mode)
        device = fopen(argv[optind], "r+b");
    else
        device = fopen(argv[optind], "rb");

    if (device == NULL) {
        perror("failed to open device file");
        return 1;
    }

    if (extract_path != NULL) {
        extract_driver(device, extract_path);
        fseek(device, 0, SEEK_SET);
    }

    if (!single_partition_mode)
        return 0;

    if (boot_block_path == NULL) {
        fprintf(stderr, "-b is required\n");
        return 1;
    }

    FILE *driver_file = NULL;

    if (driver_path != NULL) {
        driver_file = fopen(driver_path, "rb");

        if (driver_file == NULL) {
            perror("failed to open driver dump");
            return 1;
        }
    }

    // TODO: ask user for confirmation to overwrite data if -f is not specified

    struct stat device_stat;
    if (fstat(fileno(device), &device_stat) != 0) {
        perror("failed to stat device");
        return 1;
    }

    uint16_t block_size = 512;

    if (driver_file != NULL) {
        if (fread(&block_size, sizeof(block_size), 1, driver_file) != 1) {
driver_read_failed:
            fprintf(stderr, "failed to read from driver dump\n");
            fclose(driver_file);
            fclose(device);
            return 1;
        }

        block_size = big_to_native_endian_16(block_size);
    }

    struct apple_drvr_map *driver_map = checked_malloc(sizeof(struct apple_drvr_map));
    memset((void *) driver_map, 0, sizeof(struct apple_drvr_map));

    driver_map->sb_sig = native_to_big_endian_16(APPLE_DRVR_MAP_MAGIC);
    driver_map->sb_block_size = native_to_big_endian_16(block_size);
    driver_map->sb_blk_count = native_to_big_endian_32(device_stat.st_size / block_size);
    /* do these fields matter? */
    driver_map->sb_dev_type = native_to_big_endian_16(1);
    driver_map->sb_dev_id = native_to_big_endian_16(1);

    uint32_t first_free_block = 4;

    /* copy drivers from dump and populate fields in driver_map */
    if (driver_file != NULL) {
        fseek(device, first_free_block * block_size, SEEK_SET);
        fseek(driver_file, 376 + 2, SEEK_SET);

        void *buffer = checked_malloc(block_size);
        int i;

        for (i = 0;; i ++) {
            uint16_t type;
            uint16_t size_big_endian;

            if (
                fread(&type, sizeof(type), 1, driver_file) != 1
                || fread(&size_big_endian, sizeof(size_big_endian), 1, driver_file) != 1
            )
                break;

            uint16_t size = big_to_native_endian_16(size_big_endian);

            struct apple_drvr_descriptor *descriptor = &driver_map->sb_dd[i];
            descriptor->desc_block = native_to_big_endian_32(ftell(device) / block_size);
            descriptor->desc_size = size_big_endian;
            descriptor->desc_type = type;

            for (int j = 0; j < size; j ++) {
                if (fread(buffer, block_size, 1, driver_file) != 1) {
                    free(buffer);
                    free(driver_map);
                    goto driver_read_failed;
                }

                if (fwrite(buffer, block_size, 1, device) != 1) {
                    free(buffer);
                    free(driver_map);
                    goto device_write_failed;
                }
            }
        }

        free(buffer);

        driver_map->sb_drvr_count = native_to_big_endian_16(i);
        first_free_block = ((ftell(device) / block_size) + 3) & ~3;
    }

    /* write driver map to device */
    fseek(device, 0, SEEK_SET);

    if (fwrite((void *) driver_map, sizeof(struct apple_drvr_map), 1, device) != 1) {
device_write_failed:
        fprintf(stderr, "failed to write to device\n");
        free(driver_map);
        fclose(driver_file);
        fclose(device);
        return 1;
    }

    struct apple_part_map_entry *partition_header = checked_malloc(sizeof(struct apple_part_map_entry));
    memset((void *) partition_header, 0, sizeof(struct apple_part_map_entry));

    partition_header->pm_sig = native_to_big_endian_16(APPLE_PART_MAP_ENTRY_MAGIC);
    partition_header->pm_map_blk_cnt = native_to_big_endian_32(1);
    partition_header->pm_py_part_start = native_to_big_endian_32(first_free_block);
    partition_header->pm_part_blk_cnt = partition_header->pm_data_cnt = native_to_big_endian_32((device_stat.st_size / block_size) - first_free_block);
    uint32_t status = APPLE_PS_VALID | APPLE_PS_ALLOCATED | APPLE_PS_IN_USE | APPLE_PS_BOOT_INFO | APPLE_PS_READABLE | APPLE_PS_WRITABLE | APPLE_PS_BOOT_CODE_PIC;
    partition_header->pm_part_status = native_to_big_endian_32(status);
    strcpy(partition_header->pm_processor, "68000");

    fseek(driver_file, 2, SEEK_SET);
    if (fread(partition_header->reserved, sizeof(partition_header->reserved), 1, driver_file) != 1) {
        free(partition_header);
        goto driver_read_failed;
    }

    /* write partition header to device */
    fseek(device, block_size, SEEK_SET);

    if (fwrite((void *) partition_header, sizeof(struct apple_part_map_entry), 1, device) != 1) {
        free(partition_header);
        goto device_write_failed;
    }

    free(partition_header);

    uint32_t boot_block_size = 1024;
    void *boot_block_data = checked_malloc(boot_block_size);

    FILE *boot_block_file = fopen(boot_block_path, "rb");
    if (boot_block_file == NULL) {
        perror("failed to open boot block file");
        free(driver_map);
        free(boot_block_data);
        fclose(driver_file);
        fclose(device);
        return 1;
    }

    if (fread(boot_block_data, boot_block_size, 1, boot_block_file) != 1) {
        fprintf(stderr, "failed to read boot block file\n");
        free(driver_map);
        free(boot_block_data);
        fclose(boot_block_file);
        fclose(driver_file);
        fclose(device);
        return 1;
    }

    fseek(device, first_free_block * block_size, SEEK_SET);
    if (fwrite(boot_block_data, boot_block_size, 1, device) != 1) {
        free(boot_block_data);
        fclose(boot_block_file);
        goto device_write_failed;
    }

    free(driver_map);
    free(boot_block_data);
    fclose(boot_block_file);
    fclose(driver_file);
    fclose(device);

    return 0;
}
