import 'dart:io';

import 'package:song_book/services/lyric_locator.dart';
import 'package:song_book/services/song_parser.dart';

final RegExp _eventRe =
    RegExp(r'^(\S+) (partial|final) conf=\S+ alt=\d+ pos=([0-9.]+): (.*)$');
final RegExp _noteRe = RegExp(r'^(\S+) note: (.*)$');

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run tool/replay_locator.dart <song.txt> <log>');
    exit(2);
  }
  final locator = LyricLocator(parseSong(File(args[0]).readAsStringSync()));
  stdout.writeln('lines in song: ${locator.lineCount}');

  var prev = 0;
  var events = 0;
  var matched = 0;
  final diffs = <double>[];
  var backwards = 0;

  for (final raw in File(args[1]).readAsLinesSync()) {
    final note = _noteRe.firstMatch(raw);
    if (note != null) {
      stdout.writeln('${note[1]}  ---- ${note[2]} ----');
      continue;
    }
    final m = _eventRe.firstMatch(raw);
    if (m == null) continue;
    events++;
    final pos = double.parse(m[3]!);
    final text = m[4]!.trim();
    final line = locator.locate(LyricLocator.keysOf(text), previousLine: prev);
    if (line == null) {
      stdout.writeln(
          '${m[1]}  pos=${pos.toStringAsFixed(1)}  line=NULL  "$text"');
      continue;
    }
    matched++;
    if (line < prev) backwards++;
    prev = line;
    final diff = line - pos;
    diffs.add(diff.abs());
    stdout.writeln(
        '${m[1]}  pos=${pos.toStringAsFixed(1)}  line=$line  Δ=${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}  "$text"');
  }

  stdout
    ..writeln('---')
    ..writeln('events: $events  matched: $matched  back: $backwards');
  if (diffs.isNotEmpty) {
    diffs.sort();
    stdout.writeln(
        '|Δ| p50=${diffs[diffs.length ~/ 2].toStringAsFixed(1)}  max=${diffs.last.toStringAsFixed(1)}');
  }
  if (events == 0) {
    stdout.writeln('нет partial/final строк — реплеить нечего');
  }
}
