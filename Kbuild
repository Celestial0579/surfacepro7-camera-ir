# SPDX-License-Identifier: GPL-2.0-only
#
# Kbuild for the surfacepro7-camera-ir sensor and ACPI-glue modules.
#
# The IPU4P ISP stack lives in src/intel-ipu4/ and is built by its own
# (upstream-derived) Makefile; see the top-level Makefile, target modules-ipu4.
#
# Build with:
#   make -C /lib/modules/$(uname -r)/build M=$PWD modules
# which builds the four modules below. Use the top-level `make modules`
# target to build the complete stack in one go.

obj-m += ov5693.o
obj-m += ov8865.o
obj-m += ov7251.o
obj-m += surfacepro7_acpi.o

ov5693-objs		:= src/ov5693.o
ov8865-objs		:= src/ov8865.o
ov7251-objs		:= src/ov7251.o
surfacepro7_acpi-objs	:= src/surfacepro7_acpi.o

ccflags-y += -I$(src)/src
