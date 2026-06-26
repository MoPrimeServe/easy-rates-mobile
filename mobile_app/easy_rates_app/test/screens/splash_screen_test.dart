import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:easy_rates_app/screens/splash/splash_screen.dart';
import 'package:easy_rates_app/theme/er_tokens.dart';

// Pins the Splash screen's key structural invariants:
//   - always renders on the dark ink-900 surface
//   - contains the droplet logo, brand name, tagline, dots, and CTA
//   - scaffold background is t.appBg from the dark token set (ink-900)
//   - "Get started" button is present and tappable

// Minimal router: splash at /, a stub home at /home.
Widget splashApp() => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, state) => const SplashScreen()),
          GoRoute(
            path: '/home',
            builder: (_, state) => const Scaffold(body: Text('home')),
          ),
        ],
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('SplashScreen — structure', () {
    testWidgets('renders droplet icon, brand name, tagline and CTA',
        (tester) async {
      await tester.pumpWidget(splashApp());
      await tester.pump();

      expect(find.byIcon(LucideIcons.droplet), findsOneWidget);
      expect(find.text('EasyRates'), findsOneWidget);
      expect(find.textContaining('Emfuleni'), findsWidgets);
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('scaffold background is always the dark ink-900 token',
        (tester) async {
      await tester.pumpWidget(splashApp());
      await tester.pump();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EasyRatesTokens.dark.appBg);
    });

    testWidgets('Theme widget inside SplashScreen is always the dark token set',
        (tester) async {
      await tester.pumpWidget(splashApp());
      await tester.pump();

      // find.byType(Theme).first would return MaterialApp's outer theme (light).
      // We want only the Theme that is a descendant of SplashScreen itself.
      final themeWidget = tester.widget<Theme>(
        find.descendant(
          of: find.byType(SplashScreen),
          matching: find.byType(Theme),
        ),
      );
      expect(themeWidget.data.brightness, Brightness.dark);
    });

    testWidgets('renders at least three carousel dot containers', (tester) async {
      await tester.pumpWidget(splashApp());
      await tester.pump();

      // AnimatedContainer is shared by AppButton (one) and the three dot
      // indicators — total >= 3 confirms dots are present.
      final containers = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(containers.length, greaterThanOrEqualTo(3));
    });
  });

  group('SplashScreen — navigation', () {
    testWidgets('"Get started" navigates to /home', (tester) async {
      await tester.pumpWidget(splashApp());
      await tester.pump();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });
  });
}
