import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// SatSH design tokens — "motion designer clean": deep ink background,
/// soft glassy cards, violet→cyan accent gradient.
class C {
  /// Flipped by the theme setting; the whole app rebuilds afterwards.
  static bool light = false;
  static Color get bg => light ? const Color(0xFFF5F6FA) : const Color(0xFF0C0D12);
  static Color get surface => light ? const Color(0xFFFFFFFF) : const Color(0xFF15171F);
  static Color get surface2 => light ? const Color(0xFFECEEF4) : const Color(0xFF1D2029);
  static Color get stroke => light ? const Color(0x14000000) : const Color(0x14FFFFFF);
  static Color get text => light ? const Color(0xFF14151C) : const Color(0xFFEDEEF3);
  static Color get muted => light ? const Color(0xFF6B7083) : const Color(0xFF8A8FA3);
  static const termBg = Color(0xFF0C0D12);
  static const violet = Color(0xFF7C5CFF);
  static const cyan = Color(0xFF22D3EE);
  static const pink = Color(0xFFFF5C9A);
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFFF5D5D);

  static const accent = LinearGradient(
    colors: [violet, cyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Per-host card gradients.
  static const hostGradients = <List<Color>>[
    [Color(0xFF7C5CFF), Color(0xFF22D3EE)],
    [Color(0xFFFF5C9A), Color(0xFFFFA25C)],
    [Color(0xFF34D399), Color(0xFF22D3EE)],
    [Color(0xFFFBBF24), Color(0xFFFF5C9A)],
    [Color(0xFF6366F1), Color(0xFFEC4899)],
    [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  ];

  static LinearGradient hostGradient(int i) => LinearGradient(
        colors: hostGradients[i % hostGradients.length],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

const uiFont = 'SpaceGrotesk';
const monoFont = 'JetBrainsMono';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: C.light ? Brightness.light : Brightness.dark,
    fontFamily: uiFont,
    scaffoldBackgroundColor: C.bg,
    colorScheme: (C.light ? ColorScheme.light : ColorScheme.dark)(
      primary: C.violet,
      secondary: C.cyan,
      surface: C.surface,
      error: C.red,
      onSurface: C.text,
    ),
  );
  return base.copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontFamily: uiFont, fontSize: 20, fontWeight: FontWeight.w700, color: C.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      hintStyle: TextStyle(color: C.muted),
      labelStyle: TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: C.violet, width: 1.4)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(fontFamily: uiFont, color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : C.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? C.violet : C.surface2),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerColor: C.stroke,
    dividerTheme: DividerThemeData(color: C.stroke, thickness: 1, space: 20),
  );
}

const termTheme = TerminalTheme(
  cursor: Color(0xFF22D3EE),
  selection: Color(0x557C5CFF),
  foreground: Color(0xFFE6E8EF),
  background: C.termBg,
  black: Color(0xFF1D2029),
  red: Color(0xFFFF5D5D),
  green: Color(0xFF34D399),
  yellow: Color(0xFFFBBF24),
  blue: Color(0xFF7C9CFF),
  magenta: Color(0xFFB98CFF),
  cyan: Color(0xFF22D3EE),
  white: Color(0xFFD5D7E0),
  brightBlack: Color(0xFF5C6070),
  brightRed: Color(0xFFFF8080),
  brightGreen: Color(0xFF6EE7B7),
  brightYellow: Color(0xFFFDE68A),
  brightBlue: Color(0xFFA5B8FF),
  brightMagenta: Color(0xFFD4B5FF),
  brightCyan: Color(0xFF67E8F9),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFBBF24),
  searchHitBackgroundCurrent: Color(0xFFFF5C9A),
  searchHitForeground: Color(0xFF0C0D12),
);
