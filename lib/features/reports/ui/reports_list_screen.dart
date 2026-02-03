import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/reports_repository.dart';
import '../providers/report_editor_provider.dart';
import '../providers/reports_list_provider.dart';
import 'report_editor_screen.dart';
import 'template_list_screen.dart';


class ReportsListScreen extends StatelessWidget {
  const ReportsListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final listVm = context.watch<ReportsListProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => listVm.refresh(),
          ),IconButton(
  icon: const Icon(Icons.view_list_outlined),
  tooltip: 'Templates',
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TemplatesListScreen()),
    );
  },
),

        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.read<ReportEditorProvider>().newReport();
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
        },
        icon: const Icon(Icons.add),
        label: const Text('New Report'),
      ),
      body: Builder(
        builder: (_) {
          if (listVm.loading) return const Center(child: CircularProgressIndicator());
          if (listVm.reports.isEmpty) {
            return const Center(child: Text('No saved reports yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: listVm.reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final r = listVm.reports[i];
              return Card(
                child: ListTile(
                  title: Text(r.title),
                  subtitle: Text('Updated: ${r.updatedAt}'),
                  onTap: () async {
                    await context.read<ReportEditorProvider>().loadById(r.reportId);
                    // ignore: use_build_context_synchronously
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportEditorScreen()));
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => listVm.delete(r.reportId),
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
