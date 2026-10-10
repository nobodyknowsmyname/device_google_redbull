#
# Copyright (C) 2021 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Kernel
TARGET_KERNEL_DIR := device/google/redbull-kernel
TARGET_PREBUILT_KERNEL := $(TARGET_KERNEL_DIR)/Image.lz4
TARGET_PREBUILT_KERNEL_HEADERS := $(TARGET_KERNEL_DIR)/kernel-headers
TARGET_KERNEL_VERSION := 4.19
TARGET_BOARD_KERNEL_HEADERS += $(TARGET_KERNEL_DIR)/kernel-headers
BOARD_PREBUILT_DTBOIMAGE := $(TARGET_KERNEL_DIR)/dtbo.img
BOARD_PREBUILT_DTBIMAGE_DIR := $(TARGET_KERNEL_DIR)

# Kernel modules
BOOT_KERNEL_MODULES += \
    heatmap.ko \
    touch_offload.ko

KERNEL_MODULES := $(wildcard $(TARGET_KERNEL_DIR)/*.ko)
KERNEL_MODULES_LOAD := $(strip $(shell cat $(TARGET_KERNEL_DIR)/modules.load))
BOOT_KERNEL_MODULES_FILTER := $(foreach m,$(BOOT_KERNEL_MODULES),%/$(m))

# Keep all modules in vendor, and copy boot-critical modules to vendor_boot.
BOARD_VENDOR_KERNEL_MODULES := $(KERNEL_MODULES)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(filter $(BOOT_KERNEL_MODULES_FILTER),$(KERNEL_MODULES))
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(filter-out $(BOOT_KERNEL_MODULES), $(KERNEL_MODULES_LOAD))
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(filter $(BOOT_KERNEL_MODULES), $(KERNEL_MODULES_LOAD))

# Partitions
AB_OTA_PARTITIONS += \
    vendor

BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

# SELinux
include device/statix/sepolicy/libion/sepolicy.mk

# Verified Boot
ifneq ($(WITH_AVB),true)
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 3
endif
