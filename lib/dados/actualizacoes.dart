import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O mesmo sistema de actualizações das outras apps da casa.
///
/// A app pergunta à Edge Function `versao-mais-recente` se há build novo,
/// descarrega-o em segundo plano, confirma o SHA-256 publicado e entrega-o ao
/// Android. O catálogo é a tabela `versoes_apps`; o nome desta app lá é
/// [slugDaApp].
///
/// **A verificação do SHA-256 não é opcional.** O `url_download` vem de uma
/// coluna editável: sem confirmar o ficheiro, uma linha errada fazia a app
/// instalar outra coisa qualquer com a confiança de ser uma actualização
/// legítima. Sem hash publicado o instalador recusa-se a correr e sobra o
/// caminho antigo, pelo browser.
const slugDaApp = 'punho_op';

/// O que o servidor respondeu sobre a versão publicada.
class VersaoPublicada {
  const VersaoPublicada({
    required this.versao,
    required this.build,
    required this.url,
    required this.obrigatoria,
    this.notas,
    this.sha256,
  });

  final String versao;
  final int build;
  final String url;
  final bool obrigatoria;
  final String? notas;

  /// Impressão digital do APK publicado. Sem ela não se instala nada.
  final String? sha256;

  bool get podeInstalarSozinha => (sha256 ?? '').isNotEmpty;

  factory VersaoPublicada.doJson(Map<String, dynamic> json) => VersaoPublicada(
    versao: json['versao_actual'] as String,
    build: json['build_number'] as int,
    url: json['url_download'] as String,
    obrigatoria: json['obrigatoria'] as bool? ?? false,
    notas: json['notas_lancamento'] as String?,
    sha256: json['sha256'] as String?,
  );

  Map<String, dynamic> paraJson() => {
    'versao_actual': versao,
    'build_number': build,
    'url_download': url,
    'obrigatoria': obrigatoria,
    if (notas != null) 'notas_lancamento': notas,
    if (sha256 != null) 'sha256': sha256,
  };

  /// A mesma versão, mas sem poder prender a app.
  ///
  /// Só uma resposta viva do servidor tem autoridade para bloquear o operador
  /// fora da app. Um `obrigatoria: true` vindo do cache local significava que
  /// retirar a linha de `versoes_apps` deixava o telemóvel bloqueado para
  /// sempre, sem forma de recuperar sem limpar os dados da app.
  VersaoPublicada semBloqueio() => VersaoPublicada(
    versao: versao,
    build: build,
    url: url,
    obrigatoria: false,
    notas: notas,
    sha256: sha256,
  );
}

/// Em que ponto está a actualização.
enum FaseDaActualizacao {
  /// Há versão nova e ainda não se mexeu nela.
  disponivel,
  aDescarregar,

  /// Ficheiro em disco e verificado. Pronto a instalar quando ele quiser.
  pronta,
  aInstalar,

  /// O Android pediu confirmação — a app não pode fazer mais nada por si.
  aguardaConfirmacao,
  falhou,
}

/// Pergunta ao servidor se há versão nova.
///
/// **Não exige sessão iniciada.** A Edge Function corre com `verify_jwt: true`,
/// o que pede uma chave válida no header, não um utilizador autenticado: sem
/// sessão o `supabase_flutter` põe lá a chave pública do projecto. É isto que
/// permite avisar quem está preso no ecrã de entrada — que é onde um operador
/// com a app desactualizada é mais provável de ficar.
class ProcuraDeVersoes {
  ProcuraDeVersoes(SupabaseClient cliente)
    : _cliente = cliente,
      _invocar = ((corpo, cabecalhos) => cliente.functions
          .invoke('versao-mais-recente', body: corpo, headers: cabecalhos)
          .timeout(const Duration(seconds: 10)));

  /// Para testes: substitui a rede, sem cliente e portanto sem sessão — que é
  /// exactamente o cenário de quem nunca chegou a entrar.
  ProcuraDeVersoes.comInvocador(this._invocar) : _cliente = null;

  final SupabaseClient? _cliente;
  final Future<FunctionResponse> Function(
    Map<String, dynamic> corpo,
    Map<String, String>? cabecalhos,
  )
  _invocar;

