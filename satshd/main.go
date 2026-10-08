// satshd — tiny SSH server that satsh runs inside the phone ("Mode Server").
//
// Files in -dir:
//
//	host_ed25519      server host key (generated on first run)
//	authorized_keys   keys allowed to log in (one OpenSSH line each)
//	pair_token        optional "TOKEN EXPIRY_UNIX" for one-time QR pairing
//
// Stdout lines are read by the app: READY, LOGIN, PAIRED, ERR.
package main

import (
	"bufio"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/subtle"
	"encoding/binary"
	"encoding/pem"
	"flag"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/creack/pty"
	"github.com/pkg/sftp"
	"golang.org/x/crypto/ssh"
)

var (
	dir   = flag.String("dir", ".", "data dir")
	port  = flag.Int("port", 2222, "listen port")
	bind  = flag.String("bind", "0.0.0.0", "listen address")
	shell = flag.String("shell", "/system/bin/sh", "login shell")
	home  = flag.String("home", "", "home dir (default dir/home)")
	name  = flag.String("name", "phone", "display name")
)

var outMu sync.Mutex

func say(format string, a ...any) {
	outMu.Lock()
	fmt.Printf(format+"\n", a...)
	outMu.Unlock()
}

func main() {
	flag.Parse()
	if *home == "" {
		*home = filepath.Join(*dir, "home")
	}
	os.MkdirAll(*home, 0700)
	// Handy shortcut to shared storage (works if the app has storage permission).
	link := filepath.Join(*home, "storage")
	if _, err := os.Lstat(link); err != nil {
		os.Symlink("/storage/emulated/0", link)
	}

	signer, err := hostKey(filepath.Join(*dir, "host_ed25519"))
	if err != nil {
		say("ERR hostkey %v", err)
		os.Exit(1)
	}
	cfg := &ssh.ServerConfig{
		ServerVersion: "SSH-2.0-satshd_1",
		PublicKeyCallback: func(c ssh.ConnMetadata, key ssh.PublicKey) (*ssh.Permissions, error) {
			if comment, ok := authorized(key); ok {
				return &ssh.Permissions{Extensions: map[string]string{"who": comment}}, nil
			}
			return nil, fmt.Errorf("unknown key")
		},
		PasswordCallback: func(c ssh.ConnMetadata, pw []byte) (*ssh.Permissions, error) {
			if checkToken(string(pw)) {
				return &ssh.Permissions{Extensions: map[string]string{"pair": "1"}}, nil
			}
			time.Sleep(1500 * time.Millisecond) // slow down guessing
			return nil, fmt.Errorf("denied")
		},
		MaxAuthTries: 4,
	}
	cfg.AddHostKey(signer)

	ln, err := net.Listen("tcp", net.JoinHostPort(*bind, strconv.Itoa(*port)))
	if err != nil {
		say("ERR listen %v", err)
		os.Exit(2)
	}
	say("READY %d %s", *port, ssh.FingerprintSHA256(signer.PublicKey()))

	// Exit when the app closes our stdin (app died / stopped us).
	go func() {
		io.Copy(io.Discard, os.Stdin)
		if os.Getenv("SATSHD_IGNORE_STDIN") == "" {
			os.Exit(0)
		}
	}()

	for {
		nc, err := ln.Accept()
		if err != nil {
			continue
		}
		go handleConn(nc, cfg)
	}
}

func hostKey(path string) (ssh.Signer, error) {
	if b, err := os.ReadFile(path); err == nil {
		return ssh.ParsePrivateKey(b)
	}
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	blk, err := ssh.MarshalPrivateKey(priv, "satshd")
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, pem.EncodeToMemory(blk), 0600); err != nil {
		return nil, err
	}
	return ssh.NewSignerFromKey(priv)
}

func authorized(key ssh.PublicKey) (string, bool) {
	f, err := os.Open(filepath.Join(*dir, "authorized_keys"))
	if err != nil {
		return "", false
	}
	defer f.Close()
	want := key.Marshal()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 64*1024), 64*1024)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		k, comment, _, _, err := ssh.ParseAuthorizedKey([]byte(line))
		if err == nil && subtle.ConstantTimeCompare(k.Marshal(), want) == 1 {
			return comment, true
		}
	}
	return "", false
}

var tokenMu sync.Mutex

