import '../models/nodes.dart';
import '../models/report_doc.dart';
import '../models/subject_info_def.dart';
import '../models/subject_info_value.dart';

class ReportCodec {
  // =========================
  // ReportDoc
  // =========================

  static Map<String, dynamic> reportToJson(ReportDoc doc) => {
        'reportId': doc.reportId,
        'createdAtIso': doc.createdAtIso,
        'updatedAtIso': doc.updatedAtIso,

        // ✅ NEW: report title
        'reportTitle': doc.reportTitle,

        // ✅ letterhead
        'applyLetterhead': doc.applyLetterhead,
        'letterheadId': doc.letterheadId,

        // ✅ subject info schema + values
        'subjectInfoDef': doc.subjectInfoDef.toJson(),
        'subjectInfo': doc.subjectInfo.toJson(),

        // content
        'placementChoice': doc.placementChoice.name,
        'roots': doc.roots.map(sectionToJson).toList(),

        // images
        'images': doc.images
            .map((i) => {
                  'id': i.id,
                  'filePath': i.filePath,
                })
            .toList(),

        // ✅ signature block with roleTitle
        'signature': {
          'roleTitle': doc.signature.roleTitle,
          'name': doc.signature.name,
          'credentials': doc.signature.credentials,
          'signatureFilePath': doc.signature.signatureFilePath,
        },
      };

  static ReportDoc reportFromJson(Map<String, dynamic> j) {
    final createdAtIso = (j['createdAtIso'] as String?) ??
        (j['updatedAtIso'] as String?) ??
        DateTime.now().toIso8601String();

    final updatedAtIso = (j['updatedAtIso'] as String?) ??
        (j['createdAtIso'] as String?) ??
        DateTime.now().toIso8601String();

    final placementName = (j['placementChoice'] as String?) ??
        ImagePlacementChoice.attachmentsOnly.name;

    final placementChoice = _safeEnumByName<ImagePlacementChoice>(
      ImagePlacementChoice.values,
      placementName,
      fallback: ImagePlacementChoice.attachmentsOnly,
    );

    // ✅ NEW: report title (migration-safe)
    final reportTitle = (j['reportTitle'] as String?) ?? '';

    // ✅ subject info def (schema)
    final defJson = j['subjectInfoDef'];
    final subjectInfoDef = defJson is Map
        ? SubjectInfoBlockDef.fromJson(Map<String, dynamic>.from(defJson))
        : SubjectInfoBlockDef.defaults();

    // ✅ subject info values
    final valuesJson = j['subjectInfo'];
    final subjectInfo = valuesJson is Map
        ? SubjectInfoValues.fromJson(Map<String, dynamic>.from(valuesJson))
        : const SubjectInfoValues({});

    // ✅ roots
    final roots = ((j['roots'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => sectionFromJson(Map<String, dynamic>.from(e)))
        .toList();

    // ✅ images
    final images = ((j['images'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          return ImageAttachment(
            id: (m['id'] as String?) ?? '',
            filePath: (m['filePath'] as String?) ?? '',
          );
        })
        .where((img) => img.id.isNotEmpty && img.filePath.isNotEmpty)
        .toList();

    // ✅ signature
    final sig = (j['signature'] is Map)
        ? Map<String, dynamic>.from(j['signature'] as Map)
        : <String, dynamic>{};

    final signature = SignatureBlock(
      roleTitle: (sig['roleTitle'] as String?)?.trim().isNotEmpty == true
          ? (sig['roleTitle'] as String)
          : 'Reporter',
      name: (sig['name'] as String?) ?? '',
      credentials: (sig['credentials'] as String?) ?? '',
      signatureFilePath: sig['signatureFilePath'] as String?,
    );

    // ✅ letterhead (migration-safe)
    final applyLetterhead = (j['applyLetterhead'] as bool?) ?? false;
    final letterheadIdRaw = (j['letterheadId'] as String?)?.trim();
    final letterheadId =
        (letterheadIdRaw == null || letterheadIdRaw.isEmpty) ? null : letterheadIdRaw;

    return ReportDoc(
      reportId: (j['reportId'] as String?) ?? 'unknown',
      createdAtIso: createdAtIso,
      updatedAtIso: updatedAtIso,

      // ✅ NEW
      reportTitle: reportTitle,

      placementChoice: placementChoice,
      subjectInfoDef: subjectInfoDef,
      subjectInfo: subjectInfo,
      roots: roots,
      images: images,
      signature: signature,

      // ✅ letterhead
      applyLetterhead: applyLetterhead,
      letterheadId: letterheadId,
    );
  }

  // =========================
  // SectionNode
  // =========================

  static Map<String, dynamic> sectionToJson(SectionNode s) => {
        'type': 'section',
        'id': s.id,
        'title': s.title,
        'collapsed': s.collapsed,
        'style': styleToJson(s.style),
        'children': s.children.map(nodeToJson).toList(),
        'indent': s.indent,
      };

  static SectionNode sectionFromJson(Map<String, dynamic> j) => SectionNode(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        collapsed: (j['collapsed'] as bool?) ?? false,
        style: styleFromJson(
          (j['style'] is Map)
              ? Map<String, dynamic>.from(j['style'] as Map)
              : const <String, dynamic>{},
        ),
        children: ((j['children'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => nodeFromJson(Map<String, dynamic>.from(e)))
            .toList(),
        indent: (j['indent'] as int?) ?? 0,
      );

  // =========================
  // Node
  // =========================

  static Map<String, dynamic> nodeToJson(Node n) {
    if (n is SectionNode) return sectionToJson(n);

    if (n is ContentNode) {
      return {
        'type': 'content',
        'id': n.id,
        'text': n.text,
        'indent': n.indent,
      };
    }

    throw StateError('Unknown node type: ${n.runtimeType}');
  }

  static Node nodeFromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?) ?? '';

    if (type == 'section') return sectionFromJson(j);

    if (type == 'content') {
      return ContentNode(
        id: (j['id'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        indent: (j['indent'] as int?) ?? 0,
      );
    }

    throw StateError('Unknown node json type: $type');
  }

  // =========================
  // TitleStyle
  // =========================

  static Map<String, dynamic> styleToJson(TitleStyle s) => {
        'level': s.level.name,
        'bold': s.bold,
        'align': s.align.name,
      };

  static TitleStyle styleFromJson(Map<String, dynamic> j) {
    final levelName = (j['level'] as String?) ?? HeadingLevel.h2.name;
    final alignName = (j['align'] as String?) ?? TitleAlign.left.name;

    final level = _safeEnumByName<HeadingLevel>(
      HeadingLevel.values,
      levelName,
      fallback: HeadingLevel.h2,
    );

    final align = _safeEnumByName<TitleAlign>(
      TitleAlign.values,
      alignName,
      fallback: TitleAlign.left,
    );

    return TitleStyle(
      level: level,
      bold: (j['bold'] as bool?) ?? true,
      align: align,
    );
  }

  // =========================
  // Utils
  // =========================

  static T _safeEnumByName<T extends Enum>(
    List<T> values,
    String name, {
    required T fallback,
  }) {
    try {
      return values.byName(name);
    } catch (_) {
      return fallback;
    }
  }
}
