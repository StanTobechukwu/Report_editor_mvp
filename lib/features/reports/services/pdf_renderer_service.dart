import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/models/letterhead_template.dart';
import '../domain/models/nodes.dart';
import '../domain/models/report_doc.dart';
import '../domain/pdf/pdf_plan.dart';

class PdfRendererService {
  Future<Uint8List> generatePdfBytes({
    required ReportDoc doc,
    required PdfPlan plan,
    LetterheadTemplate? letterhead,
  }) async {
    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
    );

    // ---------- Text ----------
    final fullText = _flatten(doc.roots);

    final (firstPageText, remainingText) = _splitForFirstPage(
      fullText,
      inlineEnabled: doc.placementChoice == ImagePlacementChoice.inlinePage1,
    );

    // ---------- Images ----------
    final inlineImgs = await _loadImages(
      plan.page1InlineImages.map((e) => e.filePath).toList(),
    );

    final attachmentImgs = await _loadImages(
      plan.attachmentPages.expand((p) => p.images).map((e) => e.filePath).toList(),
    );

    // ---------- Signature ----------
    final signatureImg = await _loadSingle(doc.signature.signatureFilePath);

    // ---------- Letterhead logo (load ONCE) ----------
    pw.MemoryImage? logo;
    if (letterhead != null) {
      logo = await _loadLogo(letterhead);
    }

    // ---------- Title ----------
    final customTitle = doc.reportTitle.trim();
final subjectName = doc.subjectInfo.valueOf('subjectName').trim();

final titleText = doc.reportTitle.trim().isNotEmpty
    ? doc.reportTitle.trim()
    : (subjectName.isEmpty ? 'Medical Report' : '$subjectName Report');


    // ---------- Page rules ----------
    final hasAttachments = attachmentImgs.isNotEmpty;
    final hasRemainingText = remainingText.trim().isNotEmpty;

    // Signature only allowed on page 1 if nothing else follows.
    final canPlaceSignatureOnPage1 = !hasAttachments && !hasRemainingText;

    final pdf = pw.Document();

