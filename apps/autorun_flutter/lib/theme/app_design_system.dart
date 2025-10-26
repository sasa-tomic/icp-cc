import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modern Design System for ICP Autorun App
/// 
/// This class provides a comprehensive design system with:
/// - Sophisticated color schemes with semantic meaning
/// - Modern typography scale
/// - Consistent spacing and sizing
/// - Beautiful gradients and shadows
/// - Animation constants
class AppDesignSystem {
  AppDesignSystem._();

  // ==================== COLORS ====================
  
  /// Primary brand colors - Modern purple gradient
  static const Color primaryLight = Color(0xFF6366F1);
  static const Color primaryDark = Color(0xFF4F46E5);
  static const Color primaryDarker = Color(0xFF4338CA);
  
  /// Secondary brand colors - Elegant violet
  static const Color secondaryLight = Color(0xFF8B5CF6);
  static const Color secondaryDark = Color(0xFF7C3AED);
  static const Color secondaryDarker = Color(0xFF6D28D9);
  
  /// Accent colors - Modern teal
  static const Color accentLight = Color(0xFF14B8A6);
  static const Color accentDark = Color(0xFF0D9488);
  
  /// Success colors - Modern green
  static const Color successLight = Color(0xFF10B981);
  static const Color successDark = Color(0xFF059669);
  
  /// Warning colors - Warm amber
  static const Color warningLight = Color(0xFFF59E0B);
  static const Color warningDark = Color(0xFFD97706);
  
  /// Error colors - Modern red
  static const Color errorLight = Color(0xFFEF4444);
  static const Color errorDark = Color(0xFFDC2626);
  
  /// Neutral colors - Sophisticated grays
  static const Color neutral50 = Color(0xFFFAFAFA);
  static const Color neutral100 = Color(0xFFF5F5F5);
  static const Color neutral200 = Color(0xFFE5E5E5);
  static const Color neutral300 = Color(0xFFD4D4D4);
  static const Color neutral400 = Color(0xFFA3A3A3);
  static const Color neutral500 = Color(0xFF737373);
  static const Color neutral600 = Color(0xFF525252);
  static const Color neutral700 = Color(0xFF404040);
  static const Color neutral800 = Color(0xFF262626);
  static const Color neutral900 = Color(0xFF171717);

  // ==================== GRADIENTS ====================
  
