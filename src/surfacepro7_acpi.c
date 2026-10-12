// SPDX-License-Identifier: GPL-2.0-only
/*
 * surfacepro7_acpi.c - Surface Pro 7 (Intel Ice Lake, IPU4P) camera ACPI glue
 *
 * Copyright (C) 2026 surfacepro7-camera-ir contributors
 *
 * This module is the ACPI / power-sequencing companion of the out-of-tree
 * IPU4P camera stack shipped by the surfacepro7-camera-ir package.
 *
 * Responsibilities:
 *   - confirm the machine is a Surface Pro 7 (DMI) and expose that fact via
 *     a DMI modalias so udev only autoloads it there;
 *   - enumerate the camera ACPI devices (sensor: INT33BE/OV5693,
 *     INT347A/OV8865, INT347E/OV7251 IR; power/clock: INT3472);
 *   - report the power sequencing resources (ACPI power resources _PR0/_PR3,
 *     _DSM presence) that the sensor and INT3472 drivers consume;
 *   - optionally force the sensor ACPI devices into D0 so a manual modprobe
 *     sequence can be recovered after a failed probe;
 *   - publish a read-only sysfs summary under
 *     /sys/kernel/surfacepro7_camera_ir/.
 *
 * IR illuminator: the Surface Pro 7 has no ACPI or GPIO illuminator
 * resource. The IR LED is driven from the OV7251 sensor's own STROBE /
 * frame-PWM output, which the companion ov7251 module controls through the
 * `experimental_strobe_output` module parameter (see README.md, section
 * "IR illuminator"). Because there is no discrete ACPI/GPIO illuminator
 * control, no V4L2 illuminator control is fabricated here; the intended
 * userspace interface is recorded as a TODO in the README.
 */

#include <linux/acpi.h>
#include <linux/dmi.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/string.h>
#include <linux/sysfs.h>

#define SP7_IPU4P_PCI_VENDOR	0x8086
#define SP7_IPU4P_PCI_DEVICE	0x8a19

#define SP7_NUM_SENSORS		3

#define SP7_INT3472_HID		"INT3472"
#define SP7_INT3472_MAX		8

/* Same order as the media links the IPU4P ISYS driver creates. */
static const char * const sp7_sensor_hid[SP7_NUM_SENSORS] = {
	"INT33BE",	/* front camera, OV5693 */
	"INT347A",	/* rear camera,  OV8865 */
	"INT347E",	/* IR camera,    OV7251 */
};

static const char * const sp7_sensor_name[SP7_NUM_SENSORS] = {
	"front(ov5693)",
	"rear(ov8865)",
	"ir(ov7251)",
};

static const struct dmi_system_id sp7_dmi_table[] __initconst = {
	{
		.ident = "Microsoft Surface Pro 7",
		.matches = {
			DMI_MATCH(DMI_SYS_VENDOR, "Microsoft Corporation"),
			DMI_MATCH(DMI_PRODUCT_NAME, "Surface Pro 7"),
		},
	},
	{ }
};
MODULE_DEVICE_TABLE(dmi, sp7_dmi_table);

struct sp7_sensor {
	struct acpi_device *adev;	/* holds a reference while loaded */
	bool present;
	bool d0_forced;
	bool has_pr0;
	bool has_pr3;
	bool has_dsm;
};

static struct sp7_sensor sp7_sensors[SP7_NUM_SENSORS];
static unsigned int sp7_int3472_count;
static bool sp7_ipu4p_present;
static struct kobject *sp7_kobj;

static bool power_on_sensors;
module_param(power_on_sensors, bool, 0644);
MODULE_PARM_DESC(power_on_sensors,
	"Force the camera sensor ACPI devices into D0 at load time (default: off)");

static const char *sp7_product_name(void)
{
	const char *name = dmi_get_system_info(DMI_PRODUCT_NAME);

	return name ? name : "unknown";
}