func checkToken(pw string) bool {
	tokenMu.Lock()
	defer tokenMu.Unlock()
	b, err := os.ReadFile(filepath.Join(*dir, "pair_token"))
	if err != nil {
		return false
	}
	parts := strings.Fields(string(b))
	if len(parts) < 2 || len(parts[0]) < 8 {
		return false
	}
	exp, _ := strconv.ParseInt(parts[1], 10, 64)
	if time.Now().Unix() > exp {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(parts[0]), []byte(pw)) == 1
}

func handleConn(nc net.Conn, cfg *ssh.ServerConfig) {
	conn, chans, reqs, err := ssh.NewServerConn(nc, cfg)
	if err != nil {
		nc.Close()
		return
	}
	defer conn.Close()
	pairing := conn.Permissions.Extensions["pair"] == "1"
	if !pairing {
		say("LOGIN %s %s", conn.Permissions.Extensions["who"], conn.RemoteAddr())
	}
	// Keepalive replies.
	go func() {
		for r := range reqs {
			if r.WantReply {
				r.Reply(r.Type == "keepalive@openssh.com", nil)
			}
		}
	}()
	for nch := range chans {
		switch nch.ChannelType() {
		case "session":
			go session(nch, pairing)
		case "direct-tcpip":
			if pairing {
				nch.Reject(ssh.Prohibited, "pairing only")
				continue
			}
			go directTCP(nch)
		default:
			nch.Reject(ssh.UnknownChannelType, "unsupported")
		}
	}
}

type ptyReq struct {
	Term     string
	Cols     uint32
	Rows     uint32
	Width    uint32
	Height   uint32
	Modelist string
}

func session(nch ssh.NewChannel, pairing bool) {
	ch, reqs, err := nch.Accept()
	if err != nil {
		return
	}
	defer ch.Close()
	var (
		wantPty bool
		pr      ptyReq
		ptmx    *os.File
		env     []string
		started *exec.Cmd
	)
	defer func() {
		if started != nil && started.Process != nil && started.ProcessState == nil {
			started.Process.Kill()
		}
	}()
	exit := func(code int) {
		b := make([]byte, 4)
		binary.BigEndian.PutUint32(b, uint32(code))
		ch.SendRequest("exit-status", false, b)
	}
	for r := range reqs {
		switch r.Type {
		case "pty-req":
			if ssh.Unmarshal(r.Payload, &pr) == nil {
				wantPty = true
			}
			r.Reply(true, nil)
		case "window-change":
			var wc struct{ Cols, Rows, W, H uint32 }
			if ssh.Unmarshal(r.Payload, &wc) == nil && ptmx != nil {
				pty.Setsize(ptmx, &pty.Winsize{Cols: uint16(wc.Cols), Rows: uint16(wc.Rows)})
			}
		case "env":
			var kv struct{ K, V string }
			if ssh.Unmarshal(r.Payload, &kv) == nil && (kv.K == "LANG" || strings.HasPrefix(kv.K, "LC_")) {
				env = append(env, kv.K+"="+kv.V)
			}
			r.Reply(true, nil)
		case "subsystem":
			var s struct{ Name string }
			ssh.Unmarshal(r.Payload, &s)
			if s.Name != "sftp" || pairing {
				r.Reply(false, nil)
				continue
			}
			r.Reply(true, nil)
			srv, err := sftp.NewServer(ch, sftp.WithServerWorkingDirectory(*home))
			if err == nil {
				srv.Serve()
				srv.Close()
			}
			exit(0)
			return
		case "shell", "exec":
			if started != nil {
				r.Reply(false, nil)
				continue
			}
			var cmdline string
			if r.Type == "exec" {
				var e struct{ Cmd string }
				ssh.Unmarshal(r.Payload, &e)
				cmdline = e.Cmd
			}
			if pairing {
				r.Reply(true, nil)
				code := pair(ch, cmdline)
				exit(code)
				return
			}
			r.Reply(true, nil)
			var cmd *exec.Cmd
			if cmdline == "" {
				cmd = exec.Command(*shell, "-l")
			} else {
				cmd = exec.Command(*shell, "-c", cmdline)
			}
			cmd.Dir = *home
			cmd.Env = append(baseEnv(pr.Term), env...)
			if wantPty {
				ptmx, err = pty.StartWithSize(cmd, &pty.Winsize{Cols: uint16(max(pr.Cols, 20)), Rows: uint16(max(pr.Rows, 5))})
				if err != nil {
					fmt.Fprintf(ch, "satshd: %v\r\n", err)
					exit(1)
					return
				}
				p := ptmx
				go io.Copy(p, ch)
				go func() {
					io.Copy(ch, p)
					code := wait(cmd)
					p.Close()
					exit(code)
					ch.Close()
				}()
			} else {
				stdin, _ := cmd.StdinPipe()
				go func() { io.Copy(stdin, ch); stdin.Close() }()
				cmd.Stdout = ch
				cmd.Stderr = ch.Stderr()
				if err := cmd.Start(); err != nil {
					fmt.Fprintf(ch.Stderr(), "satshd: %v\n", err)
					exit(127)
					return
				}
				go func() {
					code := wait(cmd)
					exit(code)
					ch.Close()
				}()
			}
			started = cmd
		default:
			if r.WantReply {
				r.Reply(false, nil)
			}
		}
	}
}

