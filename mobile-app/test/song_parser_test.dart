import 'package:flutter_test/flutter_test.dart';
import 'package:song_book/services/example_song.dart';
import 'package:song_book/services/song_parser.dart';

/// Профиль лексем строки: «chord:Корень | word:текст | sym:символы».
List<String> lexKinds(String line) => [
      for (final l in lexLine(line))
        switch (l) {
          ChordLex(:final rootName) => 'chord:$rootName',
          WordLex(:final text) => 'word:$text',
          SymbolLex(:final text) => 'sym:$text',
        }
    ];

/// Все имена аккордов модели по порядку, в тональности самой песни.
List<String> chordNames(ParsedSong song) => [
      for (final s in song.sections)
        for (final l in s.lines)
          for (final t in l.tokens)
            if (t is SyllableToken && t.chord != null)
              t.chord!.display(song.tonic, song.tonicName)
            else if (t is ChordToken)
              t.chord.display(song.tonic, song.tonicName),
    ];

Chord _chordOf(String display, int tonic) {
  final c = parseChord(display);
  if (c == null) throw ArgumentError('не аккорд: $display');
  return Chord.fromPitch(c, tonic);
}

ChordToken chord(String display, {bool endOfLine = false, int tonic = 0}) =>
    ChordToken(_chordOf(display, tonic), endOfLine: endOfLine);

SyllableToken syl(String text,
        {String? chord,
        SyllableDash dash = SyllableDash.none,
        int tonic = 0}) =>
    SyllableToken(text,
        dash: dash, chord: chord == null ? null : _chordOf(chord, tonic));

/// Слоги слова так же, как их режет парсер: первый несёт аккорд.
List<SyllableToken> word(String text, [String? chordDisplay, int tonic = 0]) {
  final base = wordSyllables(text);
  return [
    for (var i = 0; i < base.length; i++)
      SyllableToken(base[i].text,
          dash: base[i].dash,
          chord: i == 0 && chordDisplay != null
              ? _chordOf(chordDisplay, tonic)
              : null),
  ];
}