static void sp7_power_on_sensors(void)
{
	int i;

	for (i = 0; i < SP7_NUM_SENSORS; i++) {
		struct sp7_sensor *s = &sp7_sensors[i];
		int ret;

		if (!s->present || !s->adev)
			continue;

		ret = acpi_device_set_power(s->adev, ACPI_STATE_D0);
		if (ret) {
			dev_warn(&s->adev->dev,
				 "surfacepro7_acpi: failed to force D0: %d\n",
				 ret);
			continue;
		}
		s->d0_forced = true;
		dev_info(&s->adev->dev,
			 "surfacepro7_acpi: forced ACPI power state D0\n");
	}
}

static void sp7_scan(void)
{
	struct acpi_device *adev;
	struct pci_dev *pdev;
	int i;

	pdev = pci_get_device(SP7_IPU4P_PCI_VENDOR, SP7_IPU4P_PCI_DEVICE, NULL);
	if (pdev) {
		sp7_ipu4p_present = true;
		pci_dev_put(pdev);
	}

	for (i = 0; i < SP7_NUM_SENSORS; i++) {
		struct sp7_sensor *s = &sp7_sensors[i];
		acpi_handle handle;

		s->adev = acpi_dev_get_first_match_dev(sp7_sensor_hid[i], NULL, -1);
		if (!s->adev)
			continue;

		s->present = true;
		handle = acpi_device_handle(s->adev);
		s->has_pr0 = acpi_has_method(handle, "_PR0");
		s->has_pr3 = acpi_has_method(handle, "_PR3");
		s->has_dsm = acpi_has_method(handle, "_DSM");

		dev_info(&s->adev->dev,
			 "surfacepro7_acpi: %s present (PR0=%d PR3=%d DSM=%d)\n",
			 sp7_sensor_name[i], s->has_pr0, s->has_pr3, s->has_dsm);
	}

	for_each_acpi_dev_match(adev, SP7_INT3472_HID, NULL, -1) {
		if (sp7_int3472_count < SP7_INT3472_MAX)
			sp7_int3472_count++;
	}
}

static ssize_t ipu4p_show(struct kobject *kobj, struct kobj_attribute *attr,
			  char *buf)
{
	return sysfs_emit(buf, "%s\n", sp7_ipu4p_present ? "present" : "absent");
}

static ssize_t product_show(struct kobject *kobj, struct kobj_attribute *attr,
			    char *buf)
{
	return sysfs_emit(buf, "%s\n", sp7_product_name());
}

static ssize_t sensors_show(struct kobject *kobj, struct kobj_attribute *attr,
			    char *buf)
{
	ssize_t n = 0;
	int i;

	for (i = 0; i < SP7_NUM_SENSORS; i++) {
		struct sp7_sensor *s = &sp7_sensors[i];

		if (!s->present)
			continue;
		n += sysfs_emit_at(buf, n,
				   "%s hid=%s acpi=%s pr0=%d pr3=%d dsm=%d d0_forced=%d\n",
				   sp7_sensor_name[i], sp7_sensor_hid[i],
				   acpi_dev_name(s->adev), s->has_pr0, s->has_pr3,
				   s->has_dsm, s->d0_forced);
	}

	if (!n)
		n = sysfs_emit(buf, "none\n");

	return n;
}

static ssize_t int3472_show(struct kobject *kobj, struct kobj_attribute *attr,
			    char *buf)
{
	return sysfs_emit(buf, "%u\n", sp7_int3472_count);
}

static ssize_t ir_camera_show(struct kobject *kobj, struct kobj_attribute *attr,
			      char *buf)
{
	struct sp7_sensor *s = &sp7_sensors[2];

	if (!s->present)
		return sysfs_emit(buf, "absent\n");

	return sysfs_emit(buf, "present acpi=%s\n", acpi_dev_name(s->adev));
}

