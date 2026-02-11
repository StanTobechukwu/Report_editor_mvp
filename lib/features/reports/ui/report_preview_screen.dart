import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../domain/pdf/pdf_plan.dart';
import '../domain/models/letterhead_template.dart';
import '../providers/report_editor_provider.dart';
import '../services/pdf_renderer_service.dart';
import '../data/letterhead_repository.dart';
import '../ui/letterhead_editor_screen.dart';
import '../ui/manage_letterhead.screen.dart';

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key});
  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final _renderer = PdfRendererService();
  bool _saving = false;

  // Build the PDF bytes from the provider state.
  Future<Uint8List> _buildBytes() async {
    final vm = context.read<ReportEditorProvider>();
    final plan = buildPdfPlan(vm.doc);
    final repo = context.read<LetterheadsRepository>();

    LetterheadTemplate? letterhead;
    if (vm.doc.applyLetterhead && vm.doc.letterheadId != null) {
      letterhead = await repo.loadLetterhead(vm.doc.letterheadId!);
    }

    return _renderer.generatePdfBytes(
      doc: vm.doc,
      plan: plan,
      letterhead: letterhead,
    );
  }

  // Save the generated PDF to local storage.
  Future<File> _savePdfToLocal(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/saved_pdfs');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final file = File('${folder.path}/report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _onSavePressed() async {
    if (_saving) return;
    final vm = context.read<ReportEditorProvider>();
    setState(() => _saving = true);

    try {
      await vm.save();
      final bytes = await _buildBytes();
      final file = await _savePdfToLocal(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: ${file.path.split('/').last}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Opens the letterhead selector.
  Future<void> _openLetterheadSheet() async {
    final vm = context.read<ReportEditorProvider>();
    final repo = context.read<LetterheadsRepository>();
    final templates = await repo.loadAll();
    if (!mounted) return;

    const addToken = '__add__';
    const manageToken = '__manage__';

    final result = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 12),
          children: [
            const SizedBox(height: 12),
            const Center(child: Text('Select Letterhead', style: TextStyle(fontWeight: FontWeight.bold))),
            const Divider(),
            // "None" option:
            ListTile(
              leading: Radio<String?>(value: null, groupValue: vm.doc.letterheadId, onChanged: (_) {}),
              title: const Text('None'),
              onTap: () => Navigator.pop(sheetContext, null),
            ),
            // Existing templates:
            ...templates.map((t) => ListTile(
                  leading: Radio<String?>(value: t.letterheadId, groupValue: vm.doc.letterheadId, onChanged: (_) {}),
                  title: Text(t.name),
                  onTap: () => Navigator.pop(sheetContext, t.letterheadId),
                )),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add new letterhead'),
              onTap: () => Navigator.pop(sheetContext, addToken),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Manage letterheads'),
              onTap: () => Navigator.pop(sheetContext, manageToken),
            ),
          ],
        ),
      ),
    );

    if (!mounted) return;

    if (result == addToken) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LetterheadEditorScreen(letterheadId: null)),
      );
      return;
    }

    if (result == manageToken) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ManageLetterheadsScreen()),
      );
      return;
    }

    // Update provider only after the sheet has closed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) vm.setLetterhead(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder ensures PdfPreview gets bounded constraints.
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
          IconButton(
            tooltip: 'Letterhead',
            icon: const Icon(Icons.view_headline_outlined),
            onPressed: _openLetterheadSheet,
          ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : _onSavePressed,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints.tightFor(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
            ),
            child: PdfPreview(
              build: (_) => _buildBytes(),
              allowPrinting: true,
              allowSharing: true,
            ),
          );
        },
      ),
    );
  }
}
