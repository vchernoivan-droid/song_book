import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/example_song.dart';
import 'package:song_book/services/song_parser.dart';

ChordToken chord(String display, {bool endOfLine = false}) =>
    ChordToken(_chordOf(display), endOfLine: endOfLine);

WordToken word(String text, [String? chordDisplay]) => WordToken(text,
    chord: chordDisplay == null ? null : _chordOf(chordDisplay));

Chord _chordOf(String display) {
  final c = parseChord(display);
  if (c == null) throw ArgumentError('не аккорд: $display');
  return c;
}

void main() {
  group('round-trip', () {
    test('пример песни — байт-в-байт', () {
      expect(renderSong(parseSong(kExampleSongContent)), kExampleSongContent);
    });

    test('несколько пустых строк между секциями нормализуются в одну', () {
      expect(renderSong(parseSong('Am\n\n\n\n\nF\n')), 'Am\n\nF\n');
    });

    test('файл всегда завершается переводом строки', () {
      expect(renderSong(parseSong('Am\n\nF')), 'Am\n\nF\n');
    });

    test('пустой текст — пустой результат', () {
      expect(renderSong(parseSong('')), '');
    });
  });

  group('структура модели', () {
    test('заголовок в скобках распознаётся всегда', () {
      final s = parseSong('[Что-то непонятное]\nтекст\n').sections.single;
      expect(s.title, 'Что-то непонятное');
      expect(s.kind, SectionKind.unknown);
      expect(s.titleSource, '[Что-то непонятное]');
    });

    test('ключевые слова дают kind: куплет/припев/соло', () {
      expect(parseSong('[Куплет 1]\nтекст\n').sections.single.kind,
          SectionKind.verse);
      expect(parseSong('Припев:\nтекст\n').sections.single.kind,
          SectionKind.chorus);
      expect(parseSong('[Табы — соло]\nтекст\n').sections.single.kind,
          SectionKind.solo);
    });

    test('двоеточие без ключевого слова — обычная строка текста', () {
      final s = parseSong('Бла-бла:\nтекст\n').sections.single;
      expect(s.title, isNull);
      expect(s.lines, hasLength(2));
    });

    test('пара «аккорды + текст» склеивается в одну строку', () {
      final s = parseSong('[Припев]\n   C        G\nHotel California\n')
          .sections
          .single;
      expect(s.lines, hasLength(1));
      expect(s.lines.first.tokens, [
        word('Hotel', 'C'),
        word('California', 'G'),
      ]);
    });

    test('округление назад: уехавший вправо аккорд берёт своё слово', () {
      final s = parseSong('Am                  F\nOn a dark desert highway\n')
          .sections
          .single;
      expect(s.lines.first.tokens, [
        word('On', 'Am'), word('a'), word('dark'), word('desert'),
        word('highway', 'F'),
      ]);
    });

    test('два аккорда на слове: первый — поле, второй — токен после', () {
      final s = parseSong('Em    E7\nскажите мне\n').sections.single;
      expect(s.lines.first.tokens, [
        word('скажите', 'Em'), chord('E7'), word('мне'),
      ]);
    });

    test('аккорд за концом последнего слова — конец строки', () {
      final s = parseSong('B7       Em         E7\nШо я вам скажу\n')
          .sections
          .single;
      expect(s.lines.first.tokens, [
        word('Шо', 'B7'), word('я'), word('вам'),
        word('скажу', 'Em'), chord('E7', endOfLine: true),
      ]);
    });

    test('комбо: доп. аккорд на слове + два в конце строки', () {
      final s =
          parseSong('Am  Dm         E7  A7\nслова строки\n').sections.single;
      expect(s.lines.first.tokens, [
        word('слова', 'Am'), chord('Dm'), word('строки'),
        chord('E7', endOfLine: true), chord('A7', endOfLine: true),
      ]);
    });

    test('аккорд левее начала первого слова — к первому слову', () {
      final s = parseSong('Am\n   On and on\n').sections.single;
      expect(s.lines.first.tokens.first, word('On', 'Am'));
    });

    test('аккорды без текста — прогрессия', () {
      final s = parseSong('Am   F   C   G\n');
      final line = s.sections.single.lines.single;
      expect(line.isProgression, isTrue);
      expect(line.tokens.map((t) => (t as ChordToken).chord.display).toList(),
          ['Am', 'F', 'C', 'G']);
    });

    test('табулатуры — RawToken с исходником', () {
      const tab = 'e|-------0---------------|';
      final s = parseSong(tab);
      final line = s.sections.single.lines.single;
      expect(line.tokens.single, isA<RawToken>());
      expect(line.source, tab);
    });

    test('хвостовая пометка в строке аккордов — InlineToken', () {
      final s = parseSong('Am F 2x\nтекст текст текст\n');
      final tokens = s.sections.single.lines.first.tokens;
      expect(tokens.whereType<InlineToken>().single,
          const InlineToken('2x', endOfLine: true));
    });
  });

  group('рендер из токенов (без source)', () {
    test('аккорды встают над началами слов', () {
      final song = ParsedSong([
        Section(lines: [
          Line([word('Hotel', 'C'), word('California', 'G')]),
        ]),
      ]);
      expect(renderSong(song), 'C     G\nHotel California\n');
    });

    test('доп. аккорд на слове — сразу за основным', () {
      final song = ParsedSong([
        Section(lines: [
          Line([word('On', 'Am'), chord('Dm')]),
        ]),
      ]);
      expect(renderSong(song), 'Am Dm\nOn\n');
    });

    test('слово выравнивается под аккорд, сдвинутый доп. аккордами', () {
      final song = ParsedSong([
        Section(lines: [
          Line([word('ah', 'A'), chord('B'), chord('C'), word('boo', 'Bb')]),
        ]),
      ]);
      expect(renderSong(song), 'A B C Bb\nah    boo\n');
    });

    test('хвостовой аккорд — за последним словом', () {
      final song = ParsedSong([
        Section(lines: [
          Line([word('highway'), chord('F', endOfLine: true)]),
        ]),
      ]);
      expect(renderSong(song), '        F\nhighway\n');
    });

    test('прогрессия — аккорды через три пробела', () {
      final song = ParsedSong([
        Section(lines: [
          Line([chord('Am'), chord('F')]),
        ]),
      ]);
      expect(renderSong(song), 'Am   F\n');
    });
  });

  group('кириллические двойники', () {
    test('«С7» кириллицей распознаётся и нормализуется в C7', () {
      final s = parseSong('  G        C            С7\nГоворит, послухайте\n')
          .sections
          .single;
      expect(s.lines.first.tokens, [
        word('Говорит,', 'G'),
        word('послухайте', 'C'),
        chord('C7', endOfLine: true),
      ]);
    });

    test('канонический рендер выводит латиницу', () {
      final song = parseSong('  G        C            С7\nГоворит, послухайте\n');
      expect(renderSong(song, fromSource: false),
          'G        C          C7\nГоворит, послухайте\n');
    });

    test('исходник не трогаем — байт-в-байт', () {
      const content = '  G        C            С7\nГоворит, послухайте\n';
      expect(renderSong(parseSong(content)), content);
    });
  });

  group('аннотации-хвосты', () {
    final both =
        'G        C           // you can do C7 here\n'
        'Говорит, послухайте  /\u0024%^&/ slower than  in the chorus\n';

    test('хвосты обеих строк пары — аннотации со своей стороны', () {
      final s = parseSong(both).sections.single;
      expect(s.lines, hasLength(1));
      expect(s.lines.first.tokens, [
        word('Говорит,', 'G'),
        word('послухайте', 'C'),
        const InlineToken('// you can do C7 here', endOfLine: true),
        AnnotationToken('/\u0024%^&/ slower than  in the chorus'),
      ]);
    });

    test('канонический рендер: каждый хвост в конце своей строки', () {
      expect(
          renderSong(parseSong(both), fromSource: false),
          'G        C          // you can do C7 here\n'
          'Говорит, послухайте /\u0024%^&/ slower than  in the chorus\n');
    });

    test('аннотация аккордной строки стоит за концом слов, как аккорд конца', () {
      const input = 'G               C        //укоцдулкод\nДержит в правой ручке\n';
      expect(renderSong(parseSong(input), fromSource: false),
          'G               C     //укоцдулкод\nДержит в правой ручке\n');
    });

    test('исходник с хвостами — байт-в-байт', () {
      expect(renderSong(parseSong(both)), both);
    });

    test('прогрессия с аннотацией', () {
      final s = parseSong('Am F // быстро\n').sections.single;
      expect(s.lines.single.tokens,
          [chord('Am'), chord('F'), const InlineToken('// быстро', endOfLine: true)]);
      expect(renderSong(parseSong('Am F // быстро\n'), fromSource: false),
          'Am   F // быстро\n');
    });

    test('строка текста с хвостом-пометкой', () {
      final s = parseSong('Припев (2 раза)\n').sections.single;
      expect(s.lines.single.tokens, [
        word('Припев'),
        const AnnotationToken('(2 раза)'),
      ]);
      expect(renderSong(parseSong('Припев (2 раза)\n'), fromSource: false),
          'Припев (2 раза)\n');
    });
  });

  group('канонический рендер (fromSource: false)', () {
    test('пример песни: аккорды над началами слов, разметка выравнена', () {
      final pad = ' ' * 15; // от Am до F — колонка начала последнего слова
      final padEnd = ' ' * 20; // от C до G — за концом последнего слова
      final expected = 'Пример песни\n'
          '\n'
          '[Вступление]\n'
          'Am   F   C   G\n'
          'Am   F   G   G\n'
          '\n'
          '[Куплет 1]\n'
          'Am${pad}F\n'
          'On a dark desert highway\n'
          'C${padEnd}G\n'
          'Cool wind in my hair\n'
          '\n'
          '[Припев]\n'
          'C     G\n'
          'Hotel California\n'
          'Am     F\n'
          'Such a lovely place\n'
          '\n'
          '[Табы — соло]\n'
          'e|-------0---------------|\n'
          'B|-----1---1-------------|\n'
          'G|---2-------2-----------|\n'
          'D|-2---------------------|\n'
          'A|-----------------------|\n'
          'E|-----------------------|\n'
          '\n'
          'Подсказка: в режиме просмотра текст отображается моноширинным\n'
          'шрифтом, чтобы аккорды над словами и табулатуры не «плавали».\n';
      expect(renderSong(parseSong(kExampleSongContent), fromSource: false),
          expected);
    });

    test('заголовок «Припев:» канонизируется в «[Припев]»', () {
      final song = parseSong('Припев:\n   C        G\nHotel California\n');
      expect(renderSong(song, fromSource: false),
          '[Припев]\nC     G\nHotel California\n');
    });

    test('прогрессии нормализуются к трём пробелам', () {
      expect(renderSong(parseSong('Am        F\n'), fromSource: false),
          'Am   F\n');
    });

    test('аккорды конца строки — за последним словом', () {
      final song = parseSong('B7       Em         E7\nШо я вам скажу\n');
      expect(renderSong(song, fromSource: false),
          'B7       Em    E7\nШо я вам скажу\n');
    });

    test('конструктор секции без titleSource пишет заголовок в скобках', () {
      final song = ParsedSong([
        Section(title: 'Куплет 1', kind: SectionKind.verse, lines: const []),
      ]);
      expect(renderSong(song), '[Куплет 1]\n');
    });

    test('многословная строка — слова через один пробел', () {
      expect(renderSong(parseSong('текст   с   двойными   пробелами\n'),
          fromSource: false),
          'текст с двойными пробелами\n');
    });
  });

  group('inline-переходы (~)', () {
    test('G#7~A7 разбивается на два аккорда и ~', () {
      final s = parseSong('G#7~A7\n').sections.single;
      expect(s.lines.single.tokens, [
        chord('G#7'),
        const InlineToken('~'),
        chord('A7'),
      ]);
    });

    test('слипшиеся переходы в прогрессии', () {
      final s = parseSong('Em75-   G#7~A7 G#7~A7 Dm\n').sections.single;
      expect(s.lines.single.tokens, [
        chord('Em75-'),
        chord('G#7'),
        const InlineToken('~'),
        chord('A7'),
        chord('G#7'),
        const InlineToken('~'),
        chord('A7'),
        chord('Dm'),
      ]);
    });

    test('Em75- парсится как аккорд с сырым качеством', () {
      final c = parseChord('Em75-');
      expect(c, isNotNull);
      expect(c!.root, 'E');
      expect(c.quality, 'm75-');
    });

    test('канонический рендер сохраняет ~ между аккордами', () {
      expect(renderSong(parseSong('G#7~A7\n'), fromSource: false), 'G#7~A7\n');
      expect(renderSong(parseSong('Em75-   G#7~A7 G#7~A7 Dm\n'),
          fromSource: false),
          'Em75-   G#7~A7   G#7~A7   Dm\n');
    });

    test('аккорды над текстом: G#7~A7 разбивается на аккорды и ~', () {
      final s = parseSong('G#7~A7\nслово\n').sections.single;
      expect(s.lines.single.tokens, [
        word('слово', 'G#7'),
        const InlineToken('~'),
        chord('A7'),
      ]);
    });

    test('аккорды над текстом: ~ рендерится вплотную', () {
      expect(renderSong(parseSong('G#7~A7\nслово\n'), fromSource: false),
          'G#7~A7\nслово\n');
    });
  });
}
