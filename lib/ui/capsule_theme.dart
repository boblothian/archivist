import 'package:flutter/material.dart';

const double kCapsuleRadius = 12.0;
const double kCapsuleShadowBlur = 6.0;
const Offset kCapsuleShadowOffset = Offset(0, 4);

BoxDecoration capsuleDecoration(BuildContext context) {
  // WHY: single source of truth for shadow/shape to match archive_item
  return BoxDecoration(borderRadius: BorderRadius.circular(kCapsuleRadius));
}

Widget mediaTypePill(BuildContext context, String mediatype) {
  final cs = Theme.of(context).colorScheme;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: cs.primaryContainer,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      mediatype.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}
