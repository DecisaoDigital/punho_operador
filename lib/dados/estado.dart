import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/sessao/inscricao.dart';
import 'escrita.dart';
import 'servidor.dart';

/// O que a app tem em mãos **agora**.
///
/// Não é uma cópia da empresa. É o resultado da última pergunta ao servidor, e
/// morre quando a app fecha. Cada acção do operador escreve no servidor e volta
/// a perguntar — nunca se corrige este objecto por dentro a fingir que já lá
/// chegou, porque quem manda no que é verdade é o servidor.
class EstadoDoOperador extends ChangeNotifier {
  /// Recebe as duas metades já feitas — é o que permite pôr um servidor de
  /// mentira à frente disto num teste, sem levantar um Supabase.
  EstadoDoOperador(this._servidor, this._escrita, {required this.inscricao});

  /// O caso real: liga-se ao Supabase que está a correr.
  factory EstadoDoOperador.doSupabase({
    required Inscricao inscricao,
    required SharedPreferences preferencias,
  }) => EstadoDoOperador(
    Servidor(Supabase.instance.client, empresaId: inscricao.empresaId),
    Escrita(Supabase.instance.client, preferencias, empresaId: inscricao.empresaId),
    inscricao: inscricao,
  );

  final Inscricao inscricao;
  final FonteDeDados _servidor;
  final Canal _escrita;

  bool _aCarregar = false;
  String? _erro;
  bool _deitadoFora = false;
  List<Maquina> _maquinas = const [];
  List<Reserva> _reservas = const [];
  List<Reserva> _pedidos = const [];
  List<Cliente> _clientes = const [];

  /// Avisa quem está a ver — se ainda houver alguém.
  ///
  /// Ele carrega em «Entregar» e sai do ecrã antes de a resposta chegar, ou a
  /// app vai para trás. Quando a resposta chega, este objecto já foi deitado
  /// fora, e um `notifyListeners` aí atira uma excepção que sobe pelo `finally`
  /// e deixa o `recarregar` a meio: o erro nunca chega a ser marcado, e a app
  /// fica pintada a dizer que está tudo bem. Apanhado no telemóvel.
  void _avisar() {
    if (_deitadoFora) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _deitadoFora = true;
    super.dispose();
  }

  bool get aCarregar => _aCarregar;
  String? get erro => _erro;
  List<Maquina> get maquinas => _maquinas;
  List<Cliente> get clientes => _clientes;
  List<Reserva> get pedidos => _pedidos;

  /// Tudo o que ocupa o calendário: as reservas da janela carregada mais os
  /// pedidos que ainda ninguém confirmou.
  ///
  /// Os pedidos entram porque no calendário **ocupam**: marcar por cima de um
  /// pedido é prometer a mesma máquina duas vezes, e quem está em obra a
  /// responder a um cliente não tem como saber que aquele pedido existia. Vêm
  /// de duas consultas diferentes e podem trazer a mesma reserva, daí a
  /// eliminação de repetidos pelo id local.
  List<Reserva> get ocupacao {
    final porIdLocal = <String, Reserva>{};
    for (final r in [..._reservas, ..._pedidos]) {
      porIdLocal[r.idLocal] = r;
    }
    return porIdLocal.values.toList();
  }
  int get porEnviar => _escrita.porEnviar;

  /// As entregas de hoje: reservas que começam hoje e ainda não saíram.
  List<Reserva> get entregasDeHoje => [
    for (final r in _reservas)
      if (_mesmoDia(r.inicio, DateTime.now()) &&
          (r.estado == 'confirmed' || r.estado == 'request'))
        r,
  ];

  /// As recolhas de hoje: reservas que acabam hoje e estão fora.
  List<Reserva> get recolhasDeHoje => [
    for (final r in _reservas)
      if (_mesmoDia(r.fim, DateTime.now()) && r.estado == 'rented') r,
  ];

  /// O que está fora agora, entregue noutro dia e ainda por recolher. Sem isto,
  /// uma máquina que devia ter voltado ontem desaparecia do ecrã do operador.
  List<Reserva> get recolhasEmAtraso => [
    for (final r in _reservas)
      if (r.estado == 'rented' && r.fim.isBefore(_inicioDeHoje())) r,
  ];

