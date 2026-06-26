import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/components/app_tab_bar.dart';
import 'package:easy_rates_app/theme/app_theme.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Widget host(Widget child) =>
      MaterialApp(theme: buildEasyRatesTheme(), home: Scaffold(body: child));

  group('AppTabBar', () {
    test('ships the five Emfuleni tabs with the right Lucide glyphs', () {
      expect(kEmfuleniTabs.map((t) => t.icon).toList(), [
        LucideIcons.house,
        LucideIcons.receipt,
        LucideIcons.droplet,
        LucideIcons.bell,
        LucideIcons.user,
      ]);
    });

    testWidgets('renders a glyph per tab on the ink-900 surface',
        (tester) async {
      await tester.pumpWidget(host(
        AppTabBar(currentIndex: 0, onTap: (_) {}),
      ));

      expect(find.byType(Icon), findsNWidgets(5));

      // The bar surface is the ink-900 token.
      final container = tester.widget<Container>(
        find.ancestor(of: find.byType(Row), matching: find.byType(Container)).first,
      );
      final decoration = container.decoration as BoxDecoration;
      const tokens = EasyRatesTokens.light;
      expect(decoration.color, tokens.ink900);
    });

    testWidgets('selected tab shows its label inside the lime pill',
        (tester) async {
      await tester.pumpWidget(host(
        AppTabBar(currentIndex: 2, onTap: (_) {}),
      ));
      // Only the selected tab expands to show its label.
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Home'), findsNothing);

      // A lime (primary) pill exists behind the selected tab.
      final scheme = buildEasyRatesTheme().colorScheme;
      final hasLimePill = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .any((c) => (c.decoration as BoxDecoration).color == scheme.primary);
      expect(hasLimePill, isTrue);
    });

    testWidgets('onTap reports the tapped index', (tester) async {
      int? tapped;
      await tester.pumpWidget(host(
        AppTabBar(currentIndex: 0, onTap: (i) => tapped = i),
      ));
      await tester.tap(find.byIcon(LucideIcons.user));
      expect(tapped, 4);
    });
  });
}
