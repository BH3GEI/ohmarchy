// ohtoken: print or set the HarmonyOS access token of a process (/dev/access_token_id).
// Processes started by init carry their service's token; ohsshd run under hdcd's token
// gives ssh sessions the rights `hdc shell` has (snapshot_display, uitest).
//   ohtoken get                  this process's token id and first-caller token id
//   ohtoken run TOKENID CMD ARGS set it, then exec CMD (children inherit it)
package main

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"unsafe"
)

// OpenHarmony's access_tokenid driver: _IOR/_IOW('A', 1/2, unsigned long long)
const (
	getTokenID  = 0x80084101
	setTokenID  = 0x40084102
	getFTokenID = 0x80084103
)

func ioctl(f *os.File, req uintptr, v *uint64) error {
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), req, uintptr(unsafe.Pointer(v))); e != 0 {
		return e
	}
	return nil
}

func main() {
	if len(os.Args) < 2 || (os.Args[1] != "get" && (os.Args[1] != "run" || len(os.Args) < 4)) {
		fmt.Fprintln(os.Stderr, "usage: ohtoken get | run <tokenid> cmd args...")
		os.Exit(2)
	}
	f, err := os.OpenFile("/dev/access_token_id", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	var id uint64
	if os.Args[1] == "get" {
		if err := ioctl(f, getTokenID, &id); err != nil {
			fmt.Fprintln(os.Stderr, "get:", err)
			os.Exit(1)
		}
		var fid uint64
		ioctl(f, getFTokenID, &fid) // 0 when the driver has none
		fmt.Println(id, fid)
		return
	}
	if id, err = strconv.ParseUint(os.Args[2], 10, 64); err != nil {
		fmt.Fprintln(os.Stderr, "tokenid:", err)
		os.Exit(2)
	}
	if err := ioctl(f, setTokenID, &id); err != nil {
		fmt.Fprintln(os.Stderr, "set:", err)
		os.Exit(1)
	}
	f.Close()
	path, err := exec.LookPath(os.Args[3])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(127)
	}
	fmt.Fprintln(os.Stderr, syscall.Exec(path, os.Args[3:], os.Environ()))
	os.Exit(126)
}
