# SPDX-License-Identifier: GPL-2.0-only
#
# Surface Pro 7 IPU4P (Ice Lake, PCI 8086:8a19) external module build.
#
# This is a trimmed copy of the in-kernel drivers/media/pci/intel/Makefile.
# The ipu3/, ivsc/, ipu6/ and ipu-bridge parts are deliberately not built:
# this package only ships the IPU4/IPU4P out-of-tree stack, and ipu-bridge is
# already provided by the running kernel (the modules import the
# INTEL_IPU_BRIDGE symbol namespace).
#
# force check the compile warning to make sure zero warnings
# note we may have build issue when compiler upgraded.
ccflags-y := -Wno-error=uninitialized
subdir-ccflags-y += $(call cc-disable-warning, unused-parameter)
subdir-ccflags-y += $(call cc-disable-warning, implicit-fallthrough)
subdir-ccflags-y += $(call cc-disable-warning, missing-field-initializers)
subdir-ccflags-y += $(call cc-disable-warning, int-conversion)
subdir-ccflags-y += $(call cc-disable-warning, enum-conversion)
subdir-ccflags-y += $(call cc-disable-warning, uninitialized)

# IPU4P is the Ice Lake variant of the IPU4 family and is what the Surface
# Pro 7 carries. The generation selector is supplied on the make command line
# (CONFIG_VIDEO_INTEL_IPU4P=y) because this driver is not part of any distro
# kernel configuration.
obj-$(CONFIG_VIDEO_INTEL_IPU4P)	+= ipu4/
