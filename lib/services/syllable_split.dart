/// Деление русского слова на слоги — фонетическое, по принципу
/// восходящей звучности (максимальное начало слога, Щерба): между
/// гласными граница проходит так, чтобы следующий слог начинался с
/// самой длинной цепочки согласных, с которой может начинаться русское
/// слово.
///
/// Это певческое деление («ве-сна», «и-сто-ри-я», «о-бла-ко»), а не
/// типографский перенос («вес-на», «ис-то-ри-я», «об-ла-ко»). Вход —
/// кусок слова без дефисов и знаков (составные слова вида «кто-то»
/// режет вызывающий по дефису сам). Слово без гласных — в том числе
/// латиница и цифры — один слог.
library;

const String _vowels = 'аеёиоуыэюя';

/// Буквы, которые не начинают слог: й и ъ — никогда; ь — кроме позиции
/// сразу после согласной в начале слога («пье-са»).
const String _closers = 'йьъ';

/// с/з в начале цепочки согласных не требуют роста звучности
/// («струк-ция», «сфальт», «зди-ть»).
const String _clusterPrefix = 'сз';

/// Живые шипящие скоплений согласных не начинают («мощ-ность»,
/// «конеч-ный»), в отличие от с/з и взрывных.
const String _noClusterStart = 'жшщч';

int _sonority(String ch) => switch (ch) {
      'л' || 'р' || 'м' || 'н' => 2,
      'в' || 'ф' || 'з' || 'с' || 'ж' || 'ш' || 'щ' || 'х' => 1,
      _ => 0,
    };

/// Делит [word] на слоги: одна гласная на слог; согласные между
/// гласными отходят следующему слогу, пока образуют возможное начало
/// слова, остальное закрывает предыдущий («подъ-езд», «мощ-ность»).
/// Слоги в сумме дают исходное слово, регистр сохраняется.
List<String> splitWordToSyllables(String word) {
  final lower = word.toLowerCase();
  final boundaries = <int>[];
  var prevVowel = -1;
  for (var i = 0; i < lower.length; i++) {
    if (!_vowels.contains(lower[i])) continue;
    if (prevVowel >= 0) boundaries.add(_boundary(lower, prevVowel, i));
    prevVowel = i;
  }

  final syllables = <String>[];
  var start = 0;
  for (final b in boundaries) {
    syllables.add(word.substring(start, b));
    start = b;
  }
  syllables.add(word.substring(start));
  return syllables;
}

/// Граница между гласными [prevVowel] и [vowel]: начало самого длинного
/// допустимого начала слога; если цепочка согласных не может начинать
/// слог вовсе — она закрывает предыдущий (граница перед [vowel]).
int _boundary(String lower, int prevVowel, int vowel) {
  for (var j = prevVowel + 1; j < vowel; j++) {
    if (_canStartSyllable(lower.substring(j, vowel))) return j;
  }
  return vowel;
}

/// Может ли цепочка согласных (в [lower] до гласной) начинать слог:
/// хвостовой ь — часть согласной («стье»), внутри не должно быть й/ь/ъ
/// и соседних одинаковых букв («кас-са»), звучность растёт к гласной —
/// кроме с/з в начале; ж/ш/щ/ч скоплений не начинают.
bool _canStartSyllable(String cluster) {
  var onset = cluster;
  while (onset.endsWith('ь')) {
    onset = onset.substring(0, onset.length - 1);
  }
  if (onset.isEmpty) return false;
  if (onset.length > 1 && _noClusterStart.contains(onset[0])) return false;
  for (var k = 0; k < onset.length; k++) {
    if (_closers.contains(onset[k])) return false;
    if (k > 0 && onset[k] == onset[k - 1]) return false;
  }
  for (var k = 0; k + 1 < onset.length; k++) {
    if (k == 0 && _clusterPrefix.contains(onset[0])) continue;
    if (_sonority(onset[k]) >= _sonority(onset[k + 1])) return false;
  }
  return true;
}
