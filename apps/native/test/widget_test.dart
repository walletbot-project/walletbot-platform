import 'package:app/auth/auth_controller.dart';
import 'package:app/main.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows login when no account is active', (
    WidgetTester tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});

    final auth = AuthController();
    // Note: production startup runs ConvexClient.initialize() before
    // auth.load(), and load() touches ConvexClient unconditionally
    // (_detachAuth -> setAuth). The native client can't be initialized in
    // widget tests, so we render with a freshly constructed (empty)
    // controller, which is equivalent to load() with empty storage.

    await tester.pumpWidget(MyApp(auth: auth));
    await tester.pump();

    expect(find.text('Continue without account'), findsOneWidget);
  });
}
