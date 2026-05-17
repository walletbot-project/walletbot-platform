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
    await auth.load();

    await tester.pumpWidget(MyApp(auth: auth));
    await tester.pump();

    expect(find.text('Continue without account'), findsOneWidget);
  });
}
