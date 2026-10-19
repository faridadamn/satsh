import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../media_server.dart';
import '../models.dart';
import '../sftp_download.dart';
import 'file_viewer_page.dart';
import '../ssh_manager.dart';
import '../theme.dart';
import '../widgets.dart';

class SftpPage extends StatefulWidget {
  const SftpPage({super.key, required this.host});
  final Host host;

  @override
  State<SftpPage> createState() => _SftpPageState();
}

class _SftpPageState extends State<SftpPage> {
  SftpClient? _sftp;
  String _path = '';
  List<SftpName> _items = [];
  Set<String> _linkDirs = {}; // symlinks that point at a directory
  bool _loading = true;
  String? _error;
  bool _showHidden = false;
  String? _progressLabel;
  double? _progress;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    if (_cancel?.isCompleted == false) _cancel!.complete();
    _sftp?.close();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _sftp = await SshManager.i.sftp(widget.host);
      final home = await _sftp!.absolute('.');
      await _open(home);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _open(String path) async {
    setState(() => _loading = true);
    try {
      final list = await _sftp!.listdir(path);
      list.removeWhere((e) => e.filename == '.' || e.filename == '..');
      // Symlinked folders (~/storage on Termux, /var/www links…) used to show
      // up as files and couldn't be opened. Resolve them (stat follows links).
      final base = path == '/' ? '' : path;
      final linkDirs = <String>{};
      await Future.wait(list.where((e) => e.attr.isSymbolicLink).take(200).map((e) async {
        try {
          if ((await _sftp!.stat('$base/${e.filename}')).isDirectory) linkDirs.add(e.filename);
        } catch (_) {} // dangling link
      }));
      bool isDir(SftpName e) => e.attr.isDirectory || linkDirs.contains(e.filename);
      list.sort((a, b) {
        final d = (isDir(b) ? 1 : 0) - (isDir(a) ? 1 : 0);
        return d != 0 ? d : a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      });
      setState(() {
        _path = path;
        _items = list;
        _linkDirs = linkDirs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() => _loading = false);
      toast('Ga bisa buka: $e', error: true);
    }
  }

  bool _isDir(SftpName f) => f.attr.isDirectory || _linkDirs.contains(f.filename);

  String _join(String name) => _path == '/' ? '/$name' : '$_path/$name';

  String get _parent {
    if (_path == '/' || _path.isEmpty) return '/';
    final i = _path.lastIndexOf('/');
    return i <= 0 ? '/' : _path.substring(0, i);
  }

  Completer<void>? _cancel;

  Future<void> _download(SftpName f) async {
    if (_cancel != null) {
      toast('Tunggu download yang lagi jalan beres dulu', error: true);
      return;
    }
    final total = f.attr.size ?? 0;
    final pub = await SftpDownload.publicDir();
    final dir = pub ?? await SftpDownload.privateDir();
    final dest = SftpDownload.freeName(dir, f.filename);
    final cancel = _cancel = Completer<void>();
    setState(() {
      _progressLabel = 'Download ${f.filename}';
      _progress = total > 0 ? 0 : null;
    });
    try {
      final out = await SftpDownload.fetch(_sftp!, _join(f.filename), dest, cancel: cancel.future, onProgress: (n) {
        if (mounted && total > 0) setState(() => _progress = n / total);
      });
      if (!mounted) return;
      if (pub != null) {
        toast('Kesimpen di Download/satsh/${out.uri.pathSegments.last}');
      } else {
        // No storage permission: offer it through the share sheet instead.
        toast('Izin file belum ada — pilih tempat simpennya ya');
        await SharePlus.instance.share(ShareParams(files: [XFile(out.path)]));
      }
    } catch (e) {
      if (mounted) toast(e == 'Dibatalin' ? 'Download dibatalin' : 'Gagal download: $e', error: e != 'Dibatalin');
    } finally {
      _cancel = null;
      if (mounted) setState(() => _progressLabel = null);
    }
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    var ok = 0;
    for (final pf in files) {
      try {
        final size = await pf.length() ?? 0;
        setState(() {
          _progressLabel = 'Upload ${pf.name}';
          _progress = size > 0 ? 0 : null;
        });
        var tick = DateTime.fromMillisecondsSinceEpoch(0);
        final remote = await _sftp!.open(_join(pf.name),
            mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate);
        try {
          await remote.write(pf.readAsByteStream(), onProgress: (n) {
            // ~10 UI updates a second instead of one per 32 KB chunk.
            final now = DateTime.now();
            if (!mounted || size <= 0 || now.difference(tick).inMilliseconds < 100) return;
            tick = now;
            setState(() => _progress = n / size);
          });
        } finally {
          await remote.close();
        }
        ok++;
      } catch (e) {
        toast('Gagal upload ${pf.name}: $e', error: true);
      }
    }
    if (!mounted) return;
    setState(() => _progressLabel = null);
    if (ok > 0) toast(ok == files.length ? 'Upload beres' : 'Upload beres $ok dari ${files.length} file');
    _open(_path);
  }

  Future<void> _view(SftpName f, {bool asText = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FileViewerPage(sftp: _sftp!, path: _join(f.filename), size: f.attr.size, forceText: asText),
      ),
    );
    _open(_path);
  }

