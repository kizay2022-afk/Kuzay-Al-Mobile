class SourceLocation {
  final int startLine;
  final int endLine;
  final int startOffset;
  final int endOffset;
  const SourceLocation(this.startLine,this.endLine,this.startOffset,this.endOffset);
}

class SelfEditorLocator {
  static SourceLocation? locate(String source, String fragment) {
    if (fragment.isEmpty) return null;
    final start = source.indexOf(fragment);
    if (start < 0 || source.indexOf(fragment, start + 1) >= 0) return null;
    final end = start + fragment.length;
    int lineAt(int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;
    return SourceLocation(lineAt(start), lineAt(end), start, end);
  }

  static List<String> numbered(String source, {int? highlightStart, int? highlightEnd}) {
    final lines = source.split('\n');
    final out = <String>[];
    for (var i=0;i<lines.length;i++) {
      final n=i+1;
      final marked=highlightStart!=null && highlightEnd!=null && n>=highlightStart && n<=highlightEnd;
      out.add((marked ? '▶ ' : '  ') + n.toString().padLeft(4) + ' | ' + lines[i]);
    }
    return out;
  }
}