  /// A versão a anunciar, ou `null` se não houver — ou se não se conseguiu
  /// saber. Falha em silêncio no ecrã e deixa rasto no log: um erro de rede no
  /// arranque não pode aparecer ao operador, mas também não pode ficar
  /// invisível para quem o for diagnosticar.
  Future<VersaoPublicada?> procurar() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      final sessao = _cliente?.auth.currentSession;
      final resposta = await _invocar(
        {
          'app': slugDaApp,
          'plataforma': _plataforma,
          'build_number_local': build,
        },
        sessao == null
            ? null
            : {'Authorization': 'Bearer ${sessao.accessToken}'},
      );
      final dados = resposta.data;
      if (dados is! Map || dados['actualizacao_disponivel'] != true) return null;
      return VersaoPublicada.doJson(Map<String, dynamic>.from(dados));
    } catch (erro) {
      debugPrint('[PunhoOP/update] procura falhou: ${erro.runtimeType} · $erro');
      return null;
    }
  }

  String get _plataforma => switch (Platform.operatingSystem) {
    'android' => 'android',
    'ios' => 'ios',
    'windows' => 'windows',
    _ => 'all',
  };
}

/// Descarrega o APK, confere-o e entrega-o ao Android.
class InstaladorDeApk {
  InstaladorDeApk({MethodChannel? canal, HttpClient? http})
    : _canal = canal ?? const MethodChannel('punho_op/instalador'),
      _http = http ?? HttpClient();

  final MethodChannel _canal;
  final HttpClient _http;

  Future<bool> podeInstalar() async {
    try {
      return await _canal.invokeMethod<bool>('podeInstalar') ?? false;
    } on PlatformException catch (e) {
      debugPrint('[PunhoOP/instalador] podeInstalar falhou: ${e.code}');
      return false;
    } on MissingPluginException {
      // Testes, ou qualquer sítio sem o canal nativo.
      return false;
    }
  }

  Future<void> pedirPermissao() async {
    try {
      await _canal.invokeMethod<void>('pedirPermissao');
    } on PlatformException catch (e) {
      debugPrint('[PunhoOP/instalador] pedirPermissao falhou: ${e.code}');
    } on MissingPluginException {
      // Sem canal nativo não há nada a pedir.
    }
  }

  /// Descarrega e confirma contra o hash publicado.
  ///
  /// Devolve o caminho do ficheiro, ou `null` se falhou — e nesse caso apaga o
  /// que ficou a meio, para não deixar lixo no telemóvel nem um ficheiro
  /// truncado que a tentativa seguinte confundisse com bom.
  Future<String?> descarregar(
    VersaoPublicada versao, {
    void Function(double)? aoProgredir,
  }) async {
    if (!versao.podeInstalarSozinha) {
      debugPrint('[PunhoOP/instalador] versão sem sha256 — não instalo');
      return null;
    }
    File? destino;
    try {
      final pasta = await getApplicationSupportDirectory();
      destino = File('${pasta.path}/punho-op-${versao.build}.apk');
      if (await destino.exists()) {
        // Já cá está de uma tentativa anterior: se o hash bater, poupa-se o
        // download todo.
        if (await _confere(destino, versao.sha256!)) return destino.path;
        await destino.delete();
      }

      final pedido = await _http.getUrl(Uri.parse(versao.url));
      final resposta = await pedido.close();
      if (resposta.statusCode != 200) {
        debugPrint('[PunhoOP/instalador] download deu ${resposta.statusCode}');
        return null;
      }

      final total = resposta.contentLength;
      var recebido = 0;
      final saida = destino.openWrite();
      await for (final bloco in resposta) {
        saida.add(bloco);
        recebido += bloco.length;
        if (total > 0) aoProgredir?.call(recebido / total);
      }
      await saida.flush();
      await saida.close();

      if (!await _confere(destino, versao.sha256!)) {
        debugPrint('[PunhoOP/instalador] SHA-256 não bate — ficheiro fora');
        await destino.delete();
        return null;
      }
      return destino.path;
    } catch (erro) {
      debugPrint('[PunhoOP/instalador] download falhou: $erro');
      try {
        if (destino != null && await destino.exists()) await destino.delete();
      } catch (_) {
        // Não conseguir limpar não é razão para esconder o erro original.
      }
      return null;
    }
  }

