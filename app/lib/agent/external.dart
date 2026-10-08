import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../ssh_manager.dart';
import '../store.dart';
import 'llm.dart';
import 'providers.dart';

/// "Agent eksternal": a CLI agent living on some host (e.g. Antigravity `agy`
/// in Termux/proot). satsh only sends the message over SSH and renders the
/// streamed answer — the agent's soul, memory and login stay on that host.
///
/// Stream format (agy --output-format stream-json):
///   {"event":"step_update","step_update":{"conversation_id","step_index","state","step_type","text_delta",…}}
///   {"event":"result","result":{"conversation_id","status","response","usage",…}}
class ExternalAgent {
  static const defaultCommand = 'agy --output-format stream-json {resume} -p {prompt}';
  static const presetName = 'Antigravity (Termux)';

  /// Single-quote for POSIX sh.
  static String q(String s) => "'${s.replaceAll("'", "'\\''")}'";

  static String buildCommand(String template, String prompt, String? conversationId, {String distro = ''}) {
    final t = template.trim().isEmpty ? defaultCommand : template.trim();
    var cmd = t
        .replaceAll('{resume}', conversationId == null || conversationId.isEmpty ? '' : '--conversation ${q(conversationId)}')
        .replaceAll('{prompt}', q(prompt));
    if (!t.contains('{prompt}')) cmd = '$cmd ${q(prompt)}';
    cmd = cmd.replaceAll(RegExp(r' {2,}'), ' ');
    // Login shell so PATH (npm/venv bins) matches what the user gets interactively.
    final direct = 'bash -lc ${q(cmd)}';
    if (distro.trim().isEmpty) return '$direct </dev/null';
    // Termux: hop into the proot distro only if we're not inside a proot already
    // (sshd started from inside Ubuntu → already there; proot shows up as a tracer).
    // Already inside: scrub Termux's env (LD_PRELOAD of termux-exec breaks glibc
    // programs with "invalid ELF header") and use the distro's own bash + PATH.
    const scrub = 'unset LD_PRELOAD LD_LIBRARY_PATH PREFIX TMPDIR; '
        'export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; '
        'case "\$HOME" in /data/data/com.termux*) export HOME=/root;; esac; '
        'cd "\$HOME" 2>/dev/null; ';
    final inside = '${scrub}if [ -x /bin/bash ]; then exec /bin/bash -lc ${q(cmd)} </dev/null; fi; exec $direct </dev/null';
    return 'if [ "\$(grep -s \'^TracerPid\' /proc/self/status | tr -dc 0-9)" != "0" ]; then $inside; '
        'elif command -v proot-distro >/dev/null 2>&1; then '
        'exec proot-distro login ${q(distro.trim())} -- $direct </dev/null; '
        'else exec $direct </dev/null; fi';
  }

