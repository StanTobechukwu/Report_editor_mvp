import 'package:flutter/foundation.dart';

/// Stable internal keys — NEVER change
class SubjectFieldKeys {
  static const String subjectName = 'subjectName';
  static const String subjectId = 'subjectId';
}

@immutable
class SubjectFieldDef {
  final String key;
  final String title;
  final bool required;
  final int order;
  final bool isSystem;

  const SubjectFieldDef({
    required this.key,
    required this.title,
    required this.required,
    required this.order,
    required this.isSystem,
  });

  /// Compatibility with older UI/provider code that used `fieldId`.
  String get fieldId => key;

  SubjectFieldDef copyWith({
    String? title,
    bool? required,
    int? order,
  }) {
    return SubjectFieldDef(
      key: key,
      title: title ?? this.title,
      required: required ?? this.required,
      order: order ?? this.order,
      isSystem: isSystem,
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'title': title,
        'required': required,
        'order': order,
        'isSystem': isSystem,
      };

  factory SubjectFieldDef.fromJson(Map<String, dynamic> j) {
    return SubjectFieldDef(
      key: j['key'] as String,
      title: j['title'] as String,
      required: (j['required'] as bool?) ?? false,
      order: (j['order'] as int?) ?? 0,
      isSystem: (j['isSystem'] as bool?) ?? false,
    );
  }
}

@immutable
class SubjectInfoBlockDef {
  /// Turn Subject Info on/off in the editor + output.
  final bool enabled;

  /// 1-col or 2-col layout for editor + preview + pdf.
  /// Persisted as real data (not computed).
  final int columns;

  final int schemaVersion;
  final List<SubjectFieldDef> fields;

  const SubjectInfoBlockDef({
    required this.enabled,
    required this.columns,
    required this.schemaVersion,
    required this.fields,
  });

  /// ✅ Single source of truth for defaults (solves const/defaults issues).
  static const SubjectInfoBlockDef kDefaults = SubjectInfoBlockDef(
    enabled: true,
    columns: 2,
    schemaVersion: 1,
    fields: [
      SubjectFieldDef(
        key: SubjectFieldKeys.subjectName,
        title: 'Subject Name',
        required: true,
        order: 0,
        isSystem: true,
      ),
      SubjectFieldDef(
        key: SubjectFieldKeys.subjectId,
        title: 'Subject ID',
        required: false,
        order: 1,
        isSystem: true,
      ),
    ],
  );

  factory SubjectInfoBlockDef.defaults() => kDefaults;

  List<SubjectFieldDef> get orderedFields {
    final list = fields.toList()..sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  SubjectInfoBlockDef copyWith({
    bool? enabled,
    int? columns,
    List<SubjectFieldDef>? fields,
  }) {
    final safeCols = (columns ?? this.columns) == 2 ? 2 : 1;
    return SubjectInfoBlockDef(
      enabled: enabled ?? this.enabled,
      columns: safeCols,
      schemaVersion: schemaVersion,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'columns': columns,
        'schemaVersion': schemaVersion,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  factory SubjectInfoBlockDef.fromJson(Map<String, dynamic>? j) {
    if (j == null) return kDefaults;

    final cols = (j['columns'] as int?) ?? kDefaults.columns;

    return SubjectInfoBlockDef(
      enabled: (j['enabled'] as bool?) ?? kDefaults.enabled,
      columns: cols == 2 ? 2 : 1,
      schemaVersion: (j['schemaVersion'] as int?) ?? kDefaults.schemaVersion,
      fields: ((j['fields'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => SubjectFieldDef.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