  /// Devolve `'instalado'`, `'pediu_confirmacao'` (o sistema decidiu perguntar,
  /// que é o normal à primeira vez) ou `null` em falha.
  Future<String?> instalar(String caminho) async {
    try {
      return await _canal.invokeMethod<String>('instalar', {
        'caminho': caminho,
      });
    } on PlatformException catch (e) {
      debugPrint('[PunhoOP/instalador] instalar falhou: ${e.code} · ${e.message}');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Lê em blocos: carregar o APK todo para memória para calcular o hash é
  /// pedir um estoiro num telemóvel apertado.
  Future<bool> _confere(File ficheiro, String esperado) async {
    try {
      final saida = _RecolheDigest();
      final entrada = sha256.startChunkedConversion(saida);
      await for (final bloco in ficheiro.openRead()) {
        entrada.add(bloco);
      }
      entrada.close();
      final obtido = saida.digest.toString();
      final bate = obtido.toLowerCase() == esperado.trim().toLowerCase();
      if (!bate) {
        debugPrint('[PunhoOP/instalador] esperado $esperado, obtido $obtido');
      }
      return bate;
    } catch (erro) {
      debugPrint('[PunhoOP/instalador] verificação falhou: $erro');
      return false;
    }
  }
}

/// Apanha o único `Digest` que a conversão em blocos produz no fim. Existe para
/// não trazer o `package:convert` só por causa do `AccumulatorSink`.
class _RecolheDigest implements Sink<Digest> {
  late final Digest digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}

/// O estado da actualização, para os ecrãs olharem.
class Actualizacoes extends ChangeNotifier with WidgetsBindingObserver {
  Actualizacoes({ProcuraDeVersoes? procura, InstaladorDeApk? instalador})
    : _procura =
          procura ??
          (Supabase.instance.isInitialized
              ? ProcuraDeVersoes(Supabase.instance.client)
              : null),
      _instalador = instalador ?? InstaladorDeApk();

  final ProcuraDeVersoes? _procura;
  final InstaladorDeApk _instalador;

  static const _chaveCache = 'punho_op.versao_conhecida';

  /// Um aviso guardado não vale para sempre. Se a versão for retirada de
  /// `versoes_apps` a procura passa a devolver `null` — e `null` é também o que
  /// devolve sem rede, por isso não dá para distinguir os dois casos e limpar o
  /// cache à conta disso. A validade resolve.
  static const _validadeDoCache = Duration(days: 7);

  Timer? _relogio;
  bool _vivo = true;

  VersaoPublicada? _versao;
  FaseDaActualizacao _fase = FaseDaActualizacao.disponivel;
  double _progresso = 0;
  String? _apk;
  String? _erro;

  /// A versão a anunciar, ou `null` se não há nada a dizer.
  VersaoPublicada? get versao => _versao;
  FaseDaActualizacao get fase => _fase;
  double get progresso => _progresso;
  String? get erro => _erro;

  /// O build que ele dispensou no X do aviso — só esse, e só nesta sessão.
  /// Dispensar não é esquecer: se sair uma versão ainda mais recente, o aviso
  /// volta.
  int? _dispensado;
  bool get dispensado => _dispensado != null && _dispensado == _versao?.build;
  void dispensar() {
    _dispensado = _versao?.build;
    notifyListeners();
  }

  /// Arranca a vigilância. Chamado uma vez, no arranque da app.
  Future<void> comecar() async {
    if (_procura == null) return;
    WidgetsBinding.instance.addObserver(this);
    // Voltar à app conta como momento de verificar. Sem isto havia só dois
    // momentos — o arranque de raiz e o relógio de 24 horas — e quem deixa a
    // app em segundo plano o dia todo nunca apanhava uma versão publicada
    // entretanto.
    _relogio = Timer.periodic(const Duration(hours: 24), (_) => procurar());
    await _lerCache();
    await procurar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(procurar());
  }

  @override
  void dispose() {
    _vivo = false;
    _relogio?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Pergunta ao servidor. Seguro de chamar a qualquer momento.
  Future<void> procurar() async {
    final nova = await _procura?.procurar();
    if (!_vivo || nova == null) return;
    // Só se escreve quando há novidade: uma procura falhada por estar sem rede
    // não pode apagar um aviso que já estava à vista.
    final mudou = nova.build != _versao?.build;
    _versao = nova;
    notifyListeners();
    unawaited(_guardarCache(nova));
    // Uma versão nova arranca a descarga por si — mas só em Wi-Fi, e só se
    // puder ser verificada.
    if (mudou && nova.podeInstalarSozinha) unawaited(descarregar());
  }

  /// Descarrega, se estiver em Wi-Fi.
  ///
  /// São dezenas de MB. O operador anda na rua, com plafond de dados, e gastá-lo
  /// sem lhe perguntar é abusar da confiança. Quem quiser força pelo botão.
  Future<void> descarregar() async {
    if (!await _emWifi()) {
      debugPrint('[PunhoOP/update] sem Wi-Fi — descarga adiada');
      return;
    }
    await descarregarAgora();
  }

  /// Descarrega mesmo sem Wi-Fi, porque foi ele a pedir.
  Future<void> descarregarAgora() async {
    final versao = _versao;
    if (versao == null || _fase == FaseDaActualizacao.aDescarregar) return;
    _mudar(FaseDaActualizacao.aDescarregar, progresso: 0, erro: null);
    final caminho = await _instalador.descarregar(
      versao,
      aoProgredir: (p) {
        if (_fase != FaseDaActualizacao.aDescarregar) return;
        _progresso = p;
        notifyListeners();
      },
    );
    if (!_vivo) return;
    if (caminho == null) {
      _mudar(
        FaseDaActualizacao.falhou,
        erro: 'Não consegui descarregar a actualização.',
      );
      return;
    }
    _apk = caminho;
    _mudar(FaseDaActualizacao.pronta);
  }

  /// Entrega ao Android. A app pode ser morta a meio disto — é o que acontece
  /// quando a instalação corre bem, e não é erro.
  Future<void> instalar() async {
    final caminho = _apk;
    if (caminho == null) return;
    if (!await _instalador.podeInstalar()) {
      // O Android exige autorização explícita para esta app instalar pacotes.
      // Abrem-se as definições; ele volta e carrega outra vez.
      await _instalador.pedirPermissao();
      return;
    }
    _mudar(FaseDaActualizacao.aInstalar);
    final desfecho = await _instalador.instalar(caminho);
    if (!_vivo) return;
    if (desfecho == null) {
      _mudar(FaseDaActualizacao.falhou, erro: 'A instalação não arrancou.');
      return;
    }
    if (desfecho == 'pediu_confirmacao') {
      _mudar(FaseDaActualizacao.aguardaConfirmacao);
    }
  }

  void _mudar(FaseDaActualizacao fase, {double? progresso, String? erro}) {
    _fase = fase;
    if (progresso != null) _progresso = progresso;
    _erro = erro;
    notifyListeners();
  }

  /// Wi-Fi é a única ligação que se assume gratuita. Em Android as interfaces
  /// de dados móveis chamam-se `rmnet*`/`ccmni*`; as de Wi-Fi, `wlan*`. Não é
  /// infalível, mas erra para o lado seguro: sem reconhecer Wi-Fi, não
  /// descarrega sozinho.
  Future<bool> _emWifi() async {
    try {
      final interfaces = await NetworkInterface.list(includeLoopback: false);
      return interfaces.any((i) => i.name.startsWith('wlan'));
    } catch (erro) {
      debugPrint('[PunhoOP/update] não consegui ver a rede: $erro');
      return false;
    }
  }

  /// Lê o último aviso conhecido, para o mostrar sem esperar pela rede.
  Future<void> _lerCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cru = prefs.getString(_chaveCache);
      if (cru == null) return;
      final envelope = Map<String, dynamic>.from(jsonDecode(cru) as Map);
      final quando = DateTime.tryParse(envelope['guardado_em'] as String? ?? '');
      if (quando == null ||
          DateTime.now().difference(quando) > _validadeDoCache) {
        await prefs.remove(_chaveCache);
        return;
      }
      final guardada = VersaoPublicada.doJson(
        Map<String, dynamic>.from(envelope['versao'] as Map),
      );
      final info = await PackageInfo.fromPlatform();
      if (guardada.build <= (int.tryParse(info.buildNumber) ?? 0)) {
        // Já instalou. O cache está velho e não serve.
        await prefs.remove(_chaveCache);
        return;
      }
      // A rede pode ter ganho a corrida. Se já há resposta viva, é mais fresca
      // do que isto — não a pisar.
      if (!_vivo || _versao != null) return;
      _versao = guardada.semBloqueio();
      notifyListeners();
    } catch (erro) {
      debugPrint('[PunhoOP/update] cache ilegível: $erro');
    }
  }

  Future<void> _guardarCache(VersaoPublicada versao) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _chaveCache,
        jsonEncode({
          'guardado_em': DateTime.now().toIso8601String(),
          'versao': versao.paraJson(),
        }),
      );
    } catch (erro) {
      debugPrint('[PunhoOP/update] não consegui guardar o cache: $erro');
    }
  }
}
