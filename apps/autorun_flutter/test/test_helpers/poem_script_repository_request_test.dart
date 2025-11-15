import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icp_autorun/models/script_record.dart';

import 'poem_script_repository.dart';

void main() {
  group('PoemScriptRepository request payloads', () {
    test('saveScript sends action=update when script exists', () async {
      final script = ScriptRecord(
        id: 'existing-script',
        title: 'Updated Title',
        luaSource: '-- updated',
        metadata: const {
          'description': 'Updated description',
          'category': 'Utility',
          'tags': ['updated', 'modified'],
          'version': '2.0.0',
          'price': 1.0,
          'isPublic': true,
        },
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      late Map<String, dynamic> capturedPayload;

      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path.contains('/api/v1/scripts/')) {
          return http.Response('{"success": true, "data": {}}', 200);
        }

        if (request.method == 'PUT' && request.url.path.contains('/api/v1/scripts/')) {
          capturedPayload = json.decode(request.body) as Map<String, dynamic>;
          return http.Response('{"success": true, "data": {"id": "${script.id}"}}', 200);
        }

        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final repository = PoemScriptRepository(
        baseUrl: 'http://localhost',
        client: client,
      );

      await repository.saveScript(script);

      expect(capturedPayload['action'], equals('update'));
      expect(capturedPayload['signature'], isNotEmpty);
      expect(capturedPayload['author_principal'], isNotEmpty);
      expect(capturedPayload['author_public_key'], isNotEmpty);
      expect(capturedPayload['timestamp'], isNotEmpty);
      expect(capturedPayload['script_id'], equals(script.id));
      expect(capturedPayload['tags'], equals(['modified', 'updated']));

      repository.dispose();
    });

    test('deleteScript sends action=delete', () async {
      late Map<String, dynamic> capturedPayload;

      final client = MockClient((request) async {
        if (request.method == 'DELETE' && request.url.path.contains('/api/v1/scripts/')) {
          capturedPayload = json.decode(request.body) as Map<String, dynamic>;
          return http.Response('{"success": true}', 200);
        }

        fail('Unexpected request: ${request.method} ${request.url}');
      });

      final repository = PoemScriptRepository(
        baseUrl: 'http://localhost',
        client: client,
      );

      await repository.deleteScript('delete-id');

      expect(capturedPayload['action'], equals('delete'));
      expect(capturedPayload['signature'], isNotEmpty);
      expect(capturedPayload['author_principal'], isNotEmpty);
      expect(capturedPayload['author_public_key'], isNotEmpty);
      expect(capturedPayload['timestamp'], isNotEmpty);

      repository.dispose();
    });
  });
}
