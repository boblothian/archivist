import 'package:flutter/material.dart';

class BigSectionHeader extends StatelessWidget {
  final String title;
  const BigSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 18, // Reduced from ~22 → 18
        fontWeight: FontWeight.w600, // Slightly lighter than bold
      ),
    );
  }
}
