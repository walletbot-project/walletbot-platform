import 'package:app/app_config/app_config_banner_list.dart';
import 'package:app/app_config/app_config_controller.dart';
import 'package:app/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('local version fallback follows the active locale', (
    tester,
  ) async {
    final controller = AppConfigController()..markUnsupported();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AppConfigBannerList(placement: 'home')),
        ),
      ),
    );

    expect(find.text('Update required'), findsOneWidget);
    expect(
      find.text('Update the app to continue syncing your data.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AppConfigBannerList(placement: 'home')),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Actualización obligatoria'), findsOneWidget);
    expect(
      find.text('Actualizá la aplicación para seguir sincronizando tus datos.'),
      findsOneWidget,
    );
  });
}