void main() {
  group('лексер', () {
    test('метка + пайпы + аккорды', () {
      expect(lexKinds('Вступление: Dm |   Dm   |   G   |   C   C7'), [
        'word:Вступление', 'sym::',
        'chord:D', 'sym:|', 'chord:D', 'sym:|',
        'chord:G', 'sym:|', 'chord:C', 'chord:C',
      ]);
    });

    test('слипшиеся переходы режутся, символы — аккордам не слова', () {
      expect(lexKinds('G#7~A7'), ['chord:G#', 'sym:~', 'chord:A']);
      expect(lexKinds('Em75-'), ['chord:E']);
    });

    test('фиктивные аккорды из слов не выдёргиваются', () {
      expect(lexKinds('Вступление'), ['word:Вступление']);
      expect(lexKinds('Facade'), ['word:Facade']);
      expect(lexKinds('Am I wrong'), ['chord:A', 'word:I', 'word:wrong']);
    });

    test('кириллические двойники — аккорды с нормализованным корнем', () {
      expect(lexKinds('С7 Am'), ['chord:C', 'chord:A']);
    });

    test('пунктуация прилеплена к словам отдельной лексемой', () {
      expect(lexKinds('рит, о-сень'),
          ['word:рит', 'sym:,', 'word:о', 'sym:-', 'word:сень']);
    });

    test('H = B: немецкая нотация, включая кириллического двойника Н', () {
      expect(lexKinds('H7 E7'), ['chord:H', 'chord:E']);
      expect(lexKinds('Н7'), ['chord:H']);
      expect(parseChord('Hm')!.root, 11);
    });

    test('H-нотация: строка аккордная, тоника сохраняет имя, транспонируется', () {
      const line = '            H7                E7';
      expect(isChordLineText(line), isTrue);
      expect(renderSong(parseSong('$line\n')), 'H7   E7\n');
      final t = parseSong('$line\n').transposed(1);
      expect(chordNames(t), ['C7', 'F7']);
      expect(renderSong(t), 'C7   F7\n');
    });

    test('позиции лексем — исходные колонки', () {
      final lex = lexLine('  Am | C');
      expect(lex.map((l) => l.start).toList(), [2, 5, 7]);
      expect(lex.map((l) => l.end).toList(), [4, 6, 8]);
    });

    test('классификация: всё — аккорды, кроме слов-ловушек', () {
      // метка + пайпы — аккордная строка
      expect(
          isChordLineText('Вступление: Dm |   Dm   |   G   |   C   C7'),
          isTrue);
      expect(isChordLineText('[Куплет]:Dm   A7        Dm'), isTrue);
      expect(isChordLineText('G C // комментарий'), isTrue);
      expect(isChordLineText('Am'), isTrue); // висячий аккорд
      expect(isChordLineText('Am 2x'), isTrue);

      // ловушки: союз/предлог с заглавной, английское A/Am
      expect(isChordLineText('В лесу родилась ёлочка'), isFalse);
      expect(isChordLineText('А он мне не ответил'), isFalse);
      expect(isChordLineText('С Новым годом'), isFalse);
      expect(isChordLineText('Раз. В два бита'), isFalse);
      expect(isChordLineText('Am I wrong'), isFalse);
      expect(isChordLineText('On a dark desert highway'), isFalse);
    });

    test('метка + пайпы транспонируется', () {
      final t = parseSong(
              'Вступление: Dm |   Dm   |   G   |   C   C7\n')
          .transposed(1);
      expect(chordNames(t), ['Ebm', 'Ebm', 'Ab', 'C#', 'C#7']);
    });
  });

  group('точки в строках аккордов', () {
    test('лексер: skipPeriods пропускает только точечные лексемы', () {
      expect(
          lexLine('Gm. Fm', skipPeriods: true).whereType<ChordLex>().length, 2);
      expect(lexLine('Gm. Fm').whereType<SymbolLex>().single.text, '.');
    });

    test('точки после аккордов исчезают при рендере', () {
      expect(renderSong(parseSong('Gm. Fm\n')), 'Gm   Fm\n');
      expect(renderSong(parseSong('A. B. C.\n')), 'A   B   C\n');
    });

    test('точка не сдвигает аккорд над слогом', () {
      expect(
        renderSong(parseSong('Gm. Fm\nпою песню\n')),
        renderSong(parseSong('Gm  Fm\nпою песню\n')),
      );
    });

    test('в лирике точки остаются', () {
      expect(renderSong(parseSong('пою. песню\n')), 'пою. песню\n');
    });
  });

  group('смена тоники (transposed)', () {
    test('0 полутонов — та же модель', () {
      final song = parseSong('Am F\nтекст\n');
      expect(song.transposed(0), same(song));
    });

    test('+12 полутонов — те же имена', () {
      expect(chordNames(parseSong('Am F\n').transposed(12)), ['Am', 'F']);
    });

    test('аккорды слогов, доп. смены и хвосты строки', () {
      final t =
          parseSong('Am  Dm         E7  A7\nслова строки\n').transposed(1);
      expect(chordNames(t), ['Bbm', 'Ebm', 'F7', 'Bb7']);
    });

    test('прогрессия рендерится с новыми именами', () {
      expect(renderSong(parseSong('Am   F   C   G\n').transposed(2)),
          'Bm   G   D   A\n');
    });

    test('качества аккордов сохраняются', () {
      final t = parseSong('Am7 F#m7 Cmaj7 Dsus4 Bdim\n').transposed(1);
      expect(chordNames(t), ['Bbm7', 'Gm7', 'C#maj7', 'Ebsus4', 'Cdim']);
    });

    test('слэш-аккорды транспонируют бас', () {
      final t = parseSong('C/G  G/B\n').transposed(2);
      expect(chordNames(t), ['D/A', 'A/C#']);
    });

    test('энгармоника: C#, F# — диезы; Eb, Ab, Bb — бемоли', () {
      final t = parseSong('C  F  G  D  A  Bb  A#\n').transposed(1);
      expect(chordNames(t), ['C#', 'F#', 'Ab', 'Eb', 'Bb', 'B', 'B']);
    });

    test('отрицательное смещение через ноль', () {
      expect(chordNames(parseSong('C\nF#\n').transposed(-1)), ['B', 'F']);
    });

    test('тоника рендерится написанным именем', () {
      expect(renderSong(parseSong('G#7~A7\n')), 'G#7~A7\n');
      expect(renderSong(parseSong('G#7~A7\n').transposed(1)), 'A7~Bb7\n');
    });

    test('текст песни не трогаем', () {
      final song = parseSong('On a dark desert highway\nAm I wrong\n');
      final t = song.transposed(3);
      expect(chordNames(t), isEmpty);
      expect(renderSong(t), renderSong(song));
    });

    test('табулатуры не трогаем', () {
      const tab = 'e|-------0---------------|';
      expect(renderSong(parseSong(tab).transposed(5)), '$tab\n');
    });

    test('аккорд внутри inline-комментария транспонируется', () {
      const content =
          'G        C           // you can do C7 here\nГоворит, послухайте\n';
      final t = parseSong(content).transposed(2);
      expect(chordNames(t), contains('D7'));
      expect(renderSong(t), contains('// you can do D7  here'));
    });

    test('аннотация строки текста не трогается', () {
      final line = parseSong('Припев (2 раза)\n')
          .transposed(5)
          .sections
          .single
          .lines
          .single;
      expect(line.tokens.whereType<AnnotationToken>().single,
          const AnnotationToken('(2 раза)'));
    });

    test('кириллический двойник транспонируется как обычный аккорд', () {
      expect(chordNames(parseSong('С7 Am\n').transposed(2)), ['D7', 'Bm']);
    });

    test('полный пример: аккорды меняются, текст и табы нет', () {
      const content = '''
[Вступление]
Am   F   C   G

[Куплет 1]
On a dark desert highway

[Табы]
e|-------0---------------|
''';
      final result = renderSong(parseSong(content).transposed(1));
      expect(result, contains('[Вступление]'));
      expect(result, contains('Bbm'));
      expect(result, contains('On a dark desert highway'));
      expect(result, contains('e|-------0---------------|'));
    });
  });

  group('round-trip', () {
    test('канонический рендер стабилен: повторный проход ничего не меняет', () {
      final canonical = renderSong(parseSong(kExampleSongContent));
      expect(renderSong(parseSong(canonical)), canonical);
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
    test('тоника — первый аккорд: питч и написание', () {
      final s = parseSong('Am   F\nтекст\n');
      expect(s.tonic, 9);
      expect(s.tonicName, 'A');
      expect(parseSong('G#7~A7\n').tonicName, 'G#');
      expect(parseSong('текст без аккордов\n').tonic, 0);
      expect(parseSong('текст без аккордов\n').tonicName, 'C');
    });

    test('заголовок в скобках распознаётся всегда', () {
      final s = parseSong('[Что-то непонятное]\nтекст\n').sections.single;
      expect(s.title, 'Что-то непонятное');
      expect(s.kind, SectionKind.unknown);
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
      final song = parseSong('[Припев]\n   C        G\nHotel California\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines, hasLength(1));
      expect(s.lines.first.tokens, [
        ...word('Hotel', 'C', t),
        ...word('California', 'G', t),
      ]);
    });

    test('округление назад: уехавший вправо аккорд берёт своё слово', () {
      final song =
          parseSong('Am                  F\nOn a dark desert highway\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        ...word('On', 'Am', t),
        ...word('a', null, t),
        ...word('dark', null, t),
        ...word('desert', null, t),
        ...word('highway', 'F', t),
      ]);
    });

    test('второй аккорд слова — первый аккорд своего слога', () {
      final song = parseSong('Em    E7\nскажите мне\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('ска', chord: 'Em', dash: SyllableDash.right, tonic: t),
        syl('жи', dash: SyllableDash.both, tonic: t),
        syl('те', chord: 'E7', dash: SyllableDash.left, tonic: t),
        ...word('мне', null, t),
      ]);
    });

    test('аккорд над серединой слова без дефисов — слогу переноса', () {
      final song = parseSong('Am  Dm\nслова строки\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('сло', chord: 'Am', dash: SyllableDash.right, tonic: t),
        syl('ва', chord: 'Dm', dash: SyllableDash.left, tonic: t),
        syl('стро', dash: SyllableDash.right, tonic: t),
        syl('ки', dash: SyllableDash.left, tonic: t),
      ]);
    });

    test('аккорд над серединой дефисного слова — слогу с дефисом', () {
      final song = parseSong('C        F\nПе-ре-хо-дит о-сень в ле-то\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('Пе', chord: 'C', dash: SyllableDash.right, tonic: t),
        syl('-ре', dash: SyllableDash.both, tonic: t),
        syl('-хо', dash: SyllableDash.both, tonic: t),
        syl('-дит', chord: 'F', dash: SyllableDash.left, tonic: t),
        syl('о', dash: SyllableDash.right, tonic: t),
        syl('-сень', dash: SyllableDash.left, tonic: t),
        ...word('в', null, t),
        syl('ле', dash: SyllableDash.right, tonic: t),
        syl('-то', dash: SyllableDash.left, tonic: t),
      ]);
    });

    test('дефисные части дополнительно режутся переносом', () {
      expect(wordSyllables('лю-бимый'), [
        syl('лю', dash: SyllableDash.right),
        syl('-би', dash: SyllableDash.both),
        syl('мый', dash: SyllableDash.left),
      ]);
      expect(wordSyllables('лю-би-ма-я'), [
        syl('лю', dash: SyllableDash.right),
        syl('-би', dash: SyllableDash.both),
        syl('-ма', dash: SyllableDash.both),
        syl('-я', dash: SyllableDash.left),
      ]);
    });

    test('аккорд за концом последнего слова — конец строки', () {
      final song = parseSong('B7       Em         E7\nШо я вам скажу\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        ...word('Шо', 'B7', t),
        ...word('я', null, t),
        ...word('вам', null, t),
        syl('ска', chord: 'Em', dash: SyllableDash.right, tonic: t),
        syl('жу', dash: SyllableDash.left, tonic: t),
        chord('E7', endOfLine: true, tonic: t),
      ]);
    });

    test('комбо: аккорд на втором слоге + два в конце строки', () {
      final song = parseSong('Am  Dm         E7  A7\nслова строки\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('сло', chord: 'Am', dash: SyllableDash.right, tonic: t),
        syl('ва', chord: 'Dm', dash: SyllableDash.left, tonic: t),
        syl('стро', dash: SyllableDash.right, tonic: t),
        syl('ки', dash: SyllableDash.left, tonic: t),
        chord('E7', endOfLine: true, tonic: t),
        chord('A7', endOfLine: true, tonic: t),
      ]);
    });

    test('аккорд левее первого слова — отдельный пустой слог', () {
      final song = parseSong('Am\n   On and on\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('', chord: 'Am', tonic: t),
        ...word('On', null, t),
        ...word('and', null, t),
        ...word('on', null, t),
      ]);
    });

    test('аккорд над пробелом между словами — отдельный пустой слог', () {
      const chordLine = '    A7       G#7~ A7           G#7 A7  Am';
      const wordLine = 'Где чинара        притулилась      под скалою,';
      final song = parseSong('$chordLine\n$wordLine\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.single.tokens, [
        ...word('Где', null, t),
        syl('чи', chord: 'A7', dash: SyllableDash.right, tonic: t),
        syl('на', dash: SyllableDash.both, tonic: t),
        syl('ра', dash: SyllableDash.left, tonic: t),
        syl('', chord: 'G#7', tonic: t),
        const InlineToken('~', glued: true),
        syl('при', chord: 'A7', dash: SyllableDash.right, tonic: t),
        syl('ту', dash: SyllableDash.both, tonic: t),
        syl('ли', dash: SyllableDash.both, tonic: t),
        syl('лась', dash: SyllableDash.left, tonic: t),
        syl('', chord: 'G#7', tonic: t),
        ...word('под', 'A7', t),
        ...word('скалою,', 'Am', t),
      ]);
    });

    test('аккорды без текста — прогрессия', () {
      final s = parseSong('Am   F   C   G\n');
      final line = s.sections.single.lines.single;
      expect(line.isProgression, isTrue);
      expect(
          line.tokens
              .map((t) => (t as ChordToken).chord.display(s.tonic, s.tonicName))
              .toList(),
          ['Am', 'F', 'C', 'G']);
    });

    test('табулатуры — RawToken', () {
      const tab = 'e|-------0---------------|';
      final s = parseSong(tab);
      final line = s.sections.single.lines.single;
      expect(line.tokens.single, isA<RawToken>());
    });

    test('хвостовая пометка в строке аккордов — InlineToken', () {
      final s = parseSong('Am F 2x\nтекст текст текст\n');
      final tokens = s.sections.single.lines.first.tokens;
      expect(tokens.whereType<InlineToken>().single, const InlineToken('2x'));
    });
  });

  group('рендер из токенов', () {
    test('аккорды встают над началами слов', () {
      final song = ParsedSong([
        Section(lines: [
          Line([...word('Hotel', 'C'), ...word('California', 'G')]),
        ]),
      ]);
      expect(renderSong(song), 'C     G\nHotel California\n');
    });

    test('аккорд, влезающий в слог, не дефисирует слово', () {
      final song = ParsedSong([
        Section(lines: [
          Line([
            syl('ска', chord: 'Em', dash: SyllableDash.right),
            syl('жи', dash: SyllableDash.both),
            syl('те', chord: 'G', dash: SyllableDash.left),
            ...word('мне'),
          ]),
        ]),
      ]);
      expect(renderSong(song), 'Em   G\nскажите мне\n');
    });

    test('дефисы исходника сохраняются при пересборке', () {
      // Am стоит над дефисом — под буквами «-би».
      expect(renderSong(parseSong('  Am\nлю-би-ма-я\n')),
          '   Am\nлю-би-ма-я\n');
    });

    test('аккорд прижат к слогу, дефисы исходника сохраняются', () {
      // G# — не тоника, канонизируется в Ab.
      expect(renderSong(parseSong('C      G#7\nПе-ре-хо-дит\n')),
          'C     Ab7\nПе-ре-хо-дит\n');
    });

    group('растяжка слогов дефисами', () {
      test('одиночная смена внутри слова — без дефисов', () {
        expect(renderSong(parseSong('       D7\nпод скалою\n')),
            '       D7\nпод скалою\n');
      });

      test('смена на последнем слоге — без дефисов', () {
        expect(renderSong(parseSong('F7   Bb\nвечная пчела\n')),
            'F7   Bb\nвечная  пчела\n');
      });

      test('несколько смен в слове прижаты к слогам, без дефисов', () {
        expect(renderSong(parseSong('F7 G Bb\nвечная\n')),
            'F7 G Bb\nвечная\n');
      });

      test('длинные имена растягивают слово дефисами', () {
        expect(renderSong(parseSong('F#7 G# Bb\nвеч-на-я\n')),
            'F#7 Ab Bb\nвеч-на-я\n');
      });
      test('растяжка не дублирует дефис исходника', () {
        final song = ParsedSong([
          Section(lines: [
            Line([
              syl('веч', chord: 'C#m7', dash: SyllableDash.right),
              syl('-на', chord: 'G#7', dash: SyllableDash.both),
              syl('-я', chord: 'Bb', dash: SyllableDash.left),
            ]),
          ]),
        ]);
        expect(renderSong(song), 'C#m7 Ab7 Bb\nвеч -на -я\n');
      });
    });

    test('доп. аккорд на слоге — сразу за основным', () {
      final song = ParsedSong([
        Section(lines: [
          Line([syl('On', chord: 'Am'), chord('Dm')]),
        ]),
      ]);
      expect(renderSong(song), 'Am  Dm\nOn\n');
    });

    test('слог выравнивается под аккорд, сдвинутый доп. аккордами', () {
      final song = ParsedSong([
        Section(lines: [
          Line([syl('ah', chord: 'A'), chord('B'), chord('C'), ...word('boo', 'Bb')]),
        ]),
      ]);
      expect(renderSong(song), 'A  B  C  Bb\nah       boo\n');
    });

    test('хвостовой аккорд — за последним словом', () {
      final song = ParsedSong([
        Section(lines: [
          Line([...word('highway'), chord('F', endOfLine: true)]),
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

  group('стабильность при транспонировании', () {
    const content = 'C        F\nПе-ре-хо-дит о-сень в ле-то\n';

    List<String> canonicalInKeys() => [
          for (var s = 0; s < 12; s++)
            renderSong(parseSong(content).transposed(s)),
        ];

    test('строки слов не меняются', () {
      expect(canonicalInKeys().map((l) => l.split('\n')[1]).toSet().single,
          'Пе-ре-хо-дит о-сень в ле-то');
    });

    test('колонки аккордов не двигаются', () {
      final columns = canonicalInKeys()
          .map((l) => l.split('\n').first)
          .map((line) => RegExp(r'\S+')
              .allMatches(line)
              .map((m) => m.start)
              .toList()
              .join(','))
          .toSet();
      expect(columns.single, '0,9');
    });

    test('хвост с ~: строка слов и колонки не двигаются', () {
      const content = '    A7       G#7~ A7           G#7 A7  Am\n'
          'Где чинара        притулилась      под скалою,\n';
      final renders = [
        for (var s = 0; s < 12; s++)
          renderSong(parseSong(content).transposed(s))
      ];
      expect(renders.map((l) => l.split('\n')[1]).toSet().single,
          'Где чинара      притулилась     под скалою,');
      final columns = renders
          .map((l) => l.split('\n').first)
          .map((line) => RegExp(r'\S+')
              .allMatches(line)
              .map((m) => m.start)
              .toList()
              .join(','))
          .toSet();
      expect(columns.single, '4,11,16,28,32,36');
    });

    test('эффективная ширина одинакова для всех написаний', () {
      final song = parseSong('F\n'); // тоника — сам аккорд, смещение 0
      final chord =
          (song.sections.single.lines.single.tokens.single as ChordToken).chord;
      final widths = {
        for (var s = 0; s < 12; s++)
          chordWidth(chord, song.transposed(s).tonic, song.tonicName)
      };
      expect(widths.single, 2);
    });
  });

  group('кириллические двойники', () {
    test('«С7» кириллицей распознаётся и нормализуется в C7', () {
      final song =
          parseSong('  G        C            С7\nГоворит, послухайте\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.first.tokens, [
        syl('Го', dash: SyllableDash.right, tonic: t),
        syl('во', chord: 'G', dash: SyllableDash.both, tonic: t),
        syl('рит,', dash: SyllableDash.left, tonic: t),
        syl('по', dash: SyllableDash.right, tonic: t),
        syl('слу', chord: 'C', dash: SyllableDash.both, tonic: t),
        syl('хай', dash: SyllableDash.both, tonic: t),
        syl('те', dash: SyllableDash.left, tonic: t),
        chord('C7', endOfLine: true, tonic: t),
      ]);
    });

    test('канонический рендер выводит латиницу', () {
      final song = parseSong('  G        C            С7\nГоворит, послухайте\n');
      expect(renderSong(song),
          '  G        C        C7\nГоворит, послухайте\n');
    });
  });

  group('аннотации-хвосты', () {
    final both =
        'G        C           // you can do C7 here\n'
        'Говорит, послухайте  /\u0024%^&/ slower than  in the chorus\n';

    test('хвост аккордной строки — плоские куски, аккорд — ChordToken', () {
      final song = parseSong(both);
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines, hasLength(1));
      expect(s.lines.first.tokens, [
        syl('Го', chord: 'G', dash: SyllableDash.right, tonic: t),
        syl('во', dash: SyllableDash.both, tonic: t),
        syl('рит,', dash: SyllableDash.left, tonic: t),
        syl('по', chord: 'C', dash: SyllableDash.right, tonic: t),
        syl('слу', dash: SyllableDash.both, tonic: t),
        syl('хай', dash: SyllableDash.both, tonic: t),
        syl('те', dash: SyllableDash.left, tonic: t),
        const InlineToken('// you can do'),
        chord('C7', endOfLine: true, tonic: t),
        const InlineToken('here'),
        AnnotationToken('/\u0024%^&/ slower than  in the chorus'),
      ]);
    });

    test('канонический рендер: каждый хвост в конце своей строки', () {
      expect(
          renderSong(parseSong(both)),
          'G        C          // you can do C7  here\n'
          'Говорит, послухайте /\u0024%^&/ slower than  in the chorus\n');
    });

    test('аннотация аккордной строки стоит за концом слов, как аккорд конца', () {
      const input = 'G               C        //укоцдулкод\nДержит в правой ручке\n';
      expect(renderSong(parseSong(input)),
          'G               C     //укоцдулкод\nДержит в правой ручке\n');
    });

    test('прогрессия с аннотацией', () {
      final song = parseSong('Am F // быстро\n');
      final t = song.tonic;
      expect(song.sections.single.lines.single.tokens,
          [chord('Am', tonic: t), chord('F', tonic: t), const InlineToken('// быстро')]);
      expect(renderSong(song), 'Am   F // быстро\n');
    });

    test('тире в середине строки — текст, а не аннотация', () {
      final chordLine = 'Dm${' ' * 26}Gm  A7';
      const wordLine = 'Сладострастная отрава – золотая Брич-Мулла';
      final song = parseSong('$chordLine\n$wordLine\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.single.tokens.whereType<AnnotationToken>(), isEmpty);
      expect(s.lines.single.tokens,
          contains(syl('та', chord: 'Gm', dash: SyllableDash.both, tonic: t)));
      expect(s.lines.single.tokens,
          contains(syl('Брич', chord: 'A7', dash: SyllableDash.right, tonic: t)));
    });

    test('строка текста с хвостом-пометкой', () {
      final s = parseSong('Припев (2 раза)\n').sections.single;
      expect(s.lines.single.tokens, [
        syl('При', dash: SyllableDash.right),
        syl('пев', dash: SyllableDash.left),
        const AnnotationToken('(2 раза)'),
      ]);
      expect(renderSong(parseSong('Припев (2 раза)\n')),
          'Припев (2 раза)\n');
    });
  });

  group('канонический рендер', () {
    test('пример песни: аккорды над началами слов, разметка выравнена', () {
      final pad = ' ' * 16; // от Am до F — колонка начала последнего слова
      final padEnd = ' ' * 20; // от C до G — за концом последнего слова
      final expected = 'Пример песни\n'
          '\n'
          '[Вступление]\n'
          'Am   F   C   G\n'
          'Am   F   G   G\n'
          '\n'
          '[Куплет 1]\n'
          'Am${pad}F\n'
          'On  a dark desert highway\n'
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
      expect(renderSong(parseSong(kExampleSongContent)), expected);
    });

    test('заголовок «Припев:» канонизируется в «[Припев]»', () {
      final song = parseSong('Припев:\n   C        G\nHotel California\n');
      expect(renderSong(song),
          '[Припев]\nC     G\nHotel California\n');
    });

    test('прогрессии нормализуются к трём пробелам', () {
      expect(renderSong(parseSong('Am        F\n')), 'Am   F\n');
    });

    test('аккорды конца строки — за последним словом', () {
      final song = parseSong('B7       Em         E7\nШо я вам скажу\n');
      expect(renderSong(song),
          'B7        Em    E7\nШо  я вам скажу\n');
    });

    test('конструктор секции без исходника пишет заголовок в скобках', () {
      final song = ParsedSong([
        Section(title: 'Куплет 1', kind: SectionKind.verse, lines: const []),
      ]);
      expect(renderSong(song), '[Куплет 1]\n');
    });

    test('многословная строка — слова через один пробел', () {
      expect(renderSong(parseSong('текст   с   двойными   пробелами\n')),
          'текст с двойными пробелами\n');
    });

    test('висячие аккорды рендерятся в зазорах, не наезжая на слова', () {
      const chordLine = '    A7       G#7~ A7           G#7 A7  Am';
      const wordLine = 'Где чинара        притулилась      под скалою,';
      final s = parseSong('$chordLine\n$wordLine\n');
      expect(renderSong(s),
          '    A7     Ab7~ A7          Ab7 A7  Am\n'
          'Где чинара      притулилась     под скалою,\n');
    });

    test('дефисное слово: дефисы сохраняются, аккорд над своим слогом', () {
      const input = 'C        F\nПе-ре-хо-дит о-сень в ле-то\n';
      expect(renderSong(parseSong(input)), input);
    });
  });

  group('inline-переходы (~)', () {
    test('G#7~A7 разбивается на два аккорда и ~', () {
      final song = parseSong('G#7~A7\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.single.tokens, [
        chord('G#7', tonic: t),
        const InlineToken('~', glued: true),
        chord('A7', tonic: t),
      ]);
    });

    test('слипшиеся переходы в прогрессии', () {
      final song = parseSong('Em75-   G#7~A7 G#7~A7 Dm\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.single.tokens, [
        chord('Em75-', tonic: t),
        chord('G#7', tonic: t),
        const InlineToken('~', glued: true),
        chord('A7', tonic: t),
        chord('G#7', tonic: t),
        const InlineToken('~', glued: true),
        chord('A7', tonic: t),
        chord('Dm', tonic: t),
      ]);
    });

    test('Em75- парсируется как аккорд с сырым качеством', () {
      final c = parseChord('Em75-');
      expect(c, isNotNull);
      expect(c!.root, 4);
      expect(c.quality, 'm75-');
    });

    test('канонический рендер сохраняет ~ между аккордами', () {
      expect(renderSong(parseSong('G#7~A7\n')), 'G#7~A7\n');
      expect(renderSong(parseSong('Em75-   G#7~A7 G#7~A7 Dm\n')),
          'Em75-   Ab7~A7   Ab7~A7   Dm\n');
    });

    test('аккорды над текстом: G#7~A7 разбивается на аккорды и ~', () {
      final song = parseSong('G#7~A7\nслово\n');
      final s = song.sections.single;
      final t = song.tonic;
      expect(s.lines.single.tokens, [
        syl('сло', chord: 'G#7', dash: SyllableDash.right, tonic: t),
        const InlineToken('~', glued: true),
        syl('во', chord: 'A7', dash: SyllableDash.left, tonic: t),
      ]);
    });

    test('аккорды над текстом: ~ рендерится вплотную', () {
      expect(renderSong(parseSong('G#7~A7\nслово\n')),
          'G#7~A7\nсло-во\n');
    });
  });

  group('renderSongLines', () {
    test('диапазон пары аккорды+текст', () {
      final r = renderSongLines(parseSong('Am F\nтекст\n'));
      expect(r.text, 'Am  F\nтекст\n');
      expect(r.lines, [(start: 0, end: 11)]);
    });

    test('прогрессия и пара — два диапазона', () {
      final r = renderSongLines(parseSong('Am\nAm F\nтекст\n'));
      expect(r.lines.length, 2);
      expect(r.text.substring(r.lines[0].start, r.lines[0].end), 'Am');
      expect(
          r.text.substring(r.lines[1].start, r.lines[1].end), 'Am  F\nтекст');
    });
  });

  group('строфы (stanzaStart)', () {
    test('блок без заголовка — строфа предыдущей секции, не новая', () {
      final song = parseSong('[Куплет]\nAm\nстрока1\n\nстрока2\n\nстрока3\n');
      expect(song.sections, hasLength(1));
      final s = song.sections.single;
      expect(s.kind, SectionKind.verse);
      expect(s.lines, hasLength(3));
      expect(s.lines.map((l) => l.stanzaStart), [false, true, true]);
    });

    test('блок без заголовка до первой секции с заголовком — отдельная секция', () {
      final song = parseSong('текст без заголовка\n\n[Куплет]\nAm\nстрока\n');
      expect(song.sections, hasLength(2));
      expect(song.sections.first.kind, SectionKind.unknown);
      expect(song.sections.first.lines.first.stanzaStart, isFalse);
    });

    test('пустые строки внутри секции сохраняются при рендере', () {
      expect(renderSong(parseSong('[Куплет]\nстрока1\n\nстрока2\n')),
          '[Куплет]\nстрока1\n\nстрока2\n');
    });

    test('несколько пустых строк между строфами нормализуются в одну', () {
      expect(renderSong(parseSong('[Куплет]\nстрока1\n\n\n\nстрока2\n')),
          '[Куплет]\nстрока1\n\nстрока2\n');
    });
  });

  group('propagateChords', () {
    String propagated(String content) =>
        renderSong(propagateChords(parseSong(content)));

    test('аккорды первого куплета размножаются по остальным куплетам', () {
      const input = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка
G       C
В лесу она росла

[Припев]
F       C
Хорошо поём

[Куплет 2]
Зимой и летом стройная
Зелёная была
''';
      const expected = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка
G       C
В лесу она росла

[Припев]
F       C
Хорошо поём

[Куплет 2]
Am      Dm
Зимой и летом стройная
G       C
Зелёная была
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('припев размножается по своему первому припеву, куплет не трогается', () {
      const input = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка

[Припев]
F       C
Хорошо поём
G
Хорошо

[Припев]
Хорошо поём
Хорошо
''';
      const expected = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка

[Припев]
F       C
Хорошо поём
G
Хорошо

[Припев]
F       C
Хорошо поём
G
Хорошо
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('слово короче шаблона — лишний аккорд пропускается, строки сверх шаблона не трогаются', () {
      const input = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка
G       C
В лесу она росла

[Куплет 2]
Зимой и летом стройная
Зелёная была
Третья строка без пары
''';
      const expected = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка
G       C
В лесу она росла

[Куплет 2]
Am      Dm
Зимой и летом стройная
G       C
Зелёная была
Третья строка без пары
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('повторный прогон идемпотентен', () {
      const input = '''
[Куплет 1]
Am      Dm
В лесу родилась ёлочка

[Куплет 2]
Зимой и летом стройная
''';
      final once = propagated(input);
      expect(renderSong(propagateChords(parseSong(once))), once);
    });

    test('секции без меток и табы не трогаются', () {
      const input = '''
[Куплет 1]
Am
слово

[Куплет 2]
другое

Без метки
Слова здесь

[Табы]
e|-------0---|
''';
      const expected = '''
[Куплет 1]
Am
слово

[Куплет 2]
Am
другое

Без метки
Слова здесь

[Табы]
e|-------0---|
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('шаблон — первая секция типа с аккордами', () {
      const input = '''
[Куплет 1]
Слова без аккордов

[Куплет 2]
Am      Dm
В лесу родилась ёлочка

[Куплет 3]
Зимой и летом стройная
''';
      const expected = '''
[Куплет 1]
Слова без аккордов

[Куплет 2]
Am      Dm
В лесу родилась ёлочка

[Куплет 3]
Am      Dm
Зимой и летом стройная
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('доп. аккорды на слоге переносятся целиком и в порядке', () {
      final song = ParsedSong([
        Section(kind: SectionKind.verse, lines: [
          Line([
            syl('При', chord: 'A', dash: SyllableDash.right),
            chord('B'),
            chord('C'),
            syl('-вет', chord: 'G', dash: SyllableDash.left),
          ]),
        ]),
        Section(kind: SectionKind.verse, lines: [
          Line([
            syl('При', dash: SyllableDash.right),
            syl('-вет', dash: SyllableDash.left),
          ]),
        ]),
      ]);
      final out = propagateChords(song);
      expect(out.sections[1].lines.single.tokens,
          out.sections[0].lines.single.tokens);
    });

    test('доп. аккорды слога из текста переносятся', () {
      const input = '''
[Куплет 1]
A B
там

[Куплет 2]
там
''';
      const expected = '''
[Куплет 1]
A B
там

[Куплет 2]
A B
там
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('многострофный куплет — одна секция, размножение по строкам', () {
      const input = '''
[Куплет]
Am      Dm
первая строка куплета
G       C
вторая строка куплета

E7      A7
третья строка куплета
F       B7
четвёртая строка куплета

[Куплет]
пятая строка куплета
шестая строка куплета
седьмая строка куплета
восьмая строка куплета
''';
      const expected = '''
[Куплет]
Am      Dm
первая строка куплета
G       C
вторая строка куплета

E7      A7
третья строка куплета
F       B7
четвёртая строка куплета

[Куплет]
Am      Dm
пятая строка куплета
G       C
шестая строка куплета
E7    A7
седьмая строка куплета
F       B7
восьмая строка куплета
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('тире не считается слогом', () {
      const input = '''
[Куплет 1]
Am       Am/F#     B7
Тарантас назывался арбою

[Куплет 2]
Ишаку – знатоку Туркестана
''';
      const expected = '''
[Куплет 1]
Am       Am/F#     B7
Тарантас назывался арбою

[Куплет 2]
Am       Am/F#     B7
Ишаку – знатоку Туркестана
''';
      expect(propagated(input), renderSong(parseSong(expected)));
    });

    test('зазорные аккорды переносятся после своего слога', () {
      final song = ParsedSong([
        Section(kind: SectionKind.verse, lines: [
          Line([
            ...word('да', 'Am'),
            syl('', chord: 'Dm'),
            ...word('нет', 'G'),
          ]),
        ]),
        Section(kind: SectionKind.verse, lines: [
          Line([...word('ты'), ...word('он')]),
        ]),
      ]);
      final out = propagateChords(song);
      expect(out.sections[1].lines.single.tokens, [
        ...word('ты', 'Am'),
        syl('', chord: 'Dm'),
        ...word('он', 'G'),
      ]);
    });

    test('хвостовые аккорды переносятся в хвост', () {
      final song = ParsedSong([
        Section(kind: SectionKind.verse, lines: [
          Line([...word('слово', 'Am'), chord('E7', endOfLine: true)]),
        ]),
        Section(kind: SectionKind.verse, lines: [
          Line([...word('друг')]),
        ]),
      ]);
      final out = propagateChords(song);
      expect(out.sections[1].lines.single.tokens,
          [...word('друг', 'Am'), chord('E7', endOfLine: true)]);
    });

    test('размножение стабильно через parse→render→parse', () {
      const input = '''
[Куплет 1]
Am      Dm
первая строка тут
G                  E7
вторая – строка тут

[Куплет 2]
третья строка
четвёртая строка
''';
      final once = propagated(input);
      expect(propagated(once), once);
    });
  });
}
