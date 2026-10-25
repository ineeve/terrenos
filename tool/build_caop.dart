// Builds assets/caop/caop.json from the official CAOP GeoPackage for
// mainland Portugal (SPEC.md §6.2, PLAN.md T1.1 and spike S3, ADR 0007).
//
// The GeoPackage is ~190 MB and is not committed. Download and unzip:
//   https://geo2.dgterritorio.gov.pt/caop/CAOP_Continente_2025-gpkg.zip
//
// Usage:
//   dart run tool/build_caop.dart Continente_CAOP2025.gpkg [--tolerance 10]
//
// Boundary lines come from the `cont_trocos` layer, where every line between
// two areas is stored once with the area codes on its left and right. Each
// line is simplified once (Douglas–Peucker, in PT-TM06 metres), so
// neighbouring freguesias still share exactly the same border. The tool then
// checks the result against the unsimplified lines and writes reference
// points for test/core/caop/admin_boundaries_test.dart.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:terrenos/core/caop/admin_boundaries.dart';
import 'package:terrenos/core/crs/pt_tm06.dart';

const _assetPath = 'assets/caop/caop.json';
const _referencePath = 'test_fixtures/caop_reference.json';

/// Areas outside any freguesia: 97 estuary waters, 98 Spain, 99 the sea.
const _outside = {'97', '98', '99'};

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/build_caop.dart <Continente_CAOP*.gpkg> '
      '[--tolerance metres]',
    );
    exit(2);
  }
  final path = args.first;
  final toleranceIndex = args.indexOf('--tolerance');
  final tolerance = toleranceIndex < 0
      ? 10.0
      : double.parse(args[toleranceIndex + 1]);
  final edition = int.parse(
    RegExp(r'CAOP(\d{4})').firstMatch(path)?.group(1) ?? '$caopEdition',
  );
  if (edition != caopEdition) {
    stderr.writeln(
      'Warning: building CAOP $edition; update caopEdition in '
      'lib/core/caop/admin_boundaries.dart.',
    );
  }

  // Linux usually has only the runtime library, not the -dev symlink.
  open.overrideFor(OperatingSystem.linux, () {
    try {
      return DynamicLibrary.open('libsqlite3.so');
      // DynamicLibrary.open reports a missing library with an ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return DynamicLibrary.open('libsqlite3.so.0');
    }
  });
  final db = sqlite3.open(path, mode: OpenMode.readOnly);
  final distritos = [
    for (final row in db.select(
      'SELECT dt, distrito FROM cont_distritos ORDER BY dt',
    ))
      [row['dt'] as String, row['distrito'] as String],
  ];
  final concelhos = [
    for (final row in db.select(
      'SELECT dtmn, municipio FROM cont_municipios ORDER BY dtmn',
    ))
      [row['dtmn'] as String, row['municipio'] as String],
  ];
  final freguesiaRows = db.select(
    'SELECT dtmnfr, freguesia, designacao_simplificada '
    'FROM cont_freguesias ORDER BY dtmnfr',
  );
  final lines = <_Line>[
    for (final row in db.select(
      'SELECT geom, ea_direita, ea_esquerda FROM cont_trocos '
      'ORDER BY identificador',
    ))
      _Line(
        _lineString(row['geom'] as Uint8List),
        row['ea_esquerda'] as String,
        row['ea_direita'] as String,
      ),
  ];
  db.dispose();

  // Simplify in metres, then project and quantise to 1e-5 degrees.
  var rawPoints = 0;
  var keptPoints = 0;
  final arcs = <List<int>>[];
  final arcsOf = <String, List<int>>{};
  for (final line in lines) {
    rawPoints += line.points.length ~/ 2;
    final simplified = _simplify(line.points, tolerance);
    final quantised = <int>[];
    for (var i = 0; i < simplified.length; i += 2) {
      final ll = PtTm06.toLatLon(simplified[i], simplified[i + 1]);
      final x = (ll.lon * AdminBoundaries.scale).round();
      final y = (ll.lat * AdminBoundaries.scale).round();
      final n = quantised.length;
      if (n >= 2 && quantised[n - 2] == x && quantised[n - 1] == y) continue;
      quantised.addAll([x, y]);
    }
    keptPoints += quantised.length ~/ 2;
    final index = arcs.length;
    arcs.add([_level(line.left, line.right).index, ..._deltas(quantised)]);
    for (final code in {line.left, line.right}) {
      if (!_outside.contains(code)) (arcsOf[code] ??= []).add(index);
    }
  }

  final freguesias = <List<Object>>[];
  final problems = <String>[];
  for (final row in freguesiaRows) {
    final code = row['dtmnfr'] as String;
    final own = arcsOf[code] ?? const [];
    if (own.isEmpty) problems.add('$code has no boundary lines');
    if (!_closed(own.map((i) => lines[i].points))) {
      problems.add('$code: boundary lines do not form closed rings');
    }
    freguesias.add([
      code,
      row['freguesia'] as String,
      row['designacao_simplificada'] as String,
      _bounds(own.map((i) => _undelta(arcs[i]))),
      own,
    ]);
  }
  final unknown = arcsOf.keys.toSet().difference({
    for (final f in freguesias) f[0],
  });
  if (unknown.isNotEmpty) problems.add('Unknown area codes: $unknown');
  if (problems.isNotEmpty) {
    stderr.writeln(problems.join('\n'));
    exit(1);
  }

  final json = jsonEncode({
    'format': 1,
    'edition': edition,
    'source': 'CAOP $edition, Continente. Direção-Geral do Território, CC BY.',
    'toleranceMetres': tolerance,
    'distritos': distritos,
    'concelhos': concelhos,
    'freguesias': freguesias,
    'arcs': arcs,
  });
  File(_assetPath)
    ..createSync(recursive: true)
    ..writeAsStringSync(json);

  final boundaries = AdminBoundaries.parse(json);
  stdout
    ..writeln(
      'CAOP $edition: ${freguesias.length} freguesias, '
      '${concelhos.length} concelhos, ${distritos.length} distritos',
    )
    ..writeln(
      'Boundary lines: ${lines.length}, points $rawPoints → '
      '$keptPoints at ${tolerance.toStringAsFixed(0)} m',
    )
    ..writeln(
      'Wrote $_assetPath: ${(json.length / 1e6).toStringAsFixed(2)} MB '
      '(${(gzip.encode(utf8.encode(json)).length / 1e6).toStringAsFixed(2)} '
      'MB compressed)',
    );
  _check(boundaries, lines, arcsOf);
}

