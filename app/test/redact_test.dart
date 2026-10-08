import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/redact.dart';

void main() {
  tearDown(() {
    Redact.forgetAll();
    Redact.enabled = true;
  });

  test('known token shapes', () {
    const k = 'sk-proj-abcdefghijklmnopqrstuvwxyz123456';
    final r = Redact.text('pakai key $k ya');
    expect(r, isNot(contains('abcdefghijklmnop')));
    expect(r, contains('sk-p••••'));
    expect(Redact.text('AIzaSyA1234567890abcdefghijklmnopqrstu'), isNot(contains('1234567890abc')));
    expect(Redact.text('ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123'), 'ghp_••••');
    expect(Redact.text('bot 123456789:AAHdqTcvCH1vGWJxfSeofSAs0K5PALDsaw8 ok'), 'bot 123456789:•••• ok');
  });

  test('jwt, bearer, url creds, private key', () {
    expect(Redact.text('apikey eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYW5vbiJ9.abcdefghijklmno'), contains('eyJ…••••'));
    expect(Redact.text('Authorization: Bearer abc.def-ghi_12345'), 'Authorization: Bearer ••••');
    expect(Redact.text('postgres://adam:S3cr3t!@db.host:5432/app'), 'postgres://adam:••••@db.host:5432/app');
    final pem = '-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAA\n-----END OPENSSH PRIVATE KEY-----';
    expect(Redact.text('key:\n$pem\nend'), isNot(contains('b3BlbnNzaC1rZXktdjEAAAA')));
  });

  test('assignments, flags, query strings', () {
    expect(Redact.text('DB_PASSWORD=hunter22'), 'DB_PASSWORD=••••');
    expect(Redact.text('{"api_key": "xyz98765"}'), '{"api_key": "••••"}');
    expect(Redact.text('SUPABASE_SERVICE_ROLE_KEY=abcd1234'), 'SUPABASE_SERVICE_ROLE_KEY=••••');
    expect(Redact.text('mysql -u root -pRahasia123 db'), 'mysql -u root -p•••• db');
    expect(Redact.text('sshpass -p "rahasia" ssh x'), 'sshpass -p •••• ssh x');
    expect(Redact.text('curl https://x.io/a?token=abc123&q=1'), 'curl https://x.io/a?token=••••&q=1');
    expect(Redact.text('max_tokens=4000'), 'max_tokens=4000');
    expect(Redact.text('ssh -p 2222 root@x'), 'ssh -p 2222 root@x');
  });

  test('ip addresses keep a hint, loopback stays', () {
    expect(Redact.text('vps 103.45.67.89 dan lokal 127.0.0.1'), 'vps 103.•.•.89 dan lokal 127.0.0.1');
    expect(Redact.text('versi 2.3.0 aman'), 'versi 2.3.0 aman');
  });

  test('natural language passwords (Indonesian), without masking normal sentences', () {
    expect(Redact.text('passwordnya rahasia123'), 'passwordnya ••••');
    expect(Redact.text('password vps adalah Hunter22!'), 'password vps adalah ••••');
    expect(Redact.text('kata sandi: abcd1234'), 'kata sandi: ••••');
    expect(Redact.text('pin wifi: 12345678'), 'pin wifi: ••••');
    expect(Redact.text('sandi wifi nya bebas123'), 'sandi wifi nya ••••');
    expect(Redact.text('password server gagal'), 'password server gagal');
    expect(Redact.text('passwordnya udah diganti'), 'passwordnya udah diganti');
  });

  test('known secrets are masked exactly; args deep-masked; switch off', () {
    Redact.learn(['rahasia-vps-123', null, 'abc', 'server']);
    expect(Redact.text('cek server dulu'), 'cek server dulu'); // plain short word isn't learned
    expect(Redact.text('echo rahasia-vps-123 | sudo -S ls'), 'echo •••• | sudo -S ls');
    final a = Redact.args({
      'host': 'vps',
      'password': 'x',
      'headers': {'Authorization': 'Bearer zzzzzzzzzz'},
      'cmd': ['echo', 'rahasia-vps-123'],
    });
    expect(a['password'], '••••');
    expect((a['headers'] as Map)['Authorization'], '••••');
    expect(a['cmd'], ['echo', '••••']);
    expect(a['host'], 'vps');
    Redact.enabled = false;
    expect(Redact.text('DB_PASSWORD=hunter22'), 'DB_PASSWORD=hunter22');
  });
}
