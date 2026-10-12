# SPDX-License-Identifier: GPL-2.0-only
#
# surfacepro7-camera-ir - external module build for the Surface Pro 7
# (Intel Ice Lake, IPU4P 8086:8a19) IPU4 camera stack plus the OV5693,
# OV8865 and OV7251 (IR) sensor drivers and the Surface Pro 7 ACPI glue.
#
# Usage:
#   make                       # build everything for the running kernel
#   make KCFLAGS='...'         # override the optimisation flags
#   make DESTDIR=/pkg install  # install modules below a package root
#   make clean
#
# The kernel build tree defaults to /lib/modules/$(uname -r)/build and can be
# overridden with KERNEL_VERSION= or KDIR=.

KERNEL_VERSION	?= $(shell uname -r)
KDIR		?= /lib/modules/$(KERNEL_VERSION)/build

IPU4_SUBDIR	:= src/intel-ipu4/drivers/media/pci/intel
IPU4_MODDIR	:= extra/surfacepro7-camera-ir

# Distro kernels built with clang record that in the build tree; external
# modules must then be built with the LLVM toolchain as well, otherwise the
# clang-only flags recorded in the kernel build break a GCC compile.
KDIR_CC_IS_CLANG := $(shell grep -q '^CONFIG_CC_IS_CLANG=y' \
			$(KDIR)/include/config/auto.conf 2>/dev/null && echo 1)
ifeq ($(KDIR_CC_IS_CLANG),1)
LLVM_ARG	:= LLVM=1
endif

# Optimisation profiles.
#   basic (package A): portable x86-64 baseline
#   v4    (package B): x86-64-v4 code generation, with the FP/SIMD register
#                      classes explicitly disabled again (-mgeneral-regs-only)
#                      because the kernel does not preserve FPU/SIMD state.
KCFLAGS_BASIC	?= -O2 -march=x86-64 -mtune=generic -fno-strict-aliasing
KCFLAGS_V4	?= -O3 -march=x86-64-v4 -mtune=generic -fno-strict-aliasing \
		   -mgeneral-regs-only

ifdef V4
KCFLAGS		?= $(KCFLAGS_V4)
else
KCFLAGS		?= $(KCFLAGS_BASIC)
endif

# Shared flags for both stages.
IPU4_CFG	:= EXTERNAL_BUILD=1 CONFIG_VIDEO_INTEL_IPU4P=y \
		   CONFIG_VIDEO_INTEL_IPU=m CONFIG_VIDEO_INTEL_IPU_FW_LIB=y \
		   KBUILD_MODPOST_WARN=1

.PHONY: all modules modules-ipu4 modules-sensors install install-ipu4 \
	install-sensors clean

all: modules

modules: modules-ipu4 modules-sensors

modules-ipu4:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/$(IPU4_SUBDIR) \
		srcpath=$(CURDIR)/$(IPU4_SUBDIR) $(IPU4_CFG) $(LLVM_ARG) \
		KCFLAGS="$(KCFLAGS)" modules

modules-sensors:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(LLVM_ARG) \
		KCFLAGS="$(KCFLAGS)" modules

install: modules install-ipu4 install-sensors

install-ipu4:
	$(MAKE) -C $(KDIR) M=$(CURDIR)/$(IPU4_SUBDIR) \
		srcpath=$(CURDIR)/$(IPU4_SUBDIR) $(IPU4_CFG) $(LLVM_ARG) \
		KCFLAGS="$(KCFLAGS)" INSTALL_MOD_PATH=$(DESTDIR) \
		INSTALL_MOD_DIR=$(IPU4_MODDIR) modules_install

install-sensors:
	$(MAKE) -C $(KDIR) M=$(CURDIR) $(LLVM_ARG) KCFLAGS="$(KCFLAGS)" \
		INSTALL_MOD_PATH=$(DESTDIR) INSTALL_MOD_DIR=$(IPU4_MODDIR) \
		modules_install

clean:
	-$(MAKE) -C $(KDIR) M=$(CURDIR)/$(IPU4_SUBDIR) \
		srcpath=$(CURDIR)/$(IPU4_SUBDIR) $(IPU4_CFG) clean
	-$(MAKE) -C $(KDIR) M=$(CURDIR) clean
	find $(CURDIR) \( -name '*.o' -o -name '*.ko' -o -name '*.mod' \
		-o -name '*.mod.c' -o -name '.*.cmd' -o -name 'modules.order' \
		-o -name 'Module.symvers' -o -name '.tmp_versions' \) \
		-exec rm -rf {} +