static ssize_t ir_illuminator_show(struct kobject *kobj,
				   struct kobj_attribute *attr, char *buf)
{
	return sysfs_emit(buf,
			  "path=ov7251-strobe-frame-pwm\n"
			  "acpi-gpio-resource=none\n"
			  "enable=modprobe ov7251 experimental_strobe_output=1\n"
			  "v4l2-control=todo\n");
}

static ssize_t power_show(struct kobject *kobj, struct kobj_attribute *attr,
			  char *buf)
{
	return sysfs_emit(buf, "power_on_sensors=%d\n", power_on_sensors);
}

static struct kobj_attribute sp7_attr_ipu4p =
	__ATTR_RO(ipu4p);
static struct kobj_attribute sp7_attr_product =
	__ATTR_RO(product);
static struct kobj_attribute sp7_attr_sensors =
	__ATTR_RO(sensors);
static struct kobj_attribute sp7_attr_int3472 =
	__ATTR_RO(int3472);
static struct kobj_attribute sp7_attr_ir_camera =
	__ATTR_RO(ir_camera);
static struct kobj_attribute sp7_attr_ir_illuminator =
	__ATTR_RO(ir_illuminator);
static struct kobj_attribute sp7_attr_power =
	__ATTR_RO(power);

static struct attribute *sp7_attrs[] = {
	&sp7_attr_ipu4p.attr,
	&sp7_attr_product.attr,
	&sp7_attr_sensors.attr,
	&sp7_attr_int3472.attr,
	&sp7_attr_ir_camera.attr,
	&sp7_attr_ir_illuminator.attr,
	&sp7_attr_power.attr,
	NULL,
};
ATTRIBUTE_GROUPS(sp7);

static int __init surfacepro7_acpi_init(void)
{
	int i, ret;

	pr_info("surfacepro7_acpi: Surface Pro 7 IPU4P camera ACPI glue, product=%s\n",
		sp7_product_name());

	if (!dmi_check_system(sp7_dmi_table))
		pr_warn("surfacepro7_acpi: not a Surface Pro 7; telemetry only\n");

	sp7_scan();

	if (power_on_sensors)
		sp7_power_on_sensors();

	sp7_kobj = kobject_create_and_add("surfacepro7_camera_ir",
					  kernel_kobj);
	if (!sp7_kobj) {
		ret = -ENOMEM;
		goto err_put;
	}

	ret = sysfs_create_groups(sp7_kobj, sp7_groups);
	if (ret)
		goto err_kobj;

	pr_info("surfacepro7_acpi: ipu4p=%s sensors=%d int3472=%u\n",
		sp7_ipu4p_present ? "present" : "absent",
		sp7_sensors[0].present + sp7_sensors[1].present +
			sp7_sensors[2].present,
		sp7_int3472_count);

	return 0;

err_kobj:
	kobject_put(sp7_kobj);
	sp7_kobj = NULL;
err_put:
	for (i = 0; i < SP7_NUM_SENSORS; i++) {
		acpi_dev_put(sp7_sensors[i].adev);
		sp7_sensors[i].adev = NULL;
	}

	return ret;
}

static void __exit surfacepro7_acpi_exit(void)
{
	int i;

	if (sp7_kobj) {
		sysfs_remove_groups(sp7_kobj, sp7_groups);
		kobject_put(sp7_kobj);
		sp7_kobj = NULL;
	}

	for (i = 0; i < SP7_NUM_SENSORS; i++) {
		acpi_dev_put(sp7_sensors[i].adev);
		sp7_sensors[i].adev = NULL;
	}

	pr_info("surfacepro7_acpi: unloaded\n");
}

module_init(surfacepro7_acpi_init);
module_exit(surfacepro7_acpi_exit);

MODULE_AUTHOR("surfacepro7-camera-ir contributors");
MODULE_DESCRIPTION("Surface Pro 7 (Intel IPU4P) camera ACPI/power-sequencing glue");
MODULE_LICENSE("GPL");
MODULE_SOFTDEP("pre: intel_ipu4 intel_ipu4_isys intel_ipu4_psys ov5693 ov8865 ov7251");
