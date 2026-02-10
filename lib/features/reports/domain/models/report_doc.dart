import 'package:flutter/foundation.dart';

import 'nodes.dart';
import 'subject_info_value.dart';
import 'subject_info_def.dart';

enum ImagePlacementChoice {
  attachmentsOnly,
  inlinePage1,
}

@immutable
class ImageAttachment {
  final String id;
  final String filePath;
  const ImageAttachment({required this.id, required this.filePath});
}

@immutable
class SignatureBlock {
  final String roleTitle; // Radiologist / Endoscopist / Reporter etc
  final String name;
  final String credentials;
  final String? signatureFilePath;

  const SignatureBlock({
    this.roleTitle = 'Reporter',
    this.name = '',
    this.credentials = '',
    this.signatureFilePath,
  });

  SignatureBlock copyWith({
    String? roleTitle,
    String? name,
    String? credentials,
    String? signatureFilePath,
  }) {
    return SignatureBlock(
      roleTitle: roleTitle ?? this.roleTitle,
      name: name ?? this.name,
      credentials: credentials ?? this.credentials,
      signatureFilePath: signatureFilePath ?? this.signatureFilePath,
    );
  }
}

@immutable
class ReportDoc {
  final String reportId;
  final String createdAtIso;
  final String updatedAtIso;
final String reportTitle; 
  final List<SectionNode> roots;
  final List<ImageAttachment> images;
  final ImagePlacementChoice placementChoice;
  final SignatureBlock signature;

  /// Subject Info schema + values (snapshot stored per report)
  final SubjectInfoBlockDef subjectInfoDef;
  final SubjectInfoValues subjectInfo;
 
 
  final bool applyLetterhead;
final String? letterheadId;


  const ReportDoc({
    required this.reportId,
    required this.createdAtIso,
    required this.updatedAtIso,
     this.reportTitle = '',
    this.roots = const [],
    this.images = const [],
    this.placementChoice = ImagePlacementChoice.attachmentsOnly,
    this.signature = const SignatureBlock(),
    this.applyLetterhead = false,
this.letterheadId,

    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
  })  : subjectInfoDef = subjectInfoDef ?? SubjectInfoBlockDef.kDefaults,
        subjectInfo = subjectInfo ?? const SubjectInfoValues({});

  int get maxImages =>
      placementChoice == ImagePlacementChoice.inlinePage1 ? 12 : 8;

  ReportDoc copyWith({
    String? createdAtIso,
    String? updatedAtIso,
    String? reportTitle,
    List<SectionNode>? roots,
    List<ImageAttachment>? images,
    ImagePlacementChoice? placementChoice,
    SignatureBlock? signature,
    bool? applyLetterhead,
String? letterheadId,

    SubjectInfoBlockDef? subjectInfoDef,
    SubjectInfoValues? subjectInfo,
  }) {
    return ReportDoc(
      reportId: reportId,
      createdAtIso: createdAtIso ?? this.createdAtIso,
      updatedAtIso: updatedAtIso ?? this.updatedAtIso,
      reportTitle: reportTitle ?? this.reportTitle,

      roots: roots ?? this.roots,
      images: images ?? this.images,
      placementChoice: placementChoice ?? this.placementChoice,
      signature: signature ?? this.signature,
      applyLetterhead: applyLetterhead ?? this.applyLetterhead,
letterheadId: letterheadId ?? this.letterheadId,

      subjectInfoDef: subjectInfoDef ?? this.subjectInfoDef,
      subjectInfo: subjectInfo ?? this.subjectInfo,
    );
  }
}
