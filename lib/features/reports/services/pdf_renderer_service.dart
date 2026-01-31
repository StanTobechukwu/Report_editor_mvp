import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_plan.dart';

class PdfRendererService {
  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
  }) async {
    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    final fullText = _flatten(doc.roots);

    final (firstPageText, remainingText) = _splitForFirstPage(
      fullText,
      inlineEnabled: doc.placementChoice == ImagePlacementChoice.inlinePage1,
    );

    final inlineImgs = await _loadImages(
      plan.page1InlineImages.map((e) => e.filePath).toList(),
    );

    final attachmentImgs = await _loadImages(
      plan.attachmentPages.expand((p) => p.images).map((e) => e.filePath).toList(),
    );

    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);

    final pdf = pw.Document();

    final hasAttachments = attachmentImgs.isNotEmpty;
    final hasRemainingText = remainingText.trim().isNotEmpty;

    final canPlaceSignatureOnPage1 = !hasAttachments && !hasRemainingText;

    // ---------------- Page 1 ----------------
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                'Report',
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),

              if (doc.subjectInfoDef.enabled) ...[
                _subjectInfoBlock(doc),
                pw.SizedBox(height: 12),
              ],

              // Main body (text + optional inline images)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: doc.placementChoice == ImagePlacementChoice.inlinePage1
                    ? pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Expanded(child: _textBlock(firstPageText)),
                          pw.SizedBox(width: 12),
                          pw.SizedBox(width: 160, child: _inlineColumn(inlineImgs)),
                        ],
                      )
                    : _textBlock(firstPageText),
              ),

              if (canPlaceSignatureOnPage1) ...[
                pw.SizedBox(height: 16),
                _signatureBlock(doc, signatureImg),
              ],
            ],
          );
        },
      ),
    );

    // ----------- Attachment pages (8 per page) -----------
    if (attachmentImgs.isNotEmpty) {
      final chunks = _chunk(attachmentImgs, 8);
      for (final chunk in chunks) {
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  'Image Attachments',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 12),
                _attachmentsGrid(chunk),
              ],
            ),
          ),
        );
      }
    }

    // ----------- Final page: spilled text + mandatory signature block -----------
    if (!canPlaceSignatureOnPage1) {
      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => [
            if (hasRemainingText) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(12),
                ),
                child: _textBlock(remainingText),
              ),
              pw.SizedBox(height: 16),
            ],
            _signatureBlock(doc, signatureImg),
          ],
        ),
      );
    }

    return pdf.save();
  }

  // ---------------- Subject Info (schema + values) ----------------

  pw.Widget _subjectInfoBlock(ReportDoc doc) {
    final def = doc.subjectInfoDef;
    final fields = def.orderedFields;

    if (fields.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          '(No subject info fields)',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }

    pw.Widget fieldRow(String label, String value) {
      final v = value.trim().isEmpty ? '-' : value.trim();

      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 120,
              child: pw.Text(
                label,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey800,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                v,
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    pw.Widget body;
    if (def.columns == 2) {
      // Two columns: split fields into pairs
      final items = fields
          .map((f) => (f.title, doc.subjectInfo.valueOf(f.key)))
          .toList();

      final rows = <pw.Widget>[];
      for (int i = 0; i < items.length; i += 2) {
        final left = items[i];
        final right = (i + 1 < items.length) ? items[i + 1] : null;

        rows.add(
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: fieldRow(left.$1, left.$2)),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: right == null
                    ? pw.SizedBox()
                    : fieldRow(right.$1, right.$2),
              ),
            ],
          ),
        );
      }
      body = pw.Column(children: rows);
    } else {
      body = pw.Column(
        children: fields
            .map((f) => fieldRow(f.title, doc.subjectInfo.valueOf(f.key)))
            .toList(),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(12),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Subject Info',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  // ---------------- Signature ----------------

  pw.Widget _signatureBlock(ReportDoc doc, pw.MemoryImage? signature) {
    final role = doc.signature.roleTitle.trim().isEmpty ? 'Reporter' : doc.signature.roleTitle.trim();
    final name = doc.signature.name.trim();
    final creds = doc.signature.credentials.trim();

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            role,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          if (name.isNotEmpty) pw.Text(name),
          if (creds.isNotEmpty) pw.Text(creds),
          pw.SizedBox(height: 10),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Signature:',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Container(
                  height: 60,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  alignment: pw.Alignment.centerLeft,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8),
                  child: signature == null
                      ? pw.Text(
                          '(not provided)',
                          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        )
                      : pw.Image(signature, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- UI blocks ----------------

  pw.Widget _textBlock(String text) => pw.Text(
        text.trim().isEmpty ? '(no content)' : text.trim(),
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
      );

  pw.Widget _inlineColumn(List<pw.MemoryImage> images) {
    if (images.isEmpty) {
      return pw.Container(
        height: 240,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          '(no inline images)',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
        ),
      );
    }

    return pw.Column(
      children: images.map((img) {
        return pw.Container(
          height: 70,
          margin: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 12,
            verticalRadius: 12,
            child: pw.Image(img, fit: pw.BoxFit.cover),
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _attachmentsGrid(List<pw.MemoryImage> images) {
    if (images.isEmpty) return pw.SizedBox();

    if (images.length == 1) {
      final img = images.first;
      return pw.Center(
        child: pw.Container(
          height: 360,
          width: 360,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 16,
            verticalRadius: 16,
            child: pw.Image(img, fit: pw.BoxFit.cover),
          ),
        ),
      );
    }

    return pw.GridView(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: images.map((img) {
        return pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(16),
          ),
          child: pw.ClipRRect(
            horizontalRadius: 16,
            verticalRadius: 16,
            child: pw.Image(img, fit: pw.BoxFit.cover),
          ),
        );
      }).toList(),
    );
  }

  // ---------------- helpers ----------------

  String _flatten(List<SectionNode> roots) {
    final b = StringBuffer();

    void walk(List<Node> nodes, int depth) {
      for (final n in nodes) {
        if (n is SectionNode) {
          final extra = _nodeIndent(n);
          final pad = '  ' * (depth + extra);
          final title = n.title.trim();
          if (title.isNotEmpty) {
            b.writeln('$pad$title');
          }
          walk(n.children, depth + 1);
          b.writeln();
        } else if (n is ContentNode) {
          final t = n.text.trim();
          if (t.isEmpty) continue;

          final extra = _nodeIndent(n);
          final pad = '  ' * (depth + extra);
          b.writeln('$pad$t');
        }
      }
    }

    walk(roots, 0);
    return b.toString().trim();
  }

  int _nodeIndent(Node n) {
    if (n is SectionNode) return n.indent;
    if (n is ContentNode) return n.indent;
    return 0;
  }

  (String, String) _splitForFirstPage(
    String text, {
    required bool inlineEnabled,
  }) {
    if (text.trim().isEmpty) return ('', '');

    final approxChars = inlineEnabled ? 900 : 1400;
    if (text.length <= approxChars) return (text, '');

    final cut = text.lastIndexOf('\n', approxChars);
    final idx = cut > 200 ? cut : approxChars;

    return (
      text.substring(0, idx).trim(),
      text.substring(idx).trim(),
    );
  }

  Future<List<pw.MemoryImage>> _loadImages(List<String> paths) async {
    final out = <pw.MemoryImage>[];
    for (final p in paths) {
      final img = await _loadSingle(p);
      if (img != null) out.add(img);
    }
    return out;
  }

  Future<pw.MemoryImage?> _loadSingle(String? path) async {
    if (path == null || path.isEmpty) return null;
    final f = File(path);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;
    return pw.MemoryImage(bytes);
  }

  List<List<T>> _chunk<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(items.sublist(i, (i + size).clamp(0, items.length)));
    }
    return chunks;
  }
}
