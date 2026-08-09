import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// Um servidor que devolve o que se lhe mandar devolver.
class _ServidorDeMentira implements FonteDeDados {
  _ServidorDeMentira({
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

  /// Por que ordem lhe perguntaram as coisas. É o que permite provar que a
  /// projecção foi posta em dia *antes* de alguém ler as reservas — e não
  /// depois, que era o mesmo que não a pôr.
  final porQueOrdem = <String>[];

  @override
  Future<int> porEmDia() async {
    porQueOrdem.add('porEmDia');
    return 0;
  }

  @override
  Future<List<Maquina>> maquinas() async => asMaquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async {
    porQueOrdem.add('reservas');
    return asReservas;
  }

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

/// Um canal que aceita tudo e guarda o que passou por ele.
class _CanalDeMentira implements Canal {
  final escritas = <(String, String, Map<String, Object?>)>[];
  bool haRede = true;

  @override
  Future<Resultado> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  ) async {
    escritas.add((entidade, idLocal, payload));
    return haRede ? const Resultado.feito() : const Resultado.emFila();
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

/// Uma despesa como o servidor a devolve — com o nome de quem a lançou já
/// resolvido por ele, que é o ponto: o nome não vem do payload.
Despesa despesa({
  required String idLocal,
  required int centimos,
  required String quem,
  String categoria = 'combustivel',
  String descricao = 'Gasóleo',
}) => Despesa(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {
    'id': idLocal,
    'amountCents': centimos,
    'category': categoria,
    'description': descricao,
  },
  valorCentimos: centimos,
  categoria: categoria,
  descricao: descricao,
  lancadaPor: quem,
  recebidaEm: DateTime.now(),
  arquivada: false,
);

EstadoDoOperador estadoCom(
  FonteDeDados servidor,
  // ignore: library_private_types_in_public_api
  _CanalDeMentira canal, {
  String? colaboradorId,
}) => EstadoDoOperador(
  servidor,
  canal,
  inscricao: Inscricao(
    empresaId: 'e1',
    perfil: 'colaborador',
    colaboradorId: colaboradorId,
  ),
);

void main() {
  final hoje = DateTime.now();
  DateTime as(int hora, {int dias = 0}) =>
      DateTime(hoje.year, hoje.month, hoje.day + dias, hora);

  group('a projecção é posta em dia antes de se ler', () {
    // A 8/8/2026 a app do gestor mostrava 20 clientes e esta mostrava 8,
    // durante 24 horas, sem um erro em lado nenhum: 12 clientes estavam no
    // registo e nunca chegaram à tabela que esta app lê.
    //
    // Clientes e máquinas passaram a vistas sobre o registo e deixaram de
    // poder ficar para trás. As reservas continuam tabela — precisam de índice
    // por intervalo de datas — e é aqui que se garante que ninguém lê uma
    // tabela atrasada: pôr em dia vem *antes*, não depois.
    test('pôr em dia acontece antes de ler as reservas', () async {
      final servidor = _ServidorDeMentira();
      await estadoCom(servidor, _CanalDeMentira()).recarregar();

      expect(servidor.porQueOrdem, contains('porEmDia'));
      expect(
        servidor.porQueOrdem.indexOf('porEmDia'),
        lessThan(servidor.porQueOrdem.indexOf('reservas')),
        reason: 'pôr em dia depois de ler é o mesmo que não pôr',
      );
    });

    test('não conseguir pôr em dia não impede de ler o que já lá está',
        () async {
      // O [Servidor] verdadeiro engole a falha desta chamada. Trocar o que já
      // está projectado por um ecrã de erro era dar menos informação, não mais.
      final servidor = _ServidorDeMentira(
        asReservas: [
          reserva(
            idLocal: 'sai-hoje',
            inicio: as(9),
            fim: as(18, dias: 3),
            estado: 'confirmed',
          ),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      expect(estado.erro, isNull);
      expect(estado.entregasDeHoje, hasLength(1));
    });
  });

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

      // É isto que faz o ecrã dizer "fica guardado, sobe quando houver rede".
      // Um sucesso aqui mandava-o embora convencido de que estava feito.
      final resultado = await estado.entregar(estado.entregasDeHoje.single);
      expect(resultado.subiu, isFalse);
      // Em fila **não é** recusa: sem motivo, a mensagem é a da falta de rede.
      // Uma recusa do servidor traz o motivo e não fica em fila nenhuma.
      expect(resultado.recusado, isFalse);
      expect(resultado.motivo, isNull);
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
    // Uma cobrança de mentira. Não vem de uma reserva: o servidor é que faz a
    // conta, e é isso que este bloco testa — que a app usa a conta dele em vez
    // de a refazer.
    Cobranca cobranca({
      required String reserva,
      required int previsto,
      int recebido = 0,
    }) => Cobranca(
      reservaIdLocal: reserva,
      cliente: 'Dona Ana',
      estado: 'rented',
      inicio: as(9, dias: -1),
      fim: as(18),
      previstoCentimos: previsto,
      recebidoCentimos: recebido,
      porCobrarCentimos: previsto - recebido,
    );

    test('por cobrar é o que o servidor diz que falta receber', () async {
      final servidor = _ServidorDeMentira(
        asCobrancas: [
          cobranca(reserva: 'por-pagar', previsto: 12000),
          cobranca(reserva: 'meio-pago', previsto: 30000, recebido: 15000),
        ],
      );
      final estado = estadoCom(servidor, _CanalDeMentira());
      await estado.recarregar();

      expect(estado.porCobrar.map((c) => c.reservaIdLocal), [
        'por-pagar',
        'meio-pago',
      ]);
      // O total é o que falta, não o que foi combinado. Somar o previsto dava
      // 420 € a um cliente que já entregou 150.
      expect(estado.porCobrarCentimos, 27000);
    });

    test('meio pago diz-se meio pago', () {
      final c = cobranca(reserva: 'x', previsto: 30000, recebido: 15000);
      expect(c.parcial, isTrue);
      expect(c.porCobrarCentimos, 15000);
      expect(cobranca(reserva: 'y', previsto: 100).parcial, isFalse);
    });

    test('o recebimento aponta ao cliente, à reserva e a quem recebeu',
        () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(
        _ServidorDeMentira(
          asReservas: [
            reserva(
              idLocal: 'b1',
              inicio: as(9),
              fim: as(18),
              estado: 'rented',
              valor: 12000,
            ),
          ],
        ),
        canal,
        colaboradorId: 'ficha-do-rui',
      );
      await estado.recarregar();

      await estado.aceitarPagamento(
        cobranca(reserva: 'b1', previsto: 12000),
        12000,
        metodo: 'mbWay',
      );

      final escrito = canal.escritas.single;
      expect(escrito.$1, 'receipt');
      expect(escrito.$3['amountCents'], 12000);
      expect(escrito.$3['customerId'], 'c1');
      expect(escrito.$3['bookingId'], 'b1');
      // O método é o que o operador respondeu. Estava fixo em dinheiro, e um
      // MB Way entrava na caixa como notas — a conta do gestor nunca fechava.
      expect(escrito.$3['method'], 'mbWay');
      // Quem recebeu vem da inscrição, que o servidor resolveu da sessão.
      expect(escrito.$3['recordedByCollaboratorId'], 'ficha-do-rui');
      // Em UTC, como tudo o que sobe. Sem o `Z` a data só se lia bem por acaso.
      expect(escrito.$3['date'], endsWith('Z'));
    });

    test('recebimento parcial escreve só o que entrou', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.aceitarPagamento(
        cobranca(reserva: 'b9', previsto: 30000),
        15000,
        metodo: 'cash',
      );

      expect(canal.escritas.single.$3['amountCents'], 15000);
    });
  });

  group('despesas', () {
    test('o gasto sobe sem dizer quem o lançou', () async {
      final canal = _CanalDeMentira();
      final estado = estadoCom(_ServidorDeMentira(), canal);

      await estado.lancarDespesa(
        centimos: 2340,
        categoria: 'combustivel',
        descricao: '  Gasóleo da carrinha  ',
      );

      final escrito = canal.escritas.single;
      expect(escrito.$1, 'expense');
      expect(escrito.$3['amountCents'], 2340);
      expect(escrito.$3['category'], 'combustivel');
      expect(escrito.$3['description'], 'Gasóleo da carrinha');
      expect(escrito.$3['date'], endsWith('Z'));
      // Quem lançou **não vai no payload**: provou-se que um cliente podia
      // assinar uma operação em nome de outra pessoa. O servidor carimba.
      expect(escrito.$3.containsKey('lancadaPor'), isFalse);
      expect(escrito.$3.containsKey('recordedBy'), isFalse);
    });

    test('o gasto do dia é a soma do que o servidor devolveu', () async {
      final estado = estadoCom(
        _ServidorDeMentira(
          asDespesas: [
            despesa(idLocal: 'e1', centimos: 6842, quem: 'Mariana Queiroz'),
            despesa(idLocal: 'e2', centimos: 940, quem: 'Mariana Queiroz'),
          ],
        ),
        _CanalDeMentira(),
      );
      await estado.recarregar();

      expect(estado.gastoDeHojeCentimos, 7782);
      expect(estado.despesasDeHoje.first.lancadaPor, 'Mariana Queiroz');
    });
  });

  group('leads', () {
    Lead lead(String idLocal, {String estado = 'newLead'}) => Lead(
      id: 'uuid-$idLocal',
      idLocal: idLocal,
      cru: {'id': idLocal, 'status': estado},
      nome: 'Sandra Vaz',
      telefone: '936112233',
      origem: 'Site',
      resumo: 'Quer betoneira',
      estado: estado,
      arquivada: false,
    );

    test('só aparecem os que ainda estão à espera de resposta', () async {
      final estado = estadoCom(
        _ServidorDeMentira(
          osLeads: [
            lead('novo'),
            // Já é cliente ou já se perdeu: nos dois casos não é trabalho de
            // hoje, e continuar a mostrá-lo era mandar telefonar outra vez a
            // quem já respondeu.
            lead('convertido', estado: 'converted'),
            lead('perdido', estado: 'lost'),
          ],
        ),
        _CanalDeMentira(),
      );
      await estado.recarregar();

      expect(estado.leadsPorContactar.map((l) => l.idLocal), ['novo']);
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
  // Devolve zero em vez de rebentar: o [Servidor] verdadeiro já engole a falha
  // desta chamada, porque não conseguir actualizar não pode impedir de ler o
  // que já está projectado.
  @override
  Future<int> porEmDia() async => 0;
  @override
  Future<List<Maquina>> maquinas() async => throw Exception('sem rede');
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      throw Exception('sem rede');
  @override
  Future<List<Reserva>> pedidos() async => throw Exception('sem rede');
  @override
  Future<List<Cliente>> clientes() async => throw Exception('sem rede');
  @override
  Future<List<Cobranca>> cobrancas() async => throw Exception('sem rede');
  @override
  Future<List<Lead>> leads() async => throw Exception('sem rede');
  @override
  Future<List<Despesa>> despesasDeHoje() async => throw Exception('sem rede');
}
