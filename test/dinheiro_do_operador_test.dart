import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/core/format/campos.dart';

/// O operador recebe e lança gastos em euros. A régua tem de ser a mesma do
/// gestor e do contabilista, senão o mesmo `1.200` vale coisas diferentes
/// conforme quem escreve no mesmo histórico.
void main() {
  group('centsDeTexto — a régua do dinheiro do operador', () {
    test('mil e duzentos é 1200,00 €, não 1,20 €', () {
      // O bug que motivou isto: `1.200` entrava como 120 cêntimos, e um recibo
      // de mil e duzentos euros passava no validador como um euro e vinte.
      expect(centsDeTexto('1.200'), 120000);
    });

    test('milhares com decimal: 1.200,50 → 120050 (antes dava null e recusava)',
        () {
      expect(centsDeTexto('1.200,50'), 120050);
    });

    test('vírgula é o decimal', () {
      expect(centsDeTexto('12,50'), 1250);
      expect(centsDeTexto('0,99'), 99);
    });

    test('ponto isolado é decimal de folha de cálculo inglesa', () {
      expect(centsDeTexto('1234.56'), 123456);
    });

    test('arredonda o cêntimo, não trunca', () {
      expect(centsDeTexto('12,35'), 1235);
    });

    test('vazio e ilegível são null — nunca um zero inventado', () {
      expect(centsDeTexto(''), isNull);
      expect(centsDeTexto('   '), isNull);
      expect(centsDeTexto('abc'), isNull);
      expect(centsDeTexto('1.500.00'), isNull); // dois pontos, ambíguo
    });

    test('negativo recusa-se por omissão — num recibo é engano', () {
      expect(centsDeTexto('-5,00'), isNull);
      expect(centsDeTexto('-5,00', permitirNegativo: true), -500);
    });

    test('tolera espaços e o símbolo do euro', () {
      expect(centsDeTexto(' 1 200,00 € '), 120000);
    });
  });
}
