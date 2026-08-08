import 'package:flutter/material.dart';

import '../../dados/estado.dart';
import '../../dados/servidor.dart';

// =============================================================================
// Hoje
// =============================================================================

/// O que ele tem para fazer agora.
///
/// Três blocos, por esta ordem: o que devia ter voltado e não voltou, o que sai
/// hoje, o que entra hoje. O atraso vem primeiro porque é o único que custa
/// dinheiro a cada dia que passa.
class HojeScreen extends StatelessWidget {
  const HojeScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) {
    final porEntregar = estado.entregasEmAtraso;
    final atraso = estado.recolhasEmAtraso;
    final entregas = estado.entregasDeHoje;
    final recolhas = estado.recolhasDeHoje;

    if (porEntregar.isEmpty &&
        atraso.isEmpty &&
        entregas.isEmpty &&
        recolhas.isEmpty) {
      return const Vazio(
        icone: Icons.check_circle_outline,
        titulo: 'Nada para entregar nem recolher hoje.',
        detalhe: 'Se estás à espera de alguma coisa, puxa para actualizar.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Primeiro de todos: há um cliente à espera de uma máquina que já devia
        // ter saído. É o que custa mais caro deixar passar.
        if (porEntregar.isNotEmpty) ...[
          const _Cabecalho('Já devia ter saído', urgente: true),
          for (final r in porEntregar)
            _CartaoDeReserva(
              reserva: r,
              estado: estado,
              accao: 'Entregar',
              aoAgir: () => estado.entregar(r),
              rodape: _diasDeEspera(r),
              urgente: true,
            ),
        ],
        if (atraso.isNotEmpty) ...[
          const _Cabecalho('Já devia ter voltado', urgente: true),
          for (final r in atraso)
            _CartaoDeReserva(
              reserva: r,
              estado: estado,
              accao: 'Recolher',
              aoAgir: () => estado.recolher(r),
              rodape: _diasDeAtraso(r),
              urgente: true,
            ),
        ],
        if (entregas.isNotEmpty) ...[
          const _Cabecalho('Entregar hoje'),
          for (final r in entregas)
            _CartaoDeReserva(
              reserva: r,
              estado: estado,
              accao: 'Entregar',
              aoAgir: () => estado.entregar(r),
            ),
        ],
        if (recolhas.isNotEmpty) ...[
          const _Cabecalho('Recolher hoje'),
          for (final r in recolhas)
            _CartaoDeReserva(
              reserva: r,
              estado: estado,
              accao: 'Recolher',
              aoAgir: () => estado.recolher(r),
            ),
        ],
      ],
    );
  }

  /// Dias de calendário, não horas a dividir por 24.
  ///
  /// Apanhado no telemóvel: uma reserva das 9h de ontem lida às 0h de hoje dá
  /// 15 horas, que em dias inteiros é zero — e o cartão dizia "hoje" a uma
  /// coisa de ontem. Quem conta atrasos conta dias no calendário.
  static int _diasDesde(DateTime quando) {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day)
        .difference(DateTime(quando.year, quando.month, quando.day))
        .inDays;
  }

  static String _diasDeEspera(Reserva r) {
    final dias = _diasDesde(r.inicio);
    if (dias <= 0) return 'Devia ter saído hoje';
    return dias == 1 ? 'Um dia à espera' : '$dias dias à espera';
  }

  static String _diasDeAtraso(Reserva r) {
    final dias = _diasDesde(r.fim);
    if (dias <= 0) return 'Devia ter voltado hoje';
    return dias == 1 ? 'Um dia de atraso' : '$dias dias de atraso';
  }
}

// =============================================================================
// Clientes
// =============================================================================

