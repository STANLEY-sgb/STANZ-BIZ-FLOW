import 'package:flutter/material.dart';

import 'tokens.dart';

/// Light theme built on Material 3 and customised through [BizColors].
///
/// Dark mode is intentionally not shipped yet: it will be added only once every
/// component and workflow can be verified against it.
abstract final class AppTheme {
  static const fontFamily = 'Inter';

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: BizColors.primary,
      onPrimary: BizColors.onPrimary,
      primaryContainer: BizColors.primaryContainer,
      onPrimaryContainer: BizColors.onPrimaryContainer,
      secondary: BizColors.secondary,
      onSecondary: BizColors.onSecondary,
      secondaryContainer: BizColors.secondaryContainer,
      onSecondaryContainer: BizColors.onSecondaryContainer,
      tertiary: BizColors.navy,
      onTertiary: Colors.white,
      error: BizColors.error,
      onError: Colors.white,
      errorContainer: BizColors.errorContainer,
      onErrorContainer: BizColors.error,
      surface: BizColors.surface,
      onSurface: BizColors.textPrimary,
      onSurfaceVariant: BizColors.textSecondary,
      surfaceContainerLowest: BizColors.surface,
      surfaceContainerLow: BizColors.background,
      surfaceContainer: BizColors.surfaceMuted,
      surfaceContainerHigh: BizColors.surfaceMuted,
      outline: BizColors.borderStrong,
      outlineVariant: BizColors.border,
      inverseSurface: BizColors.navy,
      onInverseSurface: Colors.white,
    );

    final text = _textTheme();
    final controlShape = RoundedRectangleBorder(borderRadius: Radii.control);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: text,
      scaffoldBackgroundColor: BizColors.background,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: BizColors.background,
        foregroundColor: BizColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: BizColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.card,
          side: const BorderSide(color: BizColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(color: BizColors.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BizColors.primary,
          foregroundColor: BizColors.onPrimary,
          disabledBackgroundColor: BizColors.border,
          disabledForegroundColor: BizColors.textDisabled,
          minimumSize: const Size(64, Sizes.controlHeight),
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BizColors.navy,
          minimumSize: const Size(64, Sizes.controlHeight),
          side: const BorderSide(color: BizColors.borderStrong),
          shape: controlShape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BizColors.secondary,
          minimumSize: const Size(Sizes.minTouch, Sizes.minTouch),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        helperMaxLines: 2,
        errorMaxLines: 3,
        filled: true,
        fillColor: BizColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        labelStyle: text.bodyMedium?.copyWith(color: BizColors.textSecondary),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: BizColors.secondary),
        hintStyle: text.bodyMedium?.copyWith(color: BizColors.textDisabled),
        border: OutlineInputBorder(
          borderRadius: Radii.control,
          borderSide: const BorderSide(color: BizColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.control,
          borderSide: const BorderSide(color: BizColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.control,
          borderSide: const BorderSide(color: BizColors.secondary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.control,
          borderSide: const BorderSide(color: BizColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.control,
          borderSide: const BorderSide(color: BizColors.error, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: BizColors.surface,
        selectedColor: BizColors.primaryContainer,
        side: const BorderSide(color: BizColors.border),
        shape: RoundedRectangleBorder(borderRadius: Radii.chip),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: BizColors.onPrimaryContainer),
        checkmarkColor: BizColors.onPrimaryContainer,
        padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xxs),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BizColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: BizColors.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelSmall?.copyWith(
            color: s.contains(WidgetState.selected) ? BizColors.navy : BizColors.textSecondary,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? BizColors.primaryPressed : BizColors.textSecondary,
            size: Sizes.iconMd,
          ),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BizColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: BizColors.navy,
        contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: Radii.control),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BizColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.card),
        titleTextStyle: text.titleLarge,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: BizColors.textSecondary,
        contentPadding: EdgeInsets.symmetric(horizontal: Space.md),
        minVerticalPadding: Space.sm,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: BizColors.primary),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? BizColors.navy : BizColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : BizColors.textPrimary,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: BizColors.border)),
        ),
      ),
    );
  }

  static TextTheme _textTheme() {
    const base = TextStyle(fontFamily: fontFamily, color: BizColors.textPrimary, height: 1.35);
    return TextTheme(
      displaySmall: base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15),
      headlineMedium: base.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2),
      headlineSmall: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: base.copyWith(fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleSmall: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: base.copyWith(fontSize: 16, fontWeight: FontWeight.w400),
      bodyMedium: base.copyWith(fontSize: 14, fontWeight: FontWeight.w400),
      bodySmall: base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w400, color: BizColors.textSecondary),
      labelLarge: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      labelMedium: base.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
      labelSmall: base.copyWith(fontSize: 11.5, fontWeight: FontWeight.w500, letterSpacing: 0.2),
    );
  }
}

/// Tabular figures keep columns of money aligned.
extension MoneyTextStyle on TextStyle {
  TextStyle get tabular => copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
