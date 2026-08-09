import 'package:flutter/material.dart';

import '../../dados/escrita.dart';
import '../../dados/estado.dart';
import '../../dados/servidor.dart';

// =============================================================================
// Hoje
// =============================================================================

/// O que ele tem para fazer agora, em cinco rubricas.
///
/// **Entregar, Recolher, Cobrar, Leads, Despesas** — uma coluna, por esta
/// ordem. Não são cinco separadores: são cinco blocos do mesmo ecrã, porque a
/// pergunta que o operador traz é uma só («o que tenho para fazer hoje») e
/// obrigá-lo a percorrer separadores para a responder é obrigá-lo a lembrar-se
/// de perguntar cinco vezes.
///
/// A ordem é a do dia dele e não uma escolha de arrumação: as máquinas saem de
/// manhã, voltam à tarde, o dinheiro cobra-se quando se está lá, os contactos
/// fazem-se nos intervalos, e as despesas lançam-se quando acontecem. Dentro de
/// cada rubrica o atraso vem primeiro — é o único que custa dinheiro por cada
/// dia que passa.
///
/// Uma coluna e não lado a lado: no telemóvel deitado sobram 192 dp de altura,
/// e duas colunas de cartões deixavam cada um com meia linha de texto. Trocar
/// para lado a lado é mudar o `ListView` por um `Row` de dois — se algum dia
/// isto for para tablet.
class HojeScreen extends StatelessWidget {
  const HojeScreen({super.key, required this.estado});
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) {
    final porEntregar = estado.entregasEmAtraso;
    final atraso = estado.recolhasEmAtraso;
    final entregas = estado.entregasDeHoje;
    final pedidos = estado.pedidosDeHoje;
    final recolhas = estado.recolhasDeHoje;
    final cobrar = estado.porCobrar;
    final leads = estado.leadsPorContactar;
    final despesas = estado.despesasDeHoje;

    if (porEntregar.isEmpty &&
        atraso.isEmpty &&
        entregas.isEmpty &&
        pedidos.isEmpty &&
        recolhas.isEmpty &&
        cobrar.isEmpty &&
        leads.isEmpty &&
        despesas.isEmpty) {
      return Vazio(
        icone: Icons.check_circle_outline,
        titulo: 'Nada em mãos hoje.',
        detalhe: 'Se estás à espera de alguma coisa, puxa para actualizar.',
        accao: FilledButton.tonalIcon(
          onPressed: () => _lancarDespesa(context, estado),
          icon: const Icon(Icons.receipt_long_outlined),
          label: const Text('Lançar um gasto'),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // ---- 1. Entregar --------------------------------------------------
        _Rubrica(
          titulo: 'Entregar',
          icone: Icons.local_shipping_outlined,
          quantos: porEntregar.length + entregas.length + pedidos.length,
          vazio: 'Não há máquinas para sair hoje.',
          children: [
            // Um cliente à espera de uma máquina que já devia ter saído é o que
            // custa mais caro deixar passar.
            for (final r in porEntregar)
              _CartaoDeReserva(
                reserva: r,
                estado: estado,
                accao: 'Entregar',
                aoAgir: () => estado.entregar(r),
                rodape: _diasDeEspera(r),
                urgente: true,
              ),
            for (final r in entregas)
              _CartaoDeReserva(
                reserva: r,
                estado: estado,
                accao: 'Entregar',
                aoAgir: () => estado.entregar(r),
              ),
            // Pedidos por responder que começam hoje. Não têm «Entregar»: um
            // pedido não confirmado não tem valor combinado, e entregá-lo era
            // pôr a máquina na rua sem dívida nenhuma registada.
            for (final r in pedidos)
              _CartaoDeReserva(
                reserva: r,
                estado: estado,
                accao: 'Confirmar a reserva',
                aoAgir: () => estado.confirmarPedido(r),
                rodape: 'Pedido por responder — confirma antes de entregar',
              ),
          ],
        ),

        // ---- 2. Recolher --------------------------------------------------
        _Rubrica(
          titulo: 'Recolher',
          icone: Icons.assignment_return_outlined,
          quantos: atraso.length + recolhas.length,
          vazio: 'Não há máquinas para voltar hoje.',
          children: [
            for (final r in atraso)
              _CartaoDeReserva(
                reserva: r,
                estado: estado,
                accao: 'Recolher',
                aoAgir: () => estado.recolher(r),
                rodape: _diasDeAtraso(r),
                urgente: true,
              ),
            for (final r in recolhas)
              _CartaoDeReserva(
                reserva: r,
                estado: estado,
                accao: 'Recolher',
                aoAgir: () => estado.recolher(r),
              ),
          ],
        ),

        // ---- 3. Cobrar ----------------------------------------------------
        _Rubrica(
          titulo: 'Cobrar',
          icone: Icons.euro_outlined,
          quantos: cobrar.length,
          resumo: cobrar.isEmpty ? null : _euros(estado.porCobrarCentimos),
          vazio: 'Está tudo pago.',
          children: [
            for (final c in cobrar)
              _CartaoDeCobranca(cobranca: c, estado: estado),
          ],
        ),

        // ---- 4. Leads -----------------------------------------------------
        _Rubrica(
          titulo: 'Leads',
          icone: Icons.phone_in_talk_outlined,
          quantos: leads.length,
          vazio: 'Ninguém à espera de resposta.',
          children: [for (final l in leads) _CartaoDeLead(lead: l)],
        ),

        // ---- 5. Despesas --------------------------------------------------
        _Rubrica(
          titulo: 'Despesas',
          icone: Icons.receipt_long_outlined,
          quantos: despesas.length,
          resumo: despesas.isEmpty
              ? null
              : _euros(estado.gastoDeHojeCentimos),
          vazio: 'Nada gasto hoje.',
          accao: TextButton.icon(
            onPressed: () => _lancarDespesa(context, estado),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Lançar'),
          ),
          children: [for (final d in despesas) _LinhaDeDespesa(despesa: d)],
        ),
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

/// Uma das cinco rubricas do dia.
///
/// **Mostra-se sempre, mesmo vazia.** Uma rubrica que desaparece quando não tem
/// nada obriga o operador a lembrar-se do que devia lá estar — e a dúvida
/// «será que não há, ou será que a app não carregou?» é exactamente o que se
/// quer evitar em obra. Vazia diz «não há», que é uma resposta.
class _Rubrica extends StatelessWidget {
  const _Rubrica({
    required this.titulo,
    required this.icone,
    required this.quantos,
    required this.vazio,
    required this.children,
    this.resumo,
    this.accao,
  });

  final String titulo, vazio;
  final IconData icone;
  final int quantos;

  /// Um número que resume a rubrica inteira — o total por cobrar, o gasto do
  /// dia. À direita do título, onde o olho já está.
  final String? resumo;

  final Widget? accao;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
          child: Row(
            children: [
              Icon(icone, size: 18, color: cores.outline),
              const SizedBox(width: 8),
              Text(
                titulo.toUpperCase(),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cores.outline,
                  letterSpacing: 0.8,
                ),
              ),
              if (quantos > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '$quantos',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cores.primary,
                  ),
                ),
              ],
              const Spacer(),
              if (resumo != null)
                Text(
                  resumo!,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: cores.onSurface,
                  ),
                ),
              ?accao,
            ],
          ),
        ),
        if (children.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(42, 0, 16, 4),
            child: Text(
              vazio,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cores.outline),
            ),
          )
        else
          ...children,
      ],
    );
  }
}

