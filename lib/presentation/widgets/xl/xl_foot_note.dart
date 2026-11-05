import 'package:flutter/material.dart';

import '../../../app/themes/xl_tokens.dart';

/// 页面脚注 / 分组标题（§15 I3/I4：统一 #666666，不再用 #ABABAB）
class XlFootNote extends StatelessWidget {
  const XlFootNote(this.text, {super.key, this.centered = true});

  final String text;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: XlDims.pagePadding,
        vertical: XlDims.m,
      ),
      child: Text(
        text,
        textAlign: centered ? TextAlign.center : TextAlign.start,
        style: XlType.meta.copyWith(color: p.sectionLabel),
      ),
    );
  }
}

/// 设置 / 任务详情分组标题（13pt #666666）
class XlSectionLabel extends StatelessWidget {
  const XlSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final p = XlPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        XlDims.pagePadding,
        XlDims.xl,
        XlDims.pagePadding,
        XlDims.s,
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: XlDims.sectionLabelSize,
          fontWeight: FontWeight.w500,
          height: 18 / XlDims.sectionLabelSize,
          color: p.sectionLabel,
        ),
      ),
    );
  }
}
