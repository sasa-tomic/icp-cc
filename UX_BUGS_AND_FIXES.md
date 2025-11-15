# Flutter App UX Bugs and Fixes

**Analysis Date**: 2025-11-14
**Total Issues Identified**: 34
**Critical/High Priority**: 9 issues
**Status**: Ready for implementation

---

## Priority Classification

### 🔴 Critical (Fix Immediately)
1. **Email Validator Broken Logic** - Identity Profile (Issue 3.1, 5.9)
2. **Duplicate Marketplace Screens** - Navigation Architecture (Issue 2.1)
3. **No Purchase Flow for Paid Scripts** - Marketplace (Issue 4.4)
4. **Hardcoded Share URLs** - Scripts & Marketplace (Issues 5.1, 5.2)
5. **No Undo for Script Deletion** - Scripts (Issue 5.7)

### 🟠 High Priority (Fix Soon)
1. **No Code Preview in Quick Upload** - Scripts (Issue 1.2)
2. **Downloaded Scripts Not Clearly Indicated** - Marketplace Cards (Issue 5.10)

### 🟡 Medium Priority (Fix This Sprint)
See detailed list below (16 issues)

### 🟢 Low Priority (Backlog)
See detailed list below (11 issues)

---

## Detailed Issue Breakdown

### **1. SCRIPT MANAGEMENT**

#### 1.1 No Feedback After Publish to Marketplace
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:397-414`
**Severity:** Medium
**Issue:** Publishing shows "Switched to Marketplace" but doesn't automatically find the script
**Fix:**
```dart
// After successful publish, switch to marketplace tab AND search for the script
await _publishToMarketplace(script);
setState(() {
  _currentTabIndex = 1; // Switch to marketplace
  _searchController.text = script.title; // Auto-search for published script
});
_performSearch(script.title); // Trigger search
```

#### 1.2 No Lua Source Preview in Quick Upload ⚠️ HIGH
**File:** `apps/autorun_flutter/lib/widgets/quick_upload_dialog.dart:104-119`
**Severity:** High
**Issue:** Generates default Lua script without showing what will be uploaded
**Fix:**
```dart
// Add preview step before upload:
// Step 1: Show form (existing)
// Step 2: NEW - Show code preview with ScriptEditor (read-only)
// Step 3: Confirm and upload
```

#### 1.3 Script Duplication - Unimplemented Scroll-to
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:429-462`
**Severity:** Low
**Issue:** "View" snackbar action has no implementation
**Fix:**
```dart
// Line 448 - Implement scroll to new script
SnackBarAction(
  label: 'View',
  onPressed: () {
    // Scroll to newScript in the list
    final index = _scripts.indexOf(newScript);
    if (index >= 0) {
      _scrollController.animateTo(
        index * 100.0, // Approximate item height
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  },
),
```

#### 1.4 Missing Download Progress Details
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:224-310`
**Severity:** Medium
**Issue:** Download progress shows only visual bar, no percentage or ETA
**Fix:**
```dart
// Add to download progress overlay:
Text('${(downloadProgress * 100).toStringAsFixed(0)}%'),
if (estimatedTimeRemaining != null)
  Text('${estimatedTimeRemaining} remaining'),
Text('${downloadedBytes} / ${totalBytes}'),
```

#### 1.5 Marketplace Download Progress (Same as 1.4)
**File:** `apps/autorun_flutter/lib/screens/marketplace_screen.dart:191-278`
**Severity:** Medium
**Fix:** Same as 1.4

#### 1.6 Unclear "Published" Badge
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:605-623`
**Severity:** Low
**Issue:** No tooltip explaining what "Published" means
**Fix:**
```dart
Tooltip(
  message: 'Published to Marketplace',
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(/* existing */),
    child: Text('Published'),
  ),
)
```

---

### **2. NAVIGATION ISSUES**

#### 2.1 Duplicate Marketplace Screens ⚠️ CRITICAL
**Files:**
- `apps/autorun_flutter/lib/screens/marketplace_screen.dart`
- `apps/autorun_flutter/lib/screens/scripts_screen.dart:772-954`

**Severity:** High
**Issue:** Marketplace appears as both separate screen AND tab in scripts_screen
**Fix:**
**Strategy:** Remove marketplace tab from scripts_screen, keep only standalone marketplace_screen. Update navigation to use single source.

**Changes Required:**
1. Remove `_buildMarketplaceTab()` from scripts_screen.dart
2. Update tab controller to have only "My Scripts" (no Marketplace tab)
3. Update bottom navigation to link to standalone marketplace_screen
4. Ensure download/bookmark actions in marketplace_screen update scripts_screen

**Implementation:**
```dart
// In scripts_screen.dart - Remove lines 772-954 (_buildMarketplaceTab)
// In main.dart - Ensure BottomNavigationBar routes to MarketplaceScreen
```

#### 2.2 Back Button Inconsistency in Dialogs
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:1040-1134`
**Severity:** Low
**Issue:** Close button varies between icon and text on different screen sizes
**Fix:**
```dart
// Always show both icon and text for consistency:
actions: [
  TextButton.icon(
    icon: Icon(Icons.close),
    label: Text('Close'),
    onPressed: () => Navigator.pop(context),
  ),
],
```

#### 2.3 Download History - Can't Navigate to Local Script
**File:** `apps/autorun_flutter/lib/screens/download_history_screen.dart`
**Severity:** Medium
**Issue:** TODO comment reveals missing navigation
**Fix:**
```dart
// On tap of history entry:
onTap: () {
  Navigator.pushNamed(
    context,
    '/scripts',
    arguments: {'scrollToScriptId': historyEntry.scriptId},
  );
}
```

#### 2.4 Marketplace Tab Doesn't Auto-Search
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:416-427`
**Severity:** Medium
**Issue:** "View in Marketplace" switches tab but doesn't search
**Fix:**
```dart
void _viewInMarketplace(Script script) async {
  setState(() {
    _currentTabIndex = 1;
    _searchController.text = script.title;
  });
  await _performSearch(script.title);
}
```

---

### **3. PROFILE MANAGEMENT**

#### 3.1 Email Validator Broken Logic ⚠️ CRITICAL
**File:** `apps/autorun_flutter/lib/widgets/identity_profile_sheet.dart:125-133`
**Severity:** High
**Issue:** Validator logic is incorrect: `!value.contains('@') || !value.contains('.')`
This validates:
- "test@test" (no dot) ✅ WRONG
- "test.test" (no @) ✅ WRONG
- "test@@test.com" ✅ WRONG

**Fix:**
```dart
// Replace with proper email validation:
validator: (value) {
  if (value == null || value.isEmpty) return null; // Optional field
  final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  if (!emailRegex.hasMatch(value)) {
    return 'Please enter a valid email address';
  }
  return null;
},
```

**OR use package:**
```yaml
# pubspec.yaml
dependencies:
  email_validator: ^2.1.17
```
```dart
import 'package:email_validator/email_validator.dart';

validator: (value) {
  if (value == null || value.isEmpty) return null;
  if (!EmailValidator.validate(value)) {
    return 'Please enter a valid email address';
  }
  return null;
},
```

#### 3.2 Website URL Validation Too Restrictive
**File:** `apps/autorun_flutter/lib/widgets/identity_profile_sheet.dart:166-174`
**Severity:** Low
**Issue:** Requires protocol but hint doesn't explain
**Fix:**
```dart
decoration: InputDecoration(
  labelText: 'Website',
  hintText: 'https://example.com', // More explicit hint
  helperText: 'Must start with https:// or http://',
),
// OR auto-prepend https:// if missing
validator: (value) {
  if (value == null || value.isEmpty) return null;
  if (!value.startsWith('http://') && !value.startsWith('https://')) {
    value = 'https://$value'; // Auto-fix
  }
  // Validate URL format
  if (!Uri.tryParse(value)?.hasAuthority ?? false) {
    return 'Please enter a valid URL';
  }
  return null;
},
```

#### 3.3 Profile Load - No Loading Indicator
**File:** `apps/autorun_flutter/lib/screens/identity_home_page.dart:111-141`
**Severity:** Medium
**Issue:** Clicking edit does nothing visible for 1-2 seconds while loading
**Fix:**
```dart
void _editIdentityProfile() async {
  // Show loading dialog
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Center(child: CircularProgressIndicator()),
  );

  await _controller.ensureProfileLoaded();

  Navigator.pop(context); // Close loading dialog

  showModalBottomSheet(/* existing code */);
}
```

