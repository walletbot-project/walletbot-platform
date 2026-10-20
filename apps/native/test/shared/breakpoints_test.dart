import 'package:app/shared/breakpoints.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<double> initialSizeAt(WidgetTester tester, Size size) async {
    late double result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (context) {
            result = detailSheetInitialSize(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('detail sheets open taller on short windows', (tester) async {
    expect(await initialSizeAt(tester, const Size(360, 640)), 0.85);
    expect(await initialSizeAt(tester, const Size(412, 759)), 0.85);
  });

  testWidgets('detail sheets keep 60% on taller windows', (tester) async {
    expect(await initialSizeAt(tester, const Size(412, 760)), 0.6);
    expect(await initialSizeAt(tester, const Size(412, 915)), 0.6);
  });
}