  /// Primary brand gradient
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryLight, secondaryLight],
  );
  
  /// Subtle background gradient
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [neutral50, neutral100],
  );
  
  /// Card gradient for depth
  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Colors.white, neutral50],
  );
  
  /// Success gradient
  static const LinearGradient successGradient = LinearGradient(
    colors: [successLight, successDark],
  );
  
  /// Error gradient
  static const LinearGradient errorGradient = LinearGradient(
    colors: [errorLight, errorDark],
  );

  // ==================== TYPOGRAPHY ====================
  
  /// Modern text styles
  static const TextStyle heading1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.0,
    height: 1.2,
  );
  
  static const TextStyle heading2 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.2,
  );
  
  static const TextStyle heading3 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.3,
  );
  
  static const TextStyle heading4 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.3,
  );
  
  static const TextStyle heading5 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.4,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  
  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );
  
  static const TextStyle caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0.2,
  );

  // ==================== SPACING ====================
  
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;
  static const double spacing80 = 80.0;
  static const double spacing96 = 96.0;

  // ==================== BORDER RADIUS ====================
  
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius16 = 16.0;
  static const double radius20 = 20.0;
  static const double radius24 = 24.0;
  static const double radius28 = 28.0;
  static const double radius32 = 32.0;
  static const double radius48 = 48.0;

  // ==================== SHADOWS ====================
  
  static List<BoxShadow> get shadowLight => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 10,
      offset: const Offset(0, 2),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];
  
  static List<BoxShadow> get shadowMedium => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.1),
      blurRadius: 15,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 30,
      offset: const Offset(0, 8),
    ),
  ];
  
  static List<BoxShadow> get shadowHeavy => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.15),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];
  
  static List<BoxShadow> get shadowColored => [
    BoxShadow(
      color: primaryLight.withValues(alpha: 0.2),
      blurRadius: 20,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: secondaryLight.withValues(alpha: 0.1),
      blurRadius: 40,
      offset: const Offset(0, 16),
    ),
  ];

  // ==================== ANIMATIONS ====================
  
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationNormal = Duration(milliseconds: 250);
  static const Duration durationSlow = Duration(milliseconds: 350);
  static const Duration durationSlower = Duration(milliseconds: 500);
  
  static const Curve curveEaseInOut = Curves.easeInOut;
  static const Curve curveEaseOut = Curves.easeOut;
  static const Curve curveEaseIn = Curves.easeIn;
  static const Curve curveBounce = Curves.elasticOut;

  // ==================== MATERIAL THEME DATA ====================
  
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primaryLight,
        secondary: secondaryLight,
        tertiary: accentLight,
        surface: neutral50,
        error: errorLight,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: neutral900,
        onError: Colors.white,
        surfaceContainerHighest: neutral100,
        surfaceContainerHigh: neutral200,
        surfaceContainerLow: neutral50,
        outline: neutral300,
        outlineVariant: neutral200,
      ),
      
      // Typography
      textTheme: const TextTheme(
        displayLarge: heading1,
        displayMedium: heading2,
        displaySmall: heading3,
        headlineLarge: heading4,
        headlineMedium: heading5,
        titleLarge: heading4,
        titleMedium: heading5,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelSmall: caption,
      ),
      
      // App bar theme
      appBarTheme: AppBarTheme(
        centerTitle: true,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: primaryLight,
        titleTextStyle: heading5.copyWith(color: neutral900),
        systemOverlayStyle: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
      ),
      
      // Navigation bar theme
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius16)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        shadowColor: Colors.black.withValues(alpha: 0.1),
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius20)),
        margin: const EdgeInsets.symmetric(horizontal: spacing4, vertical: spacing4),
        surfaceTintColor: Colors.transparent,
      ),
      
      // Elevated button theme
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
        ),
      ),
      
      // Filled button theme
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
        ),
      ),
      
      // Outlined button theme
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: primaryLight, width: 2),
        ),
      ),
      
      // Text button theme
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing8),
          minimumSize: const Size(0, 40),
        ),
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: neutral300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: neutral300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: errorLight, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: errorLight, width: 2),
        ),
        filled: true,
        fillColor: neutral50,
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
        hintStyle: bodyMedium.copyWith(color: neutral400),
      ),
      
      // Floating action button theme
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radius16))),
        sizeConstraints: BoxConstraints(minWidth: 56, minHeight: 56, maxWidth: 56, maxHeight: 56),
      ),
      
      // Dialog theme
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius24)),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),
      
      // Bottom sheet theme
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius24)),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
      ),
      
      // Snack bar theme
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
        backgroundColor: neutral900,
        contentTextStyle: bodyMedium.copyWith(color: Colors.white),
        actionTextColor: accentLight,
      ),
      
      // List tile theme
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: spacing20, vertical: spacing8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radius12))),
      ),
      
      // Divider theme
      dividerTheme: DividerThemeData(
        space: 1,
        color: neutral200,
        thickness: 1,
      ),
      
      // Chip theme
      chipTheme: ChipThemeData(
        backgroundColor: neutral100,
        selectedColor: primaryLight.withValues(alpha: 0.1),
        disabledColor: neutral200,
        labelStyle: bodySmall.copyWith(color: neutral700),
        secondaryLabelStyle: bodySmall.copyWith(color: primaryLight),
        padding: const EdgeInsets.symmetric(horizontal: spacing12, vertical: spacing4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius20)),
        side: BorderSide(color: neutral300, width: 1),
      ),
    );
  }
  
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF818CF8),
        secondary: Color(0xFFA78BFA),
        tertiary: Color(0xFF2DD4BF),
        surface: Color(0xFF111827),
        error: errorLight,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: neutral100,
        onError: Colors.white,
        surfaceContainerHighest: Color(0xFF374151),
        surfaceContainerHigh: Color(0xFF4B5563),
        surfaceContainerLow: Color(0xFF1F2937),
        outline: neutral600,
        outlineVariant: neutral500,
      ),
      
      // Typography (same as light theme)
      textTheme: const TextTheme(
        displayLarge: heading1,
        displayMedium: heading2,
        displaySmall: heading3,
        headlineLarge: heading4,
        headlineMedium: heading5,
        titleLarge: heading4,
        titleMedium: heading5,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelSmall: caption,
      ).apply(
        bodyColor: neutral100,
        displayColor: neutral100,
      ),
      
      // App bar theme
      appBarTheme: AppBarTheme(
        centerTitle: true,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: const Color(0xFF818CF8),
        titleTextStyle: heading5.copyWith(color: neutral100),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
      ),
      
      // Navigation bar theme
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: const Color(0xFF1F2937).withValues(alpha: 0.95),
        surfaceTintColor: Colors.transparent,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius16)),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 80,
        shadowColor: Colors.black.withValues(alpha: 0.3),
      ),
      
      // Card theme
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius20)),
        margin: const EdgeInsets.symmetric(horizontal: spacing4, vertical: spacing4),
        surfaceTintColor: Colors.transparent,
      ),
      
      // Input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: neutral600),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: neutral600),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: errorLight, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius12),
          borderSide: const BorderSide(color: errorLight, width: 2),
        ),
        filled: true,
        fillColor: neutral800,
        contentPadding: const EdgeInsets.symmetric(horizontal: spacing16, vertical: spacing12),
        hintStyle: bodyMedium.copyWith(color: neutral500),
      ),
      
      // Other themes inherit from light theme with dark color adjustments
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
        ),
      ),
      
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius12)),
          padding: const EdgeInsets.symmetric(horizontal: spacing24, vertical: spacing12),
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: Color(0xFF818CF8), width: 2),
        ),
      ),
      
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius24)),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: const Color(0xFF1F2937),
      ),
      
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radius24)),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        backgroundColor: Color(0xFF1F2937),
      ),
    );
  }
}

