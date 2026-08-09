import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Escreve no servidor o que o operador faz.
///
/// **Tudo passa por `punho_operacoes`.** É o único canal que o telemóvel do
/// gestor escuta: uma escrita directa numa tabela de leitura não chegava lá, e
/// ele nunca via a máquina sair. O servidor projecta para as tabelas por
/// gatilho, na mesma transacção, e o operador volta a lê-las já actualizadas.
///
/// O que o servidor deixa passar não é decidido aqui. `punho_operacoes` tem uma
/// política por perfil: um colaborador cria clientes mas não os arquiva, muda o
/// estado de uma máquina mas não a tira de circulação, e não toca em despesas,
/// veículos nem colaboradores. Esconder um botão é cortesia; a barreira é lá.
///
/// ## A fila
///
/// A regra é que no telemóvel só fica informação temporária quando não há
/// ligação — e é isso e nada mais que esta fila é. Guarda **o que ainda não
/// subiu**, e cada operação sai dela no instante em que o servidor a aceita.
/// Nunca guarda o estado da empresa.
/// Como correu uma escrita.
///
/// **Três desfechos e não dois.** Havia só `true`/`false`, e `false` era dito
/// ao operador como «Sem rede. Fica guardado e sobe assim que houver». Isso é
/// verdade quando não há rede — e é mentira quando o servidor recusou: aí a
/// operação foi deitada fora à frente dele, e ele fica à espera de uma subida
/// que não vai acontecer.
///
/// Passou a doer quando o servidor ganhou a guarda contra prometer a mesma
/// máquina duas vezes: o servidor explicava com quem ela estava, e a app
/// respondia «sem rede».
class Resultado {
  const Resultado._(this.subiu, this.motivo);

  /// O servidor tem-na.
  const Resultado.feito() : this._(true, null);

  /// Não há rede. Fica em fila e sobe sozinha.
  const Resultado.emFila() : this._(false, null);

  /// O servidor recusou em definitivo, e disse porquê. Não vai a lado nenhum.
  const Resultado.recusado(String porque) : this._(false, porque);

  final bool subiu;

  /// A explicação do servidor, quando houve uma. `null` quer dizer que o
  /// problema foi de ligação — que é coisa que passa.
  final String? motivo;

  bool get recusado => !subiu && motivo != null;
}

/// Por onde as alterações saem. Ver [FonteDeDados] para a razão de existir.
abstract interface class Canal {
  Future<Resultado> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  );
  Future<int> escoarFila();
  int get porEnviar;
}

class Escrita implements Canal {
  /// As preferências entram posicionais porque um parâmetro nomeado não pode
  /// começar por underscore, e o campo é privado.
  Escrita(this._cliente, this._preferencias, {required this.empresaId});

  final SupabaseClient _cliente;
  final String empresaId;
  final SharedPreferences _preferencias;

  static const _chaveFila = 'operacoes_por_enviar';
  static const _chaveAparelho = 'id_deste_aparelho';

