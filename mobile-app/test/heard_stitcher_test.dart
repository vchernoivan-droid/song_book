import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/heard_feed.dart';
import 'package:song_book/services/heard_stitcher.dart';

HeardEvent ev(String text, {double conf = -1.0, bool isFinal = false}) =>
    HeardEvent(sessionText: text, confidence: conf, isFinal: isFinal);

void main() {
  test('пустое событие: одна строка words=0, ничего не отправляется', () {
    final s = HeardStitcher();
    final res = s.onEvent(ev('', conf: 0.0));
    expect(res.logLines, ['partial conf=0.00 words=0']);
    expect(res.sendText, isNull);
    expect(res.phraseView, isNull);
  });

  test('первый партиал без марок, отправляется как есть', () {
    final s = HeardStitcher();
    final res = s.onEvent(ev('поехали города'));
    expect(res.logLines.single,
        'partial conf=-1.00 words=2: поехали города');
    expect(res.sendText, 'поехали города');
    expect(res.phraseView, 'поехали города');
  });

  test('рост фразы: hd=ok, финал не сохраняется', () {
    final s = HeardStitcher()
      ..onEvent(ev('поехали города'))
      ..onEvent(ev('поехали города зимние'));
    final res = s.onEvent(ev('поехали города зимние в'));
    expect(
      res.logLines.single,
      'partial conf=-1.00 words=4 pfx=3 hd=ok cf=ok: '
      'поехали города зимние в',
    );
    expect(res.logLines.any((l) => l.contains('финал')), isFalse);
  });

  test('смена головы: финал (hd) сохраняется и подклеивается до 8 слов', () {
    final s = HeardStitcher()
      ..onEvent(ev('поехали города зимние снежные'))
      ..onEvent(ev('поехали города зимние снежные в'));
    final res = s.onEvent(ev('не стоит вовсе'));
    expect(res.logLines.first, 'финал сохранён (hd): 5 слов');
    expect(res.logLines[1],
        'partial conf=-1.00 words=8 +5 pfx=0 hd=new cf=ok: '
        'поехали города зимние снежные в не стоит вовсе');
    expect(res.sendText, 'поехали города зимние снежные в не стоит вовсе');
  });

  test('флип конфиденса не хранит финал, но помечается cf=new', () {
    final s = HeardStitcher()
      ..onEvent(ev('раз два три'))
      ..onEvent(ev('раз два три четыре'));
    final res = s.onEvent(ev('раз два три четыре пять', conf: 0.0));
    expect(res.logLines.single,
        'partial conf=0.00 words=5 pfx=4 hd=ok cf=new: '
        'раз два три четыре пять');
    expect(res.logLines.any((l) => l.contains('финал')), isFalse);
  });

  test('повтор того же финала не дублируется', () {
    final s = HeardStitcher()
      ..onEvent(ev('а б в'))
      ..onEvent(ev('иное'))
      ..reset()
      ..onEvent(ev('а б в'));
    final res = s.onEvent(ev('другое'));
    expect(res.logLines.single,
        'partial conf=-1.00 words=4 +3 pfx=0 hd=new cf=ok: а б в другое');
  });

  test('пересказ финала с начала и рост: заменяет на длинный', () {
    final s = HeardStitcher()
      ..onEvent(ev('а б в'))
      ..onEvent(ev('иное')) // финал «а б в»
      ..reset()
      ..onEvent(ev('а б в'))
      ..onEvent(ev('а б в г'));
    final res = s.onEvent(ev('переключение'));
    expect(res.logLines.first, 'финал заменён (hd): 4 слов');
  });

  test('reset сбрасывает маркеры: первый партиал снова без меток', () {
    final s = HeardStitcher()..onEvent(ev('раз два'))..reset();
    final res = s.onEvent(ev('новое слово'));
    expect(res.logLines.single, 'partial conf=-1.00 words=2: новое слово');
  });

  test('clearFinals убирает подклейку', () {
    final s = HeardStitcher()
      ..onEvent(ev('а б в г д'))
      ..onEvent(ev('иное'))
      ..clearFinals();
    final res = s.onEvent(ev('иное продолжение'));
    expect(res.sendText, 'иное продолжение');
    expect(res.logLines.single,
        'partial conf=-1.00 words=2 pfx=1 hd=ok cf=ok: иное продолжение');
  });

  test('длинная фраза обрезается до tailWords', () {
    final s = HeardStitcher();
    final long = List.generate(40, (i) => 'w$i').join(' ');
    final res = s.onEvent(ev(long));
    final sent = res.sendText!.split(' ');
    expect(sent.length, 32);
    expect(sent.first, 'w8');
    expect(sent.last, 'w39');
    expect(res.logLines.single, contains('words=32'));
  });

  test('финальное событие помечается final и не меняет стич', () {
    final s = HeardStitcher()..onEvent(ev('а б в'));
    final res = s.onEvent(ev('а б в г', isFinal: true, conf: 0.0));
    expect(res.logLines.single, startsWith('final conf=0.00'));
    expect(res.sendText, 'а б в г');
  });

  test('ReplayHeardFeed проигрывает сценарий в стичер', () async {
    final feed = ReplayHeardFeed(script: [
      ev('поехали города'),
      ev('поехали города зимние'),
      ev('не стоит вовсе'),
    ]);
    final out = <String>[];
    final sub = feed.events.listen((e) => out.add(
          HeardStitcher().onEvent(e).sendText ?? '',
        ));
    await feed.start(null);
    await sub.cancel();
    await feed.cancel();
    expect(out, ['поехали города', 'поехали города зимние', 'не стоит вовсе']);
    expect(await feed.statuses.isEmpty, isTrue);
  });
}
