// node desktop/tests/test_sshcmd.js — same cases as app/test/ssh_command_test.dart
const assert = require("assert");
const { parse } = require("../web/sshcmd.js");

let n = 0;
function ok(input, host, o = {}) {
  const r = parse(input);
  assert(r, "null for " + input);
  const want = { host, port: o.port ?? null, user: o.user ?? null, password: o.pw ?? null, command: o.cmd ?? null };
  const got = { host: r.host, port: r.port ?? null, user: r.user ?? null, password: r.password ?? null, command: r.command ?? null };
  assert.deepStrictEqual(got, want, input);
  assert.strictEqual(r.notes.length, o.notes || 0, input + " notes=" + JSON.stringify(r.notes));
  n++;
}

ok("ssh -p 2222 abc123@api.instabox.sh", "api.instabox.sh", { port: 2222, user: "abc123" });
ok('mosh --ssh="ssh -p 2222" abc123@api.instabox.sh', "api.instabox.sh", { port: 2222, user: "abc123", notes: 1 });
ok("ssh root@1.2.3.4", "1.2.3.4", { user: "root" });
ok("ssh -p2222 root@vps.id", "vps.id", { port: 2222, user: "root" });
ok("ssh root@vps.id -p 2200", "vps.id", { port: 2200, user: "root" });
ok("ssh -l adam -p 22 box.local", "box.local", { port: 22, user: "adam" });
ok("ssh -o Port=2022 -o User=deploy example.com", "example.com", { port: 2022, user: "deploy" });
ok('ssh -o "Port 2022" example.com', "example.com", { port: 2022 });
ok("ssh -v -A -C me@h.io", "h.io", { user: "me" });
ok("ssh -tp2222 me@h.io", "h.io", { port: 2222, user: "me" });
ok("$ ssh -p 2222 me@h.io", "h.io", { port: 2222, user: "me" });
ok('ssh me@h.io -t "tmux new -A -s main"', "h.io", { user: "me", cmd: "tmux new -A -s main" });
ok("C:\\Windows\\System32\\OpenSSH\\ssh.exe me@h.io", "h.io", { user: "me" });
ok("ssh -i ~/.ssh/id_ed25519 me@h.io", "h.io", { user: "me", notes: 1 });
ok("ssh -J bastion me@10.0.0.5", "10.0.0.5", { user: "me", notes: 1 });
ok("ssh me@[::1]:2222", "::1", { port: 2222, user: "me" });
ok("ssh://me@h.io:2222", "h.io", { port: 2222, user: "me" });
ok("me@h.io:2222", "h.io", { port: 2222, user: "me" });
ok("h.io:2222", "h.io", { port: 2222 });
ok("sshpass -p 'r4h$sia' ssh -p 2222 me@h.io", "h.io", { port: 2222, user: "me", pw: "r4h$sia" });
ok("mosh -p 60001 me@h.io", "h.io", { user: "me", notes: 1 });
ok('mosh --ssh="ssh -p 2222 -l me" h.io -- tmux a', "h.io", { port: 2222, user: "me", notes: 1 });
for (const s of ["", "halo bre", "ssh", "ssh -p 2222", 'ssh "unclosed', "mosh", "rm -rf /", "ssh me@h!o", "ssh me@"]) {
  assert.strictEqual(parse(s), null, s);
  n++;
}
console.log("SSHCMD OK (" + n + ")");
