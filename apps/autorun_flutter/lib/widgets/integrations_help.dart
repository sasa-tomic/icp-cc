import 'package:flutter/material.dart';

import '../services/script_runner.dart';
import 'canister_call_builder.dart';

class IntegrationsHelpDialog extends StatelessWidget {
  const IntegrationsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Available integrations'),
      content: SizedBox(
        width: 600,
        child: ListView(
          shrinkWrap: true,
          children: [
            // Canister Call Builder button
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.build_circle_outlined),
              title: const Text('Canister Call Builder'),
              subtitle: const Text('Build canister method calls with a visual interface'),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () async {
                final String? luaCode = await showDialog<String>(
                  context: context,
                  builder: (_) => const CanisterCallBuilderDialog(),
                );
                if (luaCode != null && luaCode.isNotEmpty && context.mounted) {
                  // Return the generated Lua code
                  Navigator.of(context).pop(luaCode);
                }
              },
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              'Lua Helper Functions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Existing integrations
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ScriptRunner.integrationCatalog.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                final info = ScriptRunner.integrationCatalog[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${info.id} — ${info.title}'),
                  subtitle: Text(info.description),
                  onTap: () => Navigator.of(context).pop(info.example),
                );
              },
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
