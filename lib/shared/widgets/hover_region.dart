import 'package:flutter/material.dart';

class HoverRegion extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  const HoverRegion({super.key, required this.builder});

  @override
  State<HoverRegion> createState() => _HoverRegionState();
}

class _HoverRegionState extends State<HoverRegion> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: widget.builder(context, _isHovered),
    );
  }
}
