import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../domain/pdf/pdf_plan.dart';
import '../providers/report_editor_provider.dart';
import '../services/pdf_renderer_service.dart';

class ReportPreviewScreen extends StatefulWidget {
  const ReportPreviewScreen({super.key});

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  final _renderer = PdfRendererService();
  Uint8List? _lastBytes;
  bool _saving = false;

  Future<Uint8List> _buildBytes(ReportEditorProvider vm) async {
    final plan = buildPdfPlan(vm.doc);
    final bytes = await _renderer.generatePdfBytes(doc: vm.doc, plan: plan);
    _lastBytes = bytes;
    return bytes;
  }

  Future<File> _savePdfToLocal({
    required Uint8List bytes,
    required String fileBaseName,
  }) async {
    final dir = await getApplicationDocumentsDirectory();

    // Folder for your PDFs
    final pdfDir = Directory('${dir.path}/saved_pdfs');
    if (!await pdfDir.exists()) {
      await pdfDir.create(recursive: true);
    }

    // Ensure filename is safe
    final safeBase = fileBaseName.replaceAll(RegExp(r'[^\w\-]+'), '_');

    final file = File('${pdfDir.path}/$safeBase.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _onSavePressed(BuildContext context, ReportEditorProvider vm) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // 1) Save editable ReportDoc (your existing logic)
      await vm.save();

      // 2) Generate PDF bytes (cached if available)
      final bytes = _lastBytes ?? await _buildBytes(vm);

      // 3) Build a file name
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final fileBaseName = 'report_$ts';

      // 4) Save to local file
      final file = await _savePdfToLocal(bytes: bytes, fileBaseName: fileBaseName);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved: ${file.path.split('/').last}'),
          action: SnackBarAction(
            label: 'Share',
            onPressed: () {
              Printing.sharePdf(
                bytes: bytes,
                filename: file.path.split('/').last,
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ReportEditorProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview'),
        actions: [
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

