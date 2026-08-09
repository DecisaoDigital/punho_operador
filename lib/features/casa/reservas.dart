import 'package:flutter/material.dart';

import '../../core/tema/punho_tema.dart';
import '../../dados/escrita.dart';
import '../../dados/estado.dart';
import '../../dados/servidor.dart';
import 'separadores.dart';

/// O calendário de reservas, a descer.
///
/// **É o mesmo calendário do Punho, virado.** No Punho os dias são colunas
/// lado a lado, porque quem o usa está sentado a um ecrã largo. Aqui os dias
/// descem: o operador tem o telemóvel de pé numa mão, e sete colunas num ecrã
/// de telemóvel dão células onde não cabe o nome de um cliente.
///
/// O resto é igual, de propósito — as mesmas regras, para as duas apps não
/// discordarem sobre o que está marcado:
///
/// * o dia parte-se em dois, Manhã (00h) e Tarde (12h);
/// * escolhe-se **uma** máquina e depois os meios-dias;
/// * os meios-dias têm de ser seguidos: uma reserva é um período, não um
///   conjunto de bocados soltos;
/// * a reserva vai do início do primeiro ao fim do último.
///
/// Não há Semana/Mês como no Punho. Numa lista que rola não faz falta: a
/// separação existe lá porque uma grelha horizontal só mostra o que cabe no
/// ecrã de uma vez, e aqui basta continuar a rolar.
class ReservasScreen extends StatefulWidget {
  const ReservasScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  State<ReservasScreen> createState() => _ReservasScreenState();
}

class _ReservasScreenState extends State<ReservasScreen> {
  /// Quantos dias para trás e para a frente se mostram.
  ///
  /// São os mesmos 30 que o `recarregar` vai buscar. Mostrar mais dias do que
  /// os que foram carregados desenhava meios-dias livres onde ninguém sabe se
  /// há alguma coisa — que é a pior espécie de vazio.
  static const _diasAtras = 30;
  static const _diasAFrente = 30;
  static const _alturaDaLinha = 58.0;

  String? _maquinaIdLocal;
  final _seleccionados = <DateTime>{};
  late final ScrollController _rolo;

