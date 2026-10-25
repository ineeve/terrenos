/// Searching, sorting and filtering the property list (MGT-1, MGT-2,
/// MGT-8, IDN-6), and the location filled in from CAOP (PROP-9).
library;

import 'package:meta/meta.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/geometry/geometry_service.dart';
import 'package:terrenos/core/model/documents.dart';
import 'package:terrenos/core/model/geometry_history.dart';
import 'package:terrenos/core/model/identifiers.dart';
import 'package:terrenos/core/model/property_kinds.dart';

enum PropertySort { name, processNumber, area, freguesia, lastChange }

@immutable
class PropertyQuery {
  const new({
    this.search = '',
    this.sort = PropertySort.name,
    this.types = const {},
    this.landUses = const {},
    this.concelhos = const {},
    this.freguesias = const {},
    this.hasProcessNumber,
    this.plannedOnly = false,
  });

  final String search;
  final PropertySort sort;

  /// Empty sets don't filter.
  final Set<PropertyType> types;
  final Set<LandUse> landUses;
  final Set<String> concelhos;
  final Set<String> freguesias;

  /// `true`: only with a process number; `false`: only without.
  final bool? hasProcessNumber;

  /// Only properties with planned (not yet surveyed) vertices (MGT-8).
  final bool plannedOnly;

  bool get isFiltered =>
      types.isNotEmpty ||
      landUses.isNotEmpty ||
      concelhos.isNotEmpty ||
      freguesias.isNotEmpty ||
      hasProcessNumber != null ||
      plannedOnly;

  int get filterCount =>
      (types.isNotEmpty ? 1 : 0) +
      (landUses.isNotEmpty ? 1 : 0) +
      (concelhos.isNotEmpty ? 1 : 0) +
      (freguesias.isNotEmpty ? 1 : 0) +
      (hasProcessNumber != null ? 1 : 0) +
      (plannedOnly ? 1 : 0);

  PropertyQuery copyWith({
    String? search,
    PropertySort? sort,
    Set<PropertyType>? types,
    Set<LandUse>? landUses,
    Set<String>? concelhos,
    Set<String>? freguesias,
    bool? Function()? hasProcessNumber,
    bool? plannedOnly,
  }) => PropertyQuery(
    search: search ?? this.search,
    sort: sort ?? this.sort,
    types: types ?? this.types,
    landUses: landUses ?? this.landUses,
    concelhos: concelhos ?? this.concelhos,
    freguesias: freguesias ?? this.freguesias,
    hasProcessNumber: hasProcessNumber != null
        ? hasProcessNumber()
        : this.hasProcessNumber,
    plannedOnly: plannedOnly ?? this.plannedOnly,
  );

  /// Without filters, keeping the search and the sort.
  PropertyQuery get cleared => PropertyQuery(search: search, sort: sort);

  List<PropertyDocument> apply(Iterable<PropertyDocument> properties) {
    final shown = properties.where(matches).toList();
    int byName(PropertyDocument a, PropertyDocument b) =>
        foldAccents(a.name).compareTo(foldAccents(b.name));
    // Properties without the sort value go last, then by name.
    int missingLast<T extends Comparable<T>>(
      PropertyDocument a,
      PropertyDocument b,
      T? Function(PropertyDocument) key, {
      bool descending = false,
    }) {
      final ka = key(a);
      final kb = key(b);
      if (ka == null || kb == null) {
        if (ka == kb) return byName(a, b);
        return ka == null ? 1 : -1;
      }
      final c = descending ? kb.compareTo(ka) : ka.compareTo(kb);
      return c != 0 ? c : byName(a, b);
    }

    shown.sort(switch (sort) {
      PropertySort.name => byName,
      PropertySort.processNumber => (a, b) => missingLast(
        a,
        b,
        (d) => switch (d.processNumber) {
          null => null,
          final n => Identifiers.normalizeProcessNumber(n),
        },
      ),
      // Largest first.
      PropertySort.area => (a, b) => missingLast(
        a,
        b,
        propertyArea,
        descending: true,
      ),
      PropertySort.freguesia => (a, b) => missingLast(
        a,
        b,
        (d) => switch (locationOf(d)?.freguesia) {
          null => null,
          final f => foldAccents(f),
        },
      ),
      // Newest first.
      PropertySort.lastChange => (a, b) => missingLast(
        a,
        b,
        (d) => d.latestTimestamp,
        descending: true,
      ),
    });
    return shown;
  }

