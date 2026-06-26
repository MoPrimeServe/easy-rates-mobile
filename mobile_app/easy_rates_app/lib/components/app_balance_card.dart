// app_balance_card.dart — the lime-surface balance card. The Home screen's hero.
//
//   ┌─────────────────────────────────────────────┐
//   │ TOTAL OWED                       •••• 4821   │  ← eyebrow + masked acct no.
//   │                                              │
//   │ R 12 480.75                                  │  ← display figure (SA-grouped)
//   │                                              │
//   │ ACCOUNT HOLDER            DUE                 │
//   │ T. Mokoena               15 Jul 2026         │
//   └─────────────────────────────────────────────┘
//
// Every painted value resolves through the theme layer:
//   fill        → colorScheme.primary       (lime-500, both brightnesses)
//   content     → colorScheme.onPrimary     (ink-900 — reads on lime in light & dark)
//   figure type → textTheme.displayLarge     (58 Space Grotesk, tabular figures)
//   geometry    → EasyRatesTokens            (radius rXl 28, s6 padding, the 4px scale)
// Nothing is hardcoded — see the no-hardcoded-design-values guard test.
//
// Money is rendered R/SA style: an "R", a gap, the integer part grouped in threes
// with spaces, and a two-decimal cents tail (e.g. "R 12 480.75"). The figure sits
// in a single-line FittedBox, so it scales down rather than wrapping mid-number.
import 'package:flutter/material.dart';
import '../theme/theme.dart';

class AppBalanceCard extends StatelessWidget {
  const AppBalanceCard({
    super.key,
    required this.totalOwed,
    required this.accountHolder,
    required this.accountNumber,
    required this.dueDate,
    this.currencySymbol = 'R',
  });

  /// The headline figure — total amount owed on the account, in Rand.
  final double totalOwed;

  /// Account-holder display name, e.g. "T. Mokoena".
  final String accountHolder;

  /// The full municipal account number; rendered masked to its last four digits.
  final String accountNumber;

  /// Statement due date; rendered "15 Jul 2026".
  final DateTime dueDate;

  /// Currency prefix — defaults to the Rand sign.
  final String currencySymbol;

  static const List<String> _monthAbbr = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  // R/SA money formatting: "R 12 480.75" — integer part grouped in threes with
  // spaces (the SA thousands separator), two-decimal tail.
  String _formatAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final intPart = fixed.substring(0, dot);
    final decPart = fixed.substring(dot + 1);

    final grouped = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write(' ');
      grouped.write(intPart[i]);
    }
    return '$currencySymbol $grouped.$decPart';
  }

  // Mask all but the last four digits of the account number, card-style.
  String _maskedAccount() {
    final last4 = accountNumber.length <= 4
        ? accountNumber
        : accountNumber.substring(accountNumber.length - 4);
    return '•••• $last4';
  }

  String _formatDueDate() =>
      '${dueDate.day} ${_monthAbbr[dueDate.month - 1]} ${dueDate.year}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final t = theme.extension<EasyRatesTokens>()!;

    // Ink content reads on the lime fill in both brightnesses (primary is lime,
    // onPrimary is ink-900, in both schemes). Hierarchy comes from the type ramp,
    // not from colour — so a single foreground keeps the card legible day & night.
    final ink = scheme.onPrimary;
    final eyebrow = textTheme.labelSmall!.copyWith(color: ink); // 11 uppercase
    // Masked account number: Space Grotesk tabular, body size — pulled from the
    // displayLarge family (the mono/tabular face) like ErAmountDisplay does.
    final mono = textTheme.displayLarge!.copyWith(
      fontSize: AppTextStyles.moneyBaseSize,
      fontWeight: FontWeight.w600,
      color: ink,
    );

    return Container(
      padding: EdgeInsets.all(t.s6), // 24 — hero generosity
      decoration: BoxDecoration(
        color: scheme.primary, // lime-500
        borderRadius: t.radiusXl, // 28
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Eyebrow + masked account number ─────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('TOTAL OWED', style: eyebrow)),
              Text(_maskedAccount(), style: mono),
            ],
          ),
          SizedBox(height: t.s3),

          // ── The display figure ──────────────────────────────────────────
          // displayLarge is 58px; FittedBox scales it down for large amounts on
          // narrow screens rather than overflowing.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              _formatAmount(totalOwed),
              maxLines: 1,
              style: textTheme.displayLarge!.copyWith(color: ink),
            ),
          ),
          SizedBox(height: t.s5),

          // ── Account holder (left) + due date (right) ────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACCOUNT HOLDER', style: eyebrow),
                    SizedBox(height: t.s1),
                    Text(
                      accountHolder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium!.copyWith(color: ink),
                    ),
                  ],
                ),
              ),
              SizedBox(width: t.s4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('DUE', style: eyebrow),
                  SizedBox(height: t.s1),
                  Text(
                    _formatDueDate(),
                    style: textTheme.titleMedium!.copyWith(color: ink),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
