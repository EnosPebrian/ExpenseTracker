import 'package:flutter/material.dart';

class PilgrimTheme {
  static const violet = Color(0xFF6D57DF);
  static const border = Color(0xFFECEBF1);
  static const canvas = Color(0xFFF7F7FA);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: canvas,
    colorScheme: ColorScheme.fromSeed(seedColor: violet),
    fontFamily: 'Segoe UI',
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFFBFBFD),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
        borderSide: BorderSide(color: border),
      ),
    ),
  );
}