class _Line {
  new(this.points, this.left, this.right);

  /// Interleaved easting and northing in PT-TM06 metres.
  final Float64List points;
  final String left;
  final String right;
}

/// A GeoPackage geometry blob holding a 2D (or Z/M) WKB LineString.
Float64List _lineString(Uint8List blob) {
  final data = ByteData.sublistView(blob);
  final envelope = const [0, 32, 48, 48, 64][(blob[3] >> 1) & 7];
  var offset = 8 + envelope;
  final endian = blob[offset] == 1 ? Endian.little : Endian.big;
  final type = data.getUint32(offset + 1, endian);
  // ISO WKB adds 1000 for Z, 2000 for M; EWKB sets the top two bits.
  final base = type & 0x0FFFFFFF;
  if (base % 1000 != 2) throw FormatException('Not a LineString: $type');
  final hasZ = base ~/ 1000 == 1 || base ~/ 1000 == 3 || type & 0x80000000 != 0;
  final hasM = base ~/ 1000 >= 2 || type & 0x40000000 != 0;
  final stride = 2 + (hasZ ? 1 : 0) + (hasM ? 1 : 0);
  final count = data.getUint32(offset + 5, endian);
  offset += 9;
  final points = Float64List(count * 2);
  for (var i = 0; i < count; i++) {
    points[i * 2] = data.getFloat64(offset + i * stride * 8, endian);
    points[i * 2 + 1] = data.getFloat64(offset + i * stride * 8 + 8, endian);
  }
  return points;
}

