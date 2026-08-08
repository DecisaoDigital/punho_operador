import 'package:supabase_flutter/supabase_flutter.dart';

/// Lê o estado da empresa no servidor.
///
/// **Esta app não guarda nada.** Não há cópia local para consultar, não há
/// dobrar de histórico ao arranque: cada ecrã pergunta ao servidor e mostra o
/// que ele responde. É a regra do Cesar aplicada à letra — no telemóvel do
/// operador só fica a identificação dele.
///
/// As tabelas lidas aqui são a projecção de `punho_operacoes`, feita por
/// gatilho no servidor (ver `20260807_punho_projeccao_das_tabelas.sql`). São
/// **só de leitura**: escrever aqui não chegava ao registo de operações e o
/// gestor nunca via a alteração aparecer no telemóvel dele. Quando esta app
/// passar a escrever, escreve em `punho_operacoes` e a linha aparece nestas
/// tabelas por si.
///
/// O que os ecrãs precisam de perguntar está em [FonteDeDados], logo abaixo:
/// existe para se poder pôr outra coisa no lugar do [Servidor] — nos testes,
/// uma que devolve o que se quiser, sem levantar Supabase nenhum.
abstract interface class FonteDeDados {
  Future<List<Maquina>> maquinas();
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate);
  Future<List<Reserva>> pedidos();
  Future<List<Cliente>> clientes();
}

class Servidor implements FonteDeDados {
  Servidor(this._cliente, {required this.empresaId});

  final SupabaseClient _cliente;
  final String empresaId;

  /// Todas as máquinas da empresa, arquivadas de fora.
  ///
  /// «Ver disponibilidade das maquinas todas» — todas mesmo, não só as que ele
  /// entregou. Quem está ao balcão a atender um cliente precisa de responder
  /// "essa está ocupada, mas tenho esta" sem telefonar a ninguém.
  @override
  Future<List<Maquina>> maquinas() async {
    final linhas = await _cliente
        .from('punho_maquinas')
        .select('id, id_local, dados')
        .eq('empresa_id', empresaId);
    return [
      for (final l in linhas as List) Maquina._de(Map<String, dynamic>.from(l)),
    ]..removeWhere((m) => m.arquivada);
  }

  /// As reservas que tocam o intervalo pedido.
  ///
  /// Sobreposição e não "começa dentro": uma máquina entregue na segunda e
  /// recolhida na sexta conta para quarta-feira, e é isso que o separador Hoje
  /// tem de mostrar. Filtrar por `inicio` dentro do dia perdia-a.
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async {
    final linhas = await _cliente
        .from('punho_reservas')
        .select(
          'id, id_local, cliente_id, cliente_nome_snapshot, inicio, fim, '
          'estado, valor_previsto_centimos, dados',
        )
        .eq('empresa_id', empresaId)
        .lt('inicio', ate.toUtc().toIso8601String())
        .gt('fim', de.toUtc().toIso8601String())
        .order('inicio');
    return [
      for (final l in linhas as List) Reserva._de(Map<String, dynamic>.from(l)),
    ];
  }

  /// Os pedidos por tratar: alguém pediu uma máquina e ninguém respondeu.
  @override
  Future<List<Reserva>> pedidos() async {
    final linhas = await _cliente
        .from('punho_reservas')
        .select(
          'id, id_local, cliente_id, cliente_nome_snapshot, inicio, fim, '
          'estado, valor_previsto_centimos, dados',
        )
        .eq('empresa_id', empresaId)
        .inFilter('estado', ['request', 'proposalSent'])
        .order('inicio');
    return [
      for (final l in linhas as List) Reserva._de(Map<String, dynamic>.from(l)),
    ];
  }

  @override
  Future<List<Cliente>> clientes() async {
    final linhas = await _cliente
        .from('punho_clientes')
        .select('id, id_local, nome, telemovel, dados')
        .eq('empresa_id', empresaId)
        .order('nome');
    return [
      for (final l in linhas as List) Cliente._de(Map<String, dynamic>.from(l)),
    ]..removeWhere((c) => c.arquivado);
  }

  /// Que máquinas estão em cada reserva.
  ///
  /// Devolvido em bloco e não uma consulta por reserva: o separador Hoje mostra
  /// uma dúzia de linhas, e uma dúzia de idas ao servidor num telemóvel em obra
  /// é o que faz um ecrã parecer partido.
  Future<Map<String, List<String>>> maquinasPorReserva(
    List<String> reservaIds,
  ) async {
    if (reservaIds.isEmpty) return const {};
    final linhas = await _cliente
        .from('punho_reserva_maquinas')
        .select('reserva_id, maquina_id')
        .inFilter('reserva_id', reservaIds);
    final porReserva = <String, List<String>>{};
    for (final l in linhas as List) {
      final linha = Map<String, dynamic>.from(l as Map);
      porReserva
          .putIfAbsent(linha['reserva_id'] as String, () => [])
          .add(linha['maquina_id'] as String);
    }
    return porReserva;
  }
}