    // ================= PAGE 1 =================
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (_) {
          final mainContent = pw.Container(
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
                      pw.SizedBox(
                        width: 160,
                        child: _inlineColumnFixed(inlineImgs), // ✅ stable 4 slots
                      ),
                    ],
                  )
                : _textBlock(firstPageText),
          );

          final body = pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                titleText,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 12),
              if (doc.subjectInfoDef.enabled) ...[
                _subjectInfoBlock(doc),
                pw.SizedBox(height: 12),
              ],

              if (canPlaceSignatureOnPage1) ...[
                mainContent,
                pw.SizedBox(height: 16),
                _signatureBlock(doc, signatureImg),
              ] else ...[
                // ✅ prevents “shrinking” when signature NOT on page 1
                pw.Expanded(child: mainContent),
              ],
            ],
          );

          return _pageWithLetterhead(
            body: body,
            letterhead: letterhead,
            logo: logo,
          );
        },
      ),
    );

    // ================= ATTACHMENT PAGES =================
    if (attachmentImgs.isNotEmpty) {
      final chunks = _chunk(attachmentImgs, 8);

      for (final chunk in chunks) {
        pdf.addPage(
          pw.Page(
            theme: theme,
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(28),
            build: (_) {
              final body = pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'Image Attachments',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 12),

                  pw.Expanded(
                    child: _attachmentsGridFixed(chunk), // ✅ stable 8 slots
                  ),
                ],
              );

              return _pageWithLetterhead(
                body: body,
                letterhead: letterhead,
                logo: logo,
              );
            },
          ),
        );
      }
    }

    // ================= FINAL PAGE =================
    if (!canPlaceSignatureOnPage1) {
      pdf.addPage(
        pw.Page(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) {
            final body = pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
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
                if (!hasRemainingText) pw.Spacer(),
                _signatureBlock(doc, signatureImg),
              ],
            );

            return _pageWithLetterhead(
              body: body,
              letterhead: letterhead,
              logo: logo,
            );
          },
        ),
      );
    }

    return pdf.save();
  }

  // ============================================================
  // ===================== LETTERHEAD WRAP =======================
  // ============================================================

  pw.Widget _pageWithLetterhead({
    required pw.Widget body,
    required LetterheadTemplate? letterhead,
    required pw.MemoryImage? logo,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (letterhead != null) _letterheadHeader(letterhead, logo),
        pw.Expanded(child: body),
        if (letterhead != null) _letterheadFooter(letterhead),
      ],
    );
  }

  Future<pw.MemoryImage?> _loadLogo(LetterheadTemplate lh) async {
    final path = lh.logoFilePath;
    if (path == null || path.isEmpty) return null;

    final f = File(path);
    if (!await f.exists()) return null;

    final bytes = await f.readAsBytes();
    if (bytes.isEmpty) return null;

    return pw.MemoryImage(bytes);
  }

  pw.Alignment _logoAlign(LetterheadLogoAlignment a) {
    switch (a) {
      case LetterheadLogoAlignment.center:
        return pw.Alignment.center;
      case LetterheadLogoAlignment.right:
        return pw.Alignment.centerRight;
      case LetterheadLogoAlignment.left:
      default:
        return pw.Alignment.centerLeft;
    }
  }

  pw.TextAlign _textAlignFromLogoAlign(LetterheadLogoAlignment a) {
    switch (a) {
      case LetterheadLogoAlignment.center:
        return pw.TextAlign.center;
      case LetterheadLogoAlignment.right:
        return pw.TextAlign.right;
      case LetterheadLogoAlignment.left:
      default:
        return pw.TextAlign.left;
    }
  }

  pw.Widget _letterheadHeader(LetterheadTemplate lh, pw.MemoryImage? logo) {
    final align = _logoAlign(lh.logoAlign);
    final tAlign = _textAlignFromLogoAlign(lh.logoAlign);

    pw.Widget line(String text, {double size = 10, bool bold = false}) {
      final t = text.trim();
      if (t.isEmpty) return pw.SizedBox();
      return pw.Text(
        t,
        textAlign: tAlign,
        style: pw.TextStyle(
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null)
            pw.Container(
              alignment: align,
              height: 46,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
          line(lh.headerLine1, size: 14, bold: true),
          line(lh.headerLine2, size: 10),
          line(lh.headerLine3, size: 10),
          pw.SizedBox(height: 6),
          pw.Divider(),
        ],
      ),
    );
  }

  pw.Widget _letterheadFooter(LetterheadTemplate lh) {
    final left = lh.footerLeft.trim();
    final right = lh.footerRight.trim();

    if (left.isEmpty && right.isEmpty) return pw.SizedBox();

    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        children: [
          pw.Divider(),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(left, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Expanded(
                child: pw.Text(
                  right,
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ===================== SUBJECT INFO BLOCK ====================
  // ============================================================

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
              child: pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );
    }

    pw.Widget body;
    if (def.columns == 2) {
      final items =
          fields.map((f) => (f.title, doc.subjectInfo.valueOf(f.key))).toList();

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
                child: right == null ? pw.SizedBox() : fieldRow(right.$1, right.$2),
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

  // ============================================================
  // ======================== SIGNATURE BLOCK ====================
  // ============================================================

  pw.Widget _signatureBlock(ReportDoc doc, pw.MemoryImage? signature) {
    final role = doc.signature.roleTitle.trim().isEmpty
        ? 'Reporter'
        : doc.signature.roleTitle.trim();
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
                          style: const pw.TextStyle(
                            fontSize: 10,
                            color: PdfColors.grey700,
                          ),
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

  // ============================================================
  // ========================= UI BLOCKS =========================
  // ============================================================

  pw.Widget _textBlock(String text) => pw.Text(
        text.trim().isEmpty ? '(no content)' : text.trim(),
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2),
      );

  /// ✅ FIXED + STABLE: 4 equal slots that FILL the column height
  /// (This prevents the “shrinking upward” behavior.)
  pw.Widget _inlineColumnFixed(List<pw.MemoryImage> images) {
    const slots = 4;
    const gap = 10.0;

    pw.Widget slot(pw.MemoryImage? img) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: img == null
            ? pw.Center(
                child: pw.Text(
                  '(empty)',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              )
            : pw.ClipRRect(
                horizontalRadius: 12,
                verticalRadius: 12,
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
      );
    }

    final filled = List<pw.MemoryImage?>.generate(
      slots,
      (i) => i < images.length ? images[i] : null,
    );

    final children = <pw.Widget>[];
    for (int i = 0; i < slots; i++) {
      children.add(pw.Expanded(child: slot(filled[i])));
      if (i != slots - 1) children.add(pw.SizedBox(height: gap));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  /// ✅ Fixed 8 slots (2 cols × 4 rows) for attachment pages
  pw.Widget _attachmentsGridFixed(List<pw.MemoryImage> images) {
    const slots = 8;
    const cols = 2;
    const gap = 10.0;

    pw.Widget cell(pw.MemoryImage? img) {
      return pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(10),
        ),
        padding: const pw.EdgeInsets.all(4),
        child: img == null
            ? pw.Center(
                child: pw.Text(
                  '(empty)',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              )
            : pw.ClipRRect(
                horizontalRadius: 10,
                verticalRadius: 10,
                child: pw.Image(img, fit: pw.BoxFit.cover),
              ),
      );
    }

    final filled = List<pw.MemoryImage?>.generate(
      slots,
      (i) => i < images.length ? images[i] : null,
    );

    return pw.GridView(
      crossAxisCount: cols,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      childAspectRatio: 1.25,
      children: filled.map(cell).toList(),
    );
  }

  // ============================================================
  // ========================== HELPERS ==========================
  // ============================================================

  String _flatten(List<SectionNode> roots) {
    final b = StringBuffer();

    void walk(List<Node> nodes, int depth) {
      for (final n in nodes) {
        if (n is SectionNode) {
          final extra = _nodeIndent(n);
          final pad = '  ' * (depth + extra);
          final title = n.title.trim();
          if (title.isNotEmpty) b.writeln('$pad$title');
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