func wait(cmd *exec.Cmd) int {
	err := cmd.Wait()
	if err == nil {
		return 0
	}
	if ee, ok := err.(*exec.ExitError); ok {
		if st, ok := ee.Sys().(syscall.WaitStatus); ok {
			return st.ExitStatus()
		}
	}
	return 1
}

func baseEnv(term string) []string {
	if term == "" {
		term = "xterm-256color"
	}
	env := []string{
		"HOME=" + *home,
		"TERM=" + term,
		"TMPDIR=" + *home,
		"SHELL=" + *shell,
		"USER=" + *name,
		"PS1=" + *name + ":\\w \\$ ",
	}
	path := "/product/bin:/apex/com.android.runtime/bin:/apex/com.android.art/bin:/system_ext/bin:/system/bin:/system/xbin:/odm/bin:/vendor/bin:/vendor/xbin"
	for _, k := range []string{"ANDROID_DATA", "ANDROID_ROOT", "ANDROID_STORAGE", "EXTERNAL_STORAGE", "BOOTCLASSPATH", "ANDROID_ART_ROOT", "ANDROID_I18N_ROOT", "ANDROID_TZDATA_ROOT"} {
		if v := os.Getenv(k); v != "" {
			env = append(env, k+"="+v)
		}
	}
	if v := os.Getenv("PATH"); v != "" {
		path = v
	}
	return append(env, "PATH="+path)
}

// pair handles "satsh-pair <authorized_keys line>" during a token login.
func pair(ch ssh.Channel, cmdline string) int {
	const pre = "satsh-pair "
	if !strings.HasPrefix(cmdline, pre) {
		fmt.Fprintln(ch.Stderr(), "pairing session: only satsh-pair allowed")
		return 2
	}
	line := strings.TrimSpace(strings.TrimPrefix(cmdline, pre))
	k, comment, _, _, err := ssh.ParseAuthorizedKey([]byte(line))
	if err != nil {
		fmt.Fprintln(ch.Stderr(), "bad key")
		return 3
	}
	tokenMu.Lock()
	defer tokenMu.Unlock()
	os.Remove(filepath.Join(*dir, "pair_token")) // one-time
	f, err := os.OpenFile(filepath.Join(*dir, "authorized_keys"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0600)
	if err != nil {
		fmt.Fprintln(ch.Stderr(), err)
		return 4
	}
	comment = strings.Join(strings.Fields(comment), "_")
	if comment == "" {
		comment = "device"
	}
	fmt.Fprintf(f, "%s %s\n", strings.TrimSpace(string(ssh.MarshalAuthorizedKey(k))), comment)
	f.Close()
	say("PAIRED %s", comment)
	fmt.Fprintf(ch, "ok %s\n", *name)
	return 0
}

func directTCP(nch ssh.NewChannel) {
	var d struct {
		Host     string
		Port     uint32
		OrigHost string
		OrigPort uint32
	}
	if err := ssh.Unmarshal(nch.ExtraData(), &d); err != nil {
		nch.Reject(ssh.ConnectionFailed, "bad request")
		return
	}
	tc, err := net.DialTimeout("tcp", net.JoinHostPort(d.Host, strconv.Itoa(int(d.Port))), 10*time.Second)
	if err != nil {
		nch.Reject(ssh.ConnectionFailed, err.Error())
		return
	}
	ch, reqs, err := nch.Accept()
	if err != nil {
		tc.Close()
		return
	}
	go ssh.DiscardRequests(reqs)
	done := make(chan struct{}, 2)
	go func() { io.Copy(ch, tc); ch.CloseWrite(); done <- struct{}{} }()
	go func() { io.Copy(tc, ch); tc.(*net.TCPConn).CloseWrite(); done <- struct{}{} }()
	<-done
	<-done
	ch.Close()
	tc.Close()
}
