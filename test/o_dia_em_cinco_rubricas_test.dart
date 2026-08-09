import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/core/identidade/nif.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/casa/separadores.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// O separador Hoje, em cinco rubricas.
///
/// O que se prende aqui é que o operador abra a app e veja o dia inteiro sem
/// navegar: o que sai, o que volta, o que há a receber, quem está à espera de
/// resposta, e o que já se gastou. Uma rubrica que desapareça quando está
/// vazia obriga-o a lembrar-se do que devia lá estar — e é isso que estes
/// testes não deixam voltar.
class _Servidor implements FonteDeDados {
  _Servidor({
    this.asMaquinas = const [],
    this.asReservas = const [],
    this.asCobrancas = const [],
    this.osLeads = const [],
    this.asDespesas = const [],
  });
  List<Maquina> asMaquinas;
  List<Reserva> asReservas;
  List<Cobranca> asCobrancas;
  List<Lead> osLeads;
  List<Despesa> asDespesas;

  @override
  Future<int> porEmDia() async => 0;
  @override
  Future<List<Maquina>> maquinas() async => asMaquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      asReservas;
  @override
  Future<List<Reserva>> pedidos() async => const [];
  @override
  Future<List<Cliente>> clientes() async => const [];
  @override
  Future<List<Cobranca>> cobrancas() async => asCobrancas;
  @override
  Future<List<Lead>> leads() async => osLeads;
  @override
  Future<List<Despesa>> despesasDeHoje() async => asDespesas;
}

class _Canal implements Canal {
  final escritas = <(String, String, Map<String, Object?>)>[];

  @override
  Future<Resultado> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  ) async {
    escritas.add((entidade, idLocal, payload));
    return const Resultado.feito();
  }

  @override
  Future<int> escoarFila() async => 0;
  @override
  int get porEnviar => 0;
}

DateTime _as(int hora, {int dias = 0}) {
  final h = DateTime.now();
  return DateTime(h.year, h.month, h.day + dias, hora);
}

Maquina _maquina(String idLocal) => Maquina(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {'id': idLocal, 'name': 'Betoneira'},
  nome: 'Betoneira',
  referencia: '',
  categoria: '',
  estado: 'available',
  arquivada: false,
);

Reserva _reserva({
  required String idLocal,
  required DateTime inicio,
  required DateTime fim,
  required String estado,
  String cliente = 'Sr. Costa',
}) => Reserva(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {'id': idLocal, 'machineIds': ['m1']},
  clienteId: 'uuid-c1',
  clienteIdLocal: 'c1',
  clienteNome: cliente,
  inicio: inicio,
  fim: fim,
  estado: estado,
  maquinaIdsLocais: const ['m1'],
);

Cobranca _cobranca({
  required String reserva,
  required int previsto,
  int recebido = 0,
  String cliente = 'Dona Ana',
}) => Cobranca(
  reservaIdLocal: reserva,
  cliente: cliente,
  estado: 'rented',
  inicio: _as(9, dias: -1),
  fim: _as(18),
  previstoCentimos: previsto,
  recebidoCentimos: recebido,
  porCobrarCentimos: previsto - recebido,
);

Future<(EstadoDoOperador, _Canal)> _abrir(
  WidgetTester tester,
  _Servidor servidor,
) async {
  final canal = _Canal();
  final estado = EstadoDoOperador(
    servidor,
    canal,
    inscricao: const Inscricao(
      empresaId: 'e1',
      perfil: 'colaborador',
      colaboradorId: 'ficha-1',
    ),
  );
  await estado.recarregar();
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: HojeScreen(estado: estado))),
  );
  await tester.pumpAndSettle();
  return (estado, canal);
}

