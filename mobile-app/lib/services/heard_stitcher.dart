import 'dart:math' show max, min;

import 'heard_feed.dart';

final class StitchResult {
  final List<String> logLines;
  final String? sendText;
  final String? phraseView;

  const StitchResult({required this.logLines, this.sendText, this.phraseView});
}

final class HeardStitcher {
  final int minSendWords;
  final int tailWords;
  final int finalsKeep;
  final List<String> _finals = [];
  List<String> _prevWords = [];
  String _prevSessionText = '';
  double _prevConf = -1;

  HeardStitcher({this.minSendWords = 8, this.tailWords = 32, this.finalsKeep = 8});

  void reset() {
    _prevWords = [];
    _prevSessionText = '';
    _prevConf = -1;
  }

  void clearFinals() => _finals.clear();

  StitchResult onEvent(HeardEvent event) {
    final sessionText = event.sessionText;
    if (sessionText.isEmpty) {
      return StitchResult(logLines: [
        '${event.isFinal ? 'final' : 'partial'} '
            'conf=${event.confidence.toStringAsFixed(2)} words=0',
      ]);
    }
    final words = sessionText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final logLines = <String>[];
    final marks = _markerVerdicts(words, event.confidence);
    if (_headChanged(words)) {
      _storeFinal(_prevSessionText, logLines);
    }
    final stitched = _stitchForSend(words);
    final stitchedText = stitched.join(' ');
    logLines.add(
      '${event.isFinal ? 'final' : 'partial'} '
      'conf=${event.confidence.toStringAsFixed(2)} '
      'words=${stitched.length}'
          '${stitched.length > words.length ? ' +${stitched.length - words.length}' : ''}'
          '${marks.isEmpty ? '' : ' $marks'}: '
          '${stitchedText.length > 60 ? stitchedText.substring(stitchedText.length - 60) : stitchedText}',
    );
    _prevWords = words;
    _prevSessionText = sessionText;
    _prevConf = event.confidence;
    return StitchResult(
      logLines: logLines,
      sendText: stitched.isEmpty ? null : stitchedText,
      phraseView: stitchedText,
    );
  }

  String _markerVerdicts(List<String> words, double conf) {
    if (_prevWords.isEmpty) return '';
    final pfx = _commonPrefixWords(_prevWords, words);
    final hd = _headChanged(words) ? 'new' : 'ok';
    final cf = _prevConf != 0.0 && conf == 0.0 ? 'new' : 'ok';
    return 'pfx=$pfx hd=$hd cf=$cf';
  }

  bool _headChanged(List<String> words) {
    if (_prevWords.isEmpty) return false;
    final pfx = _commonPrefixWords(_prevWords, words);
    final sameHead = pfx >= min(3, min(_prevWords.length, words.length)) ||
        _headInside(words, _prevWords);
    return !sameHead;
  }

  void _storeFinal(String text, List<String> logLines) {
    if (_finals.isNotEmpty) {
      final last = _finals.last;
      if (last == text) return;
      final a = last.toLowerCase();
      final b = text.toLowerCase();
      if (a.startsWith(b) || b.startsWith(a)) {
        if (text.length > last.length) {
          _finals[_finals.length - 1] = text;
          logLines.add('финал заменён (hd): ${text.split(' ').length} слов');
        }
        return;
      }
    }
    _finals.add(text);
    if (_finals.length > finalsKeep) _finals.removeAt(0);
    logLines.add('финал сохранён (hd): ${text.split(' ').length} слов');
  }

  static bool _sameWord(String a, String b) {
    final x = a.toLowerCase();
    final y = b.toLowerCase();
    if (x == y) return true;
    if (x.length < 2 || y.length < 2) return false;
    return x.startsWith(y) || y.startsWith(x);
  }

  static int _commonPrefixWords(List<String> a, List<String> b) {
    var n = 0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (!_sameWord(a[i], b[i])) break;
      n++;
    }
    return n;
  }

  static bool _headInside(List<String> p2, List<String> p1) {
    if (p2.isEmpty) return true;
    if (p2.length < 2) {
      return p1.any((w) => _sameWord(w, p2.first));
    }
    for (var i = 0; i + 1 < p1.length; i++) {
      if (_sameWord(p1[i], p2[0]) && _sameWord(p1[i + 1], p2[1])) {
        return true;
      }
    }
    return false;
  }

  List<String> _stitchForSend(List<String> words) {
    final stitched = List<String>.of(words);
    for (var i = _finals.length - 1;
        i >= 0 && stitched.length < minSendWords;
        i--) {
      final fWords = _finals[i]
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      final need = minSendWords - stitched.length;
      stitched.insertAll(
        0,
        fWords.skip(max(0, fWords.length - need)),
      );
    }
    if (stitched.length > tailWords) {
      stitched.removeRange(0, stitched.length - tailWords);
    }
    return stitched;
  }
}
