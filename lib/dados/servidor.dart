import 'package:supabase_flutter/supabase_flutter.dart';

/// Lê o estado da empresa no servidor.
///
/// **Esta app não guarda nada.** Não há cópia local para consultar, não há
/// dobrar de histórico ao arranque: cada ecrã pergunta ao servidor e mostra o
/// que ele responde. É a regra do Cesar aplicada à letra — no telemóvel do
/// operador só fica a identificação dele.
///
/// Tudo o que se lê aqui sai de `punho_operacoes`, o registo. Mas de duas
/// maneiras diferentes, e a diferença importa:
///
/// - `punho_clientes`, `punho_maquinas` e `punho_leads` são **vistas** sobre o
///   registo (ver `20260809130000_punho_leitura_e_o_registo.sql`). Não são
///   cópias, logo não podem estar desactualizadas: perguntar-lhes é perguntar
///   ao registo.
/// - `punho_reservas` é **tabela**, porque precisa de índice por intervalo de
///   datas e de junção às máquinas. Uma tabela pode ficar para trás — e ficou,
///   a 8/8/2026. Por isso guarda a sua posição no registo e põe-se em dia
///   antes de se ler ([porEmDia]).
///
/// São todas **só de leitura**: escrever aqui não chegava ao registo e o gestor
/// nunca via a alteração no telemóvel dele. Escreve-se em `punho_operacoes`, e
/// a linha aparece por si.
///
/// O que os ecrãs precisam de perguntar está em [FonteDeDados], logo abaixo:
/// existe para se poder pôr outra coisa no lugar do [Servidor] — nos testes,
/// uma que devolve o que se quiser, sem levantar Supabase nenhum.
abstract interface class FonteDeDados {
  /// Aplica ao `punho_reservas` o que ainda lá não está, e devolve quantas
  /// operações teve de aplicar. Zero é o caso normal.
  ///
  /// Não leva empresa: o servidor tira-a da sessão. Um parâmetro aqui deixava
  /// quem chama escolher em que empresa mandava projectar.
  Future<int> porEmDia();
  Future<List<Maquina>> maquinas();
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate);
  Future<List<Reserva>> pedidos();
  Future<List<Cliente>> clientes();

  /// O que falta receber, por reserva — já com os recibos abatidos.
  ///
  /// Vem do servidor somado e não somado aqui: quem cobra pode não ser quem
  /// marcou, e dois operadores no mesmo cliente têm de ver a mesma dívida.
  Future<List<Cobranca>> cobrancas();

  /// Quem ainda não é cliente e ligou, ou deixou contacto.
  Future<List<Lead>> leads();

  /// As despesas lançadas hoje. Um colaborador só vê as suas — é o servidor
  /// que o decide, não este filtro.
  Future<List<Despesa>> despesasDeHoje();
}

class Servidor implements FonteDeDados {
  Servidor(this._cliente, {required this.empresaId});

  final SupabaseClient _cliente;
  final String empresaId;

