import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrenos/app/providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the app loads the bundled asset off the UI thread', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final caop = await container.read(adminBoundariesProvider.future);
    expect(caop.freguesias, hasLength(3049));
    expect(caop.locate(38.7076, -9.1365)?.concelho.name, 'Lisboa');
  });
}
