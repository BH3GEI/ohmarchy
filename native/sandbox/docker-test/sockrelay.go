// sockrelay: the native sandbox's /run/docker.sock (sandbox-hook.sh). Listens on
// LISTEN (root:GID, 0660) and joins each connection to dockerd's socket TARGET,
// nothing else. Exits once LISTEN's directory is gone (the sandbox stopped).
//   sockrelay LISTEN GID TARGET
// Build: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build sockrelay.go
package main

import (
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Println("usage: sockrelay LISTEN GID TARGET")
		os.Exit(2)
	}
	listen, target := os.Args[1], os.Args[3]
	gid, err := strconv.Atoi(os.Args[2])
	if err != nil {
		fmt.Println("gid:", err)
		os.Exit(2)
	}
	os.Remove(listen)
	l, err := net.Listen("unix", listen)
	if err != nil {
		fmt.Println("listen:", err)
		os.Exit(1)
	}
	if os.Chown(listen, 0, gid) != nil || os.Chmod(listen, 0o660) != nil {
		fmt.Println("could not set the socket's owner and mode")
		os.Exit(1)
	}
	fmt.Println("relay", listen, "->", target)
	go func() {
		for {
			time.Sleep(5 * time.Second)
			if _, err := os.Stat(filepath.Dir(listen)); err != nil {
				fmt.Println("sandbox gone:", err)
				os.Exit(0)
			}
		}
	}()
	for {
		c, err := l.Accept()
		if err != nil {
			fmt.Println("accept:", err)
			os.Exit(1)
		}
		go func(c net.Conn) {
			defer c.Close()
			d, err := net.Dial("unix", target)
			if err != nil {
				fmt.Println("dial:", err)
				return
			}
			defer d.Close()
			done := make(chan struct{}, 2)
			go func() { io.Copy(d, c); d.(*net.UnixConn).CloseWrite(); done <- struct{}{} }()
			go func() { io.Copy(c, d); c.(*net.UnixConn).CloseWrite(); done <- struct{}{} }()
			<-done
			<-done
		}(c)
	}
}