  /// O que devia ter saído e não saiu.
  ///
  /// Apanhado no telemóvel: uma reserva marcada para ontem, ainda por entregar,
  /// não cabia em lado nenhum. Não era de hoje, portanto não estava nas
  /// entregas; não estava alugada, portanto não estava nos atrasos. O operador
  /// abria a app e lia «nada para hoje» com um cliente à espera da máquina.
  List<Reserva> get entregasEmAtraso => [
    for (final r in _reservas)
      if ((r.estado == 'confirmed' || r.estado == 'request') &&
          r.inicio.isBefore(_inicioDeHoje()) &&
          // Se a janela já passou toda, é assunto do gestor, não trabalho de
          // hoje: entregar uma reserva que acabou ontem não faz sentido.
          r.fim.isAfter(DateTime.now()))
        r,
  ];

  /// Reservas com valor por cobrar.
  List<Reserva> get porCobrar => [
    for (final r in _reservas)
      if ((r.valorPrevistoCentimos ?? 0) > 0 &&
          const {'confirmed', 'rented', 'completed'}.contains(r.estado))
        r,
  ];

  Maquina? maquinaPorIdLocal(String idLocal) {
    for (final m in _maquinas) {
      if (m.idLocal == idLocal) return m;
    }
    return null;
  }

  /// Pergunta tudo de novo ao servidor.
  ///
  /// A janela é larga de propósito — de ontem a daqui a um mês. Uma máquina que
  /// devia ter voltado ontem e não voltou tem de continuar à vista, e um pedido
  /// para a semana também.
  Future<void> recarregar() async {
    _aCarregar = true;
    _erro = null;
    _avisar();
    try {
      // Antes de ler, empurra o que ficou de quando não havia rede: ler
      // primeiro mostrava um estado que já não conta com o trabalho dele.
      await _escrita.escoarFila();
      final agora = DateTime.now();
      final resultados = await Future.wait([
        _servidor.maquinas(),
        _servidor.reservasEntre(
          DateTime(agora.year, agora.month, agora.day - 30),
          DateTime(agora.year, agora.month, agora.day + 30),
        ),
        _servidor.pedidos(),
        _servidor.clientes(),
      ]);
      _maquinas = resultados[0] as List<Maquina>;
      _reservas = resultados[1] as List<Reserva>;
      _pedidos = resultados[2] as List<Reserva>;
      _clientes = resultados[3] as List<Cliente>;
    } catch (erro) {
      // Sem inventar uma empresa vazia: se não se conseguiu perguntar, diz-se
      // que não se conseguiu perguntar. Uma lista vazia lia-se como "não há
      // nada para entregar hoje", e isso é mentira.
      _erro = 'Não consegui falar com o servidor.';
    } finally {
      _aCarregar = false;
      _avisar();
    }
  }

  /// Entregar: a reserva passa a aluguer e as máquinas saem de disponíveis.
  ///
  /// Ordem deliberada — a reserva primeiro. Se a rede cair a meio, ficam
  /// máquinas por marcar mas o aluguer está registado; ao contrário ficavam
  /// máquinas ocupadas sem ninguém saber por causa de quê.
  Future<bool> entregar(Reserva reserva) =>
      _mover(reserva, estadoReserva: 'rented', estadoMaquina: 'rented');

  /// Recolher: a reserva fecha e as máquinas voltam a estar disponíveis.
  Future<bool> recolher(Reserva reserva) =>
      _mover(reserva, estadoReserva: 'completed', estadoMaquina: 'available');

  /// Aceitar um pedido e transformá-lo em reserva.
  Future<bool> confirmarPedido(Reserva reserva) async {
    final ok = await _guardarReserva(reserva, 'confirmed');
    await recarregar();
    return ok;
  }

  Future<bool> _mover(
    Reserva reserva, {
    required String estadoReserva,
    required String estadoMaquina,
  }) async {
    var tudoSubiu = await _guardarReserva(reserva, estadoReserva);
    for (final idLocal in reserva.maquinaIdsLocais) {
      final maquina = maquinaPorIdLocal(idLocal);
      if (maquina == null) continue;
      final subiu = await _escrita.guardar('machine', maquina.idLocal, {
        ...maquina.cru,
        'id': maquina.idLocal,
        'status': estadoMaquina,
      });
      tudoSubiu = tudoSubiu && subiu;
    }
    await recarregar();
    return tudoSubiu;
  }