/// Extension methods for easy access to design system values
extension DesignSystemExtensions on BuildContext {
  /// Get the design system colors
  AppDesignSystemColors get colors => AppDesignSystemColors.of(this);
  
  /// Get the design system text styles
  AppDesignSystemTextStyles get textStyles => AppDesignSystemTextStyles.of(this);
  
  /// Get the design system spacing
  AppDesignSystemSpacing get spacing => const AppDesignSystemSpacing();
  
  /// Get the design system shadows
  AppDesignSystemShadows get shadows => const AppDesignSystemShadows();
}

/// Color utilities
class AppDesignSystemColors {
  AppDesignSystemColors.of(BuildContext context)
      : _colorScheme = Theme.of(context).colorScheme;
  
  final ColorScheme _colorScheme;
  
  Color get primary => _colorScheme.primary;
  Color get secondary => _colorScheme.secondary;
  Color get tertiary => _colorScheme.tertiary;
  Color get surface => _colorScheme.surface;
  Color get background => _colorScheme.surface;
  Color get error => _colorScheme.error;
  Color get success => AppDesignSystem.successLight;
  Color get warning => AppDesignSystem.warningLight;
  Color get onPrimary => _colorScheme.onPrimary;
  Color get onSecondary => _colorScheme.onSecondary;
  Color get onTertiary => _colorScheme.onTertiary;
  Color get onSurface => _colorScheme.onSurface;
  Color get onBackground => _colorScheme.onSurface;
  Color get onError => _colorScheme.onError;
  Color get outline => _colorScheme.outline;
  Color get outlineVariant => _colorScheme.outlineVariant;
  Color get onSurfaceVariant => _colorScheme.onSurfaceVariant;
  Color get primaryContainer => _colorScheme.primaryContainer;
  Color get onPrimaryContainer => _colorScheme.onPrimaryContainer;
  Color get surfaceContainerHighest => _colorScheme.surfaceContainerHighest;
  Color get surfaceContainerHigh => _colorScheme.surfaceContainerHigh;
  Color get surfaceContainer => _colorScheme.surfaceContainer;
}

/// Text style utilities
class AppDesignSystemTextStyles {
  AppDesignSystemTextStyles.of(BuildContext context)
      : _textTheme = Theme.of(context).textTheme;
  
  final TextTheme _textTheme;
  
  TextStyle get heading1 => _textTheme.displayLarge ?? AppDesignSystem.heading1;
  TextStyle get heading2 => _textTheme.displayMedium ?? AppDesignSystem.heading2;
  TextStyle get heading3 => _textTheme.displaySmall ?? AppDesignSystem.heading3;
  TextStyle get heading4 => _textTheme.headlineLarge ?? AppDesignSystem.heading4;
  TextStyle get heading5 => _textTheme.headlineMedium ?? AppDesignSystem.heading5;
  TextStyle get bodyLarge => _textTheme.bodyLarge ?? AppDesignSystem.bodyLarge;
  TextStyle get bodyMedium => _textTheme.bodyMedium ?? AppDesignSystem.bodyMedium;
  TextStyle get bodySmall => _textTheme.bodySmall ?? AppDesignSystem.bodySmall;
  TextStyle get caption => _textTheme.labelSmall ?? AppDesignSystem.caption;
}

/// Spacing utilities
class AppDesignSystemSpacing {
  const AppDesignSystemSpacing();
  
  double get xs => AppDesignSystem.spacing4;
  double get sm => AppDesignSystem.spacing8;
  double get md => AppDesignSystem.spacing16;
  double get lg => AppDesignSystem.spacing24;
  double get xl => AppDesignSystem.spacing32;
  double get xxl => AppDesignSystem.spacing48;
}

/// Shadow utilities
class AppDesignSystemShadows {
  const AppDesignSystemShadows();
  
  List<BoxShadow> get light => AppDesignSystem.shadowLight;
  List<BoxShadow> get medium => AppDesignSystem.shadowMedium;
  List<BoxShadow> get heavy => AppDesignSystem.shadowHeavy;
  List<BoxShadow> get colored => AppDesignSystem.shadowColored;
}