part of 'song_parser.dart';

final RegExp _sungRe = RegExp(r'[\p{L}\p{N}]', unicode: true);

bool _isSung(String text) => _sungRe.hasMatch(text);

class _SlotChords {
  final Chord first;
  final List<Token> extras = [];

  _SlotChords(this.first);
}

class _LineLayer {
  final Map<int, _SlotChords> slots = {};
  final Map<int, List<_SlotChords>> gaps = {};
  final List<Token> tail = [];

  bool get isEmpty => slots.isEmpty && gaps.isEmpty && tail.isEmpty;
}

ParsedSong propagateChords(ParsedSong song) {
  const kinds = [SectionKind.verse, SectionKind.chorus, SectionKind.bridge];
  final sections = song.sections.toList();

  for (final kind in kinds) {
    final templateIndex = sections.indexWhere(
      (s) => s.kind == kind && s.lines.any(_lineHasChords),
    );
    if (templateIndex == -1) continue;
    final template = sections[templateIndex];
    for (var i = templateIndex + 1; i < sections.length; i++) {
      if (sections[i].kind == kind) {
        sections[i] = _applyTemplate(template, sections[i]);
      }
    }
  }

  return ParsedSong(sections, tonic: song.tonic, tonicName: song.tonicName);
}

bool _lineHasChords(Line line) =>
    line.tokens.any((t) => t is SyllableToken && t.chord != null);

Section _applyTemplate(Section template, Section target) {
  return Section(
    title: target.title,
    kind: target.kind,
    lines: [
      for (var i = 0; i < target.lines.length; i++)
        i < template.lines.length
            ? _applyLine(template.lines[i], target.lines[i])
            : target.lines[i],
    ],
  );
}

Line _applyLine(Line template, Line target) {
  final layer = _layerOf(template);
  if (layer.isEmpty) return target;
  if (!target.tokens.any((t) => t is SyllableToken)) return target;

  var index = -1;
  final tokens = <Token>[];
  for (final t in target.tokens) {
    if (t is SyllableToken) {
      if (t.text.isEmpty) {
        if (t.chord == null) tokens.add(t);
        continue;
      }
      if (!_isSung(t.text)) {
        tokens.add(t);
        continue;
      }
      index++;
      for (final slot in layer.gaps[index - 1] ?? const <_SlotChords>[]) {
        tokens.add(SyllableToken('', chord: slot.first));
        tokens.addAll(slot.extras);
      }
      final slot = layer.slots[index];
      if (slot == null) {
        tokens.add(SyllableToken(t.text, dash: t.dash));
      } else {
        tokens.add(SyllableToken(t.text, dash: t.dash, chord: slot.first));
        tokens.addAll(slot.extras);
      }
    } else if (t is ChordToken) {
      continue;
    } else if (t is InlineToken) {
      if (!t.glued) tokens.add(t);
    } else {
      tokens.add(t);
    }
  }
  tokens.addAll(layer.tail);
  return Line(tokens);
}

_LineLayer _layerOf(Line line) {
  final layer = _LineLayer();
  var index = -1;
  _SlotChords? current;
  for (final t in line.tokens) {
    if (t is SyllableToken) {
      if (t.text.isEmpty) {
        if (t.chord != null) {
          current = _SlotChords(t.chord!);
          layer.gaps.putIfAbsent(index, () => []).add(current);
        } else {
          current = null;
        }
      } else if (_isSung(t.text)) {
        index++;
        current = t.chord == null ? null : _SlotChords(t.chord!);
        if (current != null) layer.slots[index] = current;
      } else {
        current = null;
      }
    } else if (t is ChordToken) {
      if (t.endOfLine) {
        layer.tail.add(t);
        current = null;
      } else {
        current?.extras.add(t);
      }
    } else if (t is InlineToken) {
      if (t.glued) {
        current?.extras.add(t);
      } else {
        current = null;
      }
    } else {
      current = null;
    }
  }
  return layer;
}