void main() {
  testWidgets('as cinco rubricas estão lá mesmo sem nada em nenhuma', (
    tester,
  ) async {
    // Sem despesas nem nada, mas com uma entrega — senão cai no ecrã de vazio.
    await _abrir(
      tester,
      _Servidor(
        asMaquinas: [_maquina('m1')],
        asReservas: [
          _reserva(
            idLocal: 'b1',
            inicio: _as(8),
            fim: _as(18, dias: 2),
            estado: 'confirmed',
          ),
        ],
      ),
    );

    for (final r in ['ENTREGAR', 'RECOLHER', 'COBRAR', 'LEADS', 'DESPESAS']) {
      expect(find.text(r), findsOne, reason: 'falta a rubrica $r');
    }
    // As vazias dizem que estão vazias, em vez de sumirem.
    expect(find.text('Está tudo pago.'), findsOne);
    expect(find.text('Ninguém à espera de resposta.'), findsOne);
    expect(find.text('Nada gasto hoje.'), findsOne);
  });

  testWidgets('a ordem é a do dia: entregar, recolher, cobrar, leads, gastos', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(
        asMaquinas: [_maquina('m1')],
        asReservas: [
          _reserva(
            idLocal: 'b1',
            inicio: _as(8),
            fim: _as(18, dias: 2),
            estado: 'confirmed',
          ),
        ],
      ),
    );

    double y(String rotulo) => tester.getTopLeft(find.text(rotulo)).dy;
    expect(y('ENTREGAR'), lessThan(y('RECOLHER')));
    expect(y('RECOLHER'), lessThan(y('COBRAR')));
    expect(y('COBRAR'), lessThan(y('LEADS')));
    expect(y('LEADS'), lessThan(y('DESPESAS')));
  });

  testWidgets('cobrar diz de quem é e quanto falta, não quanto foi combinado', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(
        asCobrancas: [
          _cobranca(
            reserva: 'b1',
            previsto: 30000,
            recebido: 15000,
            cliente: 'Talho Silva',
          ),
        ],
      ),
    );

    // «Cobrar tem de informar de quem.»
    expect(find.text('Talho Silva'), findsOne);
    // O botão pede o que falta, não os 300 € combinados.
    expect(find.text('Receber 150,00 €'), findsOne);
    expect(find.text('Já recebeu 150,00 € de 300,00 €'), findsOne);
  });

  testWidgets('receber pergunta quanto e como, e escreve o que foi respondido',
      (tester) async {
    final (_, canal) = await _abrir(
      tester,
      _Servidor(asCobrancas: [_cobranca(reserva: 'b1', previsto: 12000)]),
    );

    await tester.tap(find.text('Receber 120,00 €'));
    await tester.pumpAndSettle();

    // Vem preenchido com o total em dívida — o caso normal é receber tudo.
    expect(find.text('120.00'), findsOne);

    await tester.enterText(find.byType(TextFormField), '50');
    await tester.tap(find.text('Dinheiro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MB Way').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Receber'));
    await tester.pumpAndSettle();

    final escrito = canal.escritas.single.$3;
    expect(escrito['amountCents'], 5000);
    expect(escrito['method'], 'mbWay');
    expect(escrito['recordedByCollaboratorId'], 'ficha-1');
  });

  testWidgets('não deixa receber mais do que se deve', (tester) async {
    final (_, canal) = await _abrir(
      tester,
      _Servidor(asCobrancas: [_cobranca(reserva: 'b1', previsto: 12000)]),
    );

    await tester.tap(find.text('Receber 120,00 €'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '500');
    await tester.tap(find.widgetWithText(FilledButton, 'Receber'));
    await tester.pumpAndSettle();

    expect(find.text('São só 120,00 €.'), findsOne);
    expect(canal.escritas, isEmpty);
  });

  testWidgets('um pedido de hoje pede confirmação, não entrega', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(
        asMaquinas: [_maquina('m1')],
        asReservas: [
          _reserva(
            idLocal: 'p1',
            inicio: _as(8),
            fim: _as(18, dias: 1),
            estado: 'request',
          ),
        ],
      ),
    );

    // Entregar um pedido saltava a confirmação e, com ela, o valor a cobrar: a
    // máquina saía e não ficava dívida nenhuma registada.
    expect(find.text('Confirmar a reserva'), findsOne);
    expect(find.text('Entregar'), findsNothing);
  });

  testWidgets('as leads dizem de onde vieram e o que a pessoa quer', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(
        osLeads: [
          Lead(
            id: 'uuid-l1',
            idLocal: 'l1',
            cru: const {'id': 'l1'},
            nome: 'Sandra Vaz',
            telefone: '936112233',
            origem: 'Site — formulário de contacto',
            resumo: 'Quer betoneira para 3 dias, obra em Gondomar.',
            estado: 'newLead',
            arquivada: false,
          ),
        ],
      ),
    );

    expect(find.text('Sandra Vaz'), findsOne);
    expect(find.text('936112233'), findsOne);
    // A origem importa: quem ligou por indicação de um cliente trata-se de
    // outra maneira de quem clicou num anúncio.
    expect(find.text('Veio de: Site — formulário de contacto'), findsOne);
    expect(
      find.text('Quer betoneira para 3 dias, obra em Gondomar.'),
      findsOne,
    );
  });

  testWidgets('a despesa mostra quem a lançou e a que horas', (tester) async {
    await _abrir(
      tester,
      _Servidor(
        asDespesas: [
          Despesa(
            id: 'uuid-e1',
            idLocal: 'e1',
            cru: const {'id': 'e1'},
            valorCentimos: 6842,
            categoria: 'combustivel',
            descricao: 'Gasóleo — carrinha',
            lancadaPor: 'Mariana Queiroz',
            recebidaEm: DateTime(2026, 8, 9, 7, 42),
            arquivada: false,
          ),
        ],
      ),
    );

    expect(find.text('Gasóleo — carrinha'), findsOne);
    expect(find.text('68,42 €'), findsAtLeast(1));
    // «O gestor tem de ver quem lhe enviou o gasto. Nome, horas, data.»
    expect(find.textContaining('Mariana Queiroz'), findsOne);
    expect(find.textContaining('09/08 07:42'), findsOne);
  });

  testWidgets('lançar um gasto escreve uma despesa sem dizer quem a lançou', (
    tester,
  ) async {
    final (_, canal) = await _abrir(tester, _Servidor());

    // Com tudo vazio o ecrã cai no aviso — e mesmo aí tem de dar para lançar.
    await tester.tap(find.text('Lançar um gasto'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, '23,40');
    await tester.enterText(find.byType(TextFormField).last, 'Broca partida');
    await tester.tap(find.widgetWithText(FilledButton, 'Lançar'));
    await tester.pumpAndSettle();

    final escrito = canal.escritas.single;
    expect(escrito.$1, 'expense');
    // Vírgula é o que o teclado português dá, e 23,40 são 2340 cêntimos.
    expect(escrito.$3['amountCents'], 2340);
    expect(escrito.$3['description'], 'Broca partida');
  });

  group('o contribuinte da inscrição', () {
    test('confere o dígito de controlo, não só a forma', () {
      expect(nifValido('501442600'), isTrue);
      expect(nifValido('219876543'), isFalse); // nove dígitos, controlo errado
      expect(nifValido('12345678'), isFalse);
      expect(nifValido('1234567890'), isFalse);
      expect(nifValido('50144260A'), isFalse);
      expect(nifValido(''), isFalse);
      expect(nifValido(null), isFalse);
    });

    test('espaços não invalidam um número certo', () {
      expect(nifValido(' 501 442 600 '), isTrue);
    });
  });
}