#### 3.4 Social Handles - No Validation
**File:** `apps/autorun_flutter/lib/widgets/identity_profile_sheet.dart:104-182`
**Severity:** Low
**Issue:** Users can enter invalid social media handles
**Fix:**
```dart
// For Telegram, Twitter, Discord:
validator: (value) {
  if (value == null || value.isEmpty) return null;

  // Remove @ if present
  value = value.replaceAll('@', '');

  // Validate alphanumeric + underscore only
  final handleRegex = RegExp(r'^[a-zA-Z0-9_]{1,32}$');
  if (!handleRegex.hasMatch(value)) {
    return 'Handle can only contain letters, numbers, and underscores';
  }
  return null;
},
// Auto-save cleaned value (without @)
```

---

### **4. MARKETPLACE**

#### 4.1 Search Debounce Not Visible
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:186-197`
**Severity:** Medium
**Issue:** 500ms debounce has no user feedback
**Fix:**
```dart
// Add isSearching state
bool _isSearching = false;

void _setupSearchListener() {
  _searchController.addListener(() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    setState(() => _isSearching = true); // NEW: Show loading state

    _debounce = Timer(const Duration(milliseconds: 500), () {
      _performSearch(_searchController.text);
      setState(() => _isSearching = false); // NEW: Hide loading
    });
  });
}

// In UI - show loading indicator:
if (_isSearching)
  LinearProgressIndicator(minHeight: 2),
```

#### 4.2 Infinite Scroll - No End Message
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:846-854`
**Severity:** Low
**Issue:** Grid just stops, no "end of results" indicator
**Fix:**
```dart
// After GridView.builder, add footer:
if (!_hasMore && _marketplaceScripts.isNotEmpty)
  Padding(
    padding: EdgeInsets.all(16),
    child: Text(
      'You\'ve reached the end',
      textAlign: TextAlign.center,
      style: TextStyle(color: Colors.grey),
    ),
  ),
```

#### 4.3 Category Filter Not Persistent
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:199-204`
**Severity:** Medium
**Issue:** Category resets when navigating away
**Fix:**
```dart
// Use PageStorage to persist:
PageStorage(
  bucket: PageStorageBucket(),
  child: /* existing category dropdown */,
)

// OR save to shared preferences:
void _onCategoryChanged(String? category) {
  setState(() => _selectedCategory = category);
  SharedPreferences.getInstance().then((prefs) {
    prefs.setString('last_selected_category', category ?? 'All');
  });
}
```

#### 4.4 Paid Scripts - No Purchase Flow ⚠️ CRITICAL
**File:** `apps/autorun_flutter/lib/widgets/script_card.dart:359-380`
**Severity:** High
**Issue:** "$" button does nothing, no error message
**Fix:**
```dart
// Option 1: Hide purchase button until implemented
if (script.price > 0 && false) // Disable for now
  /* existing purchase button */

// Option 2: Show "Coming Soon" dialog
if (script.price > 0)
  InkWell(
    onTap: () {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Payments Coming Soon'),
          content: Text('Paid scripts will be available in the next update!'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK'),
            ),
          ],
        ),
      );
    },
    child: /* existing purchase button */,
  ),
```

#### 4.5 Rating Badge - Confusing "New"
**File:** `apps/autorun_flutter/lib/widgets/script_card.dart:307-318`
**Severity:** Low
**Issue:** Old scripts with no ratings show "New"
**Fix:**
```dart
// Check both rating == 0 AND recent creation date:
if (script.rating == 0.0) {
  final daysOld = DateTime.now().difference(script.createdAt).inDays;
  if (daysOld < 7) {
    return Text('New'); // Actually new
  } else {
    return Text('No ratings yet', style: TextStyle(fontSize: 11));
  }
}
```

---

### **5. GENERAL UI/UX**

#### 5.1 Hardcoded Share URL ⚠️ CRITICAL
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:959`
**Severity:** High
**Issue:** `https://icp-marketplace.com/scripts/${script.id}` may not exist
**Fix:**
```dart
// In app_config.dart, add:
class AppConfig {
  static const String marketplaceBaseUrl = String.fromEnvironment(
    'MARKETPLACE_URL',
    defaultValue: 'https://icp-mp.kalaj.org', // Real domain
  );
}

// In scripts_screen.dart:
Share.share('${AppConfig.marketplaceBaseUrl}/scripts/${script.id}');
```

