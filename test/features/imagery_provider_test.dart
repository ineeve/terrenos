import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/core/map/imagery.dart';
import 'package:terrenos/features/map/map_page.dart';

void main() {
  // Regression: the real provider once had a const headers map, and
  // TileLayer's constructor (which adds a default User-Agent with
  // putIfAbsent) crashed the map on the phone. Widget tests use a fake
  // provider, so check the real one here.
  test('the real imagery provider works with TileLayer', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = container.read(imageryTileProviderProvider);

    expect(
      () => TileLayer(
        wmsOptions: WMSTileLayerOptions(
          baseUrl: ImagerySource.ortos2025.baseUrl,
          layers: [ImagerySource.ortos2025.layer],
        ),
        tileProvider: provider,
        userAgentPackageName: 'pt.terrenos.app',
      ),
      returnsNormally,
    );
    expect(provider.headers['User-Agent'], imageryUserAgent);
  });
}
