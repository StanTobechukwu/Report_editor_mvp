import '../models/nodes.dart';
import '../models/template_doc.dart';
import '../models/subject_info_def.dart';

class TemplateCodec {
  static Map<String, dynamic> templateToJson(TemplateDoc t) => {
        'templateId': t.templateId,
        'updatedAtIso': t.updatedAt.toIso8601String(),
        'name': t.name,
        'roots': t.roots.map(_sectionToJson).toList(),
        'subjectInfo': t.subjectInfo.toJson(),
      };

  static TemplateDoc templateFromJson(Map<String, dynamic> j) {
    return TemplateDoc(
      templateId: (j['templateId'] as String?) ?? 'unknown',
      updatedAt: DateTime.tryParse((j['updatedAtIso'] as String?) ?? '') ??
          DateTime.now(),
      name: (j['name'] as String?) ?? 'Untitled Template',
      roots: ((j['roots'] as List?) ?? const [])
          .map((e) => _sectionFromJson(e as Map<String, dynamic>))
          .toList(),
      subjectInfo:
          SubjectInfoBlockDef.fromJson(j['subjectInfo'] as Map<String, dynamic>?),
    );
  }

  // ----- nodes -----

  static Map<String, dynamic> _sectionToJson(SectionNode s) => {
        'type': 'section',
        'id': s.id,
        'title': s.title,
        'collapsed': s.collapsed,
        'style': _styleToJson(s.style),
        'indent': s.indent, // ✅ added
        'children': s.children.map(_nodeToJson).toList(),
      };

  static SectionNode _sectionFromJson(Map<String, dynamic> j) => SectionNode(
        id: (j['id'] as String?) ?? '',
        title: (j['title'] as String?) ?? '',
        collapsed: (j['collapsed'] as bool?) ?? false,
        style: _styleFromJson((j['style'] as Map?)?.cast<String, dynamic>() ?? {}),
        indent: (j['indent'] as int?) ?? 0, // ✅ added
        children: ((j['children'] as List?) ?? const [])
            .map((e) => _nodeFromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, dynamic> _nodeToJson(Node n) {
    if (n is SectionNode) return _sectionToJson(n);
    if (n is ContentNode) {
      return {
        'type': 'content',
        'id': n.id,
        'text': n.text,
        'indent': n.indent, // ✅ added (if ContentNode has indent)
      };
    }
    throw StateError('Unknown node type');
  }

  static Node _nodeFromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String?) ?? '';
    if (type == 'section') return _sectionFromJson(j);
    if (type == 'content') {
      return ContentNode(
        id: (j['id'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        indent: (j['indent'] as int?) ?? 0, // ✅ added (if ContentNode has indent)
      );
    }
    throw StateError('Unknown node json type: $type');
  }

  // ----- style -----

  static Map<String, dynamic> _styleToJson(TitleStyle s) => {
        'level': s.level.name,
        'bold': s.bold,
        'align': s.align.name,
      };

  static TitleStyle _styleFromJson(Map<String, dynamic> j) {
    return TitleStyle(
      level: HeadingLevel.values.byName(
          (j['level'] as String?) ?? HeadingLevel.h2.name),
      bold: (j['bold'] as bool?) ?? true,
      align: TitleAlign.values.byName(
          (j['align'] as String?) ?? TitleAlign.left.name),
    );
  }
}
