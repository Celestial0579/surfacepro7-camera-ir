# include/

The driver's public headers (the ones the patched kernel-API surface of this
out-of-tree stack needs, which mainline does not export to external modules)
live next to the driver sources so that the upstream-derived include paths
resolve unchanged:

```
src/intel-ipu4/include/media/ipu-isys.h
src/intel-ipu4/include/uapi/linux/ipu-isys.h
src/intel-ipu4/include/uapi/linux/ipu-isys-isa-fw.h
src/intel-ipu4/include/uapi/linux/ipu-psys.h
src/intel-ipu4/include/uapi/linux/ipu4-v4l2.h
```

`src/intel-ipu4/drivers/media/pci/intel/ipu4/Makefile` adds them with
`-I$(srcpath)/$(src)/../../../../../include` and `.../include/uapi`, so the
directory depth must stay as shipped. This file only exists to document that
layout; nothing is installed from here.
