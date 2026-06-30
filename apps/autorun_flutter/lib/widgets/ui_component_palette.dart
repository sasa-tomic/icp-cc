import 'package:flutter/material.dart';

enum UiComponentCategory { layout, text, input, display }

class UiComponent {
  const UiComponent({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.icon,
    required this.template,
  });

  final String id;
  final String name;
  final String description;
  final UiComponentCategory category;
  final IconData icon;
  final String template;
}

class UiComponentPalette {
  static const List<UiComponent> components = [
    UiComponent(
      id: 'column',
      name: 'Column',
      description: 'Vertical layout container',
      category: UiComponentCategory.layout,
      icon: Icons.view_column_rounded,
      template: '''{
  type: "column",
  children: [
    // Add child widgets here
  ]
}''',
    ),
    UiComponent(
      id: 'row',
      name: 'Row',
      description: 'Horizontal layout container',
      category: UiComponentCategory.layout,
      icon: Icons.view_stream_rounded,
      template: '''{
  type: "row",
  children: [
    // Add child widgets here
  ]
}''',
    ),
    UiComponent(
      id: 'section',
      name: 'Section',
      description: 'Card container with optional title',
      category: UiComponentCategory.layout,
      icon: Icons.crop_portrait_rounded,
      template: '''{
  type: "section",
  props: {
    title: "Section Title"
  },
  children: [
    // Add child widgets here
  ]
}''',
    ),
    UiComponent(
      id: 'text',
      name: 'Text',
      description: 'Display text with optional copy button',
      category: UiComponentCategory.text,
      icon: Icons.text_fields_rounded,
      template: '''{
  type: "text",
  props: {
    text: "Your text here",
    copy: false,
    copy_label: "Copy",
    copy_value: "value_to_copy"
  }
}''',
    ),
    UiComponent(
      id: 'button',
      name: 'Button',
      description: 'Clickable button with handler',
      category: UiComponentCategory.text,
      icon: Icons.smart_button_rounded,
      template: '''{
  type: "button",
  props: {
    label: "Click Me",
    disabled: false,
    on_press: {
      action: "handle_click",
      data: "optional_payload"
    }
  }
}''',
    ),
    UiComponent(
      id: 'text_field',
      name: 'Text Field',
      description: 'Text input with label and placeholder',
      category: UiComponentCategory.input,
      icon: Icons.input_rounded,
      template: '''{
  type: "text_field",
  props: {
    label: "Input Label",
    placeholder: "Enter text...",
    value: "",
    enabled: true,
    obscure: false,
    keyboard_type: "text",
    on_change: {
      action: "handle_input",
      field: "input_name"
    }
  }
}''',
    ),
    UiComponent(
      id: 'toggle',
      name: 'Toggle',
      description: 'Boolean switch with label',
      category: UiComponentCategory.input,
      icon: Icons.toggle_on_rounded,
      template: '''{
  type: "toggle",
  props: {
    label: "Enable feature",
    value: false,
    enabled: true,
    on_change: {
      action: "handle_toggle",
      field: "toggle_name"
    }
  }
}''',
    ),
    UiComponent(
      id: 'select',
      name: 'Select',
      description: 'Dropdown selection from options',
      category: UiComponentCategory.input,
      icon: Icons.arrow_drop_down_circle_rounded,
      template: '''{
  type: "select",
  props: {
    label: "Choose option",
    value: "",
    enabled: true,
    options: [
      { label: "Option 1", value: "opt1" },
      { label: "Option 2", value: "opt2" }
    ],
    on_change: {
      action: "handle_select",
      field: "select_name"
    }
  }
}''',
    ),
    UiComponent(
      id: 'list',
      name: 'List',
      description: 'Scrollable list of items',
      category: UiComponentCategory.display,
      icon: Icons.list_rounded,
      template: '''{
  type: "list",
  props: {
    title: "List Title",
    searchable: false,
    items: [
      { title: "Item 1", subtitle: "Description 1" },
      { title: "Item 2", subtitle: "Description 2" }
    ]
  }
}''',
    ),
    UiComponent(
      id: 'table',
      name: 'Table',
      description: 'Data table with columns and rows',
      category: UiComponentCategory.display,
      icon: Icons.table_chart_rounded,
      template: '''{
  type: "table",
  props: {
    title: "Table Title",
    columns: [
      { key: "col1", label: "Column 1" },
      { key: "col2", label: "Column 2" }
    ],
    rows: [
      { col1: "Row 1 Cell 1", col2: "Row 1 Cell 2" },
      { col1: "Row 2 Cell 1", col2: "Row 2 Cell 2" }
    ]
  }
}''',
    ),
    UiComponent(
      id: 'image',
      name: 'Image',
      description: 'Display image from URL or local',
      category: UiComponentCategory.display,
      icon: Icons.image_rounded,
      template: '''{
  type: "image",
  props: {
    src: "https://example.com/image.png",
    width: 200,
    height: 150,
    fit: "cover"
  }
}''',
    ),
    UiComponent(
      id: 'result_display',
      name: 'Result Display',
      description: 'Expandable result container',
      category: UiComponentCategory.display,
      icon: Icons.expand_rounded,
      template: '''{
  type: "result_display",
  props: {
    title: "Result",
    expandable: true,
    expanded: false,
    data: { key: "value" }
  }
}''',
    ),
  ];

  static List<UiComponent> byCategory(UiComponentCategory category) {
    return components.where((c) => c.category == category).toList();
  }

  static String categoryLabel(UiComponentCategory category) {
    switch (category) {
      case UiComponentCategory.layout:
        return 'Layout';
      case UiComponentCategory.text:
        return 'Text';
      case UiComponentCategory.input:
        return 'Input';
      case UiComponentCategory.display:
        return 'Display';
    }
  }
}

Future<String?> showUiComponentPalette({
  required BuildContext context,
}) {
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext context) => const _UiComponentPaletteSheet(),
  );
}

class _UiComponentPaletteSheet extends StatefulWidget {
  const _UiComponentPaletteSheet();

  @override
  State<_UiComponentPaletteSheet> createState() => _UiComponentPaletteSheetState();
}

class _UiComponentPaletteSheetState extends State<_UiComponentPaletteSheet> {
  UiComponentCategory _selectedCategory = UiComponentCategory.layout;

  @override
  Widget build(BuildContext context) {
    final components = UiComponentPalette.byCategory(_selectedCategory);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.widgets_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'UI Components',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to insert TypeScript snippet at cursor position',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<UiComponentCategory>(
              segments: UiComponentCategory.values.map((cat) {
                return ButtonSegment(
                  value: cat,
                  label: Text(UiComponentPalette.categoryLabel(cat)),
                );
              }).toList(),
              selected: {_selectedCategory},
              onSelectionChanged: (Set<UiComponentCategory> selection) {
                setState(() => _selectedCategory = selection.first);
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: components.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final component = components[index];
                  return _ComponentTile(
                    component: component,
                    onTap: () => Navigator.of(context).pop(component.template),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentTile extends StatelessWidget {
  const _ComponentTile({
    required this.component,
    required this.onTap,
  });

  final UiComponent component;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            component.icon,
            size: 20,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          component.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          component.description,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.add_circle_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
