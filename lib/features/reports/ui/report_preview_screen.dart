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

  // ================= BUILD PDF =================
  Future<Uint8List> _buildBytes(ReportEditorProvider vm) async {
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

  // ================= SAVE LOCAL =================
  Future<File> _savePdfToLocal(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();

    final folder = Directory('${dir.path}/saved_pdfs');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${folder.path}/report_$ts.pdf');

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
      await vm.save();

      final bytes = await _buildBytes(vm);
      final file = await _savePdfToLocal(bytes);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: ${file.path.split('/').last}')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportEditorProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
          // -------- Letterhead selector --------
          IconButton(
  tooltip: 'Letterhead',
  icon: const Icon(Icons.view_headline_outlined),
  onPressed: () async {
    final repo = context.read<LetterheadsRepository>();
    final templates = await repo.loadAll();

    if (!context.mounted) return;

    //const noneToken = '__none__';
    const addToken = '__add__';
    const manageToken = '__manage__';

    final result = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const Text(
              'Select Letterhead',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Divider(),

           RadioGroup<String?>(
  groupValue: vm.doc.letterheadId,
  onChanged: (v) => Navigator.pop(sheetContext, v),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const RadioListTile<String?>(
        value: null,
        title: Text('None'),
      ),
      ...templates.map(
        (t) => RadioListTile<String?>(
          value: t.letterheadId,
          title: Text(t.name),
        ),
      ),
    ],
  ),
),

            const Divider(),

            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add new letterhead'),
              onTap: () => Navigator.pop(sheetContext, addToken), // ✅
            ),

            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Manage letterheads'),
              onTap: () => Navigator.pop(sheetContext, manageToken), // ✅
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    //if (result == null) return;

    

   if (result == addToken) {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const LetterheadEditorScreen(letterheadId: null),
    ),
  );
  return;
}

if (result == manageToken) {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const ManageLetterheadsScreen(),
    ),
  );
  return;
}

// ✅ ALWAYS APPLY (including null = None)
vm.setLetterhead(result);

    }
  
),


          // -------- Save button --------
          IconButton(
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
     body: SizedBox.expand(
  child: PdfPreview(
    build: (_) => _buildBytes(vm),
    allowPrinting: true,
    allowSharing: true,
  ),
),

    );
  }
}