  /// A reserva volta a subir **inteira**, com o estado novo.
  ///
  /// O registo de operações guarda o estado final de cada entidade, não o que
  /// mudou. Enviar só o estado apagava tudo o resto da reserva na próxima vez
  /// que alguém a lesse.
  Future<bool> _guardarReserva(Reserva reserva, String estado) =>
      _escrita.guardar('booking', reserva.idLocal, {
        ...reserva.cru,
        'id': reserva.idLocal,
        'status': estado,
      });

  /// Um cliente novo. Arquivar não está aqui de propósito: o servidor recusa-o
  /// a um colaborador, e um botão que dá erro é pior do que não haver botão.
  Future<bool> criarCliente({
    required String nome,
    required String telemovel,
    String? nif,
    String? morada,
    String? localidade,
  }) async {
    // Vazio vai a nulo, campo a campo. Uma string vazia é um valor a fingir
    // que existe: aparece preenchida nas listas do gestor e não se distingue
    // de "ninguém perguntou".
    String? seTiver(String? v) =>
        (v ?? '').trim().isEmpty ? null : v!.trim();

    final id = novoIdLocal('c');
    final ok = await _escrita.guardar('customer', id, {
      'id': id,
      'name': nome.trim(),
      'phone': telemovel.trim(),
      'taxId': seTiver(nif),
      'email': null,
      'address': seTiver(morada),
      'postalCode': null,
      'locality': seTiver(localidade),
      'notes': '',
      'companyId': 'local-company',
      'archived': false,
    });
    await recarregar();
    return ok;
  }

  /// Uma reserva nova, marcada pelo operador no calendário.
  ///
  /// Nasce **confirmada** e não como pedido. Um pedido é o que chega de fora,
  /// à espera de resposta; isto é o operador ao telefone com o cliente a dizer
  /// "fica marcado". Registá-la como pedido punha-a à espera de alguém que já
  /// respondeu.
  ///
  /// As máquinas **não** mudam de estado aqui. `rented` é para quando a
  /// máquina sai do estaleiro, e isso é a entrega — que acontece no dia, no
  /// separador Hoje. Marcá-las já como alugadas escondia-as de toda a gente
  /// durante os dias que faltam.
  Future<bool> criarReserva({
    required Cliente cliente,
    required List<Maquina> maquinas,
    required DateTime inicio,
    required DateTime fim,
    int? valorPrevistoCentimos,
    String notas = '',
  }) async {
    final id = novoIdLocal('b');
    final ok = await _escrita.guardar('booking', id, {
      'id': id,
      'customerId': cliente.idLocal,
      'machineIds': [for (final m in maquinas) m.idLocal],
      // Em UTC, como tudo o que sobe. O servidor guarda `timestamptz` e a
      // leitura converte de volta para o fuso do telemóvel.
      'startsAt': inicio.toUtc().toIso8601String(),
      'endsAt': fim.toUtc().toIso8601String(),
      'status': 'confirmed',
      'expectedValueCents': valorPrevistoCentimos,
      'collaboratorResponsibleId': null,
      'companyId': 'local-company',
      // O nome fica gravado na reserva. Se o cliente for arquivado ou mudar de
      // nome, a reserva antiga continua a dizer com quem foi feita.
      'customerNameSnapshot': cliente.nome,
      'collaboratorNameSnapshot': '',
      'notes': notas.trim(),
    });
    await recarregar();
    return ok;
  }

  /// Aceitar um pagamento.
  Future<bool> aceitarPagamento(Reserva reserva, int centimos) async {
    final id = novoIdLocal('r');
    final ok = await _escrita.guardar('receipt', id, {
      'id': id,
      'date': DateTime.now().toIso8601String(),
      'amountCents': centimos,
      'customerId': reserva.clienteIdLocal,
      'bookingId': reserva.idLocal,
      'method': 'cash',
      'note': '',
      // Fica por atribuir: o operador é um membro (`punho_membros`), e o campo
      // pede um colaborador do negócio (`punho_colaboradores`). Inventar uma
      // correspondência entre os dois era criar um elo falso.
      'recordedByCollaboratorId': null,
      'archived': false,
    });
    await recarregar();
    return ok;
  }

  static DateTime _inicioDeHoje() {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day);
  }

  static bool _mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