#### 5.2 Hardcoded Share URL (Duplicate) ⚠️ CRITICAL
**File:** `apps/autorun_flutter/lib/screens/marketplace_screen.dart:652`
**Severity:** High
**Fix:** Same as 5.1 (extract to AppConfig)

#### 5.3 Loading Indicator - No Text on Compact Screens
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:535-537`
**Severity:** Low
**Issue:** Just CircularProgressIndicator, no context
**Fix:**
```dart
Center(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircularProgressIndicator(),
      SizedBox(height: 16),
      Text('Loading scripts...', style: TextStyle(color: Colors.grey)),
    ],
  ),
)
```

#### 5.4 Inconsistent Error Message Formatting
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:158-171`
**Severity:** Low
**Issue:** Multiple error format variants
**Fix:**
```dart
// Create unified error formatter:
Widget buildErrorMessage(String title, String message, {String? technicalDetails}) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
      SizedBox(height: 16),
      Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center),
      if (technicalDetails != null) ...[
        SizedBox(height: 16),
        ExpansionTile(
          title: Text('Technical Details'),
          children: [Text(technicalDetails)],
        ),
      ],
    ],
  );
}

// Use everywhere:
buildErrorMessage('Failed to Load Scripts', 'Please try again later',
                  technicalDetails: error.toString())
```

#### 5.5 Upload Progress - Missing Percentage
**File:** `apps/autorun_flutter/lib/screens/script_upload_screen.dart:421-433`
**Severity:** Medium
**Issue:** No progress percentage during upload
**Fix:**
```dart
// Add progress callback to upload API:
await _marketplaceService.uploadScript(
  script,
  onProgress: (sent, total) {
    setState(() {
      _uploadProgress = sent / total;
    });
  },
);

// Show in UI:
Column(
  children: [
    CircularProgressIndicator(value: _uploadProgress),
    SizedBox(height: 8),
    Text('${(_uploadProgress * 100).toStringAsFixed(0)}% uploaded'),
  ],
)
```

#### 5.6 Tab Switch Animation Jank
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:40-44`
**Severity:** Medium
**Issue:** Full setState() on tab change
**Fix:**
```dart
// Replace setState with ValueListenableBuilder:
final _showFab = ValueNotifier<bool>(true);

// In listener:
_tabController.addListener(() {
  _showFab.value = _tabController.index == 0; // No setState
});

// In build:
floatingActionButton: ValueListenableBuilder<bool>(
  valueListenable: _showFab,
  builder: (context, show, child) => show ? child! : SizedBox.shrink(),
  child: FloatingActionButton(/* existing */),
),
```

#### 5.7 No Undo for Script Deletion ⚠️ CRITICAL
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:581-584`
**Severity:** High
**Issue:** Swipe-to-delete has no undo option
**Fix:**
```dart
// Implement soft delete pattern:
void _deleteScript(Script script) {
  final deletedScript = script;

  // Remove from UI immediately
  setState(() => _scripts.remove(script));

  // Show undo snackbar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Script deleted'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          // Restore script
          setState(() => _scripts.add(deletedScript));
        },
      ),
      duration: Duration(seconds: 5),
    ),
  ).closed.then((reason) {
    // If snackbar dismissed without undo, actually delete
    if (reason != SnackBarClosedReason.action) {
      _scriptRepository.delete(deletedScript.id);
    }
  });
}
```

#### 5.8 Script Card - Inconsistent onTap Behavior
**File:** `apps/autorun_flutter/lib/widgets/script_card.dart:43-45`
**Severity:** Low
**Issue:** onTap varies between dialog and full screen
**Fix:**
```dart
// Document expected behavior in widget:
/// ScriptCard onTap behavior:
/// - Compact screens (<600px): Open full-screen editor
/// - Large screens: Open dialog
///
/// Callers can override by providing custom onTap callback
```

#### 5.10 Downloaded Scripts Not Clearly Indicated ⚠️ HIGH
**File:** `apps/autorun_flutter/lib/widgets/script_card.dart:922-945`
**Severity:** Medium
**Issue:** Small green checkmark is easy to miss
**Fix:**
```dart
// Make checkmark larger and add subtle background tint:
Container(
  decoration: BoxDecoration(
    color: isDownloaded
        ? Colors.green.withOpacity(0.05) // Subtle tint
        : null,
    border: isDownloaded
        ? Border.all(color: Colors.green.withOpacity(0.2), width: 2)
        : null,
  ),
  child: /* existing card content */,
)

// Increase checkmark size:
Icon(Icons.check_circle, color: Colors.green, size: 24), // Was 16
```

