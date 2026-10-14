import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../media_server.dart';
import '../sftp_download.dart';
import '../theme.dart';
import '../widgets.dart';

// A plain TextField gets sluggish well before 2 MB (every keystroke relayouts
// the whole text), so cap editing at 1 MB.
const maxEditBytes = 1024 * 1024;

/// Opens a remote file: editor for text, preview+editor for MD/HTML,
/// streaming player for video/audio, zoomable image viewer.
class FileViewerPage extends StatefulWidget {
  const FileViewerPage({super.key, required this.sftp, required this.path, this.size, this.forceText = false});
  final SftpClient sftp;
  final String path;
  final int? size;
  final bool forceText;

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> with SingleTickerProviderStateMixin {
  late final FileKind kind = widget.forceText ? FileKind.text : kindOf(widget.path);
  String? _base;
  String? _original;
  final _ctl = TextEditingController();
  final _undo = UndoHistoryController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  late final TabController _tabs = TabController(length: 2, vsync: this);
  WebViewController? _web;
  int _rev = 0; // bump to refresh previews after save
  double? _dl; // download progress, null = idle
  Completer<void>? _dlCancel;

  String get name => widget.path.split('/').last;
  bool get isTextual => kind == FileKind.text || kind == FileKind.markdown || kind == FileKind.html;
  bool get dirty => _original != null && _ctl.text != _original;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(() => setState(() {}));
    _init();
  }

  Future<void> _download() async {
    if (_dlCancel != null) {
      _dlCancel!.complete();
      return;
    }
    final total = widget.size ?? 0;
    final pub = await SftpDownload.publicDir();
    final dir = pub ?? await SftpDownload.privateDir();
    final cancel = _dlCancel = Completer<void>();
    setState(() => _dl = 0);
    try {
      final out = await SftpDownload.fetch(widget.sftp, widget.path, SftpDownload.freeName(dir, name),
          cancel: cancel.future, onProgress: (n) {
        if (mounted && total > 0) setState(() => _dl = n / total);
      });
      if (!mounted) return;
      if (pub != null) {
        toast('Kesimpen di Download/satsh/${out.uri.pathSegments.last}');
      } else {
        toast('Izin file belum ada — pilih tempat simpennya ya');
        await SharePlus.instance.share(ShareParams(files: [XFile(out.path)]));
      }
    } catch (e) {
      if (mounted) toast(e == 'Dibatalin' ? 'Download dibatalin' : 'Gagal download: $e', error: e != 'Dibatalin');
    } finally {
      _dlCancel = null;
      if (mounted) setState(() => _dl = null);
    }
  }