  bool matches(PropertyDocument doc) {
    if (!matchesSearch(doc, search)) return false;
    if (types.isNotEmpty &&
        !types.contains(PropertyType.fromCode(doc.field(PropertyField.type)))) {
      return false;
    }
    if (landUses.isNotEmpty &&
        !landUses.contains(
          LandUse.fromCode(doc.field(PropertyField.landUse)),
        )) {
      return false;
    }
    final location = locationOf(doc);
    if (concelhos.isNotEmpty && !concelhos.contains(location?.concelho)) {
      return false;
    }
    if (freguesias.isNotEmpty && !freguesias.contains(location?.freguesia)) {
      return false;
    }
    if (hasProcessNumber case final wanted?) {
      if ((doc.processNumber != null) != wanted) return false;
    }
    if (plannedOnly) {
      final vertices = doc.geometry.current?.vertices ?? const [];
      if (!vertices.any((v) => !v.isSurveyed)) return false;
    }
    return true;
  }

  /// Accent- and case-insensitive name match, or a normalised partial
  /// match on the process number (IDN-6).
  static bool matchesSearch(PropertyDocument doc, String query) {
    final q = query.trim();
    if (q.isEmpty) return true;
    final number = doc.processNumber;
    final key = Identifiers.normalizeProcessNumber(q);
    return foldAccents(doc.name).contains(foldAccents(q)) ||
        (number != null &&
            key.isNotEmpty &&
            Identifiers.normalizeProcessNumber(number).contains(key));
  }
}

/// Area in m², or `null` without a measurable boundary. Cached per
/// boundary version, since lists sort and total by it (§7.1).
double? propertyArea(PropertyDocument doc) {
  final current = doc.geometry.current;
  if (current == null || current.vertices.length < 3) return null;
  return _areas[current.hash] ??= GeometryService.measure(current.parts)
      .areaSquareMetres;
}

final _areas = <String, double>{};

/// Total area of [properties] in m² (MGT-2).
double totalArea(Iterable<PropertyDocument> properties) =>
    properties.fold(0, (sum, d) => sum + (propertyArea(d) ?? 0));

/// Distrito, concelho and freguesia names (PROP-9).
@immutable
class PropertyLocation {
  const new({this.distrito, this.concelho, this.freguesia, this.dicofre});

  factory fromJson(Map<String, Object?> json) => PropertyLocation(
    distrito: _text(json['distrito']),
    concelho: _text(json['concelho']),
    freguesia: _text(json['freguesia']),
    dicofre: _text(json['dicofre']),
  );

  /// Filled from CAOP: the freguesia containing the property's interior
  /// point (§6.2).
  factory fromCaop(AdminLocation location) => PropertyLocation(
    distrito: location.distrito.name,
    concelho: location.concelho.name,
    freguesia: location.freguesia.name,
    dicofre: location.freguesia.code,
  );

  final String? distrito;
  final String? concelho;
  final String? freguesia;

  /// The CAOP code; only kept while the names are the ones CAOP gave.
  final String? dicofre;

  bool get isEmpty => distrito == null && concelho == null && freguesia == null;

  Map<String, Object?>? toJson() => isEmpty
      ? null
      : {
          'distrito': distrito,
          'concelho': concelho,
          'freguesia': freguesia,
          if (dicofre != null) 'dicofre': dicofre,
        };

  @override
  bool operator ==(Object other) =>
      other is PropertyLocation &&
      other.distrito == distrito &&
      other.concelho == concelho &&
      other.freguesia == freguesia &&
      other.dicofre == dicofre;

  @override
  int get hashCode => Object.hash(distrito, concelho, freguesia, dicofre);
}

PropertyLocation? locationOf(PropertyDocument doc) =>
    switch (doc.field(PropertyField.location)) {
      final Map<String, Object?> json => PropertyLocation.fromJson(json),
      _ => null,
    };

/// The CAOP location of a boundary's interior point, so it falls inside
/// the parcel even for L-shapes; `null` outside mainland Portugal.
PropertyLocation? locateBoundary(AdminBoundaries caop, BoundaryParts parts) {
  final count = parts.fold(
    0,
    (sum, part) => sum + part.fold(0, (s, ring) => s + ring.length),
  );
  if (count < 3) return null;
  final point = GeometryService.measure(parts).interiorPoint;
  return switch (caop.locate(point.lat, point.lon)) {
    null => null,
    final found => PropertyLocation.fromCaop(found),
  };
}

String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Lowercase without diacritics, so "sao joao" finds "São João".
String foldAccents(String s) {
  const from = 'áàâãäçéèêëíìîïñóòôõöúùûü';
  const to = 'aaaaaceeeeiiiinooooouuuu';
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final char in lower.split('')) {
    final i = from.indexOf(char);
    out.write(i < 0 ? char : to[i]);
  }
  return out.toString();
}
