import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// STANZ BizFlow mark: an orange tile with a navy flow stroke, plus wordmark.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 40, this.showWordmark = true, this.onDark = false});

  final double size;
  final bool showWordmark;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final mark = Semantics(
      label: 'STANZ BizFlow',
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter()),
      ),
    );
    if (!showWordmark) return mark;
    final ink = onDark ? Colors.white : BizColors.navy;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        SizedBox(width: size * 0.28),
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'STANZ ',
                  style: TextStyle(fontWeight: FontWeight.w800, color: ink, letterSpacing: 0.5),
                ),
                const TextSpan(
                  text: 'BizFlow',
                  style: TextStyle(fontWeight: FontWeight.w600, color: BizColors.primary),
                ),
              ],
            ),
            style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: size * 0.5),
          ),
        ),
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final tile = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.28));
    canvas.drawRRect(tile, Paint()..color = BizColors.primary);
    // Rising "flow" line with three nodes: steady business growth.
    final path = Path()
      ..moveTo(s * 0.22, s * 0.68)
      ..cubicTo(s * 0.38, s * 0.68, s * 0.40, s * 0.44, s * 0.52, s * 0.46)
      ..cubicTo(s * 0.64, s * 0.48, s * 0.66, s * 0.30, s * 0.78, s * 0.30);
    canvas.drawPath(
      path,
      Paint()
        ..color = BizColors.navy
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.09
        ..strokeCap = StrokeCap.round,
    );
    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(s * 0.22, s * 0.68), s * 0.065, dot);
    canvas.drawCircle(Offset(s * 0.78, s * 0.30), s * 0.075, dot);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Constrains content width on tablets and applies the page gutter.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: Space.page),
        child: child,
      ),
    ),
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.md),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? BizColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: Radii.card,
      side: const BorderSide(color: BizColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) => SizedBox(width: expand ? double.infinity : null, child: _button());

  Widget _button() => FilledButton(
    onPressed: loading ? null : onPressed,
    child: AnimatedSwitcher(
      duration: Motion.fast,
      child: loading
          ? const SizedBox.square(
              key: ValueKey('loading'),
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: BizColors.textSecondary),
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: Sizes.iconSm), const SizedBox(width: Space.xs)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ),
    ),
  );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.lg, bottom: Space.xs),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        ),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

enum Tone { neutral, success, warning, error, info, brand }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = Tone.neutral, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  static (Color, Color) colors(Tone tone) => switch (tone) {
    Tone.success => (BizColors.successContainer, BizColors.success),
    Tone.warning => (BizColors.warningContainer, BizColors.warning),
    Tone.error => (BizColors.errorContainer, BizColors.error),
    Tone.info => (BizColors.infoContainer, BizColors.onSecondaryContainer),
    Tone.brand => (BizColors.primaryContainer, BizColors.onPrimaryContainer),
    Tone.neutral => (BizColors.surfaceMuted, BizColors.textSecondary),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: Radii.chip),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly empty state with a soft illustrated icon.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IllustratedIcon(icon: icon),
            const SizedBox(height: Space.lg),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Space.xs),
            Text(
              message,
              style: t.bodyMedium?.copyWith(color: BizColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: Space.lg),
              SizedBox(
                width: 240,
                child: PrimaryButton(label: actionLabel!, onPressed: onAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IllustratedIcon extends StatelessWidget {
  const _IllustratedIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 112,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Container(
          decoration: const BoxDecoration(color: BizColors.secondaryContainer, shape: BoxShape.circle),
        ),
        Positioned(
          right: 10,
          top: 14,
          child: Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(color: BizColors.primary, shape: BoxShape.circle),
          ),
        ),
        Positioned(
          left: 12,
          bottom: 18,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: BizColors.navy, shape: BoxShape.circle),
          ),
        ),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: BizColors.surface,
            borderRadius: BorderRadius.circular(Radii.lg),
            boxShadow: Elevations.card,
          ),
          child: Icon(icon, size: 30, color: BizColors.secondary),
        ),
      ],
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = ApiError.from(error);
    return EmptyState(
      icon: e.isNetwork ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      title: e.isNetwork ? "You're offline" : 'Something went wrong',
      message: e.message,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// Renders an [AsyncValue] with consistent loading, error and data states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});

  final AsyncValue<T> value;
  final Widget Function(T data) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => switch (value) {
    AsyncData(:final value) => data(value),
    AsyncError(:final error) when !value.hasValue => ErrorState(error: error, onRetry: onRetry),
    _ when value.hasValue => data(value.requireValue),
    _ => loading ?? const SkeletonList(),
  };
}

/// Gentle pulsing placeholders; static when the platform requests reduced motion.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.height = 16, this.width, this.radius = Radii.sm});

  final double height;
  final double? width;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
    child: Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(color: BizColors.border, borderRadius: BorderRadius.circular(widget.radius)),
    ),
  );
}

class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading',
    child: ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(Space.page),
      itemCount: count,
      separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
      itemBuilder: (_, _) => const AppCard(
        child: Row(
          children: [
            Skeleton(height: 44, width: 44, radius: Radii.md),
            SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 160),
                  SizedBox(height: Space.xs),
                  Skeleton(width: 96, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class MoneyText extends StatelessWidget {
  const MoneyText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: (style ?? Theme.of(context).textTheme.titleMedium!).tabular,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: error ? BizColors.primary : const Color(0xFF7FD6A8),
              size: 20,
            ),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: BizColors.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}
