import 'package:flutter/foundation.dart';

enum LetterheadLogoAlignment { left, center, right }

@immutable
class LetterheadTemplate {
  final String letterheadId;
  final String name;

  /// Optional assets/text
  final String? logoFilePath; // local for now (later: URL)
  final String headerLine1; // e.g., Hospital/Company
  final String headerLine2; // e.g., Address
  final String headerLine3; // e.g., Phone/Email

  final String footerLeft; // e.g., tagline
  final String footerRight; // e.g., website

  final LetterheadLogoAlignment logoAlign;

  const LetterheadTemplate({
    required this.letterheadId,
    required this.name,
    this.logoFilePath,
    this.headerLine1 = '',
    this.headerLine2 = '',
    this.headerLine3 = '',
    this.footerLeft = '',
    this.footerRight = '',
    this.logoAlign = LetterheadLogoAlignment.left,
  });

  LetterheadTemplate copyWith({
    String? name,
    String? logoFilePath,
    String? headerLine1,
    String? headerLine2,
    String? headerLine3,
    String? footerLeft,
    String? footerRight,
    LetterheadLogoAlignment? logoAlign,
  }) {
    return LetterheadTemplate(
      letterheadId: letterheadId,
      name: name ?? this.name,
      logoFilePath: logoFilePath ?? this.logoFilePath,
      headerLine1: headerLine1 ?? this.headerLine1,
      headerLine2: headerLine2 ?? this.headerLine2,
      headerLine3: headerLine3 ?? this.headerLine3,
      footerLeft: footerLeft ?? this.footerLeft,
      footerRight: footerRight ?? this.footerRight,
      logoAlign: logoAlign ?? this.logoAlign,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'letterheadId': letterheadId,
      'name': name,
      'logoFilePath': logoFilePath,
      'headerLine1': headerLine1,
      'headerLine2': headerLine2,
      'headerLine3': headerLine3,
      'footerLeft': footerLeft,
      'footerRight': footerRight,
      'logoAlign': logoAlign.name,
    };
  }

  factory LetterheadTemplate.fromJson(Map<String, dynamic> json) {
    final alignStr = (json['logoAlign'] as String?) ?? 'left';
    final align = LetterheadLogoAlignment.values.firstWhere(
      (e) => e.name == alignStr,
      orElse: () => LetterheadLogoAlignment.left,
    );

    return LetterheadTemplate(
      letterheadId: json['letterheadId'] as String,
      name: (json['name'] as String?) ?? '',
      logoFilePath: json['logoFilePath'] as String?,
      headerLine1: (json['headerLine1'] as String?) ?? '',
      headerLine2: (json['headerLine2'] as String?) ?? '',
      headerLine3: (json['headerLine3'] as String?) ?? '',
      footerLeft: (json['footerLeft'] as String?) ?? '',
      footerRight: (json['footerRight'] as String?) ?? '',
      logoAlign: align,
    );
  }
}
