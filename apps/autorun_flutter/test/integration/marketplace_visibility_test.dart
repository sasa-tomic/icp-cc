import 'package:flutter_test/flutter_test.dart';
import 'package:icp_autorun/models/marketplace_script.dart';
import 'package:icp_autorun/models/script_record.dart';
import 'package:icp_autorun/services/marketplace_open_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/api_service_manager.dart';
import '../test_helpers/poem_script_repository.dart';
import '../test_helpers/unified_test_builder.dart';

void main() {
  group('Marketplace visibility end-to-end', () {
    late PoemScriptRepository poemRepository;
    late MarketplaceOpenApiService marketplaceService;
    String? createdScriptId;

    setUpAll(() async {
      suppressDebugOutput = true;
      SharedPreferences.setMockInitialValues({});
      await ApiServiceManager.initialize();
    });

    setUp(() {
      poemRepository = PoemScriptRepository();
      marketplaceService = MarketplaceOpenApiService();
      createdScriptId = null;
    });

    tearDown(() async {
      if (createdScriptId != null) {
        await poemRepository.deleteScript(createdScriptId!);
      }
      poemRepository.dispose();
    });

    test('uploaded script appears in marketplace search results', () async {
      final uniqueSuffix = DateTime.now().millisecondsSinceEpoch;
      final ScriptRecord script = TestTemplates.createTestScriptWithSignature(
        id: 'marketplace-visibility-$uniqueSuffix',
        title: 'Marketplace Visibility Test $uniqueSuffix',
        description: 'Ensures uploaded scripts surface in marketplace search results',
        category: 'Integration',
        tags: ['visibility', 'integration', 'ui'],
        luaSource: '''
function init(arg)
  return { counter = 0, test_suffix = $uniqueSuffix }, {}
end

function view(state)
  return {
    type = "text",
    props = { text = "Marketplace visibility $uniqueSuffix" }
  }
end

function update(msg, state)
  if msg.type == "increment" then
    state.counter = state.counter + 1
  end
  return state, {}
end
''',
      );

      createdScriptId = await poemRepository.saveScript(script);
      expect(createdScriptId, isNotEmpty, reason: 'API must return a script id after upload');

      final int maxAttempts = 5;
      MarketplaceScript? discoveredScript;

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        final result = await marketplaceService.searchScripts(
          query: script.title,
          sortBy: 'createdAt',
          sortOrder: 'desc',
          limit: 10,
          offset: 0,
        );

        final matches = result.scripts.where((s) => s.id == createdScriptId).toList();
        if (matches.isNotEmpty) {
          discoveredScript = matches.first;
          break;
        }

        // Allow a short delay for eventual consistency in the API layer
        await Future.delayed(const Duration(seconds: 2));
      }

      expect(
        discoveredScript,
        isNotNull,
        reason: 'Uploaded script must be discoverable via marketplace search',
      );

      expect(discoveredScript!.title, equals(script.title));
      expect(discoveredScript.tags, containsAll(<String>['visibility', 'integration', 'ui']));
      expect(discoveredScript.isPublic, isTrue);
    });
  });
}