/// Os clientes da empresa, e criar um novo.
///
/// Não há apagar nem arquivar. Não é um botão escondido: o servidor recusa-o a
/// um colaborador, e um botão que dá erro ensina a desconfiar da app.
class ClientesScreen extends StatelessWidget {
  const ClientesScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: estado.clientes.isEmpty
        ? const Vazio(
            icone: Icons.people_outline,
            titulo: 'Ainda não há clientes.',
            detalhe: 'Cria o primeiro no botão em baixo.',
          )
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: estado.clientes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = estado.clientes[i];
              // A morada fica na linha de baixo, sozinha: é a única que é
              // comprida, e metida na mesma linha empurrava o telemóvel para
              // fora do ecrã — que é o que ele vai ligar.
              final morada = [
                if (c.morada != null && c.morada!.isNotEmpty) c.morada!,
                if (c.localidade != null && c.localidade!.isNotEmpty)
                  c.localidade!,
              ].join(', ');
              final abaixo = [
                if (c.telemovel.isNotEmpty) c.telemovel,
                if (c.nif != null && c.nif!.isNotEmpty) 'NIF ${c.nif}',
              ].join(' · ');
              return ListTile(
                isThreeLine: abaixo.isNotEmpty && morada.isNotEmpty,
                title: Text(c.nome),
                subtitle: (abaixo.isEmpty && morada.isEmpty)
                    ? null
                    : Text(
                        [
                          if (abaixo.isNotEmpty) abaixo,
                          if (morada.isNotEmpty) morada,
                        ].join('\n'),
                      ),
              );
            },
          ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _novoCliente(context),
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Novo cliente'),
    ),
  );

  Future<void> _novoCliente(BuildContext context) async {
    final nome = TextEditingController();
    final telemovel = TextEditingController();
    final contribuinte = TextEditingController();
    final morada = TextEditingController();
    final localidade = TextEditingController();
    final formulario = GlobalKey<FormState>();

    final criar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Novo cliente'),
        content: Form(
          key: formulario,
          // Cinco campos não cabem num diálogo com o teclado aberto — no
          // Redmi deitado sobram 192 dp de altura. Rola em vez de cortar.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nome,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Falta o nome.' : null,
                ),
                TextFormField(
                  controller: telemovel,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Telemóvel'),
                ),
                TextFormField(
                  controller: contribuinte,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Contribuinte',
                    // Não é obrigatório: o operador apanha o cliente em obra e
                    // nem sempre o NIF está à mão. Fica por preencher, e o
                    // gestor completa — melhor do que travar o cadastro.
                    helperText: 'Só se souber. 9 algarismos.',
                  ),
                  // Mas se escreveu alguma coisa, tem de ser um NIF. Um número
                  // a menos passa despercebido aqui e reaparece numa factura.
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    return RegExp(r'^\d{9}$').hasMatch(t)
                        ? null
                        : 'O contribuinte são 9 algarismos.';
                  },
                ),
                TextFormField(
                  controller: morada,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Morada'),
                ),
                TextFormField(
                  controller: localidade,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Localidade'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formulario.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (criar != true || !context.mounted) return;
    final subiu = await estado.criarCliente(
      nome: nome.text,
      telemovel: telemovel.text,
      nif: contribuinte.text,
      morada: morada.text,
      localidade: localidade.text,
    );
    if (context.mounted) dizerComoCorreu(context, subiu, 'Cliente criado.');
  }
}

// =============================================================================
// Máquinas
// =============================================================================

/// Todas as máquinas e se estão livres.
///
/// Todas mesmo — é o que lhe permite responder "essa está ocupada, mas tenho
/// esta" sem telefonar a ninguém.
class MaquinasScreen extends StatelessWidget {
  const MaquinasScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) {
    if (estado.maquinas.isEmpty) {
      return const Vazio(
        icone: Icons.precision_manufacturing_outlined,
        titulo: 'Ainda não há máquinas.',
        detalhe: 'Quem gere a empresa é que as cadastra.',
      );
    }
    final ordenadas = [...estado.maquinas]
      ..sort((a, b) {
        // Livres primeiro: a pergunta que se faz a este ecrã é "o que tenho
        // para dar", não "o que tenho ao todo".
        if (a.disponivel != b.disponivel) return a.disponivel ? -1 : 1;
        return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });

    return ListView.separated(
      itemCount: ordenadas.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final m = ordenadas[i];
        final cores = Theme.of(context).colorScheme;
        return ListTile(
          leading: Icon(
            m.disponivel ? Icons.check_circle : Icons.schedule,
            color: m.disponivel ? cores.primary : cores.outline,
          ),
          title: Text(m.nome),
          subtitle: Text(
            [
              if (m.referencia.isNotEmpty) m.referencia,
              if (m.categoria.isNotEmpty) m.categoria,
            ].join(' · '),
          ),
          trailing: Text(
            _estadoPorExtenso(m),
            style: TextStyle(
              color: m.disponivel ? cores.primary : cores.outline,
            ),
          ),
        );
      },
    );
  }

  /// O nome que o operador usa, não o que a base de dados guarda.
  static String _estadoPorExtenso(Maquina m) => switch (m.estado) {
    'available' => 'Livre',
    'rented' => 'Alugada',
    'maintenance' => 'Manutenção',
    // Um estado que esta versão não conhece mostra-se como está, em vez de se
    // fingir que é uma das outras.
    _ => m.estado,
  };
}