#### 5.11 Dialog Keyboard - Content Cutoff on Mobile
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:677-681`
**Severity:** Medium
**Issue:** Keyboard covers dialog content on small screens
**Fix:**
```dart
showDialog(
  context: context,
  builder: (context) => Dialog(
    insetPadding: EdgeInsets.all(16), // Ensure some padding
    child: SingleChildScrollView( // Make scrollable
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom, // Keyboard height
        ),
        child: /* existing dialog content */,
      ),
    ),
  ),
);
```

#### 5.12 Profile Complete Check - Inefficient
**File:** `apps/autorun_flutter/lib/main.dart:160-166`
**Severity:** Low
**Issue:** Checks profile completeness on every rebuild
**Fix:**
```dart
// Use ValueListenableBuilder or StreamBuilder:
class IdentityController extends ChangeNotifier {
  bool _isProfileComplete = false;
  bool get isProfileComplete => _isProfileComplete;

  void checkProfileCompleteness() {
    final complete = /* existing logic */;
    if (complete != _isProfileComplete) {
      _isProfileComplete = complete;
      notifyListeners(); // Only rebuild if changed
    }
  }
}

// In UI:
ValueListenableBuilder<bool>(
  valueListenable: _identityController.isProfileCompleteNotifier,
  builder: (context, isComplete, child) {
    if (!isComplete) return Badge(/* show badge */);
    return SizedBox.shrink();
  },
)
```

---

### **6. RESPONSIVE DESIGN ISSUES**

#### 6.1 Full-Screen Dialog - System UI Overlap
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:1045-1132`
**Severity:** Medium
**Issue:** insetPadding: EdgeInsets.zero causes system UI overlap
**Fix:**
```dart
Dialog.fullscreen(
  child: Scaffold(
    body: SafeArea( // Add SafeArea
      child: /* existing content */,
    ),
  ),
)
```

#### 6.2 Marketplace Grid - Poor Tablet Support
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:856-864`
**Severity:** Low
**Issue:** Only 2-3 columns max, tablets could show 4-5
**Fix:**
```dart
// Update ResponsiveGridConfig:
class ResponsiveGridConfig {
  static int getColumns(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 1;   // Mobile portrait
    if (width < 900) return 2;   // Mobile landscape / small tablet
    if (width < 1200) return 3;  // Tablet
    if (width < 1600) return 4;  // Large tablet / small desktop
    return 5;                    // Desktop
  }
}
```

#### 6.3 Compact Screen - ListTile Cutoff
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:586-763`
**Severity:** Low
**Issue:** Title might get cut off on very small screens
**Fix:**
```dart
ListTile(
  title: Text(
    script.title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis, // Add explicit ellipsis
  ),
  // On very compact screens, hide popup menu text:
  trailing: MediaQuery.of(context).size.width < 380
      ? IconButton(icon: Icon(Icons.more_vert), onPressed: _showMenu)
      : PopupMenuButton(/* existing */),
)
```

---

### **7. DATA & STATE MANAGEMENT**

#### 7.1 Multiple Controller Instances Not Synced
**Files:**
- `apps/autorun_flutter/lib/screens/scripts_screen.dart:37,47,72`

**Severity:** Medium
**Issue:** Separate instances don't sync when data changes
**Fix:**
```dart
// Refactor to use singleton pattern or Provider:
// Option 1: Singleton
class ScriptRepository {
  static final ScriptRepository _instance = ScriptRepository._internal();
  factory ScriptRepository() => _instance;
  ScriptRepository._internal();

  final _scriptsController = StreamController<List<Script>>.broadcast();
  Stream<List<Script>> get scriptsStream => _scriptsController.stream;

  void notifyScriptsChanged(List<Script> scripts) {
    _scriptsController.add(scripts);
  }
}

// Option 2: Use Provider (better)
// In main.dart:
MultiProvider(
  providers: [
    ChangeNotifierProvider(create: (_) => ScriptRepository()),
    ChangeNotifierProvider(create: (_) => IdentityController()),
  ],
  child: MyApp(),
)
```

