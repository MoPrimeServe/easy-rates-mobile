// usage_screen.dart — Consumption & History (Home tab → Usage).
//
// Sections:
//   • Water / Council-tax segment toggle
//   • Usage card  — headline m³ / kWh figure, ±% vs last month,
//                   period dropdown chip, sky CustomPainter line chart
//   • History list — monthly rows: period · figure · ±% delta
//   • Floating AppTabBar (Water tab, index 2, pre-selected)
//
// The line chart is drawn with a CustomPainter so it picks up the sky-500
// (scheme.secondary / t.info) token directly — no third-party chart library.
// All colours, spacing, and radii come from EasyRatesTokens.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../components/components.dart';
import '../../theme/theme.dart';

// ── Usage datasets ────────────────────────────────────────────────────────────

enum _UsageMode { water, councilTax }

@immutable
class _UsagePoint {
  const _UsagePoint(this.label, this.value);
  final String label; // month abbreviation, e.g. "Jan"
  final double value;
}

// Water (m³) — last 6 months
const _kWaterData = [
  _UsagePoint('Jan', 12.4),
  _UsagePoint('Feb', 11.8),
  _UsagePoint('Mar', 13.2),
  _UsagePoint('Apr', 14.5),
  _UsagePoint('May', 16.1),
  _UsagePoint('Jun', 18.3),
];

// Council-tax electricity (kWh) — last 6 months
const _kCouncilData = [
  _UsagePoint('Jan', 381),
  _UsagePoint('Feb', 365),
  _UsagePoint('Mar', 410),
  _UsagePoint('Apr', 445),
  _UsagePoint('May', 512),
  _UsagePoint('Jun', 498),
];

// History rows add a year label and a delta string.
@immutable
class _HistoryRow {
  const _HistoryRow(this.period, this.value, this.unit, this.delta);
  final String period; // "Jun 2026"
  final double value;
  final String unit;   // "m³" or "kWh"
  final String delta;  // "+13.7 %" or "—"
}

const _kWaterHistory = [
  _HistoryRow('Jun 2026', 18.3, 'm³', '+13.7 %'),
  _HistoryRow('May 2026', 16.1, 'm³', '+11.0 %'),
  _HistoryRow('Apr 2026', 14.5, 'm³', '+9.8 %'),
  _HistoryRow('Mar 2026', 13.2, 'm³', '+11.9 %'),
  _HistoryRow('Feb 2026', 11.8, 'm³', '−4.8 %'),
  _HistoryRow('Jan 2026', 12.4, 'm³', '—'),
];

