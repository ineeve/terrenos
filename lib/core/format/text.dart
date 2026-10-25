/// Text helpers for search.
library;

/// Lowercase without Portuguese diacritics and with collapsed spaces, so
/// "sao joao" finds "São João" (MAP-9, IDN-6).
String foldForSearch(String s) {
  const from = 'áàâãäçéèêëíìîïñóòôõöúùûü';
  const to = 'aaaaaceeeeiiiinooooouuuu';
  final buffer = StringBuffer();
  for (final char in s.trim().toLowerCase().split('')) {
    final i = from.indexOf(char);
    buffer.write(i < 0 ? char : to[i]);
  }
  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ');
}
