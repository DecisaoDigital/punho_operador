import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../dados/estado.dart';
import '../marca/marca.dart';
import '../sessao/inscricao.dart';
import '../sessao/o_meu_perfil.dart';
import 'reservas.dart';
import 'separadores.dart';

/// Os separadores da barra de cima, pela ordem em que aparecem.
///
/// **Hoje é o primeiro porque é a pergunta que o operador traz.** Ele abre a
/// app em obra, com o telemóvel numa mão, para saber o que tem para fazer
/// agora — não para navegar. Os outros existem para quando alguém lhe telefona
/// a perguntar uma coisa concreta.
///
/// A lista sai daqui e não de cinco `Tab` escritos à mão: a barra e o corpo
/// têm de ter o mesmo comprimento, e quando não têm o `TabController` rebenta
/// em execução, não na compilação.
enum Separador {
  hoje('Hoje'),
  reservas('Reservas'),
  clientes('Clientes'),
  maquinas('Máquinas'),
  pagamentos('Pagamentos');

  const Separador(this.rotulo);
  final String rotulo;
}

/// O que o operador vê depois de entrar.
class CasaDoOperador extends StatefulWidget {
  const CasaDoOperador({super.key, required this.inscricao});
  final Inscricao inscricao;

  @override
  State<CasaDoOperador> createState() => _CasaDoOperadorState();
}

class _CasaDoOperadorState extends State<CasaDoOperador> {
  EstadoDoOperador? _estado;

  /// A inscrição pode mudar sem se sair da app — é o que acontece quando a
  /// pessoa corrige o nome. Guarda-se aqui uma cópia para a barra de cima
  /// poder reflectir a correcção sem obrigar a sair e voltar a entrar.
  late Inscricao _inscricao = widget.inscricao;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  Future<void> _editarOsMeusDados() async {
    final guardou = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => OMeuPerfil(
          nomeActual: _inscricao.nome,
          nifActual: _inscricao.nif,
        ),
      ),
    );
    if (guardou != true || !mounted) return;

    // Relê do servidor em vez de assumir o que se escreveu: o servidor limpa
    // espaços e recusa o que não passa. O que ficou gravado é o que ele diz
    // que ficou, não o que o formulário tinha.
    final actualizada = await lerInscricao();
    if (!mounted || actualizada == null) return;
    setState(() => _inscricao = actualizada);
  }

  Future<void> _arrancar() async {
    final preferencias = await SharedPreferences.getInstance();
    if (!mounted) return;
    final estado = EstadoDoOperador.doSupabase(
      inscricao: widget.inscricao,
      preferencias: preferencias,
    );
    estado.addListener(_aoMudar);
    setState(() => _estado = estado);
    await estado.recarregar();
  }

  void _aoMudar() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _estado?.removeListener(_aoMudar);
    _estado?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = _estado;
    if (estado == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return DefaultTabController(
      length: Separador.values.length,
      child: Scaffold(
        appBar: AppBar(
          // O símbolo também aqui, e não só no ecrã de entrada: depois de
          // entrar, o operador passa a app inteira sem nada que lhe diga em
          // que app está. Tocar nele diz a versão instalada — que de outra
          // forma só se via saindo da sessão.
          leading: IconButton(
            onPressed: () => mostrarSobre(context),
            icon: const SimboloPunhoOp(lado: 28),
            tooltip: 'Punho OP — versão',
          ),
          // Quem está a usar a app, e onde. Ocupa a mesma linha que o nome da
          // app ocupava sozinho: num telemóvel em obra não há espaço para uma
          // barra só a dizer quem somos, e "Punho OP" já está no símbolo ao
          // lado. Sem isto, um telemóvel partilhado não diz a ninguém com que
          // conta está aberto — e o trabalho fica registado no nome errado.
          //
          // Tocar abre "Os meus dados". O lápis está sempre visível, e não só
          // quando falta o nome: quem tem o nome mal escrito precisa tanto de
          // o corrigir como quem não tem nenhum, e não descobriria o caminho
          // se ele aparecesse só a quem já está em falta.
          title: InkWell(
            onTap: _editarOsMeusDados,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _inscricao.comoSeChama,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _inscricao.empresaNome ?? 'Punho OP',
                        style: Theme.of(context).textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.edit_outlined, size: 16),
              ],
            ),
          ),
          actions: [
            if (estado.porEnviar > 0)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Tooltip(
                    message:
                        '${estado.porEnviar} por enviar. Sobem assim que houver rede.',
                    child: Chip(
                      avatar: const Icon(Icons.cloud_off, size: 16),
                      label: Text('${estado.porEnviar}'),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            IconButton(
              onPressed: () => Supabase.instance.client.auth.signOut(),
              icon: const Icon(Icons.logout),
              tooltip: 'Sair',
            ),
          ],
          bottom: TabBar(
            // De pé, num telemóvel, cinco separadores não cabem lado a lado sem
            // partir as palavras ao meio. A barra desliza — vê-se sempre o
            // separador inteiro, e o Hoje começa à vista, que é o que importa.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final s in Separador.values) Tab(text: s.rotulo)],
          ),
        ),
        body: estado.erro != null
            ? _SemServidor(erro: estado.erro!, aoTentar: estado.recarregar)
            : Stack(
                children: [
                  TabBarView(
                    children: [
                      for (final s in Separador.values)
                        RefreshIndicator(
                          onRefresh: estado.recarregar,
                          child: switch (s) {
                            Separador.hoje => HojeScreen(estado: estado),
                            Separador.reservas => ReservasScreen(
                              estado: estado,
                            ),
                            Separador.clientes => ClientesScreen(
                              estado: estado,
                            ),
                            Separador.maquinas => MaquinasScreen(
                              estado: estado,
                            ),
                            Separador.pagamentos => PagamentosScreen(
                              estado: estado,
                            ),
                          },
                        ),
                    ],
                  ),
                  // Fio fino em cima, em vez de tapar o ecrã: ele continua a
                  // ver o que estava a ler enquanto a app vai perguntar.
                  if (estado.aCarregar)
                    const Align(
                      alignment: Alignment.topCenter,
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Não se conseguiu perguntar ao servidor.
///
/// Ecrã próprio e não uma lista vazia. Esta app não guarda nada: sem servidor
/// não há estado nenhum para mostrar, e mostrar listas vazias dizia-lhe que a
/// empresa não tem trabalho — quando o que se passa é que ninguém sabe.
class _SemServidor extends StatelessWidget {
  const _SemServidor({required this.erro, required this.aoTentar});
  final String erro;
  final Future<void> Function() aoTentar;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 16),
          Text(
            erro,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta app não guarda nada no telemóvel — sem ligação não há nada '
            'para mostrar. O que tiveres feito sem rede não se perdeu.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: aoTentar,
            child: const Text('Tentar outra vez'),
          ),
        ],
      ),
    ),
  );
}
