# oh-ssh: root ssh into a HarmonyOS PC

HarmonyOS has no OpenSSH. This directory is everything the test machines (ohdev,
ohdev2) run for `ssh <machine>` from a Mac: a small Go ssh server, a helper that
gives it hdcd's access token, frpc for reaching it from outside, and an init
service that starts them at boot. The machine-specific secrets (frp server and
token, keys) are not here; the steps below say where they go.

| File | On the device | What it is |
|---|---|---|
| `src/ohsshd` | `/data/oh-ssh/ohsshd` | ssh server (gliderlabs/ssh): public keys, pty, commands through `-shell`; no sftp/scp |
| `src/ohtoken` | `/data/oh-ssh/ohtoken` | `ohtoken get`, `ohtoken run TOKENID cmd…` via `/dev/access_token_id` |
| frpc 0.61.2 | `/data/oh-ssh/frp/frpc` | upstream release, fetched by `build.sh` |
| `frpc.toml.example` | `/data/oh-ssh/frp/frpc-office.toml` | fill in server, token, proxy name, remote port |
| `boot-start.sh` | `/data/oh-ssh/boot-start.sh` | supervisor: (re)starts ohsshd (under hdcd's token) and frpc every 30 s |
| `shell.sh` | `/data/oh-ssh/shell.sh` | login shell: `/etc/profile`, then `/system/bin/sh` |
| `restart-sshd.sh`, `status.sh` | `/data/oh-ssh/` | restart ohsshd by hand; show processes and log tails |
| `ohssh.cfg` | `/system/etc/init/ohssh.cfg` | init service, boot mode, root, `u:r:su:s0` |

`ohsshd` and `ohtoken` were rebuilt from these sources on 2026-10-27 after the
originals' sources were lost; the rebuilds were checked on ohdev2 against the
running originals: the same host key file loads, commands, exit codes, stdin,
a 5 MB stream, a pty, `snapshot_display` under hdcd's token, and `ohtoken get`
printing the same `805465087 0`.

## Why hdcd's token

Processes started by init get their service's access token. Under the ssh
service's own token, `snapshot_display` and `uitest` fail with "operation not
permitted". `boot-start.sh` reads hdcd's token id from
`/data/service/el0/access_token/nativetoken.json` and starts ohsshd with
`ohtoken run <id>`, so ssh sessions can do what `hdc shell` can.

## New machine, from nothing

Needs: a HarmonyOS PC on a research build where `hdc shell` is root
(`const.boot.oemmode=rd`; `id` says `uid=0` and `context=u:r:su:s0`) and
`/system` is an overlay mounted read-write (`mount | grep ' /system '`); a
computer with hdc and a USB cable; Go on the build machine.

1. Build: `sh build.sh` (gives `out/ohsshd`, `out/ohtoken`, `out/frpc`).
2. Prepare `/data/oh-ssh` locally:

   ```
   oh-ssh/ohsshd ohtoken shell.sh boot-start.sh restart-sshd.sh status.sh
   oh-ssh/keys/authorized_keys          # your public key(s), OpenSSH format
   oh-ssh/frp/frpc
   oh-ssh/frp/frpc-office.toml          # from frpc.toml.example, filled in
   ```

   Give each machine its own proxy name and remote port.
3. Copy and install over USB:

   ```
   tar cf oh-ssh.tar oh-ssh ohssh.cfg
   hdc file send oh-ssh.tar /data/local/tmp/oh-ssh.tar
   hdc shell
   cd /data && tar xf /data/local/tmp/oh-ssh.tar && rm /data/local/tmp/oh-ssh.tar
   chmod 755 /data/oh-ssh/*.sh /data/oh-ssh/ohsshd /data/oh-ssh/ohtoken /data/oh-ssh/frp/frpc
   chmod 700 /data/oh-ssh/keys; chmod 600 /data/oh-ssh/keys/authorized_keys
   mv /data/ohssh.cfg /system/etc/init/ohssh.cfg && chmod 644 /system/etc/init/ohssh.cfg
   ```

   The host key is generated on first start (`/data/oh-ssh/ohsshd_hostkey`).
4. Start it now without rebooting (init reads cfgs only at boot):

   ```
   setsid nohup /system/bin/sh /data/oh-ssh/boot-start.sh < /dev/null > /dev/null 2>&1 &
   ```

   `sh /data/oh-ssh/status.sh` should show ohsshd and frpc, and `frpc.log`
   "start proxy success".
5. On the Mac, `~/.ssh/config`:

   ```
   Host MACHINE
       HostName FRP_SERVER_HOST
       Port REMOTE_PORT
       User root
       IdentityFile ~/.ssh/KEY
       IdentitiesOnly yes
       StrictHostKeyChecking accept-new
       ServerAliveInterval 10
       ConnectTimeout 60
   ```

   On the same network, `ssh -p 2222 root@<its address>` works without frp.
6. Reboot and check `ssh MACHINE` comes back by itself (about 30 s after boot on
   ohdev2); `/data/oh-ssh/boot-start.log` shows "supervisor start".

To remove it: delete `/system/etc/init/ohssh.cfg` (it is in the overlay) and
`/data/oh-ssh`.

## Things to know

- ohsshd reads `authorized_keys` only when it starts. After adding a key, kill
  ohsshd (by name: `cat /proc/*/comm`) and the supervisor restarts it within
  30 s, or run `restart-sshd.sh`.
- Remote commands go through `sh -c`, and quotes nested in the ssh command line
  come out mangled. Pass anything non-trivial on stdin:
  `ssh MACHINE sh -s <<'EOF' … EOF`.
- No sftp or scp. Copy with `ssh MACHINE 'cat f' > f` or tar pipes. ohdev2's
  `/usr/bin/scp` also aborts when receiving ("umask: called with invalid mask").
- HongMeng: reading `/proc/<pid>/cmdline` of a process that is exiting can
  hang forever. `boot-start.sh` reads it only after `kill -0`, in the
  background, for at most 3 s; elsewhere match by `/proc/<pid>/comm`.
- `/root` is read-only on these machines. Keep client keys and ssh configs
  under `/data` and pass `ssh -F`.
