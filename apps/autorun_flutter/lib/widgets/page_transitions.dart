import 'package:flutter/material.dart';
import '../theme/app_design_system.dart';

/// Custom page transition with smooth slide and fade animations
class SlideUpPageTransition<T> extends PageRouteBuilder<T> {
  SlideUpPageTransition({
    required this.child,
    this.duration = AppDurations.medium,
    this.curve = Curves.easeOutCubic,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final slideAnimation = Tween<Offset>(
              begin: const Offset(0, 0.1),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: curve,
            ));

            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ));

            return SlideTransition(
              position: slideAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
        );

  final Widget child;
  final Duration duration;
  final Curve curve;
}

/// Scale and fade page transition
class ScaleFadePageTransition<T> extends PageRouteBuilder<T> {
  ScaleFadePageTransition({
    required this.child,
    this.duration = AppDurations.normal,
    this.curve = Curves.easeOutBack,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final scaleAnimation = Tween<double>(
              begin: 0.9,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: curve,
            ));

            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
            ));

            return ScaleTransition(
              scale: scaleAnimation,
              child: FadeTransition(
                opacity: fadeAnimation,
                child: child,
              ),
            );
          },
        );

  final Widget child;
  final Duration duration;
  final Curve curve;
}

/// Custom page route builder for consistent transitions
class CustomPageRoute {
  static Route<T> slideUp<T>(Widget page) {
    return SlideUpPageTransition<T>(child: page);
  }

  static Route<T> scaleFade<T>(Widget page) {
    return ScaleFadePageTransition<T>(child: page);
  }
}