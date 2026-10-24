# Reading a Windows guest's disk on the HarmonyOS host

Read-only inspection of a StratoVirt `vm.qcow2` holding Windows (used on the
Oseasy backup `/data/local/backup/oseasy-win11-20261024/`), as root on ohdev,
with nothing written to the source:

```sh
SI=/system/bin/virt_service/vm_engine/stratovirt/stratovirt-img
$SI convert -f qcow2 -O raw vm.qcow2 /data/local/kaidashi/oseasy/win.raw   # sparse
# 7-Zip 23.01 linux-arm64 (7-zip.org) is glibc-linked; borrow route D's loader read-only:
R=/proc/$(cat /data/local/archtest/session.pid)/root
Z="$R/usr/lib/ld-linux-aarch64.so.1 --library-path $R/usr/lib /data/local/kaidashi/bin/7zz"
$Z l -slt win.raw                      # GPT: partition offsets and sizes
PYTHONHOME=$R/usr $R/usr/lib/ld-linux-aarch64.so.1 --library-path $R/usr/lib \
  $R/usr/bin/python3.14 slice.py win.raw OFFSET SIZE c.ntfs   # sparse copy of C:
$Z l c.ntfs 'Windows/System32/DriverStore/FileRepository/*' -r
$Z x -ox c.ntfs Windows/System32/config/SYSTEM ...
```

`slice.py` copies a byte range with `SEEK_DATA`/`SEEK_HOLE`, so a 300 GB
partition with 22 GB of data takes 22 GB and a couple of minutes. Registry
hives were read on the Mac with [regipy](https://github.com/mkorman90/regipy).
Delete `win.raw` and `c.ntfs` afterwards.
