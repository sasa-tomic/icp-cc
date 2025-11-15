class ResponsiveGridConfig {
  final int crossAxisCount;
  final double childAspectRatio;

  const ResponsiveGridConfig._({
    required this.crossAxisCount,
    required this.childAspectRatio,
  });

  factory ResponsiveGridConfig.forWidth(double width) {
    final double resolvedWidth = width.isFinite ? width : 1600;

    if (resolvedWidth >= 1400) {
      return const ResponsiveGridConfig._(
        crossAxisCount: 3,
        childAspectRatio: 1.75,
      );
    }

    if (resolvedWidth >= 800) {
      return const ResponsiveGridConfig._(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
      );
    }

    return const ResponsiveGridConfig._(
      crossAxisCount: 1,
      childAspectRatio: 1.35,
    );
  }
}
