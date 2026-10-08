import 'package:flutter_test/flutter_test.dart';
import 'package:satsh/native.dart';

void main() {
  test('markdown is cleaned up before reading it aloud', () {
    final t = Native.speakable('''## Hasil
**Disk** aman: `30%` kepake.

- cek [dokumen](https://x.com/a)
- buka https://y.com

```bash
df -h
```''');
    expect(t, isNot(contains('*')));
    expect(t, isNot(contains('#')));
    expect(t, isNot(contains('`')));
    expect(t, contains('Disk aman: 30% kepake'));
    expect(t, contains('cek dokumen'));
    expect(t, contains('buka link'));
    expect(t, contains('ada kode'));
    expect(t, isNot(contains('df -h')));
  });

  test('notify outside the app never throws', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Native.notifyIfAway('a', 'b');
  });
}
