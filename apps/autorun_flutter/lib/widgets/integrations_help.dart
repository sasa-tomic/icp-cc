import 'package:flutter/material.dart';

import '../services/script_runner.dart';

class IntegrationsHelpDialog extends StatelessWidget {
  const IntegrationsHelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Available integrations'),
      content: SizedBox(
        width: 600,
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: ScriptRunner.integrationCatalog.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final info = ScriptRunner.integrationCatalog[index];
            return ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${info.id} — ${info.title}'),
              subtitle: Text(info.description),
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Lua example:',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  info.example,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