  /// Põe a projecção das reservas em dia antes de alguém a ler.
  ///
  /// **Falhar aqui não pode impedir a leitura.** Se o servidor não responder a
  /// isto, o que está projectado continua a valer — mostrar um ecrã de erro
  /// porque a actualização não correu era trocar informação parcial por
  /// informação nenhuma. O atraso fica registado no servidor de qualquer forma.
  @override
  Future<int> porEmDia() async {
    try {
      final resposta = await _cliente.rpc<dynamic>('punho_reservas_em_dia');
      return resposta is int ? resposta : 0;
    } catch (_) {
      return 0;
    }
  }

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
        .order('inicio', ascending: true);
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
        .order('inicio', ascending: true);
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
        .order('nome', ascending: true);
    return [
      for (final l in linhas as List) Cliente._de(Map<String, dynamic>.from(l)),
    ]..removeWhere((c) => c.arquivado);
  }

  @override
  Future<List<Cobranca>> cobrancas() async {
    final linhas = await _cliente
        .from('punho_cobrancas')
        .select(
          'reserva_id_local, cliente, estado, inicio, fim, '
          'previsto_centimos, recebido_centimos, por_cobrar_centimos',
        )
        .eq('empresa_id', empresaId)
        .gt('por_cobrar_centimos', 0)
        .order('inicio', ascending: true);
    return [
      for (final l in linhas as List)
        Cobranca._de(Map<String, dynamic>.from(l)),
    ];
  }

  @override
  Future<List<Lead>> leads() async {
    final linhas = await _cliente
        .from('punho_leads')
        .select('id, id_local, dados')
        .eq('empresa_id', empresaId);
    // Só se tira o que foi arquivado — isso é uma propriedade do registo.
    // Decidir se uma lead ainda é trabalho de hoje é outra coisa, e faz-se em
    // [EstadoDoOperador.leadsPorContactar]: é uma regra do negócio, não da
    // origem dos dados, e aqui não havia como a testar sem um Supabase.
    return [
      for (final l in linhas as List) Lead._de(Map<String, dynamic>.from(l)),
    ]..removeWhere((l) => l.arquivada);
  }

  /// Filtrado pela hora **do servidor** (`recebida_em`), não pela do payload.
  ///
  /// A data que vai no payload é a que o operador escreveu, e ele pode lançar
  /// hoje um gasto de ontem. «Gastos do dia» é o que entrou hoje na empresa —
  /// e essa hora é a única que ninguém pode escrever.
  @override
  Future<List<Despesa>> despesasDeHoje() async {
    final agora = DateTime.now();
    final inicio = DateTime(agora.year, agora.month, agora.day);
    final linhas = await _cliente
        .from('punho_despesas')
        .select('id, id_local, dados, lancada_por, recebida_em')
        .eq('empresa_id', empresaId)
        .gte('recebida_em', inicio.toUtc().toIso8601String())
        .order('recebida_em', ascending: false);
    return [
      for (final l in linhas as List) Despesa._de(Map<String, dynamic>.from(l)),
    ]..removeWhere((d) => d.arquivada);
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

/// O que falta receber de uma reserva.
///
/// **Não estende [Registo] de propósito.** Não é uma entidade do registo: é uma
/// conta feita sobre duas — a reserva e os recibos dela. Não tem `cru` porque
/// não há payload nenhum para devolver intacto; nada disto se volta a escrever.
class Cobranca {
  const Cobranca({
    required this.reservaIdLocal,
    required this.cliente,
    required this.estado,
    required this.inicio,
    required this.fim,
    required this.previstoCentimos,
    required this.recebidoCentimos,
    required this.porCobrarCentimos,
  });

  final String reservaIdLocal, cliente, estado;
  final DateTime inicio, fim;
  final int previstoCentimos, recebidoCentimos, porCobrarCentimos;

  /// Já recebeu alguma coisa, mas não tudo. Muda o que se diz ao operador: não
  /// é «cobrar 300 €», é «faltam 150 dos 300».
  bool get parcial => recebidoCentimos > 0;

  factory Cobranca._de(Map<String, dynamic> linha) => Cobranca(
    reservaIdLocal: (linha['reserva_id_local'] as String?) ?? '',
    cliente: (linha['cliente'] as String?) ?? '',
    estado: (linha['estado'] as String?) ?? '',
    inicio: DateTime.parse(linha['inicio'] as String).toLocal(),
    fim: DateTime.parse(linha['fim'] as String).toLocal(),
    previstoCentimos: (linha['previsto_centimos'] as num?)?.toInt() ?? 0,
    recebidoCentimos: (linha['recebido_centimos'] as num?)?.toInt() ?? 0,
    porCobrarCentimos: (linha['por_cobrar_centimos'] as num?)?.toInt() ?? 0,
  );
}

/// Alguém que ainda não é cliente.
class Lead extends Registo {
  const Lead({
    required super.id,
    required super.idLocal,
    required super.cru,
    required this.nome,
    required this.telefone,
    required this.origem,
    required this.resumo,
    required this.estado,
    required this.arquivada,
  });

  final String nome, telefone, origem, resumo, estado;
  final bool arquivada;

  /// Convertida em cliente ou dada como perdida — em qualquer dos casos já não
  /// é trabalho de hoje.
  bool get fechada =>
      estado == 'converted' || estado == 'lost' || estado == 'won';

  factory Lead._de(Map<String, dynamic> linha) {
    final d = Registo._cruDe(linha);
    return Lead(
      id: linha['id'] as String,
      idLocal: (linha['id_local'] as String?) ?? '',
      cru: d,
      nome: (d['name'] as String?) ?? '',
      telefone: (d['phone'] as String?) ?? '',
      origem: (d['source'] as String?) ?? '',
      resumo: (d['summary'] as String?) ?? '',
      estado: (d['status'] as String?) ?? 'newLead',
      arquivada: d['archived'] == true,
    );
  }
}

/// Um gasto lançado por alguém.
class Despesa extends Registo {
  const Despesa({
    required super.id,
    required super.idLocal,
    required super.cru,
    required this.valorCentimos,
    required this.categoria,
    required this.descricao,
    required this.lancadaPor,
    required this.recebidaEm,
    required this.arquivada,
  });

  final int valorCentimos;
  final String categoria, descricao;

  /// Quem a lançou, pelo nome. **Vem de coluna própria e não do payload**: o
  /// payload é do cliente, e quem lançou é precisamente o que o cliente não
  /// pode afirmar. O servidor deriva-o de `punho_membros`.
  final String lancadaPor;

  /// A hora a que o servidor recebeu — não a que o telemóvel diz.
  final DateTime recebidaEm;

  final bool arquivada;

  factory Despesa._de(Map<String, dynamic> linha) {
    final d = Registo._cruDe(linha);
    return Despesa(
      id: linha['id'] as String,
      idLocal: (linha['id_local'] as String?) ?? '',
      cru: d,
      valorCentimos: (d['amountCents'] as num?)?.toInt() ?? 0,
      categoria: (d['category'] as String?) ?? '',
      descricao: (d['description'] as String?) ?? '',
      lancadaPor: (linha['lancada_por'] as String?) ?? 'Sem nome',
      recebidaEm: DateTime.parse(linha['recebida_em'] as String).toLocal(),
      arquivada: d['archived'] == true,
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