// =============================================================================
// Pagamentos
// =============================================================================

/// Aceitar o pagamento de uma reserva.
class PagamentosScreen extends StatelessWidget {
  const PagamentosScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) {
    final porCobrar = estado.porCobrar;
    if (porCobrar.isEmpty) {
      return const Vazio(
        icone: Icons.euro_outlined,
        titulo: 'Nada por cobrar.',
        detalhe: 'As reservas com valor aparecem aqui.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final r in porCobrar)
          _CartaoDeReserva(
            reserva: r,
            estado: estado,
            accao: 'Aceitar ${_euros(r.valorPrevistoCentimos!)}',
            aoAgir: () => estado.aceitarPagamento(r, r.valorPrevistoCentimos!),
          ),
      ],
    );
  }
}

// =============================================================================
// Peças partilhadas
// =============================================================================

class _CartaoDeReserva extends StatefulWidget {
  const _CartaoDeReserva({
    required this.reserva,
    required this.estado,
    required this.accao,
    required this.aoAgir,
    this.rodape,
    this.urgente = false,
  });

  final Reserva reserva;
  final EstadoDoOperador estado;
  final String accao;
  final Future<bool> Function() aoAgir;
  final String? rodape;
  final bool urgente;

  @override
  State<_CartaoDeReserva> createState() => _CartaoDeReservaState();
}

class _CartaoDeReservaState extends State<_CartaoDeReserva> {
  bool _aAgir = false;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final r = widget.reserva;
    final maquinas = [
      for (final id in r.maquinaIdsLocais)
        widget.estado.maquinaPorIdLocal(id)?.nome ?? id,
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              r.clienteNome.isEmpty ? 'Cliente sem nome' : r.clienteNome,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              maquinas.isEmpty ? 'Sem máquinas indicadas' : maquinas.join(', '),
            ),
            const SizedBox(height: 4),
            Text(
              '${_dataHora(r.inicio)} → ${_dataHora(r.fim)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.rodape != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.rodape!,
                style: TextStyle(
                  color: widget.urgente ? cores.error : cores.outline,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _aAgir ? null : _agir,
                child: _aAgir
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.accao),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _agir() async {
    setState(() => _aAgir = true);
    final subiu = await widget.aoAgir();
    if (!mounted) return;
    setState(() => _aAgir = false);
    dizerComoCorreu(context, subiu, 'Feito.');
  }
}

/// O que se diz ao operador depois de uma acção.
///
/// **Nunca um visto verde quando a coisa só ficou em fila.** Ele está em obra e
/// vai agir com base nisto: dizer-lhe "feito" quando o servidor ainda não sabe
/// de nada é o que faz alguém carregar duas vezes, ou ir-se embora convencido
/// de que a máquina já está marcada.
/// Diz-lhe como correu — e nunca finge que subiu quando não subiu.
void dizerComoCorreu(BuildContext context, bool subiu, String bem) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        subiu ? bem : 'Sem rede. Fica guardado e sobe assim que houver.',
      ),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho(this.texto, {this.urgente = false});
  final String texto;
  final bool urgente;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      texto.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: urgente
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.outline,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// Uma lista sem nada — dita como ausência, não como avaria.
class Vazio extends StatelessWidget {
  const Vazio({
    super.key,
    required this.icone,
    required this.titulo,
    required this.detalhe,
  });
  final IconData icone;
  final String titulo, detalhe;

  @override
  Widget build(BuildContext context) => ListView(
    // Lista e não Center: assim continua a puxar-se para actualizar mesmo
    // quando não há nada — que é justamente quando ele quer confirmar.
    children: [
      const SizedBox(height: 96),
      Icon(icone, size: 48, color: Theme.of(context).colorScheme.outline),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              detalhe,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ],
  );
}

String _dataHora(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _euros(int centimos) =>
    '${(centimos / 100).toStringAsFixed(2).replaceAll('.', ',')} €';