BoundaryLevel _level(String a, String b) {
  if (_outside.contains(a) || _outside.contains(b)) return BoundaryLevel.outer;
  if (a.substring(0, 2) != b.substring(0, 2)) return BoundaryLevel.distrito;
  if (a.substring(0, 4) != b.substring(0, 4)) return BoundaryLevel.concelho;
  return BoundaryLevel.freguesia;
}

/// Douglas–Peucker keeping both ends. A closed line is split at its point
/// farthest from the start, so it can't collapse to a single point.
Float64List _simplify(Float64List p, double tolerance) {
  final n = p.length ~/ 2;
  if (n <= 2) return p;
  final keep = List.filled(n, false)
    ..[0] = true
    ..[n - 1] = true;
  final closed = p[0] == p[2 * n - 2] && p[1] == p[2 * n - 1];
  final stack = <(int, int)>[];
  if (closed) {
    var far = 1;
    var best = -1.0;
    for (var i = 1; i < n - 1; i++) {
      final d = _hypot(p[2 * i] - p[0], p[2 * i + 1] - p[1]);
      if (d > best) (far, best) = (i, d);
    }
    keep[far] = true;
    stack.addAll([(0, far), (far, n - 1)]);
  } else {
    stack.add((0, n - 1));
  }
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    var far = -1;
    var best = tolerance;
    for (var i = a + 1; i < b; i++) {
      final d = _segmentDistance(p, i, a, b);
      if (d > best) (far, best) = (i, d);
    }
    if (far >= 0) {
      keep[far] = true;
      stack.addAll([(a, far), (far, b)]);
    }
  }
  return Float64List.fromList([
    for (var i = 0; i < n; i++)
      if (keep[i]) ...[p[2 * i], p[2 * i + 1]],
  ]);
}

double _hypot(double x, double y) => sqrt(x * x + y * y);

/// Distance from point [i] to the segment from point [a] to point [b].
double _segmentDistance(List<double> p, int i, int a, int b) {
  final ax = p[2 * a];
  final ay = p[2 * a + 1];
  final dx = p[2 * b] - ax;
  final dy = p[2 * b + 1] - ay;
  final px = p[2 * i] - ax;
  final py = p[2 * i + 1] - ay;
  final length2 = dx * dx + dy * dy;
  final t = length2 == 0 ? 0.0 : ((px * dx + py * dy) / length2).clamp(0, 1);
  return _hypot(px - t * dx, py - t * dy);
}

/// Each point as the difference from the previous one; the first from 0.
List<int> _deltas(List<int> points) {
  final deltas = List.filled(points.length, 0);
  var x = 0;
  var y = 0;
  for (var i = 0; i < points.length; i += 2) {
    deltas[i] = points[i] - x;
    deltas[i + 1] = points[i + 1] - y;
    x = points[i];
    y = points[i + 1];
  }
  return deltas;
}

List<int> _undelta(List<int> arc) {
  final points = <int>[];
  var x = 0;
  var y = 0;
  for (var i = 1; i < arc.length; i += 2) {
    x += arc[i];
    y += arc[i + 1];
    points.addAll([x, y]);
  }
  return points;
}

List<int> _bounds(Iterable<List<int>> arcs) {
  var minX = 1 << 30;
  var minY = 1 << 30;
  var maxX = -(1 << 30);
  var maxY = -(1 << 30);
  for (final points in arcs) {
    for (var i = 0; i < points.length; i += 2) {
      minX = min(minX, points[i]);
      maxX = max(maxX, points[i]);
      minY = min(minY, points[i + 1]);
      maxY = max(maxY, points[i + 1]);
    }
  }
  return [minX, minY, maxX, maxY];
}

/// Every end point is shared by an even number of the area's lines, so the
/// lines join into closed rings.
bool _closed(Iterable<Float64List> lines) {
  final ends = <String, int>{};
  for (final p in lines) {
    for (final key in [
      '${p[0]},${p[1]}',
      '${p[p.length - 2]},${p[p.length - 1]}',
    ]) {
      ends[key] = (ends[key] ?? 0) + 1;
    }
  }
  return ends.values.every((count) => count.isEven);
}

