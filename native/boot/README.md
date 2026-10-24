# Starting the native desktop at boot

`ohmarchy-desktop.cfg` is an init service in the format of the existing root ssh
service: after `bootevent.boot.completed` it runs `boot-start.sh`, which starts
route D's session, `vtest-broker` and the desktop. Opening the display app then
(re)starts the desktop for it.

Install (takes effect at the next boot). Installed on the test machine on
2026-10-24, checked statically (JSON valid, same bytes as here); not yet
verified by a reboot:

    cp boot-start.sh /data/local/archtest/boot-start.sh
    cp ohmarchy-desktop.cfg /mnt/overlay/usr/upper/etc/init/   # the /system overlay

Remove: delete the .cfg from the overlay. A failing service does not stop boot.
