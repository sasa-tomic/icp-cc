import 'script_record.dart';
import 'marketplace_script.dart';

enum ScriptSource { local, marketplace }

enum ScriptSortOption {
  lastRun('Last Run'),
  name('Name'),
  runCount('Run Count'),
  updatedAt('Last Updated'),
  source('Source');

  final String label;
  const ScriptSortOption(this.label);
}

class ScriptListItem {
  final ScriptRecord? localScript;
  final MarketplaceScript? marketplaceScript;
  final ScriptSource source;
  final bool isInstalled;
  final int runCount;
  final DateTime? lastRunAt;

  ScriptListItem._({
    this.localScript,
    this.marketplaceScript,
    required this.source,
    this.isInstalled = false,
    this.runCount = 0,
    this.lastRunAt,
  });

  factory ScriptListItem.fromLocal(
    ScriptRecord script, {
    int runCount = 0,
    DateTime? lastRunAt,
  }) {
    return ScriptListItem._(
      localScript: script,
      source: ScriptSource.local,
      isInstalled: true,
      runCount: runCount,
      lastRunAt: lastRunAt,
    );
  }

  factory ScriptListItem.fromMarketplace(
    MarketplaceScript script, {
    bool isInstalled = false,
  }) {
    return ScriptListItem._(
      marketplaceScript: script,
      source: ScriptSource.marketplace,
      isInstalled: isInstalled,
      runCount: script.downloads,
      lastRunAt: null,
    );
  }

  String get id {
    switch (source) {
      case ScriptSource.local:
        return localScript!.id;
      case ScriptSource.marketplace:
        return marketplaceScript!.id;
    }
  }

  String get title {
    switch (source) {
      case ScriptSource.local:
        return localScript!.title;
      case ScriptSource.marketplace:
        return marketplaceScript!.title;
    }
  }

  String? get emoji {
    switch (source) {
      case ScriptSource.local:
        return localScript!.emoji;
      case ScriptSource.marketplace:
        return null;
    }
  }

  String? get iconUrl {
    switch (source) {
      case ScriptSource.local:
        return localScript!.imageUrl;
      case ScriptSource.marketplace:
        return marketplaceScript!.iconUrl;
    }
  }

  String? get description {
    switch (source) {
      case ScriptSource.local:
        return null;
      case ScriptSource.marketplace:
        return marketplaceScript!.description;
    }
  }

  String? get author {
    switch (source) {
      case ScriptSource.local:
        return localScript!.marketplaceAuthor;
      case ScriptSource.marketplace:
        return marketplaceScript!.authorName;
    }
  }

  String? get version {
    switch (source) {
      case ScriptSource.local:
        return localScript!.marketplaceVersion;
      case ScriptSource.marketplace:
        return marketplaceScript!.version;
    }
  }

  DateTime get updatedAt {
    switch (source) {
      case ScriptSource.local:
        return localScript!.updatedAt;
      case ScriptSource.marketplace:
        return marketplaceScript!.updatedAt;
    }
  }

  DateTime get createdAt {
    switch (source) {
      case ScriptSource.local:
        return localScript!.createdAt;
      case ScriptSource.marketplace:
        return marketplaceScript!.createdAt;
    }
  }

  bool get isFromMarketplace =>
      source == ScriptSource.marketplace ||
      (source == ScriptSource.local && localScript!.isFromMarketplace);

  double get rating {
    switch (source) {
      case ScriptSource.local:
        return 0.0;
      case ScriptSource.marketplace:
        return marketplaceScript!.rating;
    }
  }

  int get downloads {
    switch (source) {
      case ScriptSource.local:
        return 0;
      case ScriptSource.marketplace:
        return marketplaceScript!.downloads;
    }
  }

  static List<ScriptListItem> sortItems(
    List<ScriptListItem> items,
    ScriptSortOption sortOption, {
    bool ascending = false,
  }) {
    final sorted = List<ScriptListItem>.from(items);

    switch (sortOption) {
      case ScriptSortOption.lastRun:
        sorted.sort((a, b) {
          final aTime = a.lastRunAt ?? a.updatedAt;
          final bTime = b.lastRunAt ?? b.updatedAt;
          return ascending ? aTime.compareTo(bTime) : bTime.compareTo(aTime);
        });
        break;
      case ScriptSortOption.name:
        sorted.sort((a, b) {
          final result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          return ascending ? result : -result;
        });
        break;
      case ScriptSortOption.runCount:
        sorted.sort((a, b) {
          final result = a.runCount.compareTo(b.runCount);
          return ascending ? result : -result;
        });
        break;
      case ScriptSortOption.updatedAt:
        sorted.sort((a, b) {
          final result = a.updatedAt.compareTo(b.updatedAt);
          return ascending ? result : -result;
        });
        break;
      case ScriptSortOption.source:
        sorted.sort((a, b) {
          final aPriority = a.isInstalled ? 0 : 1;
          final bPriority = b.isInstalled ? 0 : 1;
          if (aPriority != bPriority) {
            return ascending ? bPriority - aPriority : aPriority - bPriority;
          }
          return ascending
              ? a.updatedAt.compareTo(b.updatedAt)
              : b.updatedAt.compareTo(a.updatedAt);
        });
        break;
    }

    return sorted;
  }

  static List<ScriptListItem> createHybridList({
    required List<ScriptRecord> localScripts,
    required List<MarketplaceScript> marketplaceScripts,
    required Set<String> installedMarketplaceIds,
    Map<String, int>? runCounts,
    Map<String, DateTime>? lastRunAt,
  }) {
    final items = <ScriptListItem>[];
    final addedMarketplaceIds = <String>{};

    for (final script in localScripts) {
      items.add(ScriptListItem.fromLocal(
        script,
        runCount: runCounts?[script.id] ?? 0,
        lastRunAt: lastRunAt?[script.id],
      ));
      if (script.marketplaceId != null) {
        addedMarketplaceIds.add(script.marketplaceId!);
      }
    }

    for (final script in marketplaceScripts) {
      if (!addedMarketplaceIds.contains(script.id)) {
        items.add(ScriptListItem.fromMarketplace(
          script,
          isInstalled: installedMarketplaceIds.contains(script.id),
        ));
      }
    }

    return items;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScriptListItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          source == other.source;

  @override
  int get hashCode => Object.hash(id, source);

  @override
  String toString() =>
      'ScriptListItem{id: $id, title: $title, source: $source}';
}
