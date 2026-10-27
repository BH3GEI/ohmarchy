// ohsshd: a small SSH server for a HarmonyOS PC with a root shell (no OpenSSH there).
// Public-key logins only by default, a pty when the client asks for one, commands run
// through -shell. No sftp/scp subsystem: copy files with `ssh host cat f > f` or tar.
package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/x509"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"syscall"
	"unsafe"

	"github.com/creack/pty"
	"github.com/gliderlabs/ssh"
	gossh "golang.org/x/crypto/ssh"
)

func main() {
	addr := flag.String("addr", "0.0.0.0:2222", "listen address")
	authKeys := flag.String("authkeys", "", "authorized_keys file (OpenSSH format)")
	hostKey := flag.String("hostkey", "/data/local/tmp/ohsshd_hostkey", "host key file (created if missing)")
	password := flag.String("password", "", "password auth (empty = disabled)")
	shell := flag.String("shell", "/bin/sh", "shell binary")
	verbose := flag.Bool("v", false, "log accepted handshakes")
	flag.Parse()

	signer, err := loadHostKey(*hostKey)
	if err != nil {
		log.Fatal(err)
	}
	keys := loadAuthKeys(*authKeys)
	srv := &ssh.Server{
		Addr: *addr,
		Handler: func(s ssh.Session) {
			handle(s, *shell)
		},
		PublicKeyHandler: func(ctx ssh.Context, key ssh.PublicKey) bool {
			for _, k := range keys {
				if ssh.KeysEqual(k, key) {
					if *verbose {
						log.Printf("accepted %s key for %s from %s", key.Type(), ctx.User(), ctx.RemoteAddr())
					}
					return true
				}
			}
			return false
		},
	}
	if *password != "" {
		srv.PasswordHandler = func(ctx ssh.Context, p string) bool { return p == *password }
	}
	srv.AddHostKey(signer)
	log.Printf("ohsshd listening on %s (keys=%d, password=%v)", *addr, len(keys), *password != "")
	log.Fatal(srv.ListenAndServe())
}

// The host key is a PKCS#8 PEM ed25519 key, generated on first start.
func loadHostKey(path string) (gossh.Signer, error) {
	if b, err := os.ReadFile(path); err == nil {
		blk, _ := pem.Decode(b)
		if blk == nil {
			return nil, fmt.Errorf("%s: not PEM", path)
		}
		k, err := x509.ParsePKCS8PrivateKey(blk.Bytes)
		if err != nil {
			return nil, err
		}
		return gossh.NewSignerFromKey(k)
	}
	_, k, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	der, err := x509.MarshalPKCS8PrivateKey(k)
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), 0600); err != nil {
		return nil, err
	}
	s, err := gossh.NewSignerFromKey(k)
	if err == nil {
		log.Printf("generated new host key, fingerprint=%s", gossh.FingerprintSHA256(s.PublicKey()))
	}
	return s, err
}

// authorized_keys is read once, at start: restart ohsshd after changing it.
func loadAuthKeys(path string) []ssh.PublicKey {
	var keys []ssh.PublicKey
	if path == "" {
		return keys
	}
	b, err := os.ReadFile(path)
	if err != nil {
		log.Printf("authkeys: %v", err)
		return keys
	}
	for len(b) > 0 {
		k, _, _, rest, err := gossh.ParseAuthorizedKey(b)
		if err != nil {
			break
		}
		keys = append(keys, k)
		b = rest
	}
	return keys
}

func handle(s ssh.Session, shell string) {
	var cmd *exec.Cmd
	if raw := s.RawCommand(); raw != "" {
		cmd = exec.Command(shell, "-c", raw)
	} else {
		cmd = exec.Command(shell)
	}
	cmd.Env = append(os.Environ(), s.Environ()...)
	ptyReq, winCh, isPty := s.Pty()
	if isPty {
		cmd.Env = append(cmd.Env, "TERM="+ptyReq.Term)
		f, err := pty.Start(cmd)
		if err != nil {
			fmt.Fprintln(s.Stderr(), err)
			s.Exit(1)
			return
		}
		go func() {
			for w := range winCh {
				setWinsize(f, w.Width, w.Height)
			}
		}()
		go io.Copy(f, s)
		io.Copy(s, f)
		s.Exit(exitCode(cmd.Wait()))
		return
	}
	cmd.Stdout, cmd.Stderr = s, s.Stderr()
	in, err := cmd.StdinPipe()
	if err != nil {
		s.Exit(1)
		return
	}
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(s.Stderr(), err)
		s.Exit(127)
		return
	}
	go func() { io.Copy(in, s); in.Close() }()
	s.Exit(exitCode(cmd.Wait()))
}

func exitCode(err error) int {
	if e, ok := err.(*exec.ExitError); ok {
		if st, ok := e.Sys().(syscall.WaitStatus); ok && st.Signaled() {
			return 128 + int(st.Signal())
		}
		return e.ExitCode()
	}
	if err != nil {
		return 1
	}
	return 0
}

func setWinsize(f *os.File, w, h int) {
	ws := struct{ h, w, x, y uint16 }{uint16(h), uint16(w), 0, 0}
	syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), uintptr(syscall.TIOCSWINSZ), uintptr(unsafe.Pointer(&ws)))
}
