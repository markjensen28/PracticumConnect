import 'package:flutter/material.dart';

class AppTheme {
  // Shared workspace palette
  static const navy = Color(0xFF092B58);
  static const blue = Color(0xFF135FBC);
  static const deepBlue = Color(0xFF144D92);
  static const gold = Color(0xFFF8C649);
  static const sky = Color(0xFFE3EEFF);

  // Light surfaces
  static const background = Color(0xFFEDF3FC);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF4F7FD);
  static const surfaceBlue = Color(0xFFEAF2FF);
  static const border = Color(0xFFD6E2F2);
  static const borderStrong = Color(0xFFB5C8E1);

  // Text
  static const text = Color(0xFF142C49);
  static const muted = Color(0xFF4A5E79);
  static const subtle = Color(0xFF536880);

  // States
  static const success = Color(0xFF18734D);
  static const warning = Color(0xFF925D0B);
  static const danger = Color(0xFFB53F47);
  static const purple = Color(0xFF6950A1);

  static const double contentMaxWidth = 1600;
  static const double cardRadius = 14;
  static const double controlRadius = 9;

  static const double fontCaption = 13;
  static const double fontSmall = 14;
  static const double fontBody = 15;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: blue,
      brightness: Brightness.light,
      primary: blue,
      onPrimary: Colors.white,
      secondary: const Color(0xFF75A7E8),
      surface: surface,
      error: danger,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      scaffoldBackgroundColor: background,
      fontFamily: 'Segoe UI',
      visualDensity: VisualDensity.standard,
      dividerColor: border,
      splashColor: blue.withValues(alpha: .05),
      highlightColor: blue.withValues(alpha: .035),
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineLarge: const TextStyle(
          color: navy,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.65,
        ),
        headlineMedium: const TextStyle(
          color: navy,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.45,
        ),
        headlineSmall: const TextStyle(
          color: navy,
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.65,
        ),
        titleLarge: const TextStyle(
          color: text,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: const TextStyle(
          color: text,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: const TextStyle(
          color: text,
          fontSize: fontBody,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(color: text, fontSize: 16, height: 1.45),
        bodyMedium: const TextStyle(
          color: text,
          fontSize: fontBody,
          height: 1.5,
        ),
        bodySmall: const TextStyle(
          color: muted,
          fontSize: fontCaption,
          height: 1.35,
        ),
        labelLarge: const TextStyle(
          fontSize: fontSmall,
          fontWeight: FontWeight.w700,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: navy,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        hintStyle: const TextStyle(color: subtle, fontSize: fontSmall),
        labelStyle: const TextStyle(color: muted, fontSize: fontSmall),
        floatingLabelStyle: const TextStyle(
          color: deepBlue,
          fontSize: fontSmall,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: muted,
        suffixIconColor: muted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: blue, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(controlRadius),
          borderSide: const BorderSide(color: danger, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          foregroundColor: Colors.white,
          backgroundColor: blue,
          textStyle: const TextStyle(
            fontSize: fontSmall,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          foregroundColor: text,
          backgroundColor: surface,
          side: const BorderSide(color: borderStrong),
          textStyle: const TextStyle(
            fontSize: fontSmall,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(controlRadius),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: deepBlue,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          textStyle: const TextStyle(
            fontSize: fontSmall,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceSoft,
        selectedColor: surfaceBlue,
        side: const BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          color: text,
          fontSize: fontCaption,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      ),
      dataTableTheme: const DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(surfaceBlue),
        headingTextStyle: TextStyle(
          color: navy,
          fontSize: fontCaption,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: TextStyle(color: text, fontSize: fontSmall),
        dividerThickness: .7,
        horizontalMargin: 16,
        columnSpacing: 20,
        headingRowHeight: 48,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 88,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: blue,
        selectionColor: blue.withValues(alpha: .18),
        selectionHandleColor: blue,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: navy,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: fontSmall,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: blue,
        linearTrackColor: Color(0xFFEDF1F7),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: fontCaption),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(10),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? borderStrong
              : const Color(0xFFDDE3EC),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        selectedColor: deepBlue,
        selectedTileColor: surfaceBlue,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: borderStrong),
      ),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
