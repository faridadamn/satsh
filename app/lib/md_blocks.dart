/// Splits a markdown answer into prose, fenced code and blockquotes so each
/// code block / quote can get its own copy button.
class MdBlock {
  const MdBlock(this.kind, this.text, {this.lang = ''});
  final String kind; // text | code | quote
  final String text; // code: raw code; quote: text without the "> "
  final String lang;

  @override
  String toString() => '$kind[$lang]: $text';
}

List<MdBlock> splitBlocks(String md) {
  final out = <MdBlock>[];
  final lines = md.replaceAll('\r\n', '\n').split('\n');
  final prose = <String>[];
  void flushProse() {
    final t = prose.join('\n').trim();
    if (t.isNotEmpty) out.add(MdBlock('text', t));
    prose.clear();
  }

  final fenceRe = RegExp(r'^ {0,3}(`{3,}|~{3,})\s*([^\s`]*)');
  final quoteRe = RegExp(r'^ {0,3}>\s?(.*)$');
  var i = 0;
  while (i < lines.length) {
    final l = lines[i];
    final f = fenceRe.firstMatch(l);
    if (f != null) {
      flushProse();
      final fence = f.group(1)!;
      final code = <String>[];
      i++;
      while (i < lines.length && !RegExp('^ {0,3}${RegExp.escape(fence[0])}{${fence.length},}\\s*\$').hasMatch(lines[i])) {
        code.add(lines[i]);
        i++;
      }
      i++; // closing fence (or end of text while still streaming)
      out.add(MdBlock('code', code.join('\n'), lang: f.group(2) ?? ''));
      continue;
    }
    final q = quoteRe.firstMatch(l);
    if (q != null) {
      flushProse();
      final quote = <String>[];
      while (i < lines.length) {
        final m = quoteRe.firstMatch(lines[i]);
        if (m == null) break;
        quote.add(m.group(1)!);
        i++;
      }
      out.add(MdBlock('quote', quote.join('\n').trim()));
      continue;
    }
    prose.add(l);
    i++;
  }
  flushProse();
  return out;
}
