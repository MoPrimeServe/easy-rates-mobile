import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// Design-system guard — fails fast when a hardcoded design value leaks into a
// widget. Every colour, hex, and tint factor must trace to the theme layer
// (lib/theme/), never sit raw in a component or screen.
//
// Scope: scans lib/ EXCEPT lib/theme/ (the one place raw values legitimately
// live — palette, ramp, token store). Line comments are stripped before
// matching, so a value mentioned in prose is fine. To allow a deliberate
// exception on a single line, append a `// design-value-ok` marker.
//
// Runs under `flutter test`, so CI goes red the moment a leak lands.
void main() {
  // Patterns that indicate a design value bypassing the theme layer.
  // \bColors\.  matches the Material palette but NOT AppColors. (no word
  // boundary inside "AppColors"), so theme-layer constant refs stay legal.
  final forbidden = <String, RegExp>{
    'Material Colors.* palette':      RegExp(r'\bColors\.'),
    'raw Color(...) construction':    RegExp(r'\bColor\('),
    'Color.fromARGB(...)':            RegExp(r'Color\.fromARGB'),
    'hex colour literal (0x......)':  RegExp(r'0x[0-9A-Fa-f]{6,8}'),
    'numeric withAlpha()/withOpacity()':
        RegExp(r'withAlpha\(\s*[0-9]|withOpacity\('),
  };

  const allowMarker = 'design-value-ok';

  // Strip a // line comment (naive: ignores // inside string literals, which
  // this codebase doesn't use for these tokens) so prose never trips the guard.
  String stripComment(String line) {
    final i = line.indexOf('//');
    return i == -1 ? line : line.substring(0, i);
  }

  test('no hardcoded design values outside lib/theme/', () {
    final root = Directory('lib');
    expect(root.existsSync(), isTrue,
        reason: 'run from the package root (where lib/ lives)');

    final violations = <String>[];

    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      // Normalise separators so the exclusion holds on every platform.
      final rel = entity.path.replaceAll(r'\', '/');
      if (rel.contains('lib/theme/')) continue;

      final lines = entity.readAsLinesSync();
      for (var n = 0; n < lines.length; n++) {
        final raw = lines[n];
        if (raw.contains(allowMarker)) continue;
        final code = stripComment(raw);
        forbidden.forEach((label, re) {
          if (re.hasMatch(code)) {
            violations.add('$rel:${n + 1}  [$label]  ${raw.trim()}');
          }
        });
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Hardcoded design values must move into lib/theme/ (tokens) or be '
          'marked `// $allowMarker`:\n  ${violations.join('\n  ')}',
    );
  });
}