  /// Grava uma alteração.
  ///
  /// Uma recusa em definitivo **não vai para a fila**: reenviá-la dava a mesma
  /// resposta para sempre e prendia atrás dela tudo o que viesse depois. Sai
  /// daqui com o motivo, para quem chama o poder dizer ao operador.
  @override
  Future<Resultado> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  ) async {
    final operacao = {
      'id': _novoUuid(),
      'empresa_id': empresaId,
      'entidade': entidade,
      'entidade_id': idLocal,
      'payload': payload,
      'feito_em': DateTime.now().toUtc().toIso8601String(),
      'por_utilizador': _cliente.auth.currentUser?.id,
      'por_dispositivo': _aparelho(),
    };

    try {
      // Drena primeiro o que ficou encalhado, e só depois sobe a operação nova.
      // A projecção toma a maior `seq`. Se a nova subisse primeiro e o atrasado
      // a seguir, uma versão velha da mesma entidade — uma reserva que ficara em
      // fila num 503 — sobrepunha-se à nova ao ganhar a `seq` maior. `escoarFila`
      // engole as suas próprias recusas, portanto não confunde o resultado desta.
      await escoarFila();
      await _enviar([operacao]);
      return const Resultado.feito();
    } on PostgrestException catch (erro) {
      if (_recusaDefinitiva(erro.code)) {
        return Resultado.recusado(_emPortugues(erro));
      }
      await _enfileirar(operacao);
      return const Resultado.emFila();
    } catch (_) {
      await _enfileirar(operacao);
      return const Resultado.emFila();
    }
  }

  /// A mensagem do servidor, quando serve; um genérico, quando não serve.
  ///
  /// As mensagens de `23514` e `42501` do Punho são escritas para serem lidas
  /// por quem está em obra — «A Betoneira 350L já está com o Sr. Costa nessas
  /// datas» diz-lhe o que fazer a seguir. O que não se mostra é o que o
  /// Postgres escreve sozinho, que fala de colunas e restrições.
  static String _emPortugues(PostgrestException erro) {
    final m = erro.message.trim();
    if (m.isEmpty || m.contains('violates') || m.contains('constraint')) {
      return 'O servidor não aceitou. Confirma os dados e tenta outra vez.';
    }
    return m;
  }

  /// Tenta subir o que ficou para trás. Chamado ao abrir cada ecrã.
  ///
  /// Uma operação recusada em definitivo pelo servidor — por exemplo, um
  /// colaborador a tentar arquivar um cliente — **sai da fila**. Se ficasse,
  /// prendia todas as que vêm atrás dela para sempre, e o operador ficava com
  /// um contador a subir sem nunca perceber porquê.
  @override
  Future<int> escoarFila() async {
    final fila = _fila();
    if (fila.isEmpty) return 0;

    var subiram = 0;
    final ficam = <Map<String, dynamic>>[];
    for (final operacao in fila) {
      try {
        await _enviar([operacao]);
        subiram++;
      } on PostgrestException catch (erro) {
        if (_recusaDefinitiva(erro.code)) continue;
        ficam.add(operacao);
      } catch (_) {
        ficam.add(operacao);
      }
    }
    await _gravarFila(ficam);
    return subiram;
  }

  /// Quantas alterações estão à espera de rede.
  @override
  int get porEnviar => _fila().length;

  Future<void> _enviar(List<Map<String, dynamic>> linhas) => _cliente
      .from('punho_operacoes')
      // `upsert` e não `insert`: se a rede cair depois de o servidor gravar mas
      // antes de a resposta chegar, a tentativa seguinte não pode duplicar a
      // operação. O `id` único faz o resto.
      //
      // `ignoreDuplicates` põe o servidor em `on conflict do nothing` em vez de
      // `do update`, e é a diferença entre um registo e uma tabela qualquer:
      //
      // 1. Uma operação é um facto já acontecido. Reenviar não é corrigir — é
      //    repetir. "Já tenho isso, obrigado" é a resposta certa.
      // 2. `do update` disparava um UPDATE, e o gatilho de projecção é
      //    `after insert`. Um reenvio passava sem projectar nada: a operação
      //    ficava no registo e a reserva nunca chegava à tabela.
      // 3. Só assim se pode revogar o privilégio de UPDATE no registo — o
      //    Postgres exige-o em tempo de planeamento com `do update`, mesmo
      //    quando não há conflito nenhum.
      .upsert(linhas, onConflict: 'id', ignoreDuplicates: true);

  /// Erros em que voltar a tentar nunca vai dar noutra coisa.
  ///
  /// `42501` é a política a recusar, `23514` uma validação, `23502`/`22P02`
  /// dados mal formados. Tudo o resto — rede, tempo esgotado, servidor em baixo
  /// — é para tentar outra vez.
  static bool _recusaDefinitiva(String? codigo) =>
      const {'42501', '23514', '23502', '22P02', '23503'}.contains(codigo);

  List<Map<String, dynamic>> _fila() {
    final cru = _preferencias.getString(_chaveFila);
    if (cru == null || cru.isEmpty) return [];
    try {
      return [
        for (final o in jsonDecode(cru) as List)
          Map<String, dynamic>.from(o as Map),
      ];
    } catch (_) {
      // Fila ilegível é fila que não serve para nada. Apaga-se em vez de
      // deixar a app a rebentar a cada arranque.
      _preferencias.remove(_chaveFila);
      return [];
    }
  }

  Future<void> _enfileirar(Map<String, dynamic> operacao) async {
    final fila = _fila()..add(operacao);
    await _gravarFila(fila);
  }

  Future<void> _gravarFila(List<Map<String, dynamic>> fila) async {
    if (fila.isEmpty) {
      await _preferencias.remove(_chaveFila);
      return;
    }
    await _preferencias.setString(_chaveFila, jsonEncode(fila));
  }

  /// Qual aparelho fez isto. Não identifica a empresa nem o operador — serve
  /// para quem lê o registo saber que duas alterações vieram de sítios
  /// diferentes.
  String _aparelho() {
    final guardado = _preferencias.getString(_chaveAparelho);
    if (guardado != null) return guardado;
    final novo = 'operador-${DateTime.now().microsecondsSinceEpoch}';
    _preferencias.setString(_chaveAparelho, novo);
    return novo;
  }

  /// Um uuid v4 sem trazer um pacote só para isto.
  String _novoUuid() {
    final agora = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final aparelho = _aparelho().hashCode.toUnsigned(32).toRadixString(16);
    final cauda = identityHashCode(Object()).toUnsigned(32).toRadixString(16);
    final cru = (agora + aparelho + cauda + '0' * 32).substring(0, 32);
    return '${cru.substring(0, 8)}-${cru.substring(8, 12)}-4'
        '${cru.substring(13, 16)}-a${cru.substring(17, 20)}-'
        '${cru.substring(20, 32)}';
  }
}

/// Os ids que a app do gestor gera, para o operador gerar iguais.
///
/// Prefixo mais microssegundos, como em `operational_pages.dart`. Dois
/// aparelhos a criar um cliente no mesmo microssegundo é o que seria preciso
/// para colidirem.
String novoIdLocal(String prefixo) =>
    '$prefixo${DateTime.now().microsecondsSinceEpoch}';
