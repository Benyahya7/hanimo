// Hanimo 2.0 design system — the new look (2026-11-06).
// Deep space navy + violet-to-pink gradient. The old Netflix red is gone
// except for errors and delete buttons.
import 'package:flutter/material.dart';

class HanimoColors {
  static const Color background = Color(0xFF0A0A14);
  static const Color surface = Color(0xFF14141F);
  static const Color card = Color(0xFF1C1C2A);
  static const Color cardBorder = Color(0xFF2A2A3D);
  static const Color violet = Color(0xFF7C5CFF);
  static const Color pink = Color(0xFFFF3D7F);
  static const Color gold = Color(0xFFFFC531);
  static const Color green = Color(0xFF22C55E);
  static const Color textSecondary = Color(0xFFB3B3C2);
}

class HanimoGradients {
  static const LinearGradient brand = LinearGradient(
    colors: [HanimoColors.violet, HanimoColors.pink],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient brandHorizontal = LinearGradient(
    colors: [HanimoColors.violet, HanimoColors.pink],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
}

/// Primary action button with the brand gradient.
class GradientButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry padding;
  const GradientButton({super.key, required this.child, required this.onPressed, this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 20)});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: HanimoGradients.brand, borderRadius: BorderRadius.circular(14)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(padding: padding, child: Center(child: DefaultTextStyle(style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), child: child))),
        ),
      ),
    );
  }
}

/// Small gradient pill (badges, "Ep N", rank numbers live on it).
class GradientPill extends StatelessWidget {
  final String label;
  const GradientPill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(gradient: HanimoGradients.brand, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
    );
  }
}
