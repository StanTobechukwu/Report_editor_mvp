import 'package:flutter/foundation.dart';

@immutable
sealed class Node {
  final String id;
  const Node({required this.id});
}

enum HeadingLevel { h1, h2, h3, h4 }
enum TitleAlign { left, center, right }

@immutable
class TitleStyle {
  final HeadingLevel level;
  final bool bold;
  final TitleAlign align;

  const TitleStyle({
    this.level = HeadingLevel.h2,
    this.bold = true,
    this.align = TitleAlign.left,
  });

  TitleStyle copyWith({
    HeadingLevel? level,
    bool? bold,
    TitleAlign? align,
  }) {
    return TitleStyle(
      level: level ?? this.level,
      bold: bold ?? this.bold,
      align: align ?? this.align,
    );
  }
}

@immutable
class SectionNode extends Node {
  final String title;
  final bool collapsed;
  final TitleStyle style;
  final List<Node> children;

  /// ✅ indentation level for this section (0,1,2...)
  final int indent;

  const SectionNode({
    required super.id,
    required this.title,
    this.collapsed = false,
    this.style = const TitleStyle(),
    this.children = const [],
    this.indent = 0,
  });

  SectionNode copyWith({
    String? title,
    bool? collapsed,
    TitleStyle? style,
    List<Node>? children,
    int? indent,
  }) {
    return SectionNode(
      id: id,
      title: title ?? this.title,
      collapsed: collapsed ?? this.collapsed,
      style: style ?? this.style,
      children: children ?? this.children,
      indent: indent ?? this.indent,
    );
  }
}

@immutable
class ContentNode extends Node {
  final String text;

  /// ✅ indentation level for this paragraph/content node
  final int indent;

  const ContentNode({
    required super.id,
    this.text = '',
    this.indent = 0,
  });

  ContentNode copyWith({
    String? text,
    int? indent,
  }) {
    return ContentNode(
      id: id,
      text: text ?? this.text,
      indent: indent ?? this.indent,
    );
  }
}
extension TemplateClone on SectionNode {
  /// Export a template snapshot of this section.
  ///
  /// includeContent = false -> keep only SectionNode children (structure-only)
  /// includeContent = true  -> keep SectionNode + ContentNode children (text content)
  ///
  /// Images are not stored in nodes, so they are never included.
  SectionNode toTemplateNode({required bool includeContent}) {
    final outChildren = <Node>[];

    for (final child in children) {
      if (child is SectionNode) {
        outChildren.add(
          child.toTemplateNode(includeContent: includeContent),
        );
      } else if (includeContent && child is ContentNode) {
        outChildren.add(child);
      }
      // else: drop non-section nodes (and drop content when structure-only)
    }

    return SectionNode(
      id: id,
      title: title,
      collapsed: collapsed,
      style: style,
      indent: indent,
      children: outChildren,
    );
  }
}
extension ReportClone on SectionNode {
  SectionNode cloneNodeTree() {
    return SectionNode(
      id: id,
      title: title,
      collapsed: collapsed,
      style: style,
      indent: indent,
      children: children.map((n) {
        if (n is SectionNode) return n.cloneNodeTree();
        if (n is ContentNode) {
          return ContentNode(
            id: n.id,
            text: n.text,
            indent: n.indent,
          );
        }
        return n; // if you have other Node types, we can explicitly clone them too
      }).toList(growable: false),
    );
  }
}