const _kCouncilHistory = [
  _HistoryRow('Jun 2026', 498, 'kWh', '−2.7 %'),
  _HistoryRow('May 2026', 512, 'kWh', '+15.1 %'),
  _HistoryRow('Apr 2026', 445, 'kWh', '+8.5 %'),
  _HistoryRow('Mar 2026', 410, 'kWh', '+12.3 %'),
  _HistoryRow('Feb 2026', 365, 'kWh', '−4.2 %'),
  _HistoryRow('Jan 2026', 381, 'kWh', '—'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  _UsageMode _mode   = _UsageMode.water;
  int        _tabIndex = 2; // Water tab pre-selected

  List<_UsagePoint> get _chartData =>
      _mode == _UsageMode.water ? _kWaterData : _kCouncilData;

  List<_HistoryRow> get _historyRows =>
      _mode == _UsageMode.water ? _kWaterHistory : _kCouncilHistory;

  String get _currentFigure {
    final latest = _chartData.last;
    final unit   = _mode == _UsageMode.water ? ' m³' : ' kWh';
    final v      = latest.value;
    // No decimal for kWh, one for m³
    final s = _mode == _UsageMode.water
        ? v.toStringAsFixed(1)
        : v.toStringAsFixed(0);
    return '$s$unit';
  }

  String get _deltaBadge => _historyRows.first.delta;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt     = theme.textTheme;
    final t      = theme.extension<EasyRatesTokens>()!;

    const tabBarHeight = 72.0;

    return Scaffold(
      backgroundColor: t.appBg,
      body: Stack(
        children: [
          // ── Scrollable content ───────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.only(
                left: t.s5, right: t.s5,
                top: t.s4, bottom: tabBarHeight + t.s5,
              ),
              children: [
                // ── Page title ─────────────────────────────────────────────
                Text('Usage', style: tt.headlineSmall),
                SizedBox(height: t.s4),

                // ── Water / Council-tax toggle ──────────────────────────────
                _ModeToggle(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                  t: t,
                  scheme: scheme,
                  tt: tt,
                ),
                SizedBox(height: t.s4),

                // ── Usage card (figure + %, period chip, line chart) ────────
                _UsageCard(
                  mode: _mode,
                  figure: _currentFigure,
                  delta: _deltaBadge,
                  chartData: _chartData,
                  t: t,
                  scheme: scheme,
                  tt: tt,
                ),
                SizedBox(height: t.s5),

                // ── History list ────────────────────────────────────────────
                Text('History', style: tt.titleMedium),
                SizedBox(height: t.s2),
                _HistoryList(
                  rows: _historyRows,
                  t: t,
                  scheme: scheme,
                  tt: tt,
                ),
              ],
            ),
          ),

          // ── Floating tab bar ─────────────────────────────────────────────
          Positioned(
            left: t.s4, right: t.s4, bottom: t.s4,
            child: SafeArea(
              top: false,
              child: AppTabBar(
                currentIndex: _tabIndex,
                onTap: (i) {
                  if (i == 0) { context.go('/home'); return; }
                  setState(() => _tabIndex = i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode toggle ───────────────────────────────────────────────────────────────
// Two side-by-side pills in a surface pill-bar container; active = ink fill,
// inactive = transparent with muted label — mirrors the AppTabBar pattern.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.mode,
    required this.onChanged,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final _UsageMode mode;
  final ValueChanged<_UsageMode> onChanged;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(t.s1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: t.radiusPill,
      ),
      child: Row(
        children: [
          _TogglePill(
            label: 'Water',
            icon: LucideIcons.droplet,
            selected: mode == _UsageMode.water,
            onTap: () => onChanged(_UsageMode.water),
            t: t, scheme: scheme, tt: tt,
          ),
          _TogglePill(
            label: 'Council tax',
            icon: LucideIcons.zap,
            selected: mode == _UsageMode.councilTax,
            onTap: () => onChanged(_UsageMode.councilTax),
            t: t, scheme: scheme, tt: tt,
          ),
        ],
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    final color = selected ? scheme.onInverseSurface : scheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(
              horizontal: t.s3,
              vertical: t.s2,
            ),
            decoration: BoxDecoration(
              color: selected ? scheme.inverseSurface : null,
              borderRadius: t.radiusPill,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: t.iconSm, color: color),
                SizedBox(width: t.s1),
                Text(
                  label,
                  style: tt.labelMedium!.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Usage card ────────────────────────────────────────────────────────────────
class _UsageCard extends StatelessWidget {
  const _UsageCard({
    required this.mode,
    required this.figure,
    required this.delta,
    required this.chartData,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final _UsageMode mode;
  final String figure;
  final String delta;
  final List<_UsagePoint> chartData;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  // Delta is positive when it starts with '+'.
  Color _deltaColor() {
    if (delta == '—') return scheme.onSurfaceVariant;
    if (delta.startsWith('+')) return scheme.tertiary; // positive green
    return scheme.error; // negative red
  }

  @override
  Widget build(BuildContext context) {
    final sky = t.info; // sky-500 (#3E7BD8)

    return Container(
      padding: EdgeInsets.all(t.s5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: t.radiusLg,
        border: Border.all(color: scheme.outlineVariant, width: t.borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Period chip ─────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  mode == _UsageMode.water
                      ? 'Water consumption'
                      : 'Council-tax electricity',
                  style: tt.bodySmall!.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              // Period dropdown chip
              _PeriodChip(t: t, scheme: scheme, tt: tt),
            ],
          ),
          SizedBox(height: t.s3),

          // ── Headline figure + delta ─────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                figure,
                style: tt.headlineLarge!.copyWith(
                  color: scheme.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              SizedBox(width: t.s2),
              Padding(
                padding: EdgeInsets.only(bottom: t.s1), // baseline align
                child: Text(
                  '$delta vs last month',
                  style: tt.bodySmall!.copyWith(color: _deltaColor()),
                ),
              ),
            ],
          ),
          SizedBox(height: t.s4),

          // ── Sky line chart ──────────────────────────────────────────────
          SizedBox(
            height: 100,
            child: _LineChart(
              data: chartData.map((p) => p.value).toList(),
              labels: chartData.map((p) => p.label).toList(),
              color: sky,
              tt: tt,
              scheme: scheme,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Period dropdown chip ──────────────────────────────────────────────────────
class _PeriodChip extends StatelessWidget {
  const _PeriodChip({required this.t, required this.scheme, required this.tt});
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.s3, vertical: t.s1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: t.radiusPill,
        border: Border.all(color: scheme.outlineVariant, width: t.borderWidth),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Last 6 months',
            style: tt.labelSmall!.copyWith(color: scheme.onSurfaceVariant),
          ),
          SizedBox(width: t.s1),
          Icon(
            LucideIcons.chevronDown,
            size: t.iconSm - 4, // 14 — inline with the label
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

// ── Line chart ────────────────────────────────────────────────────────────────
// CustomPainter-based sky line chart.
// • Smooth cubic bezier line in sky-500 (t.info)
// • Gradient fill below the line: sky@24% → transparent
// • Month abbreviation labels below the chart
// • Terminal dot at the last data point
class _LineChart extends StatelessWidget {
  const _LineChart({
    required this.data,
    required this.labels,
    required this.color,
    required this.tt,
    required this.scheme,
  });
  final List<double> data;
  final List<String> labels;
  final Color color;
  final TextTheme tt;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    const labelHeight = 16.0;
    return Column(
      children: [
        Expanded(
          child: CustomPaint(
            painter: _ChartPainter(data: data, color: color),
            child: const SizedBox.expand(),
          ),
        ),
        SizedBox(
          height: labelHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: labels.map((l) => Text(
              l,
              style: tt.labelSmall!.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 10,
              ),
            )).toList(),
          ),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  const _ChartPainter({required this.data, required this.color});
  final List<double> data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final minVal = data.reduce(math.min);
    final maxVal = data.reduce(math.max);
    final range  = (maxVal - minVal).clamp(1.0, double.infinity);

    // Top and bottom padding inside the paint area (as fractions of height).
    const vPad = 0.12;

    Offset pt(int i) {
      final x = size.width * i / (data.length - 1);
      final y = size.height * (1 - vPad) -
                (data[i] - minVal) / range * size.height * (1 - vPad * 2);
      return Offset(x, y);
    }

    final points = List.generate(data.length, pt);

    // Smooth the line through cubic bezier control points (horizontal tangents).
    Path buildLinePath() {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length; i++) {
        final prev = points[i - 1];
        final curr = points[i];
        final cpX  = (prev.dx + curr.dx) / 2;
        path.cubicTo(cpX, prev.dy, cpX, curr.dy, curr.dx, curr.dy);
      }
      return path;
    }

    final linePath = buildLinePath();

    // Gradient fill below the line.
    final fillPath = Path.from(linePath)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withAlpha(60), color.withAlpha(0)], // chart fill gradient · design-value-ok
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // The line itself.
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Terminal dot at the latest data point.
    final last = points.last;
    canvas.drawCircle(last, 4.0, Paint()..color = color); // filled
    canvas.drawCircle(                                    // white ring
      last, 4.0,
      Paint()
        ..color = Colors.white // design-value-ok — constant-contrast ring; see dark-mode note
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.data != data || old.color != color;
}

// ── History list ──────────────────────────────────────────────────────────────
class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.rows,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final List<_HistoryRow> rows;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: t.radiusLg,
        border: Border.all(color: scheme.outlineVariant, width: t.borderWidth),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: scheme.outlineVariant),
            _HistoryRowTile(row: rows[i], t: t, scheme: scheme, tt: tt),
          ],
        ],
      ),
    );
  }
}

class _HistoryRowTile extends StatelessWidget {
  const _HistoryRowTile({
    required this.row,
    required this.t,
    required this.scheme,
    required this.tt,
  });
  final _HistoryRow row;
  final EasyRatesTokens t;
  final ColorScheme scheme;
  final TextTheme tt;

  Color _deltaColor() {
    if (row.delta == '—') return scheme.onSurfaceVariant;
    if (row.delta.startsWith('+')) return scheme.tertiary;
    return scheme.error;
  }

  String _fmtValue() {
    if (row.unit == 'm³') return '${row.value.toStringAsFixed(1)} ${row.unit}';
    return '${row.value.toStringAsFixed(0)} ${row.unit}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: t.listTilePadding,
      child: Row(
        children: [
          // Period
          Expanded(
            flex: 3,
            child: Text(
              row.period,
              style: tt.bodyMedium!.copyWith(color: scheme.onSurface),
            ),
          ),
          // Usage figure
          Text(
            _fmtValue(),
            style: tt.bodyMedium!.copyWith(
              color: scheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: t.s3),
          // Delta badge
          SizedBox(
            width: 72,
            child: Text(
              row.delta,
              textAlign: TextAlign.end,
              style: tt.bodySmall!.copyWith(color: _deltaColor()),
            ),
          ),
        ],
      ),
    );
  }
}
