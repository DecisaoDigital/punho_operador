import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/casa/reservas.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// O calendário das reservas.
///
/// O que se prende aqui é a regra que decide se uma selecção vira reserva, e
/// as datas que sobem quando ela vira. É a única lógica desta app que inventa
/// um registo do nada — tudo o resto move registos que já existem —, e um erro
/// aqui é uma máquina prometida duas vezes ao mesmo tempo.
class _Servidor implements FonteDeDados {
  _Servidor({
    this.asMaquinas = const [],
    this.asReservas = const [],
    this.osClientes = const [],
    this.osPedidos = const [],
  });
  List<Maquina> asMaquinas;
  List<Reserva> asReservas, osPedidos;
  List<Cliente> osClientes;

  @override
  Future<int> porEmDia() async => 0;
  @override
  Future<List<Maquina>> maquinas() async => asMaquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      asReservas;
  @override
  Future<List<Reserva>> pedidos() async => osPedidos;
  @override
  Future<List<Cliente>> clientes() async => osClientes;
  @override
  Future<List<Cobranca>> cobrancas() async => const [];
  @override
  Future<List<Lead>> leads() async => const [];
  @override
  Future<List<Despesa>> despesasDeHoje() async => const [];
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

Maquina _maquina(String idLocal, {String estado = 'available'}) => Maquina(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {'id': idLocal, 'name': 'Giratória', 'status': estado},
  nome: 'Giratória',
  referencia: '',
  categoria: '',
  estado: estado,
  arquivada: false,
);

Cliente _cliente() => const Cliente(
  id: 'uuid-c1',
  idLocal: 'c1',
  cru: {'id': 'c1', 'name': 'Dona Ana'},
  nome: 'Dona Ana',
  telemovel: '912345678',
  arquivado: false,
);

Reserva _reserva({
  required DateTime inicio,
  required DateTime fim,
  String estado = 'confirmed',
}) => Reserva(
  id: 'uuid-r1',
  idLocal: 'r1',
  cru: {'id': 'r1', 'machineIds': ['m1'], 'status': estado},
  clienteId: 'uuid-c1',
  clienteIdLocal: 'c1',
  clienteNome: 'Senhor Costa',
  inicio: inicio,
  fim: fim,
  estado: estado,
  maquinaIdsLocais: const ['m1'],
);

DateTime get _hoje {
  final agora = DateTime.now();
  return DateTime(agora.year, agora.month, agora.day);
}

Future<(EstadoDoOperador, _Canal)> _abrir(
  WidgetTester tester,
  _Servidor servidor,
) async {
  final canal = _Canal();
  final estado = EstadoDoOperador(
    servidor,
    canal,
    inscricao: const Inscricao(empresaId: 'e1', perfil: 'colaborador'),
  );
  await estado.recarregar();
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: ReservasScreen(estado: estado))),
  );
  await tester.pumpAndSettle();
  return (estado, canal);
}

