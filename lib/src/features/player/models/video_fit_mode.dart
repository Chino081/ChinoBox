import 'package:flutter/widgets.dart';

enum VideoFitMode {
  contain('自适应比例', BoxFit.contain),
  cover('填充屏幕', BoxFit.cover),
  fill('拉伸铺满', BoxFit.fill);

  const VideoFitMode(this.label, this.fit);

  final String label;
  final BoxFit fit;
}