/// O que é comum a tudo o que vem destas tabelas.
///
/// **`cru` é o payload inteiro, tal como a app do gestor o escreveu.** Existe
/// por uma razão concreta: o registo de operações guarda o *estado final* de
/// cada entidade, não o que mudou. Quando o operador entrega uma máquina, a
/// máquina volta a subir toda — e se subisse só os campos que esta app modela,
/// tudo o resto (a data de aquisição, as fotografias, um campo que uma versão
/// futura venha a inventar) era apagado do servidor por omissão.
///
/// Modelar campos serve para os mostrar. Guardar o cru serve para os devolver
/// intactos.
abstract class Registo {
  const Registo({required this.id, required this.idLocal, required this.cru});

  /// O `uuid` da tabela — é por este que as outras tabelas se referem a ele.
  final String id;

  /// O id que a app do gestor lhe deu (`m1785969714554173`).
  final String idLocal;

  /// O payload completo. Nunca se envia nada para o servidor sem partir daqui.
  final Map<String, dynamic> cru;

  static Map<String, dynamic> _cruDe(Map<String, dynamic> linha) =>
      Map<String, dynamic>.from(linha['dados'] as Map? ?? const {});
}

/// Uma máquina, como o operador precisa dela.
class Maquina extends Registo {
  const Maquina({
    required super.id,
    required super.idLocal,
    required super.cru,
    required this.nome,
    required this.referencia,
    required this.categoria,
    required this.estado,
    required this.arquivada,
    this.precoDiarioCentimos,
  });

  final String nome, referencia, categoria, estado;
  final bool arquivada;
  final int? precoDiarioCentimos;

  bool get disponivel => estado == 'available';

  factory Maquina._de(Map<String, dynamic> linha) {
    final d = Registo._cruDe(linha);
    return Maquina(
      id: linha['id'] as String,
      idLocal: (linha['id_local'] as String?) ?? '',
      cru: d,
      nome: (d['name'] as String?) ?? '',
      referencia: (d['reference'] as String?) ?? '',
      categoria: (d['category'] as String?) ?? '',
      estado: (d['status'] as String?) ?? 'available',
      arquivada: d['archived'] == true,
      precoDiarioCentimos: (d['dailyRateCents'] as num?)?.toInt(),
    );
  }
}

class Reserva extends Registo {
  const Reserva({
    required super.id,
    required super.idLocal,
    required super.cru,
    required this.clienteId,
    required this.clienteIdLocal,
    required this.clienteNome,
    required this.inicio,
    required this.fim,
    required this.estado,
    required this.maquinaIdsLocais,
    this.valorPrevistoCentimos,
    this.notas = '',
  });

  /// O `uuid` do cliente na tabela.
  final String clienteId;

  /// O id local do cliente — é este que viaja nos payloads.
  final String clienteIdLocal;

  final String clienteNome, estado, notas;
  final DateTime inicio, fim;

  /// Os ids locais das máquinas. A ligação por `uuid` está em
  /// `punho_reserva_maquinas`; esta lista casa com o que o gestor vê.
  final List<String> maquinaIdsLocais;

  final int? valorPrevistoCentimos;

  bool get estaFora => estado == 'rented';

  factory Reserva._de(Map<String, dynamic> linha) {
    final d = Registo._cruDe(linha);
    return Reserva(
      id: linha['id'] as String,
      idLocal: (linha['id_local'] as String?) ?? '',
      cru: d,
      clienteId: (linha['cliente_id'] as String?) ?? '',
      clienteIdLocal: (d['customerId'] as String?) ?? '',
      clienteNome: (linha['cliente_nome_snapshot'] as String?) ?? '',
      inicio: DateTime.parse(linha['inicio'] as String).toLocal(),
      fim: DateTime.parse(linha['fim'] as String).toLocal(),
      estado: (linha['estado'] as String?) ?? 'request',
      maquinaIdsLocais: d['machineIds'] is List
          ? List<String>.from(d['machineIds'] as List)
          : const [],
      valorPrevistoCentimos: (linha['valor_previsto_centimos'] as num?)?.toInt(),
      notas: (d['notes'] as String?) ?? '',
    );
  }
}

class Cliente extends Registo {
  const Cliente({
    required super.id,
    required super.idLocal,
    required super.cru,
    required this.nome,
    required this.telemovel,
    required this.arquivado,
    this.nif,
    this.morada,
    this.localidade,
  });

  final String nome, telemovel;
  final bool arquivado;
  /// Contribuinte e morada. Guardados com os nomes do Punho do gestor —
  /// `taxId` e `address` —, que é quem projecta estas linhas: um nome trocado
  /// aqui é um campo que o operador escreve e o gestor nunca vê.
  final String? nif, morada;
  final String? localidade;

  factory Cliente._de(Map<String, dynamic> linha) {
    final d = Registo._cruDe(linha);
    return Cliente(
      id: linha['id'] as String,
      idLocal: (linha['id_local'] as String?) ?? '',
      cru: d,
      nome: (linha['nome'] as String?) ?? '',
      telemovel: (linha['telemovel'] as String?) ?? '',
      arquivado: d['archived'] == true,
      nif: d['taxId'] as String?,
      morada: d['address'] as String?,
      localidade: d['locality'] as String?,
    );
  }
}