  @override
  void dispose() {
    if (_dlCancel?.isCompleted == false) _dlCancel!.complete();
    if (_base != null) MediaServer.i.unmount(_base!);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _base = await MediaServer.i.mount(widget.sftp);
      if (isTextual) {
        if ((widget.size ?? 0) > maxEditBytes) throw 'File kegedean buat diedit (> 1 MB) — download aja';
        final f = await widget.sftp.open(widget.path);
        final bytes = await f.readBytes();
        await f.close();
        if (bytes.take(8000).contains(0)) throw 'Kayaknya ini file binary, bukan teks';
        _original = utf8.decode(bytes, allowMalformed: true);
        _ctl.text = _original!;
      }
      if (kind == FileKind.html) {
        _web = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setBackgroundColor(Colors.white)
          ..loadRequest(Uri.parse(MediaServer.urlFor(_base!, widget.path)));
      }
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final f = await widget.sftp.open(widget.path,
          mode: SftpFileOpenMode.write | SftpFileOpenMode.truncate | SftpFileOpenMode.create);
      await f.writeBytes(Uint8List.fromList(utf8.encode(_ctl.text)));
      await f.close();
      _original = _ctl.text;
      _rev++;
      _web?.reload();
      HapticFeedback.mediumImpact();
      toast('Kesimpen');
    } catch (e) {
      toast('Gagal simpan: $e', error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<bool> _confirmLeave() async {
    if (!dirty) return true;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Belum disimpen'),
        content: Text('Perubahan di $name belum disimpen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Buang')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Simpan')),
        ],
      ),
    );
    if (r == 'save') await _save();
    return r != null;
  }

  @override
  Widget build(BuildContext context) {
    final hasTabs = kind == FileKind.markdown || kind == FileKind.html;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
              if (dirty) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.circle, size: 8, color: C.amber)),
            ]),
            Text(widget.path, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: monoFont)),
          ]),
          actions: [
            if (isTextual && _original != null) ...[
              IconButton(icon: const Icon(Icons.undo_rounded), onPressed: _undo.value.canUndo ? _undo.undo : null),
              IconButton(icon: const Icon(Icons.redo_rounded), onPressed: _undo.value.canRedo ? _undo.redo : null),
              IconButton(
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.save_rounded, color: dirty ? C.cyan : null),
                onPressed: dirty && !_saving ? _save : null,
              ),
            ],
            IconButton(
              tooltip: _dl == null ? 'Download ke HP' : 'Batalin download',
              icon: _dl == null
                  ? const Icon(Icons.download_rounded)
                  : SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(value: _dl == 0 ? null : _dl, strokeWidth: 2.5, color: C.cyan),
                    ),
              onPressed: _download,
            ),
            if (_base != null && (!isTextual || kind == FileKind.html))
              IconButton(
                tooltip: 'Buka di browser',
                icon: const Icon(Icons.open_in_browser_rounded),
                onPressed: () => launchUrl(Uri.parse(MediaServer.urlFor(_base!, widget.path)),
                    mode: LaunchMode.externalApplication),
              ),
          ],
          bottom: hasTabs && _error == null
              ? TabBar(
                  controller: _tabs,
                  indicatorColor: C.violet,
                  labelColor: C.text,
                  unselectedLabelColor: C.muted,
                  dividerColor: Colors.transparent,
                  tabs: const [Tab(text: 'Preview'), Tab(text: 'Edit')],
                )
              : null,
        ),
        body: SafeArea(top: false, child: _loading
            ? const Center(child: CircularProgressIndicator(color: C.violet))
            : _error != null
                ? EmptyState(icon: Icons.block_rounded, title: 'Ga bisa dibuka', subtitle: _error!)
                : switch (kind) {
                    FileKind.text => _editor(),
                    FileKind.markdown => TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
                        Markdown(
                          key: ValueKey(_rev),
                          data: _ctl.text,
                          selectable: true,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 60),
                          onTapLink: (_, href, _) {
                            if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
                          },
                          styleSheet: mdStyle(context),
                        ),
                        _editor(),
                      ]),
                    FileKind.html => TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
                        WebViewWidget(controller: _web!),
                        _editor(),
                      ]),
                    FileKind.image => InteractiveViewer(
                        maxScale: 8,
                        child: Center(
                          child: Image.network(MediaServer.urlFor(_base!, widget.path),
                              errorBuilder: (_, e, _) => EmptyState(
                                  icon: Icons.broken_image_rounded, title: 'Gambar ga kebaca', subtitle: '$e')),
                        ),
                      ),
                    FileKind.video || FileKind.audio => MediaPlayer(
                        url: MediaServer.urlFor(_base!, widget.path), audio: kind == FileKind.audio, title: name),
                    FileKind.other => const SizedBox(),
                  }),
      ),
    );
  }

  Widget _editor() => CodeEditor(controller: _ctl, undo: _undo);
}

MarkdownStyleSheet mdStyle(BuildContext context) {
  final t = Theme.of(context);
  return MarkdownStyleSheet.fromTheme(t).copyWith(
    p: TextStyle(fontSize: 15, height: 1.55, color: C.text),
    code: TextStyle(fontFamily: monoFont, fontSize: 13, color: C.cyan, backgroundColor: C.surface2),
    codeblockDecoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
    codeblockPadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      color: C.surface2,
      border: const Border(left: BorderSide(color: C.violet, width: 3)),
    ),
    h1: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: C.text),
    h2: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: C.text),
    h3: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: C.text),
    a: const TextStyle(color: C.cyan, decoration: TextDecoration.underline),
    tableBorder: TableBorder.all(color: C.stroke),
  );
}

