/// Codes stored in the `type` and `landUse` fields (SPEC.md §3.6). Codes
/// never change once released; labels come from the translations.
library;

enum PropertyType {
  rustico,
  urbano,
  misto;

  static PropertyType? fromCode(Object? code) =>
      values.where((t) => t.name == code).firstOrNull;
}

enum LandUse {
  oliveGrove('olive_grove'),
  vineyard('vineyard'),
  orchard('orchard'),
  arable('arable'),
  pasture('pasture'),
  eucalyptus('forest_eucalyptus'),
  pine('forest_pine'),
  montado('forest_oak'),
  scrubland('scrubland'),
  builtUp('built_up'),
  mixed('mixed'),
  other('other');

  new(this.code);

  static LandUse? fromCode(Object? code) =>
      values.where((u) => u.code == code).firstOrNull;

  final String code;
}
