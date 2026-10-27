// chrootprobe: does unshare(CLONE_FS|CLONE_NEWNS) + chroot on one thread change
// the root of the other threads on HongMeng? (moby's chrootarchive relies on it not)
package main

import (
	"fmt"
	"os"
	"runtime"

	"golang.org/x/sys/unix"
)

func main() {
	dir := os.Args[1]
	_, err := os.Stat("/etc/resolv.conf")
	fmt.Println("before: stat /etc/resolv.conf:", err)
	done := make(chan struct{})
	held := make(chan struct{})
	go func() {
		runtime.LockOSThread() // never unlocked: the thread is thrown away
		fmt.Println("unshare:", unix.Unshare(unix.CLONE_FS|unix.CLONE_NEWNS))
		fmt.Println("chroot:", unix.Chroot(dir))
		_, err := os.Stat("/etc/resolv.conf")
		fmt.Println("chrooted thread: stat /etc/resolv.conf:", err)
		close(done)
		<-held
	}()
	<-done
	runtime.LockOSThread() // main goroutine on its own (other) thread
	_, err = os.Stat("/etc/resolv.conf")
	fmt.Println("other thread: stat /etc/resolv.conf:", err)
	close(held)
}
