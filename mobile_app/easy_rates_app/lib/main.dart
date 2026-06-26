import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'router.dart';
import 'theme/theme.dart';

void main() {
  // Fonts ship bundled in assets/fonts/ (Space Grotesk + Manrope static weights),
  // so google_fonts resolves them locally — no first-launch CDN fetch / FOUT, which
  // matters for low-connectivity municipal users. Disable runtime fetching so a
  // missing variant fails loudly in dev rather than silently reaching for the network.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const EasyRatesApp());
}

class EasyRatesApp extends StatelessWidget {
  const EasyRatesApp({super.key});

  @override
  Widget build(BuildContext context) {
    // ThemeController lives above MaterialApp so any screen can flip brightness;
    // the Consumer rebuilds MaterialApp when themeMode changes.
    return ChangeNotifierProvider(
      create: (_) => ThemeController(),
      child: Consumer<ThemeController>(
        builder: (context, controller, _) => MaterialApp.router(
          title: 'EasyRates',
          debugShowCheckedModeBanner: false,
          theme: buildEasyRatesTheme(),
          darkTheme: buildEasyRatesDarkTheme(),
          themeMode: controller.mode,
          routerConfig: appRouter,
        ),
      ),
    );
  }
}