#### 7.2 Downloaded Scripts Set - Stale Data
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:51-54,208-222`
**Severity:** Medium
**Issue:** Set loaded once, never refreshed after upload
**Fix:**
```dart
// Refresh after upload:
void _onScriptUploaded(Script script) {
  _loadDownloadedScriptIds(); // Refresh the set
  setState(() {
    // Update UI
  });
}

// OR listen to repository changes:
_scriptRepository.onScriptsChanged.listen((event) {
  _loadDownloadedScriptIds();
});
```

#### 7.3 Categories - No Caching
**File:** `apps/autorun_flutter/lib/screens/scripts_screen.dart:173-180`
**Severity:** Low
**Issue:** Categories reload on every navigation
**Fix:**
```dart
// Cache categories in memory with timestamp:
class MarketplaceService {
  static List<String>? _cachedCategories;
  static DateTime? _cacheTime;
  static const cacheDuration = Duration(hours: 1);

  Future<List<String>> getCategories() async {
    if (_cachedCategories != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < cacheDuration) {
      return _cachedCategories!;
    }

    final categories = await _fetchCategories();
    _cachedCategories = categories;
    _cacheTime = DateTime.now();
    return categories;
  }
}
```

---

## Implementation Priority Order

### Sprint 1 (Week 1) - Critical Fixes
1. ✅ Fix email validator broken logic (3.1)
2. ✅ Remove duplicate marketplace screens (2.1)
3. ✅ Fix hardcoded share URLs (5.1, 5.2)
4. ✅ Add undo for script deletion (5.7)
5. ✅ Hide/disable paid scripts purchase button (4.4)

### Sprint 2 (Week 2) - High Priority UX
1. ✅ Add code preview to quick upload (1.2)
2. ✅ Make downloaded scripts more visible (5.10)
3. ✅ Add download progress details (1.4, 1.5)
4. ✅ Add upload progress percentage (5.5)
5. ✅ Show loading indicator for profile load (3.3)

### Sprint 3 (Week 3) - Medium Priority Polish
1. Search debounce feedback (4.1)
2. Category filter persistence (4.3)
3. Navigate from download history (2.3)
4. Auto-search in marketplace view (2.4)
5. Fix tab animation jank (5.6)
6. Sync multiple controller instances (7.1)
7. Refresh downloaded scripts set (7.2)
8. Dialog keyboard handling (5.11)

### Backlog - Low Priority
- All remaining low-priority issues
- Responsive design tweaks
- Performance optimizations

---

## Testing Checklist

After implementing fixes:

- [ ] Email validation accepts only valid emails
- [ ] Marketplace screen is singular (no duplicate)
- [ ] Share URLs use correct domain
- [ ] Script deletion has undo option (5 second window)
- [ ] Paid scripts show "Coming Soon" dialog
- [ ] Quick upload shows code preview before submit
- [ ] Downloaded marketplace cards have visible green indicator
- [ ] Download progress shows percentage and ETA
- [ ] Upload progress shows percentage
- [ ] Profile edit shows loading state
- [ ] Search shows "Searching..." during debounce
- [ ] Category filter persists across navigation
- [ ] Download history navigates to local script
- [ ] "View in Marketplace" auto-searches for script
- [ ] Tab switching doesn't cause visible jank
- [ ] Multiple screens show synced data
- [ ] Dialogs don't get covered by keyboard
- [ ] App works on tablets (3-4 columns)
- [ ] App works on small phones (320px width)

---

## Metrics to Track

- **User Satisfaction**: Subjective "app feels awesome" metric
- **Task Completion Rate**: % of users who successfully upload/download scripts
- **Error Rate**: Number of validation errors per user action
- **Navigation Confusion**: Bounce rate between screens
- **Performance**: Frame rate during tab switches and scrolling

---

## Notes

- All file paths are relative to `/home/sat/projects/icp-cc/`
- Line numbers may shift as fixes are implemented
- Test on multiple screen sizes: 320px (iPhone SE), 375px (iPhone), 768px (iPad), 1024px+ (desktop)
- Ensure all fixes maintain existing functionality
- Follow DRY, YAGNI, TDD principles from AGENTS.md

---

**Next Steps**: Implement Sprint 1 critical fixes first, then move to Sprint 2 high-priority UX improvements.