/// Monospace editor with a line-number gutter.
class CodeEditor extends StatefulWidget {
  const CodeEditor({super.key, required this.controller, required this.undo});
  final TextEditingController controller;
  final UndoHistoryController undo;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _scroll = ScrollController();
  final _gutterScroll = ScrollController();
  bool _wrap = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_gutterScroll.hasClients) _gutterScroll.jumpTo(_scroll.offset.clamp(0, _gutterScroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final lines = '\n'.allMatches(widget.controller.text).length + 1;
    const style = TextStyle(fontFamily: monoFont, fontSize: 13, height: 1.5);
    final field = TextField(
      controller: widget.controller,
      undoController: widget.undo,
      scrollController: _scroll,
      maxLines: null,
      expands: true,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      style: style.copyWith(color: C.text),
      decoration: const InputDecoration(
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(8, 12, 12, 200),
      ),
    );
    return Stack(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!_wrap)
          Container(
            width: 44,
            color: C.surface,
            child: ListView.builder(
              controller: _gutterScroll,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(0, 12, 8, 200),
              itemCount: lines,
              itemExtent: 13 * 1.5,
              itemBuilder: (_, i) => Text('${i + 1}', textAlign: TextAlign.right, style: style.copyWith(color: C.muted)),
            ),
          ),
        Expanded(
          child: _wrap
              ? field
              : LayoutBuilder(
                  builder: (_, box) => SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: box.maxWidth * 2.2, height: box.maxHeight, child: field),
                  ),
                ),
        ),
      ]),
      Positioned(
        right: 12,
        bottom: 12,
        child: Pressable(
          onTap: () => setState(() => _wrap = !_wrap),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_wrap ? Icons.wrap_text_rounded : Icons.notes_rounded, size: 16, color: C.muted),
              const SizedBox(width: 6),
              Text(_wrap ? 'wrap' : 'no-wrap', style: TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// Video/audio player streaming from the local media server.
class MediaPlayer extends StatefulWidget {
  const MediaPlayer({super.key, required this.url, required this.audio, required this.title});
  final String url;
  final bool audio;
  final String title;

  @override
  State<MediaPlayer> createState() => _MediaPlayerState();
}

class _MediaPlayerState extends State<MediaPlayer> with SingleTickerProviderStateMixin {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  String? _err;
  bool _ui = true;
  Timer? _hide;
  double? _drag; // slider position while the thumb is held

  @override
  void initState() {
    super.initState();
    _c.addListener(() {
      if (!mounted) return;
      _c.value.isPlaying ? _spin.repeat() : _spin.stop();
      setState(() {});
    });
    _c.initialize().then((_) {
      _c.play();
      _scheduleHide();
    }).catchError((e) {
      if (mounted) setState(() => _err = '$e');
    });
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (!widget.audio) _hide = Timer(const Duration(seconds: 3), () => mounted ? setState(() => _ui = false) : null);
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c.dispose();
    _spin.dispose();
    super.dispose();
  }

  String _t(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_err != null) {
      return EmptyState(icon: Icons.error_outline_rounded, title: 'Gagal muter', subtitle: _err!);
    }
    final v = _c.value;
    final pos = v.position, dur = v.duration;
    final controls = Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: widget.audio
          ? null
          : const BoxDecoration(
              gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            activeTrackColor: C.cyan,
            thumbColor: Colors.white,
            inactiveTrackColor: Colors.white24,
          ),
          child: Slider(
            value: dur.inMilliseconds == 0
                ? 0
                : (_drag ?? pos.inMilliseconds.toDouble()).clamp(0, dur.inMilliseconds.toDouble()),
            max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
            // Seek once on release: seeking on every drag event made the
            // player open (and drop) a new HTTP range request per frame.
            onChanged: (x) => setState(() {
              _drag = x;
              _hide?.cancel();
            }),
            onChangeEnd: (x) {
              _drag = null;
              _c.seekTo(Duration(milliseconds: x.round()));
              _scheduleHide();
            },
          ),
        ),
        Row(children: [
          Text(_t(_drag != null ? Duration(milliseconds: _drag!.round()) : pos), style: const TextStyle(fontFamily: monoFont, fontSize: 12, color: Colors.white70)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
            onPressed: () => _c.seekTo(pos - const Duration(seconds: 10)),
          ),
          Pressable(
            onTap: () {
              v.isPlaying ? _c.pause() : _c.play();
              _scheduleHide();
            },
            child: Container(
              width: 58,
              height: 58,
              decoration: const BoxDecoration(gradient: C.accent, shape: BoxShape.circle),
              child: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 32),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
            onPressed: () => _c.seekTo(pos + const Duration(seconds: 10)),
          ),
          const Spacer(),
          Text(_t(dur), style: const TextStyle(fontFamily: monoFont, fontSize: 12, color: Colors.white70)),
        ]),
      ]),
    );

    if (widget.audio) {
      return Container(
        color: C.termBg,
        child: Column(children: [
          const Spacer(),
          RotationTransition(
            turns: _spin,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                gradient: const SweepGradient(colors: [C.violet, C.cyan, C.pink, C.violet]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.4), blurRadius: 60)],
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: C.termBg, shape: BoxShape.circle),
                  child: const Icon(Icons.music_note_rounded, color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          if (v.isBuffering) const Padding(padding: EdgeInsets.all(8), child: Text('buffering…', style: TextStyle(color: Colors.white54))),
          const Spacer(),
          controls,
        ]),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() => _ui = !_ui);
        _scheduleHide();
      },
      child: Container(
        color: Colors.black,
        child: Stack(children: [
          Center(
            child: v.isInitialized
                ? AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(_c))
                : const CircularProgressIndicator(color: C.violet),
          ),
          if (v.isBuffering && v.isInitialized) const Center(child: CircularProgressIndicator(color: Colors.white54)),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AnimatedOpacity(
              opacity: _ui ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: IgnorePointer(ignoring: !_ui, child: SafeArea(top: false, child: controls)),
            ),
          ),
        ]),
      ),
    );
  }
}
