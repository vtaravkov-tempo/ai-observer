// Minimal TCP forwarder: fwd LISTEN_PORT=HOST:PORT ...
// Only forwards bytes to the fixed targets given on the command line.
package main

import (
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

func pipe(dst, src net.Conn, wg *sync.WaitGroup) {
	defer wg.Done()
	_, _ = io.Copy(dst, src)
	if c, ok := dst.(*net.TCPConn); ok {
		_ = c.CloseWrite()
	}
}

func main() {
	for _, a := range os.Args[1:] {
		port, target, ok := strings.Cut(a, "=")
		if !ok {
			log.Fatalf("bad arg %q", a)
		}
		l, err := net.Listen("tcp", ":"+port)
		if err != nil {
			log.Fatal(err)
		}
		log.Printf("forwarding :%s -> %s", port, target)
		go func() {
			for {
				c, err := l.Accept()
				if err != nil {
					log.Fatal(err)
				}
				go func() {
					defer c.Close()
					u, err := net.DialTimeout("tcp", target, 5*time.Second)
					if err != nil {
						log.Printf("dial %s: %v", target, err)
						return
					}
					defer u.Close()
					var wg sync.WaitGroup
					wg.Add(2)
					go pipe(u, c, &wg)
					go pipe(c, u, &wg)
					wg.Wait()
				}()
			}
		}()
	}
	select {}
}