  DateTime get _hoje {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day);
  }

  @override
  void initState() {
    super.initState();
    // Abre em hoje, não no primeiro dia da janela. Quem abre o calendário
    // quer marcar para os próximos dias; começar 30 dias atrás obrigava a
    // rolar sempre antes de fazer seja o que for.
    _rolo = ScrollController(initialScrollOffset: _diasAtras * _alturaDaLinha);
  }

  @override
  void dispose() {
    _rolo.dispose();
    super.dispose();
  }

  List<Maquina> get _maquinas => [
    for (final m in widget.estado.maquinas)
      if (!m.arquivada) m,
  ];

  Maquina? get _maquina {
    for (final m in _maquinas) {
      if (m.idLocal == _maquinaIdLocal) return m;
    }
    return null;
  }

  /// As reservas da máquina escolhida.
  List<Reserva> get _daMaquina {
    final id = _maquinaIdLocal;
    if (id == null) return const [];
    return [
      for (final r in widget.estado.ocupacao)
        if (r.maquinaIdsLocais.contains(id) &&
            r.estado != 'completed' &&
            r.estado != 'cancelled')
          r,
    ];
  }

  /// O período que a selecção representa, ou nulo se ela não serve.
  ///
  /// Nulo quando está vazia ou quando tem buracos: dois meios-dias soltos não
  /// são um aluguer, são dois. Deixá-los criar uma reserva única marcava como
  /// ocupado o meio que ficou pelo caminho.
  ({DateTime inicio, DateTime fim})? get _periodo {
    if (_seleccionados.isEmpty) return null;
    final ordenados = _seleccionados.toList()..sort();
    for (var i = 1; i < ordenados.length; i++) {
      if (ordenados[i].difference(ordenados[i - 1]) !=
          const Duration(hours: 12)) {
        return null;
      }
    }
    return (
      inicio: ordenados.first,
      fim: ordenados.last.add(const Duration(hours: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_maquinas.isEmpty) {
      return const Vazio(
        icone: Icons.precision_manufacturing_outlined,
        titulo: 'Ainda não há máquinas.',
        detalhe: 'Sem máquinas não há o que reservar. Quem as regista é o '
            'gestor, no Punho.',
      );
    }

    // A máquina escolhida pode desaparecer da lista sem esta escolha mudar: o
    // gestor arquiva-a no Punho enquanto o operador tem meios-dias marcados, e
    // a actualização seguinte deixa `_maquinaIdLocal` a apontar para nada. O
    // rodapé lê `_maquina!` e a app rebentava com o ecrã já aberto.
    //
    // Limpa-se em vez de se proteger o `!`: uma selecção de uma máquina que já
    // não está disponível não é para aproveitar, é para refazer.
    if (_maquinaIdLocal != null && _maquina == null) {
      _maquinaIdLocal = null;
      _seleccionados.clear();
    }

    final periodo = _periodo;
    return Column(
      children: [
        _EscolhaDeMaquina(
          maquinas: _maquinas,
          escolhida: _maquinaIdLocal,
          aoEscolher: (id) => setState(() {
            _maquinaIdLocal = id;
            // A selecção era daquela máquina. Guardá-la ao trocar deixava
            // meios-dias marcados numa grelha que já é de outra coisa.
            _seleccionados.clear();
          }),
        ),
        const Divider(height: 1),
        Expanded(child: _grelha()),
        if (_maquinaIdLocal == null)
          const _Rodape(texto: 'Escolhe uma máquina para marcares os dias.')
        else if (_seleccionados.isNotEmpty && periodo == null)
          const _Rodape(
            texto: 'Os meios-dias têm de ser seguidos. Uma reserva é um '
                'período, não bocados soltos.',
          )
        else if (periodo != null)
          _RodapeDeCriar(
            texto: '${_maquina!.nome} · ${_comoSeLe(periodo)}',
            aoLimpar: () => setState(_seleccionados.clear),
            aoCriar: () => _criar(periodo),
          ),
      ],
    );
  }

  Widget _grelha() {
    final primeiro = _hoje.subtract(const Duration(days: _diasAtras));
    final total = _diasAtras + _diasAFrente + 1;
    return ListView.builder(
      controller: _rolo,
      itemExtent: _alturaDaLinha,
      itemCount: total,
      itemBuilder: (context, i) {
        final dia = DateTime(primeiro.year, primeiro.month, primeiro.day + i);
        return _LinhaDoDia(
          dia: dia,
          hoje: dia == _hoje,
          celulas: [
            for (final manha in [true, false])
              _celula(dia, manha),
          ],
        );
      },
    );
  }

  _Celula _celula(DateTime dia, bool manha) {
    final inicio = DateTime(dia.year, dia.month, dia.day, manha ? 0 : 12);
    final fim = inicio.add(const Duration(hours: 12));
    Reserva? ocupante;
    for (final r in _daMaquina) {
      if (r.inicio.isBefore(fim) && r.fim.isAfter(inicio)) {
        ocupante = r;
        break;
      }
    }
    return _Celula(
      rotulo: manha ? 'Manhã' : 'Tarde',
      ocupante: ocupante,
      seleccionada: _seleccionados.contains(inicio),
      activa: _maquinaIdLocal != null,
      aoTocar: () {
        if (_maquinaIdLocal == null) return;
        if (ocupante != null) {
          _mostrarReserva(ocupante);
          return;
        }
        setState(() {
          if (!_seleccionados.add(inicio)) _seleccionados.remove(inicio);
        });
      },
    );
  }

  String _comoSeLe(({DateTime inicio, DateTime fim}) periodo) {
    String meioDia(DateTime d) =>
        '${d.day}/${d.month} ${d.hour == 0 ? 'Manhã' : 'Tarde'}';
    final ultimo = periodo.fim.subtract(const Duration(hours: 12));
    return periodo.inicio == ultimo
        ? meioDia(periodo.inicio)
        : '${meioDia(periodo.inicio)} até ${meioDia(ultimo)}';
  }

  /// O que já está marcado naquele meio-dia, e o que se pode fazer com isso.
  Future<void> _mostrarReserva(Reserva r) async {
    final ePedido = r.estado == 'request';
    final confirmar = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.clienteNome.isEmpty ? 'Sem nome' : r.clienteNome,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${r.inicio.day}/${r.inicio.month} até '
                '${r.fim.day}/${r.fim.month} · ${_estadoPorExtenso(r.estado)}',
              ),
              if (r.notas.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(r.notas),
              ],
              const SizedBox(height: 20),
              if (ePedido)
                // O pedido continua a poder virar reserva — só deixou de ter
                // um separador só para ele. Aparece onde ocupa: no calendário.
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Fazer reserva'),
                ),
            ],
          ),
        ),
      ),
    );
    if (confirmar != true || !mounted) return;
    final resultado = await widget.estado.confirmarPedido(r);
    if (mounted) dizerComoCorreu(context, resultado, 'Reserva feita.');
  }

  static String _estadoPorExtenso(String estado) => switch (estado) {
    'request' => 'pedido por responder',
    'proposalSent' => 'proposta enviada',
    'confirmed' => 'reservada',
    'rented' => 'entregue',
    _ => estado,
  };

  Future<void> _criar(({DateTime inicio, DateTime fim}) periodo) async {
    final clientes = widget.estado.clientes;
    if (clientes.isEmpty) {
      // Não é uma escrita que correu bem — é uma que nem se tentou. Dizê-lo
      // como sucesso funcionava por acaso, porque a mensagem era o aviso.
      dizerComoCorreu(
        context,
        const Resultado.feito(),
        'Cria primeiro o cliente, no separador Clientes.',
      );
      return;
    }

    final cliente = await showDialog<Cliente>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Para quem é a reserva?'),
        children: [
          for (final c in clientes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c.nome),
                subtitle: c.telemovel.isEmpty ? null : Text(c.telemovel),
              ),
            ),
        ],
      ),
    );
    if (cliente == null || !mounted) return;

    final resultado = await widget.estado.criarReserva(
      cliente: cliente,
      maquinas: [_maquina!],
      inicio: periodo.inicio,
      fim: periodo.fim,
    );
    if (!mounted) return;
    setState(_seleccionados.clear);
    dizerComoCorreu(context, resultado, 'Reserva marcada.');
  }
}

