import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../domain/pdf/pdf_plan.dart';
import '../providers/report_editor_provider.dart';
import '../services/pdf_renderer_service.dart';

import '../data/letterhead_repository.dart';
//import '../ui/letterhead_selector_sheet.dart';
import '../ui/letterhead_editor_screen.dart';

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key});

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final _renderer = PdfRendererService();
  //Uint8List? _lastBytes;
  bool _saving = false;

  Future<Uint8List> _buildBytes(ReportEditorProvider vm) async {
    final plan = buildPdfPlan(vm.doc);
    final bytes = await _renderer.generatePdfBytes(doc: vm.doc, plan: plan);
   // _lastBytes = bytes;
    return bytes;
  }

  Future<File> _savePdfToLocal({
    required Uint8List bytes,
    required String fileBaseName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();

    final pdfDir = Directory('${dir.path}/saved_pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    final safeBase = fileBaseName.replaceAll(RegExp(r'[^\w\-]+'), '_');

    final file = File('${pdfDir.path}/$safeBase.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
Future<void> _onSavePressed(
  BuildContext context,
  ReportEditorProvider vm,
) async {
  if (_saving) return;

  setState(() => _saving = true);

  try {
    // save editable doc
    await vm.save();

    // ALWAYS regenerate PDF (no cache)
    final bytes = await _buildBytes(vm);

    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = await _savePdfToLocal(
      bytes: bytes,
      fileBaseName: 'report_$ts',
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('PDF saved: ${file.path.split('/').last}')),
    );
  } finally {
    if (mounted) setState(() => _saving = false);
  }
}


  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportEditorProvider>();
    final letterheadsRepo = context.read<LetterheadsRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
        IconButton(
  tooltip: 'Letterhead',
  icon: const Icon(Icons.view_headline_outlined),
  onPressed: () async {
    try {
      final repo = context.read<LetterheadsRepository>();
      final templates = await repo.loadAll();

      if (!mounted) return;

      const noneToken = '__none__';

      final result = await showModalBottomSheet<String?>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const Text(
                  'Select Letterhead',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Divider(),

                // NONE
                RadioListTile<String?>(
                  value: noneToken,
                  groupValue: (vm.doc.letterheadId ?? noneToken),
                  title: const Text('None'),
                  onChanged: (v) => Navigator.pop(sheetContext, v),
                ),

                // EXISTING
                ...templates.map(
                  (t) => RadioListTile<String?>(
                    value: t.letterheadId,
                    groupValue: (vm.doc.letterheadId ?? noneToken),
                    title: Text(t.name),
                    onChanged: (v) => Navigator.pop(sheetContext, v),
                  ),
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add new letterhead'),
                  onTap: () => Navigator.pop(sheetContext, '__add__'),
                ),

                ListTile(
                  leading: const Icon(Icons.edit),
                  title: const Text('Manage letterheads'),
                  onTap: () => Navigator.pop(sheetContext, '__manage__'),
                ),

                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );

      // User dismissed the bottom sheet (tapped outside / swiped down)
      if (result == null) return;

      if (result == '__add__' || result == '__manage__') {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LetterheadEditorScreen(letterheadId: null),
          ),
        );
        return;
      }

      // Apply selection
      if (result == noneToken) {
        vm.setLetterhead(null);
      } else {
        vm.setLetterhead(result);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Letterhead error: $e')),
      );
    }
  },
),

          IconButton(
            tooltip: 'Save PDF',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            onPressed: _saving ? null : () => _onSavePressed(context, vm),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => _buildBytes(vm),
        allowPrinting: true,
        allowSharing: true,
        canChangePageFormat: false,
        canChangeOrientation: false,
      ),
    );
  }
}