void main() {
  testWidgets('sem máquina escolhida não se marca nada', (tester) async {
    await _abrir(tester, _Servidor(asMaquinas: [_maquina('m1')]));

    expect(find.text('Escolhe uma máquina para marcares os dias.'), findsOne);

    // Tocar num meio-dia antes de escolher a máquina não pode marcar nada: a
    // marcação é sempre de uma máquina, e sem ela não se sabe de qual.
    await tester.tap(find.text('Manhã').first);
    await tester.pump();
    expect(find.text('Reservar'), findsNothing);
  });

  testWidgets('dois meios-dias seguidos dão uma reserva', (tester) async {
    final (_, canal) = await _abrir(
      tester,
      _Servidor(asMaquinas: [_maquina('m1')], osClientes: [_cliente()]),
    );

    await tester.tap(find.text('Giratória'));
    await tester.pump();

    // O calendário abre em hoje: a primeira linha à vista é a de hoje.
    await tester.tap(find.text('Manhã').first);
    await tester.pump();
    await tester.tap(find.text('Tarde').first);
    await tester.pump();

    expect(find.textContaining('Giratória ·'), findsOne);
    await tester.tap(find.text('Reservar'));
    await tester.pumpAndSettle();

    // Escolher para quem é faz parte: uma reserva sem cliente não serve a
    // ninguém, e é o cliente que o operador tem ao telefone.
    await tester.tap(find.text('Dona Ana'));
    await tester.pumpAndSettle();

    final escrito = canal.escritas.single;
    expect(escrito.$1, 'booking');
    expect(escrito.$3['status'], 'confirmed');
    expect(escrito.$3['machineIds'], ['m1']);
    expect(escrito.$3['customerId'], 'c1');
    // O nome fica gravado na reserva, não só a referência ao cliente.
    expect(escrito.$3['customerNameSnapshot'], 'Dona Ana');

    // O dia inteiro: das 0h de hoje às 0h de amanhã, em UTC.
    expect(
      DateTime.parse(escrito.$3['startsAt']! as String),
      _hoje.toUtc(),
    );
    expect(
      DateTime.parse(escrito.$3['endsAt']! as String),
      _hoje.add(const Duration(days: 1)).toUtc(),
    );
  });

  testWidgets('meios-dias com buraco pelo meio não viram reserva', (
    tester,
  ) async {
    await _abrir(
      tester,
      _Servidor(asMaquinas: [_maquina('m1')], osClientes: [_cliente()]),
    );

    await tester.tap(find.text('Giratória'));
    await tester.pump();

    // Manhã de hoje e manhã de amanhã: 24 horas de distância, com a tarde de
    // hoje livre no meio. Deixar isto criar uma reserva única marcava como
    // ocupada uma tarde que ninguém pediu.
    await tester.tap(find.text('Manhã').at(0));
    await tester.pump();
    await tester.tap(find.text('Manhã').at(1));
    await tester.pump();

    expect(find.text('Reservar'), findsNothing);
    expect(find.textContaining('têm de ser seguidos'), findsOne);
  });

  testWidgets('o que já está marcado mostra de quem é e não se marca por cima', (
    tester,
  ) async {
    final (_, canal) = await _abrir(
      tester,
      _Servidor(
        asMaquinas: [_maquina('m1')],
        asReservas: [
          _reserva(inicio: _hoje, fim: _hoje.add(const Duration(days: 1))),
        ],
        osClientes: [_cliente()],
      ),
    );

    await tester.tap(find.text('Giratória'));
    await tester.pump();

    // Ocupado diz o nome. Dizer só "ocupada" obrigava a abrir cada célula para
    // saber se era do cliente que está ao telefone.
    expect(find.text('Senhor Costa'), findsAtLeast(1));

    await tester.tap(find.text('Senhor Costa').first);
    await tester.pumpAndSettle();

    // Abre a reserva em vez de a seleccionar — e não escreveu nada.
    expect(find.text('Reservar'), findsNothing);
    expect(canal.escritas, isEmpty);
  });

  testWidgets('um pedido que ocupa o calendário pode virar reserva ali', (
    tester,
  ) async {
    final (_, canal) = await _abrir(
      tester,
      _Servidor(
        asMaquinas: [_maquina('m1')],
        osPedidos: [
          _reserva(
            inicio: _hoje,
            fim: _hoje.add(const Duration(days: 1)),
            estado: 'request',
          ),
        ],
        osClientes: [_cliente()],
      ),
    );

    await tester.tap(find.text('Giratória'));
    await tester.pump();
    await tester.tap(find.text('Senhor Costa').first);
    await tester.pumpAndSettle();

    // O separador Pedidos desapareceu, mas o trabalho que lá se fazia não:
    // aparece onde o pedido ocupa espaço, que é no calendário.
    await tester.tap(find.text('Fazer reserva'));
    await tester.pumpAndSettle();

    expect(canal.escritas.single.$1, 'booking');
    expect(canal.escritas.single.$3['status'], 'confirmed');
  });
}
