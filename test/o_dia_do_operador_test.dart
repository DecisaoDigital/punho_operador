import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// Um servidor que devolve o que se lhe mandar devolver.
class _ServidorDeMentira implements FonteDeDados {
  _ServidorDeMentira({this.asMaquinas = const [], this.asReservas = const []});
  List<Maquina> asMaquinas;
  List<Reserva> asReservas;

  @override
  Future<List<Maquina>> maquinas() async => asMaquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      asReservas;
  @override
  Future<List<Reserva>> pedidos() async => const [];
  @override
  Future<List<Cliente>> clientes() async => const [];
}

/// Um canal que aceita tudo e guarda o que passou por ele.
class _CanalDeMentira implements Canal {
  final escritas = <(String, String, Map<String, Object?>)>[];
  bool haRede = true;

  @override
  Future<bool> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  ) async {
    escritas.add((entidade, idLocal, payload));
    return haRede;
  }

  @override
  Future<int> escoarFila() async => 0;
  @override
  int get porEnviar => 0;
}

Maquina maquina(String idLocal, {String estado = 'available'}) => Maquina(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {
    'id': idLocal,
    'name': 'Máquina $idLocal',
    'status': estado,
    'acquiredOn': '2024-01-01T00:00:00.000Z',
    'photoPaths': ['foto.jpg'],
  },
  nome: 'Máquina $idLocal',
  referencia: '',
  categoria: '',
  estado: estado,
  arquivada: false,
);

Reserva reserva({
  required String idLocal,
  required DateTime inicio,
  required DateTime fim,
  required String estado,
  List<String> maquinas = const [],
  int? valor,
}) => Reserva(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {
    'id': idLocal,
    'customerId': 'c1',
    'machineIds': maquinas,
    'status': estado,
    'notes': 'a nota que não se pode perder',
  },
  clienteId: 'uuid-c1',
  clienteIdLocal: 'c1',
  clienteNome: 'Cliente',
  inicio: inicio,
  fim: fim,
  estado: estado,
  maquinaIdsLocais: maquinas,
  valorPrevistoCentimos: valor,
);

// ignore: library_private_types_in_public_api
EstadoDoOperador estadoCom(FonteDeDados servidor, _CanalDeMentira canal) =>
    EstadoDoOperador(
      servidor,
      canal,
      inscricao: const Inscricao(empresaId: 'e1', perfil: 'colaborador'),
    );