class _EscolhaDeMaquina extends StatelessWidget {
  const _EscolhaDeMaquina({
    required this.maquinas,
    required this.escolhida,
    required this.aoEscolher,
  });
  final List<Maquina> maquinas;
  final String? escolhida;
  final ValueChanged<String> aoEscolher;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        for (final m in maquinas)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: m.idLocal == escolhida,
              onSelected: (_) => aoEscolher(m.idLocal),
              label: Text(m.nome),
              // A manutenção é a única que impede: uma máquina alugada hoje
              // pode receber reserva para a semana que vem, e travá-la aqui
              // tirava-lhe metade do valor.
              avatar: m.estado == 'maintenance'
                  ? const Icon(Icons.build, size: 16)
                  : null,
            ),
          ),
      ],
    ),
  );
}

class _LinhaDoDia extends StatelessWidget {
  const _LinhaDoDia({
    required this.dia,
    required this.hoje,
    required this.celulas,
  });
  final DateTime dia;
  final bool hoje;
  final List<Widget> celulas;

  static const _nomes = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

  @override
  Widget build(BuildContext context) {
    final fimDeSemana = dia.weekday >= DateTime.saturday;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        color: hoje ? PunhoTema.laranja.withValues(alpha: 0.10) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        children: [
          // Uma linha só, e não o dia por cima do mês: em duas linhas o texto
          // pedia 56 dp de altura numa linha de 48 e transbordava 9 px.
          // Apanhado pelo teste do calendário, antes de chegar ao telemóvel.
          SizedBox(
            width: 68,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_nomes[dia.weekday - 1]} ${dia.day}/${dia.month}',
                  maxLines: 1,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: hoje ? FontWeight.w900 : FontWeight.w700,
                    // O fim-de-semana não impede nada — só se distingue, para
                    // quem procura uma data não contar mal os dias.
                    color: fimDeSemana
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ),
          for (final celula in celulas) Expanded(child: celula),
        ],
      ),
    );
  }
}

class _Celula extends StatelessWidget {
  const _Celula({
    required this.rotulo,
    required this.ocupante,
    required this.seleccionada,
    required this.activa,
    required this.aoTocar,
  });
  final String rotulo;
  final Reserva? ocupante;
  final bool seleccionada, activa;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final ocupada = ocupante != null;
    final (Color fundo, Color letra) = switch ((ocupada, seleccionada)) {
      (true, _) => (PunhoTema.ocupada.withValues(alpha: 0.14), PunhoTema.ocupada),
      (_, true) => (PunhoTema.laranja, PunhoTema.navyDeep),
      _ => (Colors.white, Theme.of(context).colorScheme.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Material(
        color: activa ? fundo : fundo.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: aoTocar,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: ocupada
                    ? PunhoTema.ocupada.withValues(alpha: 0.35)
                    : Theme.of(context).dividerColor,
              ),
            ),
            child: Text(
              // Ocupado mostra de quem é. Dizer só "ocupado" obrigava a abrir
              // para saber se era do cliente que está ao telefone.
              ocupada
                  ? (ocupante!.clienteNome.isEmpty
                        ? 'Ocupada'
                        : ocupante!.clienteNome)
                  : rotulo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: letra,
                fontWeight: seleccionada || ocupada
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape({required this.texto});
  final String texto;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
      ),
    ),
  );
}

class _RodapeDeCriar extends StatelessWidget {
  const _RodapeDeCriar({
    required this.texto,
    required this.aoLimpar,
    required this.aoCriar,
  });
  final String texto;
  final VoidCallback aoLimpar, aoCriar;

  @override
  Widget build(BuildContext context) => Material(
    color: PunhoTema.navy,
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: aoLimpar,
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Limpar',
            ),
            FilledButton(onPressed: aoCriar, child: const Text('Reservar')),
          ],
        ),
      ),
    ),
  );
}