/// Compares lookups on the asset with the unsimplified lines at random
/// points, and writes reference points far from any border.
void _check(
  AdminBoundaries boundaries,
  List<_Line> lines,
  Map<String, List<int>> arcsOf,
) {
  final bounds = {
    for (final MapEntry(:key, :value) in arcsOf.entries)
      key: _metreBounds(value.map((i) => lines[i].points)),
  };
  String? exact(double m, double p) {
    for (final MapEntry(:key, :value) in arcsOf.entries) {
      final b = bounds[key]!;
      if (m < b[0] || p < b[1] || m > b[2] || p > b[3]) continue;
      var inside = false;
      for (final i in value) {
        final q = lines[i].points;
        for (var j = 2; j < q.length; j += 2) {
          final (x1, y1, x2, y2) = (q[j - 2], q[j - 1], q[j], q[j + 1]);
          if ((y1 > p) != (y2 > p) &&
              m < (x2 - x1) * (p - y1) / (y2 - y1) + x1) {
            inside = !inside;
          }
        }
      }
      if (inside) return key;
    }
    return null;
  }

  double distanceToBorder(String code, double m, double p) {
    var best = double.infinity;
    for (final i in arcsOf[code]!) {
      final q = lines[i].points;
      for (var j = 2; j < q.length; j += 2) {
        best = min(
          best,
          _segmentDistance([...q.sublist(j - 2, j + 2), m, p], 2, 0, 1),
        );
      }
    }
    return best;
  }

  final random = Random(2026);
  const samples = 20000;
  var inside = 0;
  var disagreements = 0;
  var worst = 0.0;
  final timer = Stopwatch();
  final reference = <Map<String, Object>>[];
  for (var s = 0; s < samples; s++) {
    // Mainland Portugal in PT-TM06.
    final m = -120000 + random.nextDouble() * 285000;
    final p = -300000 + random.nextDouble() * 580000;
    final expected = exact(m, p);
    final ll = PtTm06.toLatLon(m, p);
    timer.start();
    final found = boundaries.locate(ll.lat, ll.lon)?.freguesia.code;
    timer.stop();
    if (expected != null) inside++;
    if (found != expected) {
      disagreements++;
      final code = expected ?? found!;
      worst = max(worst, distanceToBorder(code, m, p));
    } else if (expected != null &&
        reference.length < 150 &&
        distanceToBorder(expected, m, p) > 100) {
      reference.add({
        'lat': double.parse(ll.lat.toStringAsFixed(6)),
        'lon': double.parse(ll.lon.toStringAsFixed(6)),
        'freguesia': expected,
      });
    }
  }
  final microseconds = timer.elapsedMicroseconds / samples;
  stdout
    ..writeln(
      'Check: $samples random points, $inside inside a freguesia; '
      '$disagreements differ from the unsimplified lines, all within '
      '${worst.toStringAsFixed(1)} m of a border',
    )
    ..writeln('Lookup: ${microseconds.toStringAsFixed(1)} µs per point');
  final fixture = {
    'about':
        'Points more than 100 m from any freguesia border in CAOP '
        '$caopEdition, with the freguesia that contains them according to '
        'the unsimplified boundary lines. Written by tool/build_caop.dart.',
    'points': reference,
  };
  const pretty = JsonEncoder.withIndent('  ');
  File(_referencePath).writeAsStringSync('${pretty.convert(fixture)}\n');
  stdout.writeln('Wrote $_referencePath: ${reference.length} points');
}

List<double> _metreBounds(Iterable<Float64List> lines) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final p in lines) {
    for (var i = 0; i < p.length; i += 2) {
      minX = min(minX, p[i]);
      maxX = max(maxX, p[i]);
      minY = min(minY, p[i + 1]);
      maxY = max(maxY, p[i + 1]);
    }
  }
  return [minX, minY, maxX, maxY];
}