  /// Runs one turn. Appends assistant/tool messages to [history] as they stream.
  /// Returns the conversation id reported by the agent.
  static Future<String?> run({
    required ProviderCfg cfg,
    required String prompt,
    required List<Msg> history,
    String? conversationId,
    void Function()? onChange,
    void Function(String)? onStatus,
    bool Function()? isCancelled,
  }) async {
    final host = Store.i.host(cfg.base);
    if (host == null) throw LlmError('Host buat ${cfg.name} belum dipilih / udah kehapus. Buka Pengaturan → Agent.');
    onStatus?.call('Nyambung ke ${host.label}…');
    final client = await SshManager.i.client(host);
    final SSHSession sess = await client.execute(buildCommand(cfg.model, prompt, conversationId, distro: cfg.distro));
    onStatus?.call('${cfg.name} mikir…');

    String? conv = conversationId;
    final textMsgs = <int, Msg>{}; // step_index → assistant message
    final callIds = <int, String>{}; // step_index → tool call id
    final finished = <int>{};
    final junk = <String>[];
    var gotJson = false;
    String? finalResponse;
    String? failStatus;
    var anyText = false;

    void handle(Map<String, dynamic> j) {
      gotJson = true;
      final ev = j['event'];
      if (ev == 'step_update' && j['step_update'] is Map) {
        final su = Map<String, dynamic>.from(j['step_update']);
        conv = (su['conversation_id'] as String?) ?? conv;
        final idx = (su['step_index'] as num?)?.toInt() ?? -1;
        final type = '${su['step_type'] ?? ''}';
        final state = '${su['state'] ?? ''}'.toUpperCase();
        if (type == 'user_input') return;
        if (type == 'agent_response') {
          final d = su['text_delta'];
          if (d is String && d.isNotEmpty) {
            final m = textMsgs.putIfAbsent(idx, () {
              final m = Msg(role: 'assistant');
              history.add(m);
              return m;
            });
            m.text += d;
            if (m.text.trim().isNotEmpty) anyText = true;
            onStatus?.call('${cfg.name} ngetik…');
            onChange?.call();
          }
          return;
        }
        if (type.contains('think') || type.contains('plan')) {
          onStatus?.call('${cfg.name} mikir…');
          return;
        }
        // Anything else is a tool / action step.
        final name = _toolName(su, type);
        if (!callIds.containsKey(idx)) {
          final id = 'ext_${conv ?? ''}_$idx';
          callIds[idx] = id;
          history.add(Msg(role: 'assistant', calls: [ToolCall(id: id, name: name, args: _args(su))]));
          onStatus?.call('${cfg.name}: $name…');
          onChange?.call();
        }
        final bad = state.contains('ERROR') || state.contains('FAIL') || state.contains('CANCEL');
        if ((state == 'DONE' || bad) && finished.add(idx)) {
          history.add(Msg(role: 'tool', callId: callIds[idx], name: name, text: _output(su, state), isError: bad));
          onStatus?.call('${cfg.name} mikir…');
          onChange?.call();
        }
      } else if (ev == 'result' && j['result'] is Map) {
        final r = Map<String, dynamic>.from(j['result']);
        conv = (r['conversation_id'] as String?) ?? conv;
        finalResponse = r['response'] as String?;
        final st = '${r['status'] ?? 'SUCCESS'}'.toUpperCase();
        if (st != 'SUCCESS') failStatus = r['error']?.toString() ?? st;
      }
    }

    final lines = sess.stdout.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());
    final errBuf = StringBuffer();
    final errSub = sess.stderr.cast<List<int>>().transform(const Utf8Decoder(allowMalformed: true)).listen(errBuf.write);
    Timer? watch;
    watch = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (isCancelled?.call() ?? false) {
        try {
          sess.kill(SSHSignal.INT);
        } catch (_) {}
        sess.close();
        watch?.cancel();
      }
    });
    try {
      await for (final l in lines) {
        final s = l.trim();
        if (s.isEmpty) continue;
        if (s.startsWith('{')) {
          try {
            handle(Map<String, dynamic>.from(jsonDecode(s)));
            continue;
          } catch (_) {}
        }
        junk.add(s);
        if (junk.length > 40) junk.removeAt(0);
      }
      await sess.done.timeout(const Duration(seconds: 5), onTimeout: () {});
    } finally {
      watch.cancel();
      await errSub.cancel();
    }
    // close any tool chips that never reported DONE
    for (final e in callIds.entries) {
      if (!finished.contains(e.key)) {
        history.add(Msg(role: 'tool', callId: e.value, name: 'step', text: '(ga ada laporan selesai)'));
      }
    }
    if (isCancelled?.call() ?? false) {
      history.add(Msg(role: 'event', text: '⏹️ Dihentiin'));
      return conv;
    }
    if (!anyText && (finalResponse ?? '').trim().isNotEmpty) {
      history.add(Msg(role: 'assistant', text: finalResponse!.trim()));
    }
    if (failStatus != null) throw LlmError('${cfg.name}: $failStatus');
    if (!gotJson) {
      final out = [...junk, errBuf.toString().trim()].where((e) => e.isNotEmpty).join('\n');
      final code = sess.exitCode;
      if (out.contains('not found')) {
        throw LlmError('Perintah agent ga ketemu di ${host.label}. Cek perintahnya di Pengaturan → Agent.\n$out');
      }
      throw LlmError('${cfg.name} ga ngasih jawaban (exit ${code ?? '?'}).${out.isEmpty ? '' : '\n${_tail(out)}'}');
    }
    return conv;
  }

  static String _tail(String s) => s.length > 600 ? '…${s.substring(s.length - 600)}' : s;

  static String _toolName(Map<String, dynamic> su, String type) {
    for (final k in ['tool_name', 'toolName', 'name']) {
      if (su[k] is String && (su[k] as String).isNotEmpty) return su[k];
    }
    for (final k in ['tool', 'tool_call', 'toolCall', 'action']) {
      final v = su[k];
      if (v is Map && v['name'] is String) return v['name'];
      if (v is String && v.isNotEmpty) return v;
    }
    return type.isEmpty ? 'step' : type;
  }

  static const _meta = {'conversation_id', 'step_index', 'state', 'step_type', 'usage', 'duration_seconds', 'text_delta'};

  static Map<String, dynamic> _args(Map<String, dynamic> su) {
    final out = <String, dynamic>{};
    for (final e in su.entries) {
      if (_meta.contains(e.key)) continue;
      if (e.value is Map) {
        final m = Map<String, dynamic>.from(e.value);
        for (final k in ['args', 'arguments', 'input', 'parameters']) {
          if (m[k] is Map) out.addAll(Map<String, dynamic>.from(m[k]));
        }
        for (final x in m.entries) {
          if (x.value is! Map) out.putIfAbsent(x.key, () => x.value);
        }
      } else {
        out[e.key] = e.value;
      }
    }
    return out;
  }

  static String _output(Map<String, dynamic> su, String state) {
    for (final k in ['output', 'result', 'summary', 'message', 'error', 'text_delta']) {
      final v = su[k];
      if (v is String && v.trim().isNotEmpty) return v;
      if (v is Map || v is List) return const JsonEncoder.withIndent('  ').convert(v);
    }
    return state == 'DONE' ? 'selesai' : state.toLowerCase();
  }
}
