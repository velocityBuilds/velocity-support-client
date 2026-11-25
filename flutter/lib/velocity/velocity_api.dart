// Velocity Remote: thin wrapper over the single Rust entry point (src/velocity/mod.rs).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

class VelocityResult {
  final bool ok;
  final dynamic data;
  final String error;
  const VelocityResult(this.ok, this.data, this.error);
}

Future<VelocityResult> velocityCall(String op,
    [Map<String, dynamic> args = const {}]) async {
  try {
    final raw = await bind.velocityCall(op: op, args: jsonEncode(args));
    final m = jsonDecode(raw);
    return VelocityResult(
        m['ok'] == true, m['data'], (m['error'] ?? '').toString());
  } catch (e) {
    return VelocityResult(false, null, 'Something went wrong: $e');
  }
}

bool get isVelocityTechnician => bind.velocityRole() == 'technician';

/// Velocity Builds And Repairs palette (matches the platform's admin design tokens).
class VColors {
  static const accent = Color(0xFF2563EB);
  static const accentDark = Color(0xFF1D4FD7);
  static const navy = Color(0xFF0B1324);
  static const bg = Color(0xFFF4F6FA);
  static const card = Colors.white;
  static const text = Color(0xFF0F1A2B);
  static const muted = Color(0xFF5B6678);
  static const border = Color(0xFFE2E7EF);
  static const ok = Color(0xFF157347);
  static const warn = Color(0xFF8A5800);
  static const danger = Color(0xFFC0352B);
}

/// The Velocity PC Build & Repair logo (assets/velocity_logo.png). [size] is its height.
class VelocityMark extends StatelessWidget {
  final double size;
  const VelocityMark({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/velocity_logo.png',
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // Falls back to a plain "V" if the image is ever missing.
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: VColors.accent, borderRadius: BorderRadius.circular(size * 0.26)),
        child: Text('V', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.55, height: 1.0)),
      ),
    );
  }
}

class VelocityHeader extends StatelessWidget {
  final String title;
  const VelocityHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const VelocityMark(size: 52),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: VColors.text)),
          const Text('Velocity Builds And Repairs',
              style: TextStyle(fontSize: 12, color: VColors.muted)),
        ]),
      ),
    ]);
  }
}

class VCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const VCard(
      {super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: VColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VColors.border),
      ),
      child: child,
    );
  }
}

class VStatusDot extends StatelessWidget {
  final bool on;
  final String label;
  const VStatusDot({super.key, required this.on, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = on ? VColors.ok : VColors.muted;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label,
          style: TextStyle(fontSize: 13, color: c, fontWeight: FontWeight.w600)),
    ]);
  }
}

ButtonStyle vPrimaryButton({double height = 48}) => ElevatedButton.styleFrom(
      backgroundColor: VColors.accent,
      foregroundColor: Colors.white,
      disabledBackgroundColor: const Color(0xFFB8C7EE),
      disabledForegroundColor: Colors.white,
      minimumSize: Size.fromHeight(height),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );

ButtonStyle vSecondaryButton({double height = 44}) => OutlinedButton.styleFrom(
      foregroundColor: VColors.text,
      minimumSize: Size.fromHeight(height),
      side: const BorderSide(color: VColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
    );

InputDecoration vInput(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: VColors.accent, width: 2)),
    );
