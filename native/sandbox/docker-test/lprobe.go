// lprobe: a service only on the host's 127.0.0.1:18081 for 40 s (demo.sh); logs
// every accepted connection. Build: GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build lprobe.go
package main

import (
	"fmt"
	"net"
	"time"
)

func main() {
	l, err := net.Listen("tcp", "127.0.0.1:18081")
	if err != nil {
		fmt.Println("listen:", err)
		return
	}
	go func() { time.Sleep(40 * time.Second); l.Close() }()
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		fmt.Println("accepted from", c.RemoteAddr())
		c.Write([]byte("host-secret\n"))
		c.Close()
	}
}
