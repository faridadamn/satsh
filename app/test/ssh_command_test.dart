import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/pages/host_edit_page.dart';
import 'package:satsh/ssh_command.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  void ok(String input, String host, {int? port, String? user, String? pw, String? cmd, int notes = 0}) {
    final r = SshCommand.parse(input);
    expect(r, isNotNull, reason: input);
    expect(r!.host, host, reason: '$input → $r');
    expect(r.port, port, reason: '$input → $r');
    expect(r.user, user, reason: '$input → $r');
    expect(r.password, pw, reason: '$input → $r');
    expect(r.command, cmd, reason: '$input → $r');
    expect(r.notes.length, notes, reason: '$input → $r');
  }

  test('the two lines from Instabox', () {
    ok('ssh -p 2222 abc123@api.instabox.sh', 'api.instabox.sh', port: 2222, user: 'abc123');
    ok('mosh --ssh="ssh -p 2222" abc123@api.instabox.sh', 'api.instabox.sh', port: 2222, user: 'abc123', notes: 1);
    final m = SshCommand.parse('mosh --ssh="ssh -p 2222" abc123@api.instabox.sh')!;
    expect(m.notes.first, contains('mosh'));
  });

  test('ssh variants', () {
    ok('ssh root@1.2.3.4', '1.2.3.4', user: 'root');
    ok('ssh -p2222 root@vps.id', 'vps.id', port: 2222, user: 'root');
    ok('ssh root@vps.id -p 2200', 'vps.id', port: 2200, user: 'root');
    ok('ssh -l adam -p 22 box.local', 'box.local', port: 22, user: 'adam');
    ok('ssh -o Port=2022 -o User=deploy example.com', 'example.com', port: 2022, user: 'deploy');
    ok('ssh -o "Port 2022" example.com', 'example.com', port: 2022);
    ok('ssh -v -A -C me@h.io', 'h.io', user: 'me');
    ok('ssh -tt me@h.io', 'h.io', user: 'me');
    ok('ssh -tp2222 me@h.io', 'h.io', port: 2222, user: 'me');
    ok('\$ ssh -p 2222 me@h.io', 'h.io', port: 2222, user: 'me');
    ok('  ssh   me@h.io  ', 'h.io', user: 'me');
    ok('ssh me@h.io -t "tmux new -A -s main"', 'h.io', user: 'me', cmd: 'tmux new -A -s main');
    ok('ssh me@h.io uptime', 'h.io', user: 'me', cmd: 'uptime');
    ok('/usr/bin/ssh me@h.io', 'h.io', user: 'me');
    ok('ssh -i ~/.ssh/id_ed25519 me@h.io', 'h.io', user: 'me', notes: 1);
    ok('ssh -J bastion me@10.0.0.5', '10.0.0.5', user: 'me', notes: 1);
    ok('ssh -L 8080:localhost:80 me@h.io', 'h.io', user: 'me', notes: 1);
    ok('ssh user.name+x@h.io', 'h.io', user: 'user.name+x');
    ok('ssh me@[::1]:2222', '::1', port: 2222, user: 'me');
  });

  test('bare forms', () {
    ok('ssh://me@h.io:2222', 'h.io', port: 2222, user: 'me');
    ok('ssh://h.io', 'h.io');
    ok('me@h.io:2222', 'h.io', port: 2222, user: 'me');
    ok('me@h.io', 'h.io', user: 'me');
    ok('h.io:2222', 'h.io', port: 2222);
    ok('[fe80::1]:22', 'fe80::1', port: 22);
  });

  test('sshpass carries the password', () {
    ok("sshpass -p 'r4h\$sia' ssh -p 2222 me@h.io", 'h.io', port: 2222, user: 'me', pw: r'r4h$sia');
  });

  test('mosh options belong to mosh', () {
    // -p is mosh's UDP port here, not SSH's
    ok('mosh -p 60001 me@h.io', 'h.io', user: 'me', notes: 1);
    ok('mosh --ssh="ssh -p 2222 -l me" h.io -- tmux a', 'h.io', port: 2222, user: 'me', notes: 1);
    ok("mosh --ssh='ssh -p 2222' me@h.io", 'h.io', port: 2222, user: 'me', notes: 1);
  });

  test('junk is rejected', () {
    for (final s in ['', 'halo bre', 'ssh', 'ssh -p 2222', 'ssh "unclosed', 'mosh', 'rm -rf /', 'ssh me@h!o', 'ssh me@']) {
      expect(SshCommand.parse(s), isNull, reason: s);
    }
  });

  test('looksLikeCommand', () {
    expect(SshCommand.looksLikeCommand('vps.example.com'), isFalse);
    expect(SshCommand.looksLikeCommand('10.0.0.1'), isFalse);
    expect(SshCommand.looksLikeCommand('ssh -p 2222 a@b'), isTrue);
    expect(SshCommand.looksLikeCommand('a@b'), isTrue);
    expect(SshCommand.looksLikeCommand('b:2222'), isTrue);
  });

  testWidgets('pasting a full command into the host field fills the form', (t) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await t.runAsync(Store.i.load);
    await t.pumpWidget(const MaterialApp(home: HostEditPage()));
    await t.pump();
    final fields = find.byType(TextField);
    // order: label, host, port, user, …
    await t.enterText(fields.at(1), 'mosh --ssh="ssh -p 2222" abc123@api.instabox.sh');
    await t.pump();
    await t.pump();
    String text(int i) => (t.widget(fields.at(i)) as TextField).controller!.text;
    expect(text(1), 'api.instabox.sh');
    expect(text(2), '2222');
    expect(text(3), 'abc123');
    expect(find.textContaining('Keisi: abc123@api.instabox.sh:2222'), findsOneWidget);
    expect(find.textContaining('belum bisa mosh'), findsOneWidget);
  });
}