/// O que falta receber de uma reserva, e de quem.
///
/// «Cobrar tem de informar de quem» — o nome do cliente é o título, não uma
/// legenda: é a primeira coisa que o operador precisa de ler para saber a quem
/// vai pedir dinheiro.
class _CartaoDeCobranca extends StatelessWidget {
  const _CartaoDeCobranca({required this.cobranca, required this.estado});
  final Cobranca cobranca;
  final EstadoDoOperador estado;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    cobranca.cliente.isEmpty
                        ? 'Cliente sem nome'
                        : cobranca.cliente,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  _euros(cobranca.porCobrarCentimos),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_dataHora(cobranca.inicio)} → ${_dataHora(cobranca.fim)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            // Um pagamento parcial tem de se ver, senão o operador pede o valor
            // todo a quem já deu metade.
            if (cobranca.parcial) ...[
              const SizedBox(height: 4),
              Text(
                'Já recebeu ${_euros(cobranca.recebidoCentimos)} '
                'de ${_euros(cobranca.previstoCentimos)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cores.primary),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _receber(context),
                child: Text('Receber ${_euros(cobranca.porCobrarCentimos)}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _receber(BuildContext context) async {
    final pago = await mostrarRecebimento(context, cobranca);
    if (pago == null || !context.mounted) return;
    final resultado = await estado.aceitarPagamento(
      cobranca,
      pago.centimos,
      metodo: pago.metodo,
    );
    if (!context.mounted) return;
    dizerComoCorreu(context, resultado, 'Recebido.');
  }
}

/// Um contacto por fazer.
class _CartaoDeLead extends StatelessWidget {
  const _CartaoDeLead({required this.lead});
  final Lead lead;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lead.nome.isEmpty ? 'Sem nome' : lead.nome,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (lead.telefone.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(lead.telefone),
          ],
          if (lead.origem.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Veio de: ${lead.origem}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (lead.resumo.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(lead.resumo, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    ),
  );
}

/// Um gasto do dia, com quem o lançou e a que horas.
///
/// «O gestor tem de ver quem lhe enviou o gasto. Nome do funcionário, horas,
/// data.» As horas são as do **servidor** (`recebida_em`), não as do payload:
/// a data que o operador escreve é uma alegação, a hora a que a operação
/// chegou é um facto.
class _LinhaDeDespesa extends StatelessWidget {
  const _LinhaDeDespesa({required this.despesa});
  final Despesa despesa;

  @override
  Widget build(BuildContext context) {
    final d = despesa;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.receipt_outlined),
      title: Text(
        d.descricao.isEmpty
            ? (d.categoria.isEmpty ? 'Gasto sem descrição' : d.categoria)
            : d.descricao,
      ),
      subtitle: Text(
        '${d.lancadaPor} · ${_dataHora(d.recebidaEm)}'
        '${d.categoria.isEmpty ? '' : ' · ${d.categoria}'}',
      ),
      trailing: Text(
        _euros(d.valorCentimos),
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

/// O que o operador respondeu no diálogo de recebimento.
class Recebimento {
  const Recebimento({required this.centimos, required this.metodo});
  final int centimos;
  final String metodo;
}

/// Os métodos de pagamento que o Punho do gestor conhece.
///
/// **Os mesmos nomes que o modelo dele usa** (`PaymentMethod`). Um nome
/// inventado aqui era um recibo que o gestor não sabia ler.
const _metodos = <String, String>{
  'cash': 'Dinheiro',
  'mbWay': 'MB Way',
  'multibanco': 'Multibanco',
  'transfer': 'Transferência',
  'other': 'Outro',
};

/// Pergunta quanto e como. Devolve `null` se desistir.
Future<Recebimento?> mostrarRecebimento(
  BuildContext context,
  Cobranca cobranca,
) {
  final valor = TextEditingController(
    text: (cobranca.porCobrarCentimos / 100).toStringAsFixed(2),
  );
  final formulario = GlobalKey<FormState>();
  var metodo = 'cash';

  return showDialog<Recebimento>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refazer) => AlertDialog(
        title: Text(
          cobranca.cliente.isEmpty ? 'Receber' : 'Receber de ${cobranca.cliente}',
        ),
        content: Form(
          key: formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: valor,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quanto recebeu',
                    suffixText: '€',
                  ),
                  validator: (v) {
                    final c = _centimosDeTexto(v);
                    if (c == null) return 'Escreve um valor.';
                    if (c <= 0) return 'Tem de ser mais do que zero.';
                    if (c > cobranca.porCobrarCentimos) {
                      return 'São só ${_euros(cobranca.porCobrarCentimos)}.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: metodo,
                  decoration: const InputDecoration(labelText: 'Como pagou'),
                  items: [
                    for (final e in _metodos.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => refazer(() => metodo = v ?? 'cash'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Deixar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formulario.currentState!.validate()) return;
              Navigator.of(context).pop(
                Recebimento(
                  centimos: _centimosDeTexto(valor.text)!,
                  metodo: metodo,
                ),
              );
            },
            child: const Text('Receber'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _lancarDespesa(
  BuildContext context,
  EstadoDoOperador estado,
) async {
  final valor = TextEditingController();
  final descricao = TextEditingController();
  final formulario = GlobalKey<FormState>();
  var categoria = 'combustivel';

  const categorias = <String, String>{
    'combustivel': 'Combustível',
    'portagens': 'Portagens',
    'material': 'Material',
    'refeicoes': 'Refeições',
    'reparacao': 'Reparação',
    'outro': 'Outro',
  };

  final lancar = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, refazer) => AlertDialog(
        title: const Text('Lançar um gasto'),
        content: Form(
          key: formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: valor,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Quanto',
                    suffixText: '€',
                  ),
                  validator: (v) {
                    final c = _centimosDeTexto(v);
                    if (c == null) return 'Escreve um valor.';
                    return c <= 0 ? 'Tem de ser mais do que zero.' : null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: categoria,
                  decoration: const InputDecoration(labelText: 'De quê'),
                  items: [
                    for (final e in categorias.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) =>
                      refazer(() => categoria = v ?? 'outro'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descricao,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'O que foi',
                    helperText: 'O gestor vê isto e o teu nome.',
                  ),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Diz o que foi.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deixar'),
          ),
          FilledButton(
            onPressed: () {
              if (!formulario.currentState!.validate()) return;
              Navigator.of(context).pop(true);
            },
            child: const Text('Lançar'),
          ),
        ],
      ),
    ),
  );

  if (lancar != true || !context.mounted) return;
  final resultado = await estado.lancarDespesa(
    centimos: _centimosDeTexto(valor.text)!,
    categoria: categoria,
    descricao: descricao.text,
  );
  if (!context.mounted) return;
  dizerComoCorreu(context, resultado, 'Gasto lançado.');
}

/// Euros escritos por uma pessoa, em cêntimos.
///
/// Aceita vírgula e ponto — quem escreve num telemóvel português escreve
/// «12,50», e o teclado numérico dá as duas. `null` quer dizer que não se
/// consegue ler, e nesse caso não se adivinha zero: zero é um valor, e um
/// recibo de zero euros é pior do que um erro no ecrã.
int? _centimosDeTexto(String? texto) {
  final limpo = (texto ?? '').trim().replaceAll(' ', '').replaceAll(',', '.');
  if (limpo.isEmpty) return null;
  final euros = double.tryParse(limpo);
  if (euros == null || euros.isNaN || euros.isInfinite) return null;
  // Arredonda em vez de truncar: `(12.35 * 100).toInt()` dá 1234 em vírgula
  // flutuante, e um cêntimo a menos por cada recibo é uma caixa que não fecha.
  return (euros * 100).round();
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
    final resultado = await estado.criarCliente(
      nome: nome.text,
      telemovel: telemovel.text,
      nif: contribuinte.text,
      morada: morada.text,
      localidade: localidade.text,
    );
    if (context.mounted) dizerComoCorreu(context, resultado, 'Cliente criado.');
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
///
/// A mesma lista que a rubrica «Cobrar» do separador Hoje, e de propósito: são
/// a mesma pergunta, e duas contas diferentes para a mesma dívida era a app a
/// contradizer-se a si própria consoante o separador aberto.
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
        detalhe: 'As reservas com valor por receber aparecem aqui.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Falta receber ${_euros(estado.porCobrarCentimos)} ao todo.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final c in porCobrar)
          _CartaoDeCobranca(cobranca: c, estado: estado),
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
  final Future<Resultado> Function() aoAgir;
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
    final resultado = await widget.aoAgir();
    if (!mounted) return;
    setState(() => _aAgir = false);
    dizerComoCorreu(context, resultado, 'Feito.');
  }
}

/// O que se diz ao operador depois de uma acção.
///
/// **Nunca um visto verde quando a coisa só ficou em fila.** Ele está em obra e
/// vai agir com base nisto: dizer-lhe "feito" quando o servidor ainda não sabe
/// de nada é o que faz alguém carregar duas vezes, ou ir-se embora convencido
/// de que a máquina já está marcada.
///
/// E nunca «sem rede» quando o servidor **recusou**. Eram os dois o mesmo
/// `false`, e a diferença é toda: uma fica guardada e sobe sozinha, a outra foi
/// deitada fora e não volta. Quando o servidor explica porquê — «a Betoneira
/// já está com o Sr. Costa nessas datas» — é isso que ele tem de ler, e fica no
/// ecrã o tempo de o ler.
void dizerComoCorreu(BuildContext context, Resultado resultado, String bem) {
  final recusa = resultado.motivo;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        resultado.subiu
            ? bem
            : recusa ?? 'Sem rede. Fica guardado e sobe assim que houver.',
      ),
      behavior: SnackBarBehavior.floating,
      duration: recusa == null
          ? const Duration(seconds: 4)
          : const Duration(seconds: 8),
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
    this.accao,
  });
  final IconData icone;
  final String titulo, detalhe;

  /// O que ainda se pode fazer quando não há nada à espera. Um ecrã vazio sem
  /// saída nenhuma manda a pessoa sair da app para lançar um gasto.
  final Widget? accao;

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
            if (accao != null) ...[const SizedBox(height: 24), accao!],
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
