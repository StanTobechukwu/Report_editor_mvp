import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/templates_repository.dart';
import '../providers/template_list_provider.dart';
import '../providers/report_editor_provider.dart';
import 'report_editor_screen.dart';
import 'template_editor_screen.dart';

class TemplatesListScreen extends StatelessWidget {
  const TemplatesListScreen({super.key});

  Future<_TemplateOpenChoice?> _askOpenChoice(BuildContext context) {
    return showDialog<_TemplateOpenChoice>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Open template'),
        content: const Text('How do you want to use this template?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _TemplateOpenChoice.fillReport),
            child: const Text('Fill as report'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, _TemplateOpenChoice.editTemplate),
            child: const Text('Edit template'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<TemplateListProvider>();
    final repo = context.read<TemplatesRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => listVm.load(),
          ),
        ],
      ),
      body: Builder(
        builder: (_) {
          if (listVm.loading) return const Center(child: CircularProgressIndicator());
          if (listVm.templates.isEmpty) {
            return const Center(child: Text('No templates yet. Create one from the Report Editor.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: listVm.templates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final t = listVm.templates[i];
              return Card(
                child: ListTile(
                  title: Text(t.name),
                  subtitle: Text('Updated: ${t.updatedAt}'),
                  onTap: () async {
                    final choice = await _askOpenChoice(context);
                    if (choice == null) return;

                    if (choice == _TemplateOpenChoice.fillReport) {
                      final template = await repo.loadTemplate(t.templateId);
                      context.read<ReportEditorProvider>().newReportFromTemplate(template);
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportEditorScreen()),
                      );
                      return;
                    }

                    if (!context.mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TemplateEditorScreen(templateId: t.templateId),
                      ),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => listVm.delete(t.templateId),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

enum _TemplateOpenChoice { fillReport, editTemplate }
