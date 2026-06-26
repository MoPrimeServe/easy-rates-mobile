import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        actions: [
          IconButton(
            icon: Icon(
              context.watch<ThemeController>().isDark
                  ? LucideIcons.sun
                  : LucideIcons.moon,
            ),
            tooltip: 'Toggle theme',
            onPressed: () => context.read<ThemeController>().toggle(),
          ),
          IconButton(
            icon: const Icon(LucideIcons.bell),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: t.screenPadding,
        children: [
          ErCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amount due', style: textTheme.labelSmall),
                const SizedBox(height: AppSpacing.sm),
                const ErAmountDisplay(
                  current: 1842.50,
                  previous: 2100.00,
                  label: null,
                ),
                const SizedBox(height: AppSpacing.md),
                const ErStatusBadge(ErStatus.partial),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Charges breakdown', style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          // TODO: replace with real line items from provider
          ..._placeholderLineItems(context),
        ],
      ),
    );
  }

  List<Widget> _placeholderLineItems(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final monoBase = textTheme.displayLarge!.copyWith(
      fontSize: AppTextStyles.moneyBaseSize, fontWeight: FontWeight.w500,
    );
    const items = [
      ('Water & Sanitation', 620.00),
      ('Electricity', 980.00),
      ('Property Rates', 180.00),
      ('Refuse', 62.50),
    ];
    return items
        .map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ErCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(item.$1, style: textTheme.bodyLarge),
                  Text(
                    'R ${item.$2.toStringAsFixed(2)}',
                    style: monoBase,
                  ),
                ],
              ),
            ),
          ),
        )
        .toList();
  }
}
