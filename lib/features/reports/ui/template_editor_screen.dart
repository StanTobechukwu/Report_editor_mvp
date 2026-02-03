import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/templates_repository.dart';
import '../domain/models/template_doc.dart';
import '../providers/template_editor_provider.dart';

class TemplateEditorScreen extends StatelessWidget {
  final String templateId;
  const TemplateEditorScreen({super.key, required this.templateId});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<TemplatesRepository>();

    return FutureBuilder<TemplateDoc>(
      future: repo.loadTemplate(templateId),
      builder: (context, snap) {
        if (!snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: const Text('Template Editor')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        return ChangeNotifierProvider(
          create: (_) => TemplateEditorProvider(snap.data!),
          child: const _TemplateEditorBody(),
        );
      },
    );
  }
}

class _TemplateEditorBody extends StatelessWidget {
  const _TemplateEditorBody();

  Future<String?> _askTemplateName(BuildContext context, String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Template name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(hintText: 'e.g., Upper GI Template'),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<bool?> _askSaveMode(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Save template as'),
        content: const Text(
          'Choose whether to save just the structure, or include default text content.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Structure only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Include content'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final repo = context.read<TemplatesRepository>();
    final vm = context.read<TemplateEditorProvider>();

    final name = await _askTemplateName(context, vm.template.name);
    if (name == null) return;

    final includeContent = await _askSaveMode(context);
    if (includeContent == null) return;

    final doc = vm.buildForSave(name: name, includeContent: includeContent);
    await repo.saveTemplate(doc);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Template saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<TemplateEditorProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(vm.template.name),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: () => _save(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Subject Info', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: vm.subjectInfo.enabled,
                    onChanged: vm.toggleSubjectInfo,
                    title: const Text('Enabled'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Columns:'),
                      const SizedBox(width: 12),
                      SegmentedButton<int>(
                        segments: const [
                          ButtonSegment(value: 1, label: Text('1')),
                          ButtonSegment(value: 2, label: Text('2')),
                        ],
                        selected: {vm.subjectInfo.columns},
                        onSelectionChanged: (s) => vm.setSubjectInfoColumns(s.first),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const Text('Fields', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  ...vm.subjectInfo.orderedFields.map(
                    (f) => ListTile(
                      title: Text(f.title),
                      subtitle: Text(f.key),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: f.required,
                            onChanged: (v) => vm.toggleRequired(f.key, v ?? false),
                          ),
                          if (!f.isSystem)
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => vm.removeField(f.key),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => vm.addCustomField(title: 'Custom Field', required: false),
                    icon: const Icon(Icons.add),
                    label: const Text('Add field'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
