# Starting the native desktop at boot (not installed yet)

`ohmarchy-desktop.cfg` is an init service in the format of the existing root ssh
service: after `bootevent.boot.completed` it runs `boot-start.sh`, which starts
route D's session, `vtest-broker` and the desktop. Opening the display app then
(re)starts the desktop for it.

Install (needs a reboot to take effect; not done yet):

    cp boot-start.sh /data/local/archtest/boot-start.sh
    cp ohmarchy-desktop.cfg /mnt/overlay/usr/upper/etc/init/   # the /system overlay

Remove: delete the .cfg from the overlay. A failing service does not stop boot.
