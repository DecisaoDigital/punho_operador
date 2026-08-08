import 'package:flutter/material.dart';

/// As cores do Punho, no Punho OP.
///
/// **Esta app é um apêndice do Punho, não um vizinho.** O operador e o gestor
/// olham para o mesmo negócio; se as duas apps não se parecerem, quem as usa
/// tem de aprender duas casas em vez de uma.
///
/// É uma cópia deliberada de `lib/core/theme/punho_theme.dart` do Punho, e não
/// um pacote partilhado: são dois projectos Flutter separados, com ritmos de
/// lançamento diferentes. Se um dia mudarem as cores, mudam-se nos dois — e é
/// por isso que os valores estão aqui em cima, à vista, e não espalhados.
abstract final class PunhoTema {
  static const navy = Color(0xFF10283A);
  static const navyDeep = Color(0xFF0A1C2A);
  static const laranja = Color(0xFFF2A23A);
  static const fundoSuave = Color(0xFFF5F7FA);

  /// Verde e vermelho de estado. Não vêm do esquema porque o esquema é
  /// derivado do laranja e daria dois tons de laranja para "livre" e "ocupada"
  /// — que é exactamente a distinção que tem de se ver de relance, em obra,
  /// com o telemóvel ao sol.
  static const livre = Color(0xFF2E7D32);
  static const ocupada = Color(0xFFC62828);

  static ThemeData get claro {
    final esquema = ColorScheme.fromSeed(
      seedColor: laranja,
      brightness: Brightness.light,
      surface: fundoSuave,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: fundoSuave,
      appBarTheme: const AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      // A TabBar herda o navy do AppBar. Sem estes ajustes o Material 3 põe os
      // rótulos em cinzento, que sobre navy não se lê.
      tabBarTheme: TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.70),
        indicatorColor: laranja,
        overlayColor: WidgetStatePropertyAll(
          Colors.white.withValues(alpha: 0.08),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFFE5EAF0)),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: laranja,
          foregroundColor: navyDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      // O botão flutuante é o «Novo cliente» e o «Nova reserva». No Punho o
      // laranja é a cor de quem age; sem isto ficava no lilás de fábrica do
      // Material 3, que não é de nenhuma das duas apps.
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: laranja,
        foregroundColor: navyDeep,
      ),
      listTileTheme: const ListTileThemeData(iconColor: navy),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: laranja),
    );
  }
}
