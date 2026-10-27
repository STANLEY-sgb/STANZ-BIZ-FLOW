import 'package:flutter/material.dart';

/// STANZ BizFlow design tokens.
///
/// Orange/coral = primary actions and selected highlights.
/// Blue = secondary actions, information and charts.
/// Navy = headings, navigation and visual grounding.
/// Components must use these tokens instead of literal colours.
abstract final class BizColors {
  // Brand
  static const primary = Color(0xFFF47745); // orange/coral
  static const primaryPressed = Color(0xFFE0612F);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFFFFEBE2);
  static const onPrimaryContainer = Color(0xFF8A3210);

  static const secondary = Color(0xFF438FCB); // medium blue
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFEAF4FC); // light blue
  static const onSecondaryContainer = Color(0xFF1C5785);

  static const navy = Color(0xFF20243F);
  static const navySoft = Color(0xFF2E3458);

  // Surfaces
  static const background = Color(0xFFF8FAFC); // warm off-white
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF1F4F8);

  // Text
  static const textPrimary = Color(0xFF20243F);
  static const textSecondary = Color(0xFF5F6B7E); // darkened from #687386 for AA contrast on off-white
  static const textDisabled = Color(0xFF9AA4B2);

  static const border = Color(0xFFE3E9F0);
  static const borderStrong = Color(0xFFCBD5E1);

  // Status
  static const success = Color(0xFF21865A);
  static const successContainer = Color(0xFFE3F4EB);
  static const warning = Color(0xFFB87508); // darker than #D99018 so text on white meets AA
  static const warningContainer = Color(0xFFFFF3DC);
  static const error = Color(0xFFD94848);
  static const errorContainer = Color(0xFFFDE8E8);
  static const info = secondary;
  static const infoContainer = secondaryContainer;
}

/// 4-point spacing scale.
abstract final class Space {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Horizontal page gutter.
  static const double page = 16;
}

abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  static final BorderRadius card = BorderRadius.circular(lg);
  static final BorderRadius control = BorderRadius.circular(md);
  static final BorderRadius chip = BorderRadius.circular(sm);
}

abstract final class Sizes {
  static const double controlHeight = 52;
  static const double minTouch = 48;
  static const double iconSm = 18;
  static const double iconMd = 22;
  static const double iconLg = 28;
  static const double borderWidth = 1;

  /// Content width cap so tablets do not stretch phone layouts edge to edge.
  static const double maxContentWidth = 720;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 360);
  static const curve = Curves.easeOutCubic;
}

abstract final class Elevations {
  static const List<BoxShadow> card = [BoxShadow(color: Color(0x0A20243F), blurRadius: 12, offset: Offset(0, 4))];
  static const List<BoxShadow> raised = [BoxShadow(color: Color(0x1420243F), blurRadius: 24, offset: Offset(0, 8))];
}
