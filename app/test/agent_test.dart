// Agent loop, tools, LLM wire formats, media server, keygen, backup.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:satsh/agent/agent.dart';
import 'package:satsh/agent/brain.dart';
import 'package:satsh/agent/llm.dart';
import 'package:satsh/agent/tools.dart';
import 'package:satsh/keygen.dart';
import 'package:satsh/media_server.dart';
import 'package:satsh/models.dart';
import 'package:satsh/ssh_manager.dart';
import 'package:satsh/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrustAll implements Prompts {
  @override
  Future<String?> askPassword(Host h, {String? reason}) async => null;
  @override
  Future<bool> trustHostKey(Host h, String type, String fp, String? oldFp) async => true;
}

/// Plays back a script: each step sees the history and returns a reply.
class ScriptedLlm implements LlmProvider {
  ScriptedLlm(this.steps);
  final List<LlmReply Function(List<Msg>)> steps;
  int i = 0;
  @override
  Future<LlmReply> chat(String system, List<Msg> history, List<ToolSpec> tools) async {
    expect(system, contains('satsh agent'));
    expect(tools.map((t) => t.name), contains('ssh_exec'));
    return steps[i++](history);
  }
}

ToolCall call(String name, Map<String, dynamic> args) => ToolCall(id: 'c_$name${DateTime.now().microsecond}', name: name, args: args);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory phone;
  final host = Host(id: 'h1', label: 'local', host: '127.0.0.1', port: 2222, username: 'tester');
  final agent = AgentController.i;

  setUpAll(() async {
    HttpOverrides.global = null; // allow real sockets for the local servers
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Store.i.load();
    Brain.rootOverride = (await Directory.systemTemp.createTemp('brain')).path;
    await AgentController.i.load();
    Store.i.set('reviewEvery', 0);
    await Store.i.saveHost(host, password: 'rahasia123');
    SshManager.i.prompts = TrustAll();
    phone = await Directory.systemTemp.createTemp('phone');
    phoneBase = phone.path;
    await Directory('${phone.path}/Download').create();
    await File('${phone.path}/Download/catatan.md').writeAsString('# Belanja\n- kopi\n- gula');
    await File('${phone.path}/Download/invoice-mei.pdf').writeAsBytes([1, 2, 3]);
  });

  test('agent runs phone + ssh tools, asks approval for risky ones', () async {
    final approvals = <String>[];
    agent.approver = (tool, args) async {
      approvals.add(tool.spec.name);
      return tool.spec.name == 'phone_delete' ? 'no' : 'yes';
    };
    agent.providerOverride = ScriptedLlm([
      (h) => LlmReply('Oke gw cek dulu', [
            call('phone_search', {'query': 'invoice'}),
            call('phone_read', {'path': 'Download/catatan.md'}),
          ]),
      (h) {
        final results = h.where((m) => m.role == 'tool').toList();
        expect(results[0].text, contains('Download/invoice-mei.pdf'));
        expect(results[1].text, contains('kopi'));
        return LlmReply('', [
          call('ssh_exec', {'host': 'local', 'command': 'echo dari_vps && whoami'}),
          call('phone_write', {'path': 'Notes/hasil.txt', 'content': 'halo'}),
          call('phone_delete', {'path': 'Download/catatan.md'}),
        ]);
      },
      (h) {
        final r = h.where((m) => m.role == 'tool').toList();
        expect(r[2].text, contains('dari_vps'));
        expect(r[2].text, contains('tester'));
        expect(r[3].text, startsWith('OK'));
        expect(r[4].text, contains('NOLAK'));
        return LlmReply('Beres bre', []);
      },
    ]);
    await agent.send('cariin invoice terus cek server');
    expect(agent.messages.last.text, 'Beres bre');
    expect(approvals, ['ssh_exec', 'phone_write', 'phone_delete']);
    expect(File('${phone.path}/Notes/hasil.txt').readAsStringSync(), 'halo');
    expect(File('${phone.path}/Download/catatan.md').existsSync(), isTrue); // delete was refused
    expect(agent.busy, isFalse);
  });

  test('transfer, sftp_write/read and timeout', () async {
    agent.approver = (_, _) async => 'yes';
    agent.newChat();
    agent.providerOverride = ScriptedLlm([
      (h) => LlmReply('', [
            call('transfer', {'host': 'local', 'direction': 'upload', 'phone_path': 'Download/invoice-mei.pdf', 'remote_path': '/home/tester/inv.pdf'}),
            call('sftp_write', {'host': 'local', 'path': '/home/tester/a.txt', 'content': 'isi-dari-agent'}),
            call('sftp_read', {'host': 'local', 'path': '/home/tester/a.txt'}),
            call('transfer', {'host': 'local', 'direction': 'download', 'phone_path': 'Back/inv.pdf', 'remote_path': '/home/tester/inv.pdf'}),
            call('ssh_exec', {'host': 'local', 'command': 'sleep 20', 'timeout_s': 2}),
            call('sftp_list', {'host': 'loc'}),
          ]),
      (h) {
        final r = h.where((m) => m.role == 'tool').map((m) => m.text).toList();
        expect(r[0], contains('Upload OK'));
        expect(r[2], 'isi-dari-agent');
        expect(r[3], contains('Download OK'));
        expect(r[4], contains('TIMEOUT'));
        expect(r[5], contains('inv.pdf'));
        return LlmReply('ok', []);
      },
    ]);
    await agent.send('go');
    expect(File('${phone.path}/Back/inv.pdf').readAsBytesSync(), [1, 2, 3]);
  });

  test('supabase tools against a fake PostgREST', () async {
    final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    srv.listen((req) async {
      final body = await utf8.decoder.bind(req).join();
      seen.add('${req.method} ${req.uri} ${req.headers.value('apikey')} $body');
      req.response.headers.contentType = ContentType.json;
      req.response.write(req.method == 'GET' ? '[{"id":1,"total":50000}]' : '[{"id":2}]');
      await req.response.close();
    });
    Store.i.set('supabaseUrl', 'http://127.0.0.1:${srv.port}');
    await Store.i.setSecret('supabaseKey', 'kunci');
    agent.newChat();
    agent.providerOverride = ScriptedLlm([
      (h) => LlmReply('', [
            call('supabase_select', {'table': 'orders', 'filter': 'status=eq.paid', 'order': 'id.desc', 'limit': 5}),
            call('supabase_mutate', {'action': 'insert', 'table': 'orders', 'data_json': '{"total":1}'}),
            call('supabase_mutate', {'action': 'delete', 'table': 'orders'}),
          ]),
      (h) {
        final r = h.where((m) => m.role == 'tool').toList();
        expect(r[0].text, contains('50000'));
        expect(r[1].text, contains('"id":2'));
        expect(r[2].isError, isTrue); // delete without filter refused
        return LlmReply('ok', []);
      },
    ]);
    await agent.send('cek order');
    expect(seen[0], startsWith('GET /rest/v1/orders?select=%2A&status=eq.paid&order=id.desc&limit=5 kunci'));
    expect(seen[1], contains('POST /rest/v1/orders'));
    expect(seen.length, 2);
    await srv.close(force: true);
  });

  test('OpenAI-compatible wire format with tool round-trip', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body);
      expect(req.url.toString(), 'https://api.deepseek.com/v1/chat/completions');
      expect(req.headers['Authorization'], 'Bearer sk-x');
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_1',
                      'type': 'function',
                      'function': {'name': 'ssh_hosts', 'arguments': '{}'}
                    }
                  ]
                }
              }
            ]
          }),
          200);
    });
    final p = OpenAiCompat(baseUrl: 'https://api.deepseek.com/v1/', apiKey: 'sk-x', model: 'deepseek-chat', client: client);
    final hist = [
      Msg(role: 'user', text: 'halo'),
      Msg(role: 'assistant', text: '', calls: [ToolCall(id: 'a', name: 'device_info', args: {})]),
      Msg(role: 'tool', callId: 'a', name: 'device_info', text: 'HP: x'),
    ];
    final r = await p.chat('sys', hist, allTools.map((t) => t.spec).toList());
    expect(r.calls.single.name, 'ssh_hosts');
    expect(sent['messages'][0], {'role': 'system', 'content': 'sys'});
    expect(sent['messages'][2]['tool_calls'][0]['function']['arguments'], '{}');
    expect(sent['messages'][3], {'role': 'tool', 'tool_call_id': 'a', 'content': 'HP: x'});
    expect(sent['tools'][0]['function']['parameters']['type'], 'object');
  });

  test('Gemini wire format keeps thought signatures & merges tool turns', () async {
    late Map<String, dynamic> sent;
    final client = MockClient((req) async {
      sent = jsonDecode(req.body);
      expect(req.url.path, endsWith('/models/gemini-2.5-flash:generateContent'));
      expect(req.headers['x-goog-api-key'], 'g-key');
      return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'role': 'model',
                  'parts': [
                    {'text': 'mikir', 'thought': true},
                    {'text': 'Cek dulu'},
                    {
                      'functionCall': {'name': 'phone_list', 'args': {'path': 'Download'}},
                      'thoughtSignature': 'SIG'
                    }
                  ]
                }
              }
            ]
          }),
          200);
    });
    final p = Gemini(apiKey: 'g-key', model: 'gemini-2.5-flash', client: client);
    final r1 = await p.chat('sys', [Msg(role: 'user', text: 'hai')], allTools.map((t) => t.spec).toList());
    expect(r1.text, 'Cek dulu');
    expect(r1.calls.single.args['path'], 'Download');
    final hist = [
      Msg(role: 'user', text: 'hai'),
      Msg(role: 'assistant', text: r1.text, calls: r1.calls, raw: r1.raw),
      Msg(role: 'tool', callId: r1.calls[0].id, name: 'phone_list', text: 'a.txt'),
    ];
    await p.chat('sys', hist, allTools.map((t) => t.spec).toList());
    final contents = sent['contents'] as List;
    expect(contents.map((c) => c['role']).toList(), ['user', 'model', 'user']);
    expect((contents[1]['parts'] as List).last['thoughtSignature'], 'SIG');
    expect(contents[2]['parts'][0]['functionResponse']['name'], 'phone_list');
    expect(sent['tools'][0]['functionDeclarations'][0]['parameters']['type'], 'OBJECT');
  });

  test('media server streams with Range + serves html dir index', () async {
    final sftp = await SshManager.i.sftp(host);
    final data = Uint8List.fromList(List.generate(500000, (i) => i % 256));
    final f = await sftp.open('/home/tester/video.mp4',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    await f.writeBytes(data);
    await f.close();
    await sftp.mkdir('/home/tester/site').catchError((_) {});
    final g = await sftp.open('/home/tester/site/index.html',
        mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
    await g.writeBytes(Uint8List.fromList(utf8.encode('<h1>hai</h1>')));
    await g.close();

    final base = await MediaServer.i.mount(sftp);
    final url = MediaServer.urlFor(base, '/home/tester/video.mp4');
    final full = await http.get(Uri.parse(url));
    expect(full.statusCode, 200);
    expect(full.headers['content-type'], 'video/mp4');
    expect(full.bodyBytes, data);
    final part = await http.get(Uri.parse(url), headers: {'Range': 'bytes=1000-1999'});
    expect(part.statusCode, 206);
    expect(part.headers['content-range'], 'bytes 1000-1999/500000');
    expect(part.bodyBytes, data.sublist(1000, 2000));
    final tail = await http.get(Uri.parse(url), headers: {'Range': 'bytes=499990-'});
    expect(tail.bodyBytes, data.sublist(499990));
    final html = await http.get(Uri.parse(MediaServer.urlFor(base, '/home/tester/site/')));
    expect(html.body, '<h1>hai</h1>');
    expect((await http.get(Uri.parse(MediaServer.urlFor(base, '/nope')))).statusCode, 404);
    MediaServer.i.unmount(base);
    expect((await http.get(Uri.parse(url))).statusCode, 403);
    sftp.close();
    expect(kindOf('a/b.MD'), FileKind.markdown);
    expect(kindOf('x.mp3'), FileKind.audio);
    expect(kindOf('.bashrc'), FileKind.text);
  });

  test('generated ed25519 key installs and logs in', () async {
    final k = generateEd25519();
    expect(k.privatePem, contains('BEGIN OPENSSH PRIVATE KEY'));
    expect(publicLineFromPem(k.privatePem).split(' ')[1], k.publicLine.split(' ')[1]);
    final out = await runSsh(host, "echo '${k.publicLine}' >> ~/.ssh/authorized_keys && echo KEY_OK");
    expect(out, contains('KEY_OK'));
    final kh = Host(id: 'hk', label: 'keyed', host: '127.0.0.1', port: 2222, username: 'tester', auth: 'key');
    await Store.i.saveHost(kh, key: k.privatePem);
    final r = await runSsh(kh, 'echo via_key');
    expect(r, contains('via_key'));
    // encrypted variant parses back
    final enc = generateEd25519(passphrase: 'pw');
    expect(SSHKeyPair.fromPem(enc.privatePem, 'pw'), hasLength(1));
  });

  test('backup roundtrip', () async {
    final json = await Store.i.exportJson(withSecrets: true);
    expect(json, contains('rahasia123'));
    final plain = await Store.i.exportJson();
    expect(plain, isNot(contains('rahasia123')));
    final n = Store.i.hosts.length;
    await Store.i.deleteHost('h1');
    expect(await Store.i.password('h1'), isNull);
    await Store.i.importJson(json);
    expect(Store.i.hosts.length, n);
    expect(await Store.i.password('h1'), 'rahasia123');
    expect(() => Store.i.importJson('{"app":"lain"}'), throwsA(anything));
  });
}