void main() {
  final hoje = DateTime.now();
  DateTime as(int hora, {int dias = 0}) =>
      DateTime(hoje.year, hoje.month, hoje.day + dias, hora);

  group('o que ele vê no Hoje', () {
    test('entregar hoje é o que começa hoje e ainda não saiu', () async {
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'sai-hoje',
            inicio: as(9),
            fim: as(18, dias: 3),
            estado: 'confirmed',
          ),
          reserva(
            idLocal: 'ja-saiu',
            inicio: as(9),
            fim: as(18, dias: 3),
            estado: 'rented',
          ),
          reserva(
            idLocal: 'sai-amanha',
            inicio: as(9, dias: 1),
            fim: as(18, dias: 4),
            estado: 'confirmed',
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      expect(estado.entregasDeHoje.map((r) => r.idLocal), ['sai-hoje']);
    });

    test('recolher hoje é o que está fora e acaba hoje', () async {
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'volta-hoje',
            inicio: as(9, dias: -2),
            fim: as(18),
            estado: 'rented',
          ),
          reserva(
            idLocal: 'nem-saiu',
            inicio: as(9, dias: -2),
            fim: as(18),
            estado: 'confirmed',
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      expect(estado.recolhasDeHoje.map((r) => r.idLocal), ['volta-hoje']);
    });

    test('o que devia ter voltado ontem não desaparece do ecrã', () async {
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'atrasada',
            inicio: as(9, dias: -5),
            fim: as(18, dias: -2),
            estado: 'rented',
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      // Não é de hoje nem de amanhã: se só houvesse "hoje", ninguém a via mais.
      expect(estado.recolhasDeHoje, isEmpty);
      expect(estado.recolhasEmAtraso.map((r) => r.idLocal), ['atrasada']);
    });

    test('o que devia ter saído ontem e não saiu não desaparece', () async {
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'por-entregar',
            inicio: as(9, dias: -1),
            fim: as(18, dias: 2),
            estado: 'confirmed',
          ),
          reserva(
            idLocal: 'ja-passou-toda',
            inicio: as(9, dias: -5),
            fim: as(18, dias: -2),
            estado: 'confirmed',
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      // Apanhado no telemóvel: uma reserva de ontem por entregar não era de
      // hoje nem estava alugada, e caía de todas as listas. O operador lia
      // "nada para hoje" com um cliente à espera da máquina.
      expect(estado.entregasDeHoje, isEmpty);
      expect(estado.entregasEmAtraso.map((r) => r.idLocal), ['por-entregar']);
      // Uma reserva cuja janela já passou toda não é trabalho de hoje.
      expect(
        estado.entregasEmAtraso.map((r) => r.idLocal),
        isNot(contains('ja-passou-toda')),
      );
    });
  });

  group('o que sobe quando ele age', () {
    test('entregar manda a reserva e as máquinas, sem perder campos', () async {
      final servidor = _ServidorDeMentira(
        asMaquinas: [maquina('m1'), maquina('m2')],
        asReservas: [
          reserva(
            idLocal: 'b1',
            inicio: as(9),
            fim: as(18, dias: 2),
            estado: 'confirmed',
            maquinas: ['m1', 'm2'],
          ),
        ],
      );
      final canal = _CanalDeMentira();
      final estado = estadoCom(servidor, canal);
      await estado.recarregar();

      await estado.entregar(estado.entregasDeHoje.single);

      expect(canal.escritas.length, 3, reason: 'a reserva e as duas máquinas');

      final aReserva = canal.escritas.first;
      expect(aReserva.$1, 'booking');
      expect(aReserva.$3['status'], 'rented');
      // O registo guarda o estado final da entidade. Se subisse só o estado, a
      // nota — e tudo o resto — era apagada na próxima leitura.
      expect(aReserva.$3['notes'], 'a nota que não se pode perder');
      expect(aReserva.$3['machineIds'], ['m1', 'm2']);

      for (final escrita in canal.escritas.skip(1)) {
        expect(escrita.$1, 'machine');
        expect(escrita.$3['status'], 'rented');
        expect(escrita.$3['photoPaths'], ['foto.jpg']);
        expect(escrita.$3['acquiredOn'], '2024-01-01T00:00:00.000Z');
      }
    });

    test('recolher devolve as máquinas a disponíveis', () async {
      final servidor = _ServidorDeMentira(
        asMaquinas: [maquina('m1', estado: 'rented')],
        asReservas: [
          reserva(
            idLocal: 'b1',
            inicio: as(9, dias: -2),
            fim: as(18),
            estado: 'rented',
            maquinas: ['m1'],
          ),
        ],
      );
      final canal = _CanalDeMentira();
      final estado = estadoCom(servidor, canal);
      await estado.recarregar();

      await estado.recolher(estado.recolhasDeHoje.single);

      expect(canal.escritas.first.$3['status'], 'completed');
      expect(canal.escritas.last.$1, 'machine');
      expect(canal.escritas.last.$3['status'], 'available');
    });

    test('sem rede diz que não subiu, em vez de dizer que sim', () async {
      final servidor = _ServidorDeMentira(
        asMaquinas: [maquina('m1')],
        asReservas: [
          reserva(
            idLocal: 'b1',
            inicio: as(9),
            fim: as(18, dias: 1),
            estado: 'confirmed',
            maquinas: ['m1'],
          ),
        ],
      );
      final canal = _CanalDeMentira()..haRede = false;
      final estado = estadoCom(servidor, canal);
      await estado.recarregar();

      // É este falso que faz o ecrã dizer "fica guardado, sobe quando houver
      // rede". Um true aqui mandava-o embora convencido de que estava feito.
      expect(await estado.entregar(estado.entregasDeHoje.single), isFalse);
    });

    test('um cliente novo nunca vai arquivado', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.criarCliente(nome: '  Ana  ', telemovel: '912345678');

      final escrito = canal.escritas.single;
      expect(escrito.$1, 'customer');
      expect(escrito.$3['name'], 'Ana');
      // O servidor recusa a um colaborador uma escrita com `archived: true`.
      // Mandá-lo assim era a app pedir uma coisa que sabe que vai levar não.
      expect(escrito.$3['archived'], false);
    });

    test('sem NIF vai nulo e não string vazia', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.criarCliente(nome: 'Ana', telemovel: '912', nif: '   ');

      // '' é um NIF que não existe a fingir que existe.
      expect(canal.escritas.single.$3['taxId'], isNull);
    });

    test('contribuinte e morada sobem com os nomes que o gestor lê', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.criarCliente(
        nome: 'Ana',
        telemovel: '912345678',
        nif: ' 501234567 ',
        morada: '  Rua das Flores, 12  ',
        localidade: 'Braga',
      );

      // `taxId` e `address` são os nomes do modelo do Punho do gestor, que é
      // quem projecta estas linhas. Escritos de outra maneira, o operador
      // preenchia os campos e o gestor abria a ficha vazia — sem erro nenhum
      // pelo meio, que é o que torna isto difícil de apanhar.
      final escrito = canal.escritas.single.$3;
      expect(escrito['taxId'], '501234567');
      expect(escrito['address'], 'Rua das Flores, 12');
      expect(escrito['locality'], 'Braga');
    });

    test('morada em branco vai nula, como o NIF', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.criarCliente(nome: 'Ana', telemovel: '912', morada: '   ');

      expect(canal.escritas.single.$3['address'], isNull);
    });
  });

  group('pagamentos', () {
    test('por cobrar é o que tem valor e já não é um pedido', () async {
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'com-valor',
            inicio: as(9, dias: -1),
            fim: as(18),
            estado: 'rented',
            valor: 12000,
          ),
          reserva(
            idLocal: 'sem-valor',
            inicio: as(9, dias: -1),
            fim: as(18),
            estado: 'rented',
          ),
          reserva(
            idLocal: 'ainda-pedido',
            inicio: as(9, dias: -1),
            fim: as(18),
            estado: 'request',
            valor: 5000,
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      expect(estado.porCobrar.map((r) => r.idLocal), ['com-valor']);
    });

    test('o recebimento aponta para o cliente e para a reserva', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.aceitarPagamento(
        reserva(
          idLocal: 'b1',
          inicio: as(9),
          fim: as(18),
          estado: 'rented',
          valor: 12000,
        ),
        12000,
      );

      final escrito = canal.escritas.single;
      expect(escrito.$1, 'receipt');
      expect(escrito.$3['amountCents'], 12000);
      expect(escrito.$3['customerId'], 'c1');
      expect(escrito.$3['bookingId'], 'b1');
      // O operador é um membro, não um colaborador do negócio. Fazer aqui uma
      // correspondência entre os dois era inventar um elo.
      expect(escrito.$3['recordedByCollaboratorId'], isNull);
    });
  });

  test('sem servidor não se finge uma empresa vazia', () async {
    final estado = estadoCom(_ServidorQueFalha(), _CanalDeMentira());
    await estado.recarregar();

    expect(estado.erro, isNotNull);
    // As listas ficam vazias, mas o ecrã olha para o erro primeiro. Sem isto,
    // ele lia "nada para entregar hoje" quando o que houve foi falta de rede.
    expect(estado.entregasDeHoje, isEmpty);
  });
}

class _ServidorQueFalha implements FonteDeDados {
  @override
  Future<List<Maquina>> maquinas() async => throw Exception('sem rede');
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      throw Exception('sem rede');
  @override
  Future<List<Reserva>> pedidos() async => throw Exception('sem rede');
  @override
  Future<List<Cliente>> clientes() async => throw Exception('sem rede');
}
