# Starting the native desktop at boot

`ohmarchy-desktop.cfg` is an init service in the format of the existing root ssh
service: after `bootevent.boot.completed` it runs `boot-start.sh`, which starts
route D's session, `vtest-broker`, the desktop and route I's docker gate (the VM
itself starts only when docker is used). Opening the display app then
(re)starts the desktop for it. A run of the hook without a reboot, with the app
and docker used as a user would: `tests/demo/autostart.sh` (2026-10-26, pass;
docs/native-desktop.md).

Install (takes effect at the next boot). Installed on the test machine on
2026-10-24, checked statically (JSON valid, same bytes as here); not yet
verified by a reboot:

    cp boot-start.sh /data/local/archtest/boot-start.sh
    cp ohmarchy-desktop.cfg /mnt/overlay/usr/upper/etc/init/   # the /system overlay

Remove: delete the .cfg from the overlay. A failing service does not stop boot.

## What has been checked without a reboot (2026-10-24)

- Ran: `boot-start.sh` from a cold state (session, broker and desktop stopped), under
  the conditions init gives a service (clean environment with init's service PATH,
  cwd `/`, root, `u:r:su:s0`, detached, stdin `/dev/null`): session, `vtest-broker
  --on-app`, Hyprland (not safe mode) and the 666 socket came up. One round; the
  session is shared with other work, so it is not stopped again for more rounds.
- Static, against OpenHarmony init (`services/init/init_service_manager.c`):
  `start-mode` takes condition/boot/normal; `once` is a plain attribute; standard
  init forbids no path; gid names resolve like ohssh's (root, shell, log, readproc);
  `secon` is applied with setcon, and the init-started ohssh runs as `u:r:su:s0`.
  The job (`bootevent.boot.completed=true` -> `start <name>`) is ohssh's, verbatim.
  Three device cfgs (boot_detector, hwnffserver, xlogcat) use the same
  condition + once + boot-completed pattern.
- Only a reboot shows: init loading the file (`begetctl start_service` before then
  answers "Cannot find service": init reads cfgs at boot).
