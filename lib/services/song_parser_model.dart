part of 'song_parser.dart';

enum SectionKind { verse, chorus, bridge, intro, outro, solo, unknown }

const Map<String, int> _letterPitch = {
  'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11, 'H': 11,
};

const List<String> _pitchNames = [
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

int _mod12(int pitch) => ((pitch % 12) + 12) % 12;

String pitchName(int pitch) => _pitchNames[_mod12(pitch)];

int _pitchOf(String root) {
  final letter = root.substring(0, 1);
  final accidental = root.length > 1 ? root.substring(1) : '';
  var pitch = _letterPitch[letter]!;
  if (accidental == '#' || accidental == '♯') pitch += 1;
  if (accidental == 'b' || accidental == '♭') pitch -= 1;
  return _mod12(pitch);
}

// Абсолютный аккорд (питчи) строкового слоя; в модель уходит Chord вычитанием тоники.
class PitchChord {
  final int root;
  final String quality;
  final int? bass;

  const PitchChord({required this.root, this.quality = '', this.bass});

  String get display => bass == null
      ? '${pitchName(root)}$quality'
      : '${pitchName(root)}$quality/${pitchName(bass!)}';

  @override
  bool operator ==(Object other) =>
      other is PitchChord &&
      other.root == root &&
      other.quality == quality &&
      other.bass == bass;

  @override
  int get hashCode => Object.hash(root, quality, bass);

  @override
  String toString() => display;
}

// Смещения от тоники; тоника не хранится, имя считает display().
class Chord {
  final int rootOffset;
  final String quality;
  final int? bassOffset;

  const Chord({
    required this.rootOffset,
    this.quality = '',
    this.bassOffset,
  });

  Chord.fromPitch(PitchChord chord, int tonic)
      : rootOffset = _mod12(chord.root - tonic),
        quality = chord.quality,
        bassOffset =
            chord.bass == null ? null : _mod12(chord.bass! - tonic);

  // Смещение 0 — тоника — пишем tonicName, прочие по таблице имён.
  String display(int tonic, [String? tonicName]) {
    String name(int offset) => offset == 0 && tonicName != null
        ? tonicName
        : pitchName(tonic + offset);
    final root = name(rootOffset);
    final bass =
        bassOffset == null ? null : name(bassOffset!);
    return bass == null ? '$root$quality' : '$root$quality/$bass';
  }

  @override
  bool operator ==(Object other) =>
      other is Chord &&
      other.rootOffset == rootOffset &&
      other.quality == quality &&
      other.bassOffset == bassOffset;

  @override
  int get hashCode => Object.hash(rootOffset, quality, bassOffset);

  @override
  String toString() => '$rootOffset$quality';
}

sealed class Token {
  const Token();
}

// right — первый слог, left — последний, both — середина; начало слова — none|right.
enum SyllableDash { none, right, both, left }

class SyllableToken extends Token {
  // Ведущий дефис исходника — в тексте; растяжечный дефис модель не хранит (только рендер).
  final String text;

  final SyllableDash dash;

  final Chord? chord;

  const SyllableToken(this.text, {this.dash = SyllableDash.none, this.chord});

  @override
  bool operator ==(Object other) =>
      other is SyllableToken &&
      other.text == text &&
      other.dash == dash &&
      other.chord == chord;

  @override
  int get hashCode => Object.hash(text, dash, chord);
}

class ChordToken extends Token {
  final Chord chord;

  final bool endOfLine;

  const ChordToken(this.chord, {this.endOfLine = false});

  @override
  bool operator ==(Object other) =>
      other is ChordToken &&
      other.chord == chord &&
      other.endOfLine == endOfLine;

  @override
  int get hashCode => Object.hash(chord, endOfLine);
}

class RawToken extends Token {
  final String text;
  const RawToken(this.text);

  @override
  bool operator ==(Object other) => other is RawToken && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class AnnotationToken extends Token {
  final String text;

  const AnnotationToken(this.text);

  @override
  bool operator ==(Object other) =>
      other is AnnotationToken && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

class InlineToken extends Token {
  // ~ вплотную к предыдущему аккорду (glued) или пометка «2x»/«// …» через пробел.
  final String text;

  final bool glued;

  const InlineToken(this.text, {this.glued = false});

  @override
  bool operator ==(Object other) =>
      other is InlineToken && other.text == text && other.glued == glued;

  @override
  int get hashCode => Object.hash(text, glued);
}

// Слитная пара «аккорды+текст» — одна Line: первый аккорд в SyllableToken.chord, смены — ChordToken, за концом слов — ChordToken(endOfLine).
class Line {
  final List<Token> tokens;

  const Line(this.tokens);

  bool get isProgression =>
      tokens.isNotEmpty && tokens.every((t) => t is! SyllableToken);
}

class Section {
  final String? title;

  final SectionKind kind;
  final List<Line> lines;

  const Section({
    this.title,
    this.kind = SectionKind.unknown,
    required this.lines,
  });
}

class ParsedSong {
  final List<Section> sections;

  final int tonic;

  // Написание тоники как в исходнике («G#», не «Ab»).
  final String tonicName;

  const ParsedSong(this.sections, {this.tonic = 0, this.tonicName = 'C'});

  // Меняем только тонику — смещения аккордов те же.
  ParsedSong transposed(int semitones) => semitones == 0
      ? this
      : ParsedSong(sections,
          tonic: _mod12(tonic + semitones),
          tonicName: pitchName(tonic + semitones));
}
