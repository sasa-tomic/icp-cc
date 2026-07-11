import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../controllers/script_controller.dart';
import '../controllers/account_controller.dart';
import '../models/account.dart';
import '../models/profile.dart';
import '../models/profile_keypair.dart';
import '../models/script_record.dart';
import '../models/marketplace_script.dart';
import '../models/script_list_item.dart';
import '../services/script_repository.dart';
import '../services/script_runner.dart';
import '../services/marketplace_open_api_service.dart';
import '../services/download_history_service.dart';
import '../services/download_signature_service.dart';
import '../services/favorites_service.dart';
import '../services/icpay_service.dart';
import '../services/script_integrity_service.dart';
import '../services/search_history_service.dart';
import '../services/onboarding_progress_service.dart';
import '../services/secure_storage_readiness.dart';
import '../services/service_locator.dart';
import '../theme/app_design_system.dart';

import '../rust/native_bridge.dart';
import '../widgets/connectivity_scope.dart';
import '../widgets/keyboard_shortcuts.dart';
import '../widgets/offline_banner.dart';
import '../widgets/script_app_host.dart';
import '../widgets/quick_upload_dialog.dart';
import '../widgets/script_details_dialog.dart';
import '../widgets/profile_scope.dart';
import '../widgets/animated_fab.dart';
import '../widgets/page_transitions.dart';
import '../widgets/script_execution_bottom_sheet.dart';
import '../widgets/script_row_menus.dart';
import '../widgets/scripts_empty_state.dart';
import '../widgets/scripts_list_item_tile.dart';
import '../widgets/scripts_search_bar.dart';
import 'script_creation_screen.dart';
import 'download_history_screen.dart';
import 'account_registration_wizard.dart';
import 'account_registration_prompt_dialog.dart';
import 'script_editor_dialog.dart';
import 'script_filter_sheet.dart';
import 'unified_setup_wizard.dart';

class ScriptsScreen extends StatefulWidget {
  const ScriptsScreen({
    super.key,
    this.marketplaceService,
    this.controller,
  });

  final MarketplaceOpenApi? marketplaceService;
  final ScriptController? controller;

  @override
  State<ScriptsScreen> createState() => ScriptsScreenState();
}

