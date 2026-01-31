import 'package:flutter/foundation.dart';
import 'nodes.dart';
import 'subject_info_def.dart';

@immutable
class TemplateDoc {
  final String templateId;
  final DateTime updatedAt;
  final String name;
  final List<SectionNode> roots;
  final SubjectInfoBlockDef subjectInfo;

  TemplateDoc({
    required this.templateId,
    required this.updatedAt,
    required this.name,
    required this.roots,
    SubjectInfoBlockDef? subjectInfo,
  }) : subjectInfo = subjectInfo ?? SubjectInfoBlockDef.kDefaults;

  TemplateDoc copyWith({
    DateTime? updatedAt,
    String? name,
    List<SectionNode>? roots,
    SubjectInfoBlockDef? subjectInfo,
  }) {
    return TemplateDoc(
      templateId: templateId,
      updatedAt: updatedAt ?? this.updatedAt,
      name: name ?? this.name,
      roots: roots ?? this.roots,
      subjectInfo: subjectInfo ?? this.subjectInfo,
    );
  }
}
