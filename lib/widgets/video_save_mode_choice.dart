import 'package:flutter/material.dart';

import 'sliding_choice.dart';

class VideoSaveModeChoice extends StatelessWidget {
  const VideoSaveModeChoice({
    super.key,
    required this.reencode,
    required this.onChanged,
  });

  final bool reencode;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: 250,
        child: SlidingChoice<bool>(
          values: const [false, true],
          value: reencode,
          labelBuilder: (reencode) => reencode ? '정확하게' : '빠르게',
          iconBuilder: (reencode) => reencode ? Icons.gps_fixed : Icons.bolt,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
