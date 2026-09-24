import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary palette (School Navy & Indigo)
  static const primary = Color(0xFF1E3A8A); // Deep navy blue
  static const primaryLight = Color(0xFF3B82F6);
  static const primaryDark = Color(0xFF172554);
  static const secondary = Color(0xFF0D9488); // Teal accent

  // Status colors
  static const present = Color(0xFF10B981); // Emerald green
  static const late = Color(0xFFF59E0B); // Amber
  static const absent = Color(0xFFEF4444); // Crimson red
  static const halfDay = Color(0xFF8B5CF6); // Purple

  // Neutrals & Surfaces
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;
  static const cardBackground = Colors.white;
  static const border = Color(0xFFE2E8F0);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textMuted = Color(0xFF94A3B8);

  // Dark mode
  static const darkBackground = Color(0xFF0F172A);
  static const darkSurface = Color(0xFF1E293B);
  static const darkBorder = Color(0xFF334155);
  static const darkTextPrimary = Color(0xFFF8FAFC);
  static const darkTextSecondary = Color(0xFF94A3B8);
}
