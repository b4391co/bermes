import 'package:flutter/material.dart';
import 'tokens.dart';

/// Tema claro de Hermes Pocket.
///
/// Fondo claro predominante, texto oscuro, burbujas de usuario oscuras,
/// respuestas sobre superficie suave. Sombra contenida, densidad buena.
ThemeData buildLightTheme() {
  const bg = Color(0xFFF7F7F8); // casi blanco, neutro cálido
  const surface = Color(0xFFFFFFFF);
  const surfaceSoft = Color(0xFFF0F0F3); // burbujas del bot
  const ink = Color(0xFF16181D); // texto principal
  const inkSoft = Color(0xFF5A6072); // secundario
  const accent = Color(0xFF16181D); // acción primaria = tinta (estilo Grok)
  // Burbuja del usuario (oscura): la consume features/chat vía Hp tokens.

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: ink,
          brightness: Brightness.light,
        ).copyWith(
          surface: bg,
          surfaceContainerLowest: surface,
          surfaceContainerLow: surfaceSoft,
          primary: ink,
          onPrimary: Colors.white,
          secondary: const Color(0xFF5B6CFF),
          error: Hp.error,
        ),
    scaffoldBackgroundColor: bg,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: ink),
    ),
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          titleLarge: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          bodyLarge: const TextStyle(
            fontSize: 15.5,
            height: 1.45,
            letterSpacing: -0.1,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14.5,
            height: 1.42,
            letterSpacing: -0.1,
          ),
          bodySmall: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: inkSoft,
          ),
          labelSmall: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: inkSoft,
          ),
        ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE8E8EC),
      thickness: 0.7,
      space: 0.7,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: Color(0xFF9AA0AE)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Hp.s4,
        vertical: Hp.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: const BorderSide(color: Color(0xFFE4E4EA)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: const BorderSide(color: Color(0xFFE4E4EA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: const BorderSide(color: Color(0xFFB9BECE)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Hp.rMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Hp.s5, vertical: Hp.s3),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Hp.s4),
      dense: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : const Color(0xFFF4F4F6),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? accent : const Color(0xFFD6D8E0),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Hp.rSm),
      ),
      backgroundColor: const Color(0xFF23252B),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}

/// Tema oscuro diseñado de verdad: no una inversión.
/// Fondo carbón neutro, sin negros puros, acentos ligeramente elevados.
ThemeData buildDarkTheme() {
  const bg = Color(0xFF101114); // carbón, no negro
  const surface = Color(0xFF17181C);
  const surfaceSoft = Color(0xFF1D1F24); // burbujas del bot
  const ink = Color(0xFFEDEEF2);
  const inkSoft = Color(0xFF9BA1AF);
  // Burbuja del usuario (elevada en oscuro): la consume features/chat.

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: ink,
          brightness: Brightness.dark,
        ).copyWith(
          surface: bg,
          surfaceContainerLowest: surface,
          surfaceContainerLow: surfaceSoft,
          primary: ink,
          onPrimary: const Color(0xFF101114),
          secondary: const Color(0xFF7C89FF),
          error: const Color(0xFFF87171),
        ),
    scaffoldBackgroundColor: bg,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      iconTheme: IconThemeData(color: ink),
    ),
    textTheme: base.textTheme
        .apply(bodyColor: ink, displayColor: ink)
        .copyWith(
          titleLarge: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleMedium: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          bodyLarge: const TextStyle(
            fontSize: 15.5,
            height: 1.45,
            letterSpacing: -0.1,
          ),
          bodyMedium: const TextStyle(
            fontSize: 14.5,
            height: 1.42,
            letterSpacing: -0.1,
          ),
          bodySmall: const TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: inkSoft,
          ),
          labelSmall: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: inkSoft,
          ),
        ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF26282E),
      thickness: 0.7,
      space: 0.7,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: Color(0xFF6B7180)),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Hp.s4,
        vertical: Hp.s3,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Hp.rLg),
        borderSide: const BorderSide(color: Color(0xFF3A3E48)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: ink,
        foregroundColor: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Hp.rMd),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Hp.s5, vertical: Hp.s3),
        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: ink,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Hp.s4),
      dense: false,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? const Color(0xFF101114)
            : const Color(0xFF3A3D46),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? ink : const Color(0xFF33363F),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Hp.rSm),
      ),
      backgroundColor: const Color(0xFF2A2D36),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13.5),
    ),
    splashFactory: InkSparkle.splashFactory,
  );
}
