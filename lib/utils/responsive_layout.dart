import 'package:flutter/material.dart';

/// A utility class for responsive design breakpoints and helpers.
class Responsive {
  /// Width threshold for tablets (e.g., iPads).
  static const double tabletBreakpoint = 600;

  /// Width threshold for desktop/web.
  static const double desktopBreakpoint = 1024;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < tabletBreakpoint;

  static bool isTablet(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint &&
      MediaQuery.of(context).size.width < desktopBreakpoint;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= tabletBreakpoint;

  /// Calculate a responsive cross axis count for grid layouts.
  static int getGridCrossAxisCount(BuildContext context, {int mobile = 1, int tablet = 2, int desktop = 3}) {
    final width = MediaQuery.of(context).size.width;
    if (width >= desktopBreakpoint) return desktop;
    if (width >= tabletBreakpoint) return tablet;
    return mobile;
  }
}

/// A widget that builds different UI depending on the screen size.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context)? mobileBuilder;
  final Widget Function(BuildContext context)? tabletBuilder;
  final Widget Function(BuildContext context)? desktopBuilder;

  /// The default builder if a specific breakpoint builder is missing.
  final Widget Function(BuildContext context) builder;

  const ResponsiveBuilder({
    super.key,
    required this.builder,
    this.mobileBuilder,
    this.tabletBuilder,
    this.desktopBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (Responsive.isDesktop(context)) {
      return desktopBuilder?.call(context) ?? tabletBuilder?.call(context) ?? builder(context);
    }
    if (Responsive.isTablet(context)) {
      return tabletBuilder?.call(context) ?? builder(context);
    }
    return mobileBuilder?.call(context) ?? builder(context);
  }
}

/// A wrapper widget that constrains its child to a maximum width.
/// Useful for single-column layouts (settings, auth) on tablets.
class MaxWidthContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;

  const MaxWidthContainer({
    super.key,
    required this.child,
    this.maxWidth = 800,
    this.alignment = Alignment.topCenter,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      heightFactor: 1.0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
