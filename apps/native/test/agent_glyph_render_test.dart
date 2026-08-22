import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders `assets/agent-glyph.svg` the way the voice FAB does, to catch the
/// mask silently dropping out of the drawing.
void main() {
  testWidgets('agent glyph renders with its mask applied', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF6DE7D8),
          body: Center(
            child: SvgPicture.asset(
              'assets/agent-glyph.svg',
              width: 160,
              height: 160,
              colorFilter: const ColorFilter.mode(
                Color(0xFF00201C),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('agent_glyph.png'),
    );
  });
}