  Future<void> _newFile() async {
    final name = await askText(context, 'File baru', hint: 'mis. notes.md');
    if (name == null || name.trim().isEmpty) return;
    try {
      final f = await _sftp!.open(_join(name.trim()),
          mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.exclusive);
      await f.close();
      await _open(_path);
      final created = _items.where((e) => e.filename == name.trim()).firstOrNull;
      if (created != null) _view(created, asText: kindOf(created.filename) == FileKind.other);
    } catch (e) {
      toast('Gagal: $e', error: true);
    }
  }

  Future<void> _mkdir() async {
    final name = await askText(context, 'Folder baru', hint: 'nama folder');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _sftp!.mkdir(_join(name.trim()));
      _open(_path);
    } catch (e) {
      toast('Gagal: $e', error: true);
    }
  }

  void _menu(SftpName f) {
    final full = _join(f.filename);
    showSheet(
      useSafeArea: true,
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(f.filename,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (!_isDir(f)) ...[
            ListTile(
              leading: const Icon(Icons.visibility_rounded),
              title: Text(switch (kindOf(f.filename)) {
                FileKind.video || FileKind.audio => 'Putar',
                FileKind.image => 'Lihat',
                FileKind.html || FileKind.markdown => 'Preview & edit',
                _ => 'Buka / edit',
              }),
              onTap: () {
                Navigator.pop(c);
                _view(f);
              },
            ),
            if (kindOf(f.filename) != FileKind.text)
              ListTile(
                leading: const Icon(Icons.edit_note_rounded),
                title: const Text('Edit sebagai teks'),
                onTap: () {
                  Navigator.pop(c);
                  _view(f, asText: true);
                },
              ),
          ],
          if (!_isDir(f))
            ListTile(
              leading: const Icon(Icons.download_rounded),
              title: const Text('Download ke HP'),
              onTap: () {
                Navigator.pop(c);
                _download(f);
              },
            ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline_rounded),
            title: const Text('Rename'),
            onTap: () async {
              Navigator.pop(c);
              final n = await askText(context, 'Rename', initial: f.filename);
              if (n == null || n.trim().isEmpty || n == f.filename) return;
              try {
                await _sftp!.rename(full, _join(n.trim()));
                _open(_path);
              } catch (e) {
                toast('Gagal: $e', error: true);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy path'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: full));
              Navigator.pop(c);
              toast('Path ke-copy');
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: C.red),
            title: const Text('Hapus', style: TextStyle(color: C.red)),
            onTap: () async {
              Navigator.pop(c);
              if (!await confirm(context, 'Hapus ${f.filename}?',
                  f.attr.isDirectory ? 'Folder harus kosong dulu.' : 'Ga bisa di-undo.')) {
                return;
              }
              try {
                f.attr.isDirectory ? await _sftp!.rmdir(full) : await _sftp!.remove(full);
                _open(_path);
              } catch (e) {
                toast('Gagal hapus: $e', error: true);
              }
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  String _size(int? b) {
    if (b == null) return '';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
  }

  IconData _icon(SftpName f) {
    if (_linkDirs.contains(f.filename)) return Icons.folder_special_rounded;
    if (f.attr.isDirectory) return Icons.folder_rounded;
    if (f.attr.isSymbolicLink) return Icons.link_rounded;
    final n = f.filename.toLowerCase();
    switch (kindOf(n)) {
      case FileKind.image:
        return Icons.image_rounded;
      case FileKind.video:
        return Icons.movie_rounded;
      case FileKind.audio:
        return Icons.music_note_rounded;
      case FileKind.html:
        return Icons.html_rounded;
      case FileKind.markdown:
        return Icons.article_rounded;
      default:
    }
    if (RegExp(r'\.(zip|tar|gz|xz|7z|rar)$').hasMatch(n)) return Icons.archive_rounded;
    if (RegExp(r'\.(py|js|ts|dart|sh|json|ya?ml|toml|php|go|rs|c|cpp|html|css)$').hasMatch(n)) {
      return Icons.code_rounded;
    }
    return Icons.description_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final items = _showHidden ? _items : _items.where((e) => !e.filename.startsWith('.')).toList();
    return PopScope(
      canPop: _path == '/' || _path.isEmpty || _error != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _open(_parent);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.host.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(_path, style: TextStyle(fontSize: 11, color: C.muted, fontFamily: monoFont)),
          ]),
          actions: [
            IconButton(
              tooltip: 'File tersembunyi',
              icon: Icon(_showHidden ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              onPressed: () => setState(() => _showHidden = !_showHidden),
            ),
            IconButton(icon: const Icon(Icons.note_add_rounded), onPressed: _sftp == null ? null : _newFile),
            IconButton(icon: const Icon(Icons.create_new_folder_rounded), onPressed: _sftp == null ? null : _mkdir),
            IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _sftp == null ? null : () => _open(_path)),
          ],
          bottom: _progressLabel == null
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(34),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('$_progressLabel  ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                        ),
                        if (_cancel != null)
                          GestureDetector(
                            onTap: () {
                              if (_cancel?.isCompleted == false) _cancel!.complete();
                            },
                            child: Text('Batal', style: TextStyle(fontSize: 12, color: C.red, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                            value: _progress, minHeight: 4, color: C.cyan, backgroundColor: C.surface2),
                      ),
                    ]),
                  ),
                ),
        ),
        floatingActionButton: _sftp == null
            ? null
            : Pressable(
                onTap: _upload,
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  decoration: BoxDecoration(
                    gradient: C.accent,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: C.violet.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.upload_rounded, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
        body: _error != null
            ? EmptyState(icon: Icons.cloud_off_rounded, title: 'Gagal konek SFTP', subtitle: _error!)
            : AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _loading && _items.isEmpty
                    ? const Center(child: CircularProgressIndicator(color: C.violet))
                    : RefreshIndicator(
                        key: ValueKey(_path),
                        color: C.violet,
                        onRefresh: () => _open(_path),
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                          itemCount: items.length + (_path == '/' ? 0 : 1),
                          itemBuilder: (_, idx) {
                            if (_path != '/' && idx == 0) {
                              return _Row(
                                icon: Icons.subdirectory_arrow_left_rounded,
                                name: '..',
                                meta: 'naik satu folder',
                                color: C.muted,
                                onTap: () => _open(_parent),
                              );
                            }
                            final f = items[idx - (_path == '/' ? 0 : 1)];
                            return StaggerIn(
                              index: idx,
                              child: _Row(
                                icon: _icon(f),
                                name: f.filename,
                                meta: _isDir(f) ? (f.attr.isSymbolicLink ? 'link folder' : 'folder') : _size(f.attr.size),
                                color: _isDir(f) ? C.violet : C.cyan,
                                onTap: () => _isDir(f)
                                    ? _open(_join(f.filename))
                                    : (kindOf(f.filename) == FileKind.other ? _menu(f) : _view(f)),
                                onLong: () => _menu(f),
                              ),
                            );
                          },
                        ),
                      ),
              ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.name, required this.meta, required this.color, required this.onTap, this.onLong});
  final IconData icon;
  final String name;
  final String meta;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLong;

  @override
  Widget build(BuildContext context) => Pressable(
        scale: 0.98,
        onTap: onTap,
        onLongPress: onLong,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            Text(meta, style: TextStyle(color: C.muted, fontSize: 12)),
          ]),
        ),
      );
}
