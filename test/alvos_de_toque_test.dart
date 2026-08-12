import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/casa/reservas.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// **Que altura tem, na realidade, cada coisa em que se carrega — no OP.**
///
/// Achado 6.1/6.6. O OP nunca tinha sido olhado: a auditoria contou os toques
/// do Punho e do Control e deixou esta app de fora por inteiro.
///
/// A app tem cinco sítios onde se toca e quatro deles são `IconButton` com
/// `tooltip` — tamanho e nome resolvidos pelo Material. O que interessa medir é
/// o quinto: a célula de meio-dia do calendário, que é a peça que este operador
/// carrega mais vezes por dia, **de pé, numa obra, provavelmente com luva**.
///
/// Aqui não se estima a partir do `itemExtent`: a linha tem 58 dp mas a célula
/// leva `padding` e vive dentro de uma `Row` com o rótulo do dia ao lado. Só
/// medindo se sabe com o que é que o dedo fica.
///
/// 48 dp é o mínimo do Material e o que as WCAG 2.2 aceitam com folga.

class _Servidor implements FonteDeDados {
  _Servidor({this.asMaquinas = const []});
  List<Maquina> asMaquinas;

  @override
  Future<int> porEmDia() async => 0;
  @override
  Future<List<Maquina>> maquinas() async => asMaquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async => const [];
  @override
  Future<List<Reserva>> pedidos() async => const [];
  @override
  Future<List<Cliente>> clientes() async => const [];
  @override
  Future<List<Cobranca>> cobrancas() async => const [];
  @override
  Future<List<Lead>> leads() async => const [];
  @override
  Future<List<Despesa>> despesasDeHoje() async => const [];
}

class _Canal implements Canal {
  @override
  Future<Resultado> guardar(String e, String i, Map<String, Object?> p) async =>
      const Resultado.feito();
  @override
  Future<int> escoarFila() async => 0;
  @override
  int get porEnviar => 0;
}

Maquina _maquina() => const Maquina(
  id: 'uuid-m1',
  idLocal: 'm1',
  cru: {'id': 'm1', 'name': 'Giratória', 'status': 'available'},
  nome: 'Giratória',
  referencia: '',
  categoria: '',
  estado: 'available',
  arquivada: false,
);

void main() {
  const minimo = 48.0;

  /// A altura da caixa que responde ao toque, e não a do texto lá dentro.
  ///
  /// `find.ancestor` até ao `InkWell` de propósito: o `Text('Manhã')` mede o
  /// tamanho da letra, que não é o que o dedo acerta. Quem mede o `Text` conclui
  /// sempre que está tudo mal.
  double alturaDoAlvo(WidgetTester tester, String rotulo) {
    final alvo = find.ancestor(
      of: find.text(rotulo).first,
      matching: find.byType(InkWell),
    );
    return tester.getSize(alvo.first).height;
  }

  Future<void> abrirCalendario(WidgetTester tester) async {
    final estado = EstadoDoOperador(
      _Servidor(asMaquinas: [_maquina()]),
      _Canal(),
      inscricao: const Inscricao(empresaId: 'e1', perfil: 'colaborador'),
    );
    await estado.recarregar();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ReservasScreen(estado: estado))),
    );
    await tester.pumpAndSettle();
  }

  group('o calendário de reservas', () {
    testWidgets('a célula da manhã dá para o dedo', (tester) async {
      await abrirCalendario(tester);

      final altura = alturaDoAlvo(tester, 'Manhã');
      expect(
        altura,
        greaterThanOrEqualTo(minimo),
        reason: 'a célula de meio-dia tem ${altura.toStringAsFixed(1)} dp, e é '
            'o que este operador carrega mais vezes por dia',
      );
    });

    testWidgets('a da tarde também', (tester) async {
      await abrirCalendario(tester);

      final altura = alturaDoAlvo(tester, 'Tarde');
      expect(altura, greaterThanOrEqualTo(minimo));
    });

    testWidgets('escolher a máquina é um alvo, não um alfinete', (tester) async {
      await abrirCalendario(tester);

      // O chip da máquina vive numa barra de 56 dp com 8 de folga em cima e em
      // baixo, o que lhe deixa 40. O Material dá-lhe área de toque para além do
      // que pinta, e é essa que conta — mede-se o `ChoiceChip` inteiro.
      final altura = tester.getSize(find.byType(ChoiceChip).first).height;
      expect(
        altura,
        greaterThanOrEqualTo(minimo),
        reason: 'o chip da máquina tem ${altura.toStringAsFixed(1)} dp',
      );
    });
  });

  // Controlo negativo: se a régua deixar de saber apanhar um alvo pequeno, os
  // testes de cima passam a passar por engano.
  testWidgets('a régua sabe apanhar um alvo pequeno', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: InkWell(onTap: () {}, child: const Text('minúsculo')),
          ),
        ),
      ),
    );

    expect(alturaDoAlvo(tester, 'minúsculo'), lessThan(minimo));
  });
}
