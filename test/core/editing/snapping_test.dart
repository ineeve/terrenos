import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/editing/snapping.dart';

void main() {
  // 1 unit of longitude/latitude = 1 pixel, for easy reasoning.
  (double, double) screen(({double lon, double lat}) p) => (p.lon, p.lat);

  test('snaps to the nearest candidate within the distance', () {
    final result = snapTo(
      (lon: 0, lat: 0),
      [(lon: 8, lat: 0), (lon: 3, lat: 4), (lon: 20, lat: 0)],
      screen,
    );
    expect(result, (lon: 3.0, lat: 4.0));
  });

  test('does not snap when everything is too far', () {
    expect(snapTo((lon: 0, lat: 0), [(lon: 11, lat: 0)], screen), isNull);
    expect(snapTo((lon: 0, lat: 0), const [], screen), isNull);
  });

  test('the distance can be changed', () {
    expect(
      snapTo((lon: 0, lat: 0), [(lon: 15, lat: 0)], screen, maxPixels: 20),
      (lon: 15.0, lat: 0.0),
    );
  });
}