class ScriptsScreenState extends State<ScriptsScreen>
    with WidgetsBindingObserver {
  late final ScriptController _controller;
  final RustScriptBridge _bridge = RustScriptBridge(const RustBridgeLoader());

  ScriptAppRuntime _runtimeFor(ScriptRecord r) => ScriptAppRuntime(_bridge);

  late final MarketplaceOpenApi _marketplaceService =
      widget.marketplaceService ?? MarketplaceOpenApiService();

  /// Typed view of [_marketplaceService] as the concrete service. The paid
  /// download + buy flows (and entitlement queries with account_id) need
  /// methods that live on [MarketplaceOpenApiService] (not the minimal browse
  /// interface). Production always registers the concrete service; browse-only
  /// test fakes that inject a different [MarketplaceOpenApi] never invoke
  /// these flows, so the cast is safe.
  MarketplaceOpenApiService get _api =>
      _marketplaceService as MarketplaceOpenApiService;
  final DownloadHistoryService _downloadHistoryService =
      DownloadHistoryService();
  final SearchHistoryService _searchHistoryService = SearchHistoryService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<MarketplaceScript> _marketplaceScripts = [];
  List<String> _categories = [];
  final Set<String> _downloadingScriptIds = <String>{};
  final Map<String, double> _downloadProgress = <String, double>{};
  Set<String> _downloadedScriptIds = {};
  // `_isMarketplaceLoading=true` shows the initial spinner; `_marketplaceLoadInitiated`
  // lets the first fetch run (the re-entrancy guard only blocks later concurrent calls).
  bool _isMarketplaceLoading = true;
  bool _marketplaceLoadInitiated = false;
  bool _isLoadingMore = false;
  bool _isSearching = false;
  int _offset = 0;
  bool _hasMore = true;

  /// Non-null when the last marketplace browse load FAILED. Drives the inline
  /// "Couldn't load the marketplace — Retry" panel in place of the misleading
  /// "Your library is empty" state (UXR-5 / AUD-1). Cleared at the start of
  /// every (re)load and never set on load-more failures (the list stays as-is).
  _MarketplaceLoadError? _marketplaceLoadError;

  String _selectedCategory = 'All';
  final String _sortBy = 'createdAt';
  final String _sortOrder = 'desc';
  String _searchQuery = '';
  List<ScriptRecord> _filteredLocalScripts = [];
  ScriptSortOption _allScriptsSortOption = ScriptSortOption.lastRun;
  bool _allScriptsSortAscending = false;
  bool _showDownloadedOnly = false;
  bool _showFavoritesOnly = false;
  Set<String> _favoriteScriptIds = {};
  final FavoritesService _favoritesService = FavoritesService();
  List<String> _recentSearches = [];
  bool _showRecentSearches = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = (widget.controller ?? ScriptController(ScriptRepository.instance))
      ..addListener(_onChanged);
    _controller.ensureLoaded();
    _initializeMarketplace();
    _loadCategories();
    _loadDownloadedScripts();
    _initializeMarketplaceData();
    _loadRecentSearches();
    _loadFavorites();
    _searchFocusNode.addListener(_onSearchFocusChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  /// App-resume detection for return-from-ICPay-checkout. When the user taps
  /// Buy we open the hosted checkout in the external browser; on resume we
  /// refetch the scripts the user is mid-purchase on so a completed payment
  /// (recorded by the ICPay webhook) flips `purchased` to true and the UI
  /// swaps the Buy CTA for Download.
  ///
  /// Why [WidgetsBindingObserver] and not `app_links`: `app_links` is for
  /// INBOUND deep links (custom URL scheme), and ICPay's hosted checkout does
  /// not redirect back into the app via a deep link — the user simply
  /// returns to the app after paying in the browser. `didChangeAppLifecycleState`
  /// is the single, platform-agnostic signal for "user came back to the app".
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_pendingPurchaseAccountIds.isEmpty) return;
    _refetchPendingPurchases();
  }

  /// Script IDs the user has opened ICPay checkout for, mapped to the backend
  /// account id that initiated the purchase. Drained as each refetch confirms
  /// the purchase. Storing the account id at Buy-tap time avoids re-resolving
  /// it (a backend round-trip) on every app resume.
  final Map<String, String> _pendingPurchaseAccountIds = <String, String>{};

  Future<void> _refetchPendingPurchases() async {
    if (_pendingPurchaseAccountIds.isEmpty) return;
    final entries = _pendingPurchaseAccountIds.entries.toList();
    for (final entry in entries) {
      final scriptId = entry.key;
      final accountId = entry.value;
      try {
        final updated =
            await _api.getScriptDetails(scriptId, accountId: accountId);
        if (!mounted) return;
        if (updated.purchased == true) {
          _pendingPurchaseAccountIds.remove(scriptId);
          setState(() {
            _marketplaceScripts = _marketplaceScripts
                .map((s) => s.id == scriptId ? updated : s)
                .toList();
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              AppDesignSystem.successSnackBar(
                'Payment confirmed — "${updated.title}" is ready to download!',
              ),
            );
          }
        }
      } catch (e) {
        // Network/backend hiccup — leave the entry pending so the next resume
        // retries. Do NOT spam the user on every failed refetch.
        debugPrint('Refetch pending purchase $scriptId failed: $e');
      }
    }
  }

  /// Resolves the backend [Account] for the active profile via
  /// [AccountController] (cached, falls back to a backend fetch). Returns null
  /// if the user has no profile / unregistered profile.
  ///
  /// Buy + paid-download both need the backend Account.id (for entitlement
  /// queries) and the active keypair (for signing) — this returns both so the
  /// two flows share one resolution path.
  Future<_ActiveAccount?> _resolveActiveAccount() async {
    final profileController = ProfileScope.of(context, listen: false);
    final profile = profileController.activeProfile;
    if (profile == null) return null;
    final keypair = profile.primaryKeypair;
    if (profile.username == null) {
      return _ActiveAccount(profile: profile, keypair: keypair, account: null);
    }
    final accountController =
        AccountController(profileController: profileController);
    try {
      final account = await accountController.getAccountForProfile(profile);
      return _ActiveAccount(
          profile: profile, keypair: keypair, account: account);
    } finally {
      accountController.dispose();
    }
  }

  Future<void> _loadFavorites() async {
    final favorites = await _favoritesService.getAllFavorites();
    if (mounted) {
      setState(() {
        _favoriteScriptIds = favorites;
      });
    }
    // Listen for future changes
    _favoritesService.favoritesStream.listen((favorites) {
      if (mounted) {
        setState(() {
          _favoriteScriptIds = favorites;
        });
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    final searches = await _searchHistoryService.getRecentSearches();
    if (mounted) {
      setState(() {
        _recentSearches = searches;
      });
    }
  }

  void _onSearchFocusChanged() {
    if (_searchFocusNode.hasFocus && _recentSearches.isNotEmpty) {
      setState(() {
        _showRecentSearches = true;
      });
    } else {
      setState(() {
        _showRecentSearches = false;
      });
    }
  }

  void _selectRecentSearch(String query) {
    _searchController.text = query;
    _searchQuery = query;
    _showRecentSearches = false;
    _searchFocusNode.unfocus();
    _addSearchToHistory(query);
    _loadMarketplaceScripts();
  }

  Future<void> _addSearchToHistory(String query) async {
    if (query.trim().isNotEmpty) {
      await _searchHistoryService.addSearchQuery(query);
      await _loadRecentSearches();
    }
  }

  Future<void> _clearSearchHistory() async {
    await _searchHistoryService.clearHistory();
    await _loadRecentSearches();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar('Search history cleared'),
      );
    }
  }

  Future<void> _initializeMarketplaceData() async {
    await _loadSavedCategory();
    await _loadMarketplaceScripts();
  }

  void _onChanged() {
    if (!mounted) return;
    // Update filtered local scripts when controller's scripts change
    _updateFilteredLocalScripts();
    setState(() {});
  }

  void _updateFilteredLocalScripts() {
    final allScripts = _controller.scripts;
    if (_searchQuery.isEmpty) {
      _filteredLocalScripts = allScripts;
    } else {
      final queryLower = _searchQuery.toLowerCase();
      _filteredLocalScripts = allScripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(queryLower);
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(queryLower) ?? false;
        return titleMatch || authorMatch;
      }).toList();
    }
  }

  void createNewScript() {
    _showCreateSheet();
  }

  void focusSearch() {
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  Future<void> refreshContent() async {
    await _controller.refresh();
    await _refreshMarketplaceScripts();
  }

  Future<void> _initializeMarketplace() async {
    // No initialization needed for open API service
  }

  Future<void> _loadMarketplaceScripts({bool isLoadMore = false}) async {
    if (isLoadMore && (_isLoadingMore || !_hasMore)) return;
    if (!isLoadMore && _marketplaceLoadInitiated && _isMarketplaceLoading) return;

    setState(() {
      if (isLoadMore) {
        _isLoadingMore = true;
      } else {
        _marketplaceLoadInitiated = true;
        _isMarketplaceLoading = true;
        _offset = 0;
        _marketplaceScripts.clear();
        // Reset the error state for this attempt; it's re-set in the catch on
        // failure. Cleared here (not on success) so a single source drives it.
        _marketplaceLoadError = null;
      }
    });

    try {
      final result = await _marketplaceService.searchScripts(
        query: _searchQuery.isEmpty ? null : _searchQuery,
        category: _selectedCategory == 'All' ? null : _selectedCategory,
        sortBy: _sortBy,
        sortOrder: _sortOrder,
        limit: MarketplaceOpenApiService.defaultSearchLimit,
        offset: _offset,
      );

      setState(() {
        if (isLoadMore) {
          _marketplaceScripts.addAll(result.scripts);
        } else {
          _marketplaceScripts = result.scripts;
        }
        _hasMore = result.hasMore;
        _offset += result.scripts.length;
      });
    } catch (e) {
      // LOUD failure: log the full cause for debugging, and surface a typed
      // error state to the UI so the user gets "Couldn't load the marketplace
      // — Retry" instead of a silent, misleading empty library (UXR-5/AUD-1).
      // Load-more failures leave the existing list intact (the user already
      // has items to look at).
      debugPrint('Failed to load marketplace scripts: $e');
      if (!isLoadMore) {
        _marketplaceLoadError = _MarketplaceLoadError(_toShortReason(e));
      }
    } finally {
      setState(() {
        if (isLoadMore) {
          _isLoadingMore = false;
        } else {
          _isMarketplaceLoading = false;
        }
      });
    }
  }

  Future<void> _loadCategories() async {
    try {
      _categories = ['All', ...await _marketplaceService.fetchCategories()];
      if (mounted) setState(() {});
    } catch (e) {
      // fetchCategories already degrades to static defaults internally, so this
      // is a last-resort guard (e.g. the static call itself threw).
      debugPrint('Failed to load categories: $e');
    }
  }

  Future<void> _refreshMarketplaceScripts() async {
    await _loadMarketplaceScripts();
  }

  /// Short, user-readable rendering of a marketplace-load error. Strips the
  /// noisy `Exception:` prefix and caps the length so the panel subtitle stays
  /// scannable while still being honest about the cause (no silent masking).
  static String _toShortReason(Object e) {
    final cleaned = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    const max = 140;
    return cleaned.length > max ? '${cleaned.substring(0, max)}…' : cleaned;
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;

    // Filter local scripts by query
    final allScripts = _controller.scripts;
    if (query.isEmpty) {
      _filteredLocalScripts = allScripts;
    } else {
      final queryLower = query.toLowerCase();
      _filteredLocalScripts = allScripts.where((s) {
        final titleMatch = s.title.toLowerCase().contains(queryLower);
        // Also check author for marketplace-downloaded scripts
        final authorMatch =
            s.marketplaceAuthor?.toLowerCase().contains(queryLower) ?? false;
        return titleMatch || authorMatch;
      }).toList();
    }

    setState(() => _isSearching = true);
    _debouncedSearch();
  }

  void _debouncedSearch() {
    Future.delayed(AppDurations.debounce, () {
      if (mounted && _searchController.text == _searchQuery) {
        _addSearchToHistory(_searchQuery);
        _loadMarketplaceScripts();
        setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _loadSavedCategory() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCategory = prefs.getString('last_selected_category');
    if (savedCategory != null && mounted) {
      setState(() {
        _selectedCategory = savedCategory;
      });
    }
  }

  void _onCategoryChanged(String category) async {
    setState(() {
      _selectedCategory = category;
    });
    // Persist category selection
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_selected_category', category);
    _loadMarketplaceScripts();
  }

  Future<void> _loadDownloadedScripts() async {
    try {
      // Load from download history service
      final downloadHistory =
          await _downloadHistoryService.getDownloadHistory();
      final downloadedIds =
          downloadHistory.map((record) => record.marketplaceScriptId).toSet();

      setState(() {
        _downloadedScriptIds = downloadedIds;
      });
    } catch (e) {
      debugPrint('Failed to load downloaded scripts: $e');
    }
  }

  Future<void> _downloadScript(MarketplaceScript script,
      {String? version}) async {
    if (_downloadingScriptIds.contains(script.id)) return;

    setState(() {
      _downloadingScriptIds.add(script.id);
      _downloadProgress[script.id] = 0.0;
    });

    try {
      final progressUpdates = [0.3, 0.6, 0.9];
      for (final progress in progressUpdates) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            _downloadProgress[script.id] = progress;
          });
        }
      }

      final bundle =
          await _marketplaceService.downloadScript(script.id, version: version);

      final integrityService = ScriptIntegrityService();
      final sha256Checksum = integrityService.computeChecksum(bundle);

      final effectiveVersion = version ?? script.version ?? '1.0.0';
      final titleSuffix =
          version != null ? ' (Marketplace v$version)' : ' (Marketplace)';

      final createdScript = await _controller.createScript(
        title: '${script.title}$titleSuffix',
        // W6-9: persist the marketplace artwork (iconUrl) so the installed
        // tile keeps its icon instead of reverting to the generic 📦. The 📦
        // emoji stays as the fallback shown when the image fails to load.
        imageUrl: script.iconUrl,
        emoji: '📦',
        bundleOverride: bundle,
        metadata: {
          'marketplace_id': script.id,
          'marketplace_title': script.title,
          'marketplace_author': script.authorName,
          'marketplace_version': effectiveVersion,
          'downloaded_at': DateTime.now().toIso8601String(),
          'sha256_checksum': sha256Checksum,
        },
      );

      if (!mounted) return;

      await _downloadHistoryService.addToHistory(
        marketplaceScriptId: script.id,
        title: script.title,
        authorName: script.authorName ?? 'Unknown',
        version: effectiveVersion,
        localScriptId: createdScript.id,
      );

      setState(() {
        _downloadedScriptIds.add(script.id);
      });

      // Record first script interaction for GettingStartedCard
      await OnboardingProgressService().recordFirstScriptInteraction();

      if (mounted) {
        final versionText = version != null ? ' v$version' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"${script.title}"$versionText added to your library!',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppDesignSystem.successColor,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Run',
              textColor: Colors.white,
              onPressed: () => _runScript(createdScript),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppDesignSystem.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingScriptIds.remove(script.id);
          _downloadProgress.remove(script.id);
        });
      }
    }
  }

  void _showScriptDetails(BuildContext context, MarketplaceScript script) {
    final isFree = script.price <= 0;
    final owned = script.isDownloadable;
    showDialog(
      context: context,
      builder: (context) => ScriptDetailsDialog(
        script: script,
        // Free scripts use the legacy bundle-from-details download; paid
        // scripts that have been purchased go through the authenticated
        // signed-download flow. Paid + not purchased yields a null download
        // callback so the dialog renders the Buy CTA instead.
        onDownload: isFree
            ? () => _downloadScript(script)
            : (owned ? () => _downloadPaidScript(script) : null),
        onBuy: (!isFree && !owned) ? () => _buyScript(script) : null,
        isDownloading: _downloadingScriptIds.contains(script.id),
        isDownloaded: _downloadedScriptIds.contains(script.id),
      ),
    );
  }

  /// Buy CTA for a paid, not-yet-purchased script. Loads the active account,
  /// creates an ICPay payment intent, opens the hosted checkout in the
  /// external browser, then records the script as pending so app-resume
  /// refetches its entitlement.
  Future<void> _buyScript(MarketplaceScript script) async {
    final active = await _resolveActiveAccount();
    if (!mounted) return;
    if (active == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Create a profile first to purchase scripts.'),
        ),
      );
      return;
    }
    final account = active.account;
    if (account == null) {
      // Profile exists but isn't registered on the backend — signing up is a
      // prerequisite for purchase (the backend credits purchases by account).
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Register a marketplace account first to purchase.'),
        ),
      );
      return;
    }

    final icpay = getIt<IcpayService>();
    final messenger = ScaffoldMessenger.of(context);
    IcpayClientConfig config;
    try {
      config = await icpay.loadConfig(_api);
    } on PaymentsNotConfiguredException {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              "Payments aren't available on this server yet."),
          backgroundColor: AppDesignSystem.errorColor,
        ),
      );
      return;
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not load payment config: $e'),
          backgroundColor: AppDesignSystem.errorColor,
        ),
      );
      return;
    }

    PaymentIntent intent;
    try {
      intent = await icpay.createPaymentIntent(
        accountId: account.id,
        scriptId: script.id,
        usdAmount: script.price,
        config: config,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Payment setup failed: $e'),
          backgroundColor: AppDesignSystem.errorColor,
        ),
      );
      return;
    }

    final launched = await icpay.openCheckout(intent);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not open the checkout page. '
              'Check that a browser is installed.'),
        ),
      );
      return;
    }

    // Record the pending purchase so app-resume refetches entitlement. The
    // webhook (received by the backend) records the actual purchase; this just
    // drives the client-side UI refresh.
    _pendingPurchaseAccountIds[script.id] = account.id;

    messenger.showSnackBar(
      const SnackBar(
        content: Text(
            'Complete payment in your browser, then return to download.'),
        duration: Duration(seconds: 6),
      ),
    );
  }

  /// Authenticated paid-bundle download. Signs `download:{id}:{ts}:{nonce}`
  /// with the active keypair, POSTs to the authenticated download endpoint,
  /// then hands the bundle to the same install flow as free downloads.
  ///
  /// On `PurchaseRequiredException` (402) the user hasn't paid — route them
  /// to Buy. On `DownloadAuthException` (401) the signing key isn't bound to
  /// the account, which is a loud error (shouldn't happen in normal flow).
  Future<void> _downloadPaidScript(MarketplaceScript script) async {
    if (_downloadingScriptIds.contains(script.id)) return;

    final active = await _resolveActiveAccount();
    if (!mounted) return;
    if (active == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Create a profile first to download paid scripts.')),
      );
      return;
    }
    final account = active.account;
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Register a marketplace account first to download.')),
      );
      return;
    }

    setState(() {
      _downloadingScriptIds.add(script.id);
      _downloadProgress[script.id] = 0.0;
    });

    try {
      final progressUpdates = [0.3, 0.6, 0.9];
      for (final progress in progressUpdates) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          setState(() {
            _downloadProgress[script.id] = progress;
          });
        }
      }

      final signed = await DownloadSignatureService.createSignedRequest(
        signingKeypair: active.keypair,
        accountId: account.id,
        scriptId: script.id,
      );
      final bundle = await _api.downloadPaidScriptBundle(
        script.id,
        accountId: account.id,
        publicKeyB64: signed.publicKeyB64,
        signatureB64: signed.signatureB64,
        timestamp: signed.timestamp,
        nonce: signed.nonce,
      );

      await _installBundle(script, bundle);
    } on PurchaseRequiredException catch (e) {
      // Paid but not purchased — flip the local view to "not owned" and route
      // to the Buy flow.
      setState(() {
        _marketplaceScripts = _marketplaceScripts
            .map((s) => s.id == script.id ? s.copyWith(purchased: false) : s)
            .toList();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Purchase required (\$${e.price.toStringAsFixed(2)}). '
                'Tap Buy to unlock.'),
            duration: const Duration(seconds: 4),
          ),
        );
        await _buyScript(script);
      }
    } on DownloadAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Download authentication failed: ${e.detail}. '
                'Try re-registering your account.'),
            backgroundColor: AppDesignSystem.errorColor,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppDesignSystem.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _downloadingScriptIds.remove(script.id);
          _downloadProgress.remove(script.id);
        });
      }
    }
  }

  /// Shared install path for both free + paid downloads: integrity-check the
  /// bundle, create a local script record, record download history, and snackbar.
  /// Extracted from `_downloadScript` so the paid flow reuses it verbatim.
  Future<void> _installBundle(
      MarketplaceScript script, String bundle) async {
    final integrityService = ScriptIntegrityService();
    final sha256Checksum = integrityService.computeChecksum(bundle);

    final effectiveVersion = script.version ?? '1.0.0';
    final createdScript = await _controller.createScript(
      title: '${script.title} (Marketplace)',
      // W6-9: persist the marketplace artwork so the installed tile keeps its
      // icon. 📦 remains the image-load-failure fallback.
      imageUrl: script.iconUrl,
      emoji: '📦',
      bundleOverride: bundle,
      metadata: {
        'marketplace_id': script.id,
        'marketplace_title': script.title,
        'marketplace_author': script.authorName,
        'marketplace_version': effectiveVersion,
        'downloaded_at': DateTime.now().toIso8601String(),
        'sha256_checksum': sha256Checksum,
      },
    );

    if (!mounted) return;

    await _downloadHistoryService.addToHistory(
      marketplaceScriptId: script.id,
      title: script.title,
      authorName: script.authorName ?? 'Unknown',
      version: effectiveVersion,
      localScriptId: createdScript.id,
    );

    setState(() {
      _downloadedScriptIds.add(script.id);
    });

    await OnboardingProgressService().recordFirstScriptInteraction();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '"${script.title}" added to your library!',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: AppDesignSystem.successColor,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Run',
            textColor: Colors.white,
            onPressed: () => _runScript(createdScript),
          ),
        ),
      );
    }
  }

  Future<void> _runScript(ScriptRecord record) async {
    await runLocalScript(
      context,
      script: record,
      scriptController: _controller,
      runtime: _runtimeFor(record),
      onExpand: () => _expandScriptToFullScreen(record),
    );
  }

  void _expandScriptToFullScreen(ScriptRecord record) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(record.title)),
        body: ScriptAppHost(
            runtime: _runtimeFor(record),
            script: record.bundle,
            initialArg: const <String, dynamic>{}),
      ),
    ));
  }

  Future<void> _confirmAndDeleteScript(ScriptRecord record) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete script'),
          content: Text('Delete "${record.title}"? This cannot be undone.'),
          actions: <Widget>[
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _controller.deleteScript(record.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Script deleted')));
    }
  }

  Future<void> _showCreateSheet() async {
    // Use script creation screen with custom transition
    final ScriptRecord? rec = await Navigator.of(context).push<ScriptRecord>(
      CustomPageRoute.scaleFade(
        ScriptCreationScreen(
          controller: _controller,
        ),
      ),
    );
    if (mounted && rec != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Script created successfully!',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            backgroundColor: AppDesignSystem.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            action: SnackBarAction(
              label: 'Publish',
              textColor: Colors.white,
              onPressed: () => _publishToMarketplace(rec),
            ),
          ),
        );
      }
    }
  }

  Future<void> _publishToMarketplace(ScriptRecord record) async {
    // Check if user has a registered account
    final profileController = ProfileScope.of(context, listen: false);
    final profile = profileController.activeProfile;

    if (profile?.username == null) {
      // User doesn't have an account - show registration prompt
      final shouldRegister = await _showAccountRegistrationPrompt();
      if (!shouldRegister) {
        // User declined to register
        return;
      }

      // Navigate to registration wizard
      if (!mounted) return;
      final Account? account = await Navigator.push<Account>(
        context,
        MaterialPageRoute<Account>(
          builder: (context) => AccountRegistrationWizard(
            keypair: profile!.primaryKeypair,
            accountController: AccountController(
              profileController: profileController,
            ),
            initialDisplayName: profile.name,
          ),
        ),
      );

      // If registration successful, update profile username
      if (account != null && mounted) {
        await profileController.updateProfileUsername(
          profileId: profile!.id,
          username: account.username,
        );
      } else {
        // Registration cancelled or failed
        return;
      }
    }

    // Proceed with upload
    if (!mounted) return;
    final bool? uploaded = await showDialog<bool>(
      context: context,
      builder: (context) => QuickUploadDialog(
        script: record,
      ),
    );

    if (uploaded == true) {
      // Refresh downloaded scripts to include the newly published one
      await _loadDownloadedScripts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          AppDesignSystem.successSnackBar('Script published successfully!'),
        );
      }
    }
  }

  /// Shows a prompt asking user to register for marketplace publishing
  /// Returns true if user wants to register, false if dismissed
  Future<bool> _showAccountRegistrationPrompt() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const AccountRegistrationPromptDialog(),
    );
    return result ?? false;
  }

  void _viewInMarketplace(ScriptRecord record) {
    final marketplaceTitle = record.metadata['marketplace_title'] as String? ??
        record.title.replaceAll(' (Marketplace)', '');

    setState(() {
      _searchController.text = marketplaceTitle;
      _searchQuery = marketplaceTitle;
    });
    _loadMarketplaceScripts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Searching marketplace for "$marketplaceTitle"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _duplicateScript(ScriptRecord record) async {
    try {
      final newScript = await _controller.createScript(
        title: '${record.title} (Copy)',
        emoji: record.emoji,
        imageUrl: record.imageUrl,
        bundleOverride: record.bundle,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar(
          'Script duplicated as "${newScript.title}"',
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              // Scroll to the new script (implementation depends on your list view)
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to duplicate script: $e'),
            backgroundColor: AppDesignSystem.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _copyScriptSource(ScriptRecord record) async {
    await copyScriptSourceToClipboard(record);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        AppDesignSystem.successSnackBar('Script source code copied to clipboard'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use filtered local scripts (updated in _onChanged and _onSearchChanged)
    final scripts = _filteredLocalScripts;

    // WU-1: when the user dismissed the first-run wizard without creating a
    // profile, the library empty-state must offer "Set Up Profile" instead of
    // the keypair-dependent Create / Browse CTAs. Lookup is defensive: in
    // production a ProfileScope is always present, but unit tests often pump
    // ScriptsScreen without one, so a missing scope is treated as "no gating"
    // (legacy behavior). dependOnInheritedWidgetOfExactType keeps this reactive.
    final profileScope =
        context.dependOnInheritedWidgetOfExactType<ProfileScope>();
    final profileController = profileScope?.notifier;
    final hasProfile =
        profileController == null || profileController.profiles.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scripts'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'download_history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => DownloadHistoryScreen(
                      // UXR7-6: the empty-state CTA returns to this tab and
                      // refreshes the marketplace browse view instead of
                      // telling the user to switch tabs manually.
                      onBrowseMarketplace: _browseMarketplaceFromEmptyState,
                    ),
                  ),
                );
              } else if (value == 'clear_search_history') {
                _clearSearchHistory();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'download_history',
                child: Row(
                  children: [
                    Icon(Icons.history),
                    SizedBox(width: 12),
                    Text('Download History'),
                  ],
                ),
              ),
              PopupMenuItem(
                enabled: _recentSearches.isNotEmpty,
                value: 'clear_search_history',
                child: Row(
                  children: [
                    Icon(
                      Icons.clear_all,
                      color: _recentSearches.isNotEmpty
                          ? null
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Clear Search History',
                      style: TextStyle(
                        color: _recentSearches.isNotEmpty
                            ? null
                            : Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              OfflineBanner(
                isOnline: ConnectivityScope.of(context).isOnline,
                onDismiss: () => ConnectivityScope.of(context, listen: false)
                    .dismissBanner(),
              ),
              _buildSearchBar(),
              Expanded(
                child: _buildUnifiedListView(scripts, hasProfile: hasProfile),
              ),
            ],
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 90,
            child: ShortcutTooltip(
              label: 'New Script',
              shortcut: DesktopShortcuts.getShortcutLabel('new'),
              child: AnimatedFab(
                heroTag: 'scripts_fab',
                onPressed: _controller.isBusy ? null : _showCreateSheet,
                icon: const Icon(Icons.add_rounded),
                label: 'New Script',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedListView(List<ScriptRecord> localScripts,
      {required bool hasProfile}) {
    final lastRunMap = <String, DateTime>{};
    for (final s in localScripts) {
      if (s.lastRunAt != null) {
        lastRunMap[s.id] = s.lastRunAt!;
      }
    }

    final hybridItems = ScriptListItem.createHybridList(
      localScripts: localScripts,
      marketplaceScripts: _marketplaceScripts,
      installedMarketplaceIds: _downloadedScriptIds,
      runCounts: {for (final s in localScripts) s.id: s.runCount},
      lastRunAt: lastRunMap,
    );

    var sortedItems = ScriptListItem.sortItems(
      hybridItems,
      _allScriptsSortOption,
      ascending: _allScriptsSortAscending,
    );

    if (_showDownloadedOnly) {
      sortedItems = sortedItems.where((item) {
        if (item.source == ScriptSource.local && item.localScript != null) {
          return item.localScript!.isFromMarketplace;
        }
        return item.isInstalled;
      }).toList();
    }

    if (_showFavoritesOnly) {
      sortedItems = sortedItems.where((item) {
        if (item.source == ScriptSource.local && item.localScript != null) {
          return _favoriteScriptIds.contains(item.localScript!.id);
        }
        if (item.source == ScriptSource.marketplace &&
            item.marketplaceScript != null) {
          return _favoriteScriptIds.contains(item.marketplaceScript!.id);
        }
        return false;
      }).toList();
    }

    final displayedItems = sortedItems;

    final isLoadingAnything = _controller.isBusy || _isMarketplaceLoading;
    final hasNoContent = localScripts.isEmpty && displayedItems.isEmpty;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (isLoadingAnything && hasNoContent) {
          return const Center(child: CircularProgressIndicator());
        }

        if (displayedItems.isEmpty && !isLoadingAnything) {
          // W6-8: a non-empty search that matched nothing is NOT a "your
          // library is empty" situation (scripts may well be installed). Show
          // a distinct "No scripts match '<query>'" state with a Clear-search
          // affordance so the user understands the search came up empty.
          // Takes precedence over the filter/library kinds because the active
          // query is the most salient cause of the empty result.
          if (_searchQuery.isNotEmpty) {
            return ScriptsEmptyState(
              kind: ScriptsEmptyStateKind.searchNoResults,
              searchQuery: _searchQuery,
              onClearSearch: _clearSearch,
            );
          }
          final kind = _showDownloadedOnly
              ? ScriptsEmptyStateKind.downloadedFilter
              : _showFavoritesOnly
                  ? ScriptsEmptyStateKind.favoritesFilter
                  : ScriptsEmptyStateKind.library;
          // A marketplace browse-load failure is the ROOT CAUSE of an empty
          // library view when the backend is unreachable. Surface the error +
          // Retry panel instead of the misleading "Your library is empty —
          // create a script" copy, which says the opposite of what happened
          // (UXR-5 / AUD-1). Filtered views keep their own empty copy: there
          // the failure is incidental and the filter message is more useful.
          if (kind == ScriptsEmptyStateKind.library &&
              _marketplaceLoadError != null) {
            return _MarketplaceLoadErrorPanel(
              message: _marketplaceLoadError!.message,
              onRetry: _refreshMarketplaceScripts,
            );
          }
          return ScriptsEmptyState(
            kind: kind,
            hasProfile: hasProfile,
            onCreateScript: _showCreateSheet,
            onBrowseMarketplace: _browseMarketplaceFromEmptyState,
            onSetupProfile: _openSetupWizard,
            onClearDownloadedFilter: _clearDownloadedFilter,
            onClearFavoritesFilter: _clearFavoritesFilter,
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            await _controller.refresh();
            await _refreshMarketplaceScripts();
          },
          child: CustomScrollView(
            slivers: [
              ..._buildUnifiedListContent(
                displayedItems: displayedItems,
                isLoadingAnything: isLoadingAnything,
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: 100),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildUnifiedListContent({
    required List<ScriptListItem> displayedItems,
    required bool isLoadingAnything,
  }) {
    if (displayedItems.isEmpty && !isLoadingAnything) {
      return [];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAllScriptsListItem(displayedItems[index]),
          childCount: displayedItems.length,
        ),
      ),
    ];
  }

  Widget _buildAllScriptsListItem(ScriptListItem item) {
    final isLocalScript =
        item.source == ScriptSource.local && item.localScript != null;
    return ScriptsListItemTile(
      item: item,
      onTap: () => _handleAllScriptsItemTap(item),
      onLongPress: () =>
          showScriptContextMenuSheet(context, item, _contextMenuActionsFor(item)),
      onSecondaryTapUp: (details) => showScriptContextMenuPopup(
        context,
        item,
        details.globalPosition,
        _contextMenuActionsFor(item),
        canPublish:
            item.localScript != null && !item.localScript!.isFromMarketplace,
        isDownloaded: item.marketplaceScript != null &&
            _downloadedScriptIds.contains(item.marketplaceScript!.id),
      ),
      trailing: isLocalScript
          ? LocalScriptRowMenu(
              record: item.localScript!,
              isFavorite: _favoriteScriptIds.contains(item.localScript!.id),
              onRun: () => _runScript(item.localScript!),
              onEdit: () => _editScript(item.localScript!),
              onPublish: () => _publishToMarketplace(item.localScript!),
              onConfirmDelete: () => _confirmAndDeleteScript(item.localScript!),
              onDuplicate: () => _duplicateScript(item.localScript!),
              onCopySource: () => _copyScriptSource(item.localScript!),
              onViewInMarketplace: () => _viewInMarketplace(item.localScript!),
              onToggleFavorite: () => _toggleFavorite(item.localScript!.id),
            )
          : item.source == ScriptSource.marketplace &&
                  item.marketplaceScript != null
              ? MarketplaceScriptRowMenu(
                  script: item.marketplaceScript!,
                  isDownloaded: _downloadedScriptIds
                      .contains(item.marketplaceScript!.id),
                  isDownloading: _downloadingScriptIds
                      .contains(item.marketplaceScript!.id),
                  isFavorite:
                      _favoriteScriptIds.contains(item.marketplaceScript!.id),
                  onViewDetails: () =>
                      _showScriptDetails(context, item.marketplaceScript!),
                  onDownload: () => _downloadScript(item.marketplaceScript!),
                  onShare: () => _shareScript(context, item.marketplaceScript!),
                  onToggleFavorite: () =>
                      _toggleFavorite(item.marketplaceScript!.id),
                )
              : null,
    );
  }

  /// Builds the bundle of callbacks the extracted context-menu helpers dispatch
  /// to. Each closure captures the specific record/script on [item]; the menu
  /// code only invokes the ones valid for the item's source.
  ScriptContextMenuActions _contextMenuActionsFor(ScriptListItem item) {
    return ScriptContextMenuActions(
      onRun: () => _runScript(item.localScript!),
      onEdit: () => _editScript(item.localScript!),
      onDuplicate: () => _duplicateScript(item.localScript!),
      onDelete: () => _confirmAndDeleteScript(item.localScript!),
      onPublish: () => _publishToMarketplace(item.localScript!),
      onCopySource: () => _copyScriptSource(item.localScript!),
      onViewDetails: () => _showScriptDetails(context, item.marketplaceScript!),
      onDownload: () => _downloadScript(item.marketplaceScript!),
      onShare: () => _shareScript(context, item.marketplaceScript!),
      isDownloading: item.marketplaceScript != null &&
          _downloadingScriptIds.contains(item.marketplaceScript!.id),
    );
  }

  /// ONE-TAP EXECUTION (#34): Single tap on local script runs immediately.
  /// Edit is accessible via overflow menu or long-press context menu.
  void _handleAllScriptsItemTap(ScriptListItem item) {
    if (item.source == ScriptSource.local && item.localScript != null) {
      // Record first script interaction for GettingStartedCard
      OnboardingProgressService().recordFirstScriptInteraction();
      // ONE-TAP: Run script immediately on tap
      _runScript(item.localScript!);
    } else if (item.source == ScriptSource.marketplace &&
        item.marketplaceScript != null) {
      _showScriptDetails(context, item.marketplaceScript!);
    }
  }

  /// Opens the script editor for editing.
  /// This is now a secondary action, accessible via overflow menu or long-press.
  void _editScript(ScriptRecord record) {
    OnboardingProgressService().recordFirstScriptInteraction();
    showDialog<void>(
      context: context,
      builder: (_) => ScriptEditorDialog(
        controller: _controller,
        record: record,
      ),
    );
  }

  Widget _buildSearchBar() {
    return ScriptsSearchBar(
      searchController: _searchController,
      searchFocusNode: _searchFocusNode,
      onSearchChanged: _onSearchChanged,
      activeFilterCount: _getActiveFilterCount(),
      activeFilters: _getActiveFilters(),
      onClearAllFilters: _clearAllFilters,
      onFilterButtonPressed: () => _showFilterPopover(context),
      showRecentSearches: _showRecentSearches,
      recentSearches: _recentSearches,
      onSelectRecentSearch: _selectRecentSearch,
      onRemoveRecentSearch: (query) async {
        await _searchHistoryService.removeSearchQuery(query);
        await _loadRecentSearches();
      },
      isSearching: _isSearching,
    );
  }

  /// Returns a list of active filters with their labels and dismiss callbacks.
  List<ScriptsActiveFilter> _getActiveFilters() {
    final filters = <ScriptsActiveFilter>[];

    // Category filter (not 'All')
    if (_selectedCategory != 'All') {
      filters.add(ScriptsActiveFilter(
        label: _selectedCategory,
        onDismiss: () {
          setState(() {
            _selectedCategory = 'All';
          });
          _loadMarketplaceScripts();
        },
      ));
    }

    // Sort filter (not default 'lastRun')
    if (_allScriptsSortOption != ScriptSortOption.lastRun) {
      filters.add(ScriptsActiveFilter(
        label: 'Sort: ${_allScriptsSortOption.label}',
        onDismiss: () {
          setState(() {
            _allScriptsSortOption = ScriptSortOption.lastRun;
            _allScriptsSortAscending = false;
          });
        },
      ));
    }

    // Downloaded filter
    if (_showDownloadedOnly) {
      filters.add(ScriptsActiveFilter(
        label: 'Downloaded',
        onDismiss: _clearDownloadedFilter,
      ));
    }

    // Favorites filter
    if (_showFavoritesOnly) {
      filters.add(ScriptsActiveFilter(
        label: 'Favorites',
        onDismiss: _clearFavoritesFilter,
      ));
    }

    return filters;
  }

  /// Clears all active filters and refreshes marketplace scripts.
  void _clearAllFilters() {
    setState(() {
      _selectedCategory = 'All';
      _allScriptsSortOption = ScriptSortOption.lastRun;
      _allScriptsSortAscending = false;
      _showDownloadedOnly = false;
      _showFavoritesOnly = false;
    });
    _loadMarketplaceScripts();
  }

  /// Clears the "Downloaded" filter to show all scripts.
  void _clearDownloadedFilter() {
    setState(() {
      _showDownloadedOnly = false;
    });
  }

  /// Clears the "Favorites" filter to show all scripts.
  void _clearFavoritesFilter() {
    setState(() {
      _showFavoritesOnly = false;
    });
  }

  /// Clears the active search query (W6-8). The primary action of the
  /// search-no-results empty state: resets the query, clears the search field,
  /// re-runs the local filter + marketplace browse so the user is back to the
  /// full list.
  void _clearSearch() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _filteredLocalScripts = _controller.scripts;
    });
    _loadMarketplaceScripts();
  }

  /// Toggles the favorite status of a script.
  Future<void> _toggleFavorite(String scriptId) async {
    await _favoritesService.toggleFavorite(scriptId);
    // The _favoriteScriptIds set will be updated via the favoritesStream
    // listener in _loadFavorites(), which triggers setState.
  }

  /// Re-opens the first-run [UnifiedSetupWizard] from the library empty-state.
  ///
  /// Used when the user dismissed the wizard without creating a profile: rather
  /// than dead-ending them on keypair-dependent CTAs, this gives them a direct
  /// path back to profile creation. Mirrors [showFirstRunSetupIfNeeded] in
  /// `main.dart` without introducing a circular import on the app entry point.
  Future<void> _openSetupWizard() async {
    final profileController = ProfileScope.of(context, listen: false);
    final accountController =
        AccountController(profileController: profileController);
    await Navigator.of(context).push<UnifiedSetupResult>(
      MaterialPageRoute<UnifiedSetupResult>(
        fullscreenDialog: true,
        builder: (_) => UnifiedSetupWizard(
          profileController: profileController,
          accountController: accountController,
          secureStorageReadiness: SecureStorageReadiness(),
        ),
      ),
    );
  }

  /// Clears all filters and refreshes marketplace scripts.
  /// Used as secondary action in empty state to help users discover marketplace.
  void _browseMarketplaceFromEmptyState() {
    setState(() {
      _showDownloadedOnly = false;
      _showFavoritesOnly = false;
      _selectedCategory = 'All';
      _searchQuery = '';
      _searchController.clear();
    });
    _loadMarketplaceScripts();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing marketplace scripts...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Returns the number of active (non-default) filters.
  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedCategory != 'All') count++;
    if (_allScriptsSortOption != ScriptSortOption.lastRun) count++;
    if (_showDownloadedOnly) count++;
    if (_showFavoritesOnly) count++;
    return count;
  }

  /// Shows the filter popover with category and sort options.
  void _showFilterPopover(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: AppDesignSystem.sheetBorderRadius,
      ),
      builder: (context) => FilterBottomSheet(
        categories: _categories,
        selectedCategory: _selectedCategory,
        sortOption: _allScriptsSortOption,
        sortAscending: _allScriptsSortAscending,
        showDownloadedOnly: _showDownloadedOnly,
        showFavoritesOnly: _showFavoritesOnly,
        onCategoryChanged: (category) {
          _onCategoryChanged(category);
          Navigator.of(context).pop();
        },
        onSortChanged: (option, ascending) {
          setState(() {
            _allScriptsSortOption = option;
            _allScriptsSortAscending = ascending;
          });
        },
        onDownloadedFilterChanged: (value) {
          setState(() {
            _showDownloadedOnly = value;
          });
        },
        onFavoritesFilterChanged: (value) {
          setState(() {
            _showFavoritesOnly = value;
          });
        },
        onReset: () {
          setState(() {
            _selectedCategory = 'All';
            _allScriptsSortOption = ScriptSortOption.lastRun;
            _allScriptsSortAscending = false;
            _showDownloadedOnly = false;
            _showFavoritesOnly = false;
          });
          Navigator.of(context).pop();
          _loadMarketplaceScripts();
        },
      ),
    );
  }

  void _shareScript(BuildContext context, MarketplaceScript script) async {
    final shareUrl = '${AppConfig.marketplaceWebUrl}/scripts/${script.id}';

    // Capture context before async operation
    final messenger = ScaffoldMessenger.of(context);

    await Clipboard.setData(ClipboardData(text: shareUrl));
    if (mounted) {
      messenger.showSnackBar(
        AppDesignSystem.successSnackBar('Script link copied to clipboard!'),
      );
    }
  }
}

/// Copies a script's TypeScript bundle to the system clipboard.
///
/// "Copy Source" is a clipboard action (not a file export): the bundle the
/// author wrote is placed on the clipboard verbatim. Extracted as a top-level
/// function so the behavior is unit-testable without pumping the full screen.
Future<void> copyScriptSourceToClipboard(ScriptRecord record) {
  return Clipboard.setData(ClipboardData(text: record.bundle));
}

/// Resolved active-profile context for purchase + paid-download flows.
/// [account] is null when the profile isn't registered on the backend yet —
/// callers gate on that to prompt registration before purchasing.
class _ActiveAccount {
  final Profile profile;
  final ProfileKeypair keypair;
  final Account? account;

  const _ActiveAccount({
    required this.profile,
    required this.keypair,
    required this.account,
  });
}

/// Typed marketplace browse-load failure (UXR-5 / AUD-1). Carries a single
/// user-readable [message] derived from the underlying error so the load-error
/// panel can render an honest, actionable reason alongside the Retry button.
@immutable
class _MarketplaceLoadError {
  const _MarketplaceLoadError(this.message);

  final String message;

  @override
  String toString() => '_MarketplaceLoadError: $message';
}

/// Inline error + Retry panel shown in place of the library empty-state when a
/// marketplace browse load failed. Mirrors the app's design language (circular
/// gradient-tinted icon, title + subtitle, modern button) but is error-themed
/// so it reads as a failure, not as "you have no scripts".
///
/// Distinguished from [ScriptsEmptyState] (genuine empty result) by the
/// presence of a [_MarketplaceLoadError] on the screen state — the two never
/// render at the same time.
class _MarketplaceLoadErrorPanel extends StatelessWidget {
  const _MarketplaceLoadErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDesignSystem.spacing32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.error.withValues(alpha: 0.1),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: AppDesignSystem.spacing24),
            Text(
              "Couldn't load the marketplace",
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDesignSystem.spacing8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppDesignSystem.spacing24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
