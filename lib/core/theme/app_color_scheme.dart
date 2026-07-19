import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Softens the *neutral* tones of a shadcn preset while keeping its
/// accent colors (primary, destructive, ring, ...) untouched.
///
/// The stock presets pair near-black backgrounds with near-white text -
/// too harsh for an app that's mostly text. These overrides move the
/// neutrals to warm grays (dark: dark-gray background with off-white
/// text, light: off-white background with dark-gray text) so the accent
/// color from the user's chosen preset stays the only saturated thing
/// on screen.
ShadColorScheme softenedLightScheme(ShadColorScheme preset) {
  const foreground = Color(0xFF1F1E1D);
  return preset.copyWith(
    background: const Color(0xFFFAF9F7),
    foreground: foreground,
    card: const Color(0xFFFFFFFF),
    cardForeground: foreground,
    popover: const Color(0xFFFFFFFF),
    popoverForeground: foreground,
    secondary: const Color(0xFFF0EEE9),
    secondaryForeground: foreground,
    muted: const Color(0xFFF0EEE9),
    mutedForeground: const Color(0xFF6E6B64),
    accent: const Color(0xFFEFEDE8),
    accentForeground: foreground,
    border: const Color(0xFFE5E3DD),
    input: const Color(0xFFE5E3DD),
  );
}

ShadColorScheme softenedDarkScheme(ShadColorScheme preset) {
  const foreground = Color(0xFFE8E6E3);
  return preset.copyWith(
    background: const Color(0xFF262624),
    foreground: foreground,
    card: const Color(0xFF2B2B29),
    cardForeground: foreground,
    popover: const Color(0xFF30302E),
    popoverForeground: foreground,
    secondary: const Color(0xFF3A3A37),
    secondaryForeground: foreground,
    muted: const Color(0xFF32322F),
    mutedForeground: const Color(0xFFA6A39E),
    accent: const Color(0xFF343432),
    accentForeground: foreground,
    border: const Color(0xFF3A3A37),
    input: const Color(0xFF3A3A37),
  );
}

/// Extends the Material theme that ShadApp derives from the shadcn one
/// (see ShadAppState.materialTheme) with the component themes it leaves
/// at Material defaults. Without this, still-Material surfaces (AppBar,
/// Card, Drawer, dialogs, bottom sheets) pick M3's tinted container
/// colors, which don't match the shadcn palette - e.g. the gray AppBar
/// in dark mode.
ThemeData materialThemeFrom(ThemeData base, ShadThemeData shadTheme) {
  final colors = shadTheme.colorScheme;
  return base.copyWith(
    canvasColor: colors.background,
    cardColor: colors.card,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: colors.background,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.popover,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.popover,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.mutedForeground,
    ),
  );
}
