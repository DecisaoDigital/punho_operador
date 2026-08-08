import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:punho_operador/core/config/supabase_config.dart';
import 'package:punho_operador/main.dart' as app;
import 'package:supabase_flutter/supabase_flutter.dart';

/// O dia do operador, corrido no telemóvel e contra o servidor a sério.
///
/// Não há aqui servidor de mentira nenhum: entra-se com a conta de colaborador,
/// carrega-se nos botões que ele carrega, e a seguir vai-se perguntar ao
/// servidor se o que ficou lá é o que devia ficar. É a diferença entre a app
/// *parecer* que funciona e ela funcionar.
///
/// Corre com:
/// ```
/// flutter test integration_test/o_dia_no_telemovel_test.dart -d <aparelho> \
///   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=... \
///   --dart-define=EMAIL_DE_TESTE=... --dart-define=SENHA_DE_TESTE=...
/// ```
const _email = String.fromEnvironment('EMAIL_DE_TESTE');
const _senha = String.fromEnvironment('SENHA_DE_TESTE');
const _empresa = String.fromEnvironment(
  'EMPRESA_DE_TESTE',
  defaultValue: '0e12f989-310c-47fc-a6e0-15231eb44848',
);

/// As máquinas da empresa de teste. A reserva do ensaio leva-as as duas, para
/// se ver que a entrega mexe em todas e não só na primeira.
const _maquinas = ['m1785969714554173', 'm1785969728505636'];

/// Espera até a condição se dar, sem fixar um tempo de sono à sorte.
///
/// `pumpAndSettle` não serve aqui: a app está sempre a falar com a rede e nunca
/// assenta. Isto vai bombeando frames e desiste ao fim do prazo.
Future<void> ateQue(
  WidgetTester tester,
  bool Function() condicao, {
  Duration prazo = const Duration(seconds: 45),
  String porque = '',
}) async {
  final fim = DateTime.now().add(prazo);
  while (DateTime.now().isBefore(fim)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (condicao()) return;
  }
  // O que estava no ecrã vai junto. Sem isto, uma espera falhada só diz que
  // esperou, e a corrida seguinte custa outra confirmação à mão no telemóvel.
  fail('esgotou o tempo à espera: $porque\nno ecrã estava: ${_oQueSeVe()}');
}

/// Tudo o que está escrito no ecrã, para acompanhar uma falha.
String _oQueSeVe() {
  final textos = <String>[];
  for (final elemento in find.byType(Text).evaluate()) {
    final t = (elemento.widget as Text).data;
    if (t != null && t.trim().isNotEmpty) textos.add(t.trim());
  }
  return textos.isEmpty ? '(nada)' : textos.join(' | ');
}

/// O mesmo, mas para o que só se vê perguntando ao servidor.
Future<T> ateQueOServidor<T>(
  WidgetTester tester,
  Future<T> Function() perguntar,
  bool Function(T) chega, {
  Duration prazo = const Duration(seconds: 45),
  String porque = '',
}) async {
  final fim = DateTime.now().add(prazo);
  T ultimo = await perguntar();
  while (DateTime.now().isBefore(fim)) {
    if (chega(ultimo)) return ultimo;
    await tester.pump(const Duration(milliseconds: 500));
    ultimo = await perguntar();
  }
  fail('esgotou o tempo à espera do servidor: $porque (último: $ultimo)');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('entra, entrega e recolhe — e o servidor fica a saber', (
    tester,
  ) async {
    expect(
      SupabaseConfig.enabled,
      isTrue,
      reason: 'faltam os --dart-define do Supabase',
    );
    expect(_email, isNotEmpty, reason: 'falta EMAIL_DE_TESTE');

    app.main();
    await tester.pump(const Duration(seconds: 2));
    final cliente = Supabase.instance.client;

    // ---- preparar o dia --------------------------------------------------
    // A reserva do ensaio começa e acaba hoje: é o que faz o mesmo cartão
    // aparecer primeiro em «Entregar hoje» e depois em «Recolher hoje».
    final idDaReserva = 'b${DateTime.now().microsecondsSinceEpoch}';
    await cliente.auth.signInWithPassword(email: _email, password: _senha);
    await _arrumarOCenario(cliente, idDaReserva);
    await cliente.auth.signOut();
    await tester.pump(const Duration(seconds: 1));

    // ---- entrar ----------------------------------------------------------
    await ateQue(
      tester,
      () => find.byType(TextField).evaluate().length >= 2,
      porque: 'o ecrã de entrada não apareceu',
    );
    final campos = find.byType(TextField);
    await tester.enterText(campos.at(0), _email);
    await tester.enterText(campos.at(1), _senha);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.tap(find.byType(FilledButton).first);

    // A sessão primeiro, e só depois o ecrã. Esperar por "Punho OP" não servia:
    // é também o título do ecrã de entrada, e a espera dava-se por satisfeita
    // sem ninguém ter entrado.
    await ateQue(
      tester,
      () => cliente.auth.currentSession != null,
      porque: 'a entrada não deu sessão nenhuma',
    );
    await ateQue(
      tester,
      () => find.byType(TabBar).evaluate().isNotEmpty,
      porque: 'não chegou à casa depois de entrar',
    );

    // ---- o que ele tem para fazer hoje -----------------------------------
    await ateQue(
      tester,
      // Em maiúsculas: é o `_Cabecalho` que as põe, e um `find.text` procura
      // exactamente o que está desenhado.
      () => find.text('ENTREGAR HOJE').evaluate().isNotEmpty,
      porque: 'a entrega de hoje não apareceu no ecrã',
    );
    expect(find.text('Cliente da Prova OP'), findsWidgets);

    // ---- entregar --------------------------------------------------------
    await tester.tap(find.text('Entregar').first);

    // A pergunta que interessa não é o que o ecrã diz — é o que ficou no
    // servidor, porque é lá que o gestor vai ler.
    final entregue = await ateQueOServidor(
      tester,
      () => _estadoDaReserva(cliente, idDaReserva),
      (e) => e == 'rented',
      porque: 'a reserva não passou a alugada no servidor',
    );
    expect(entregue, 'rented');
    await _ateQueAsMaquinasFiquem(
      tester,
      cliente,
      'rented',
      porque: 'as duas máquinas tinham de sair de disponíveis',
    );
    // O resto da reserva não se pode ter perdido pelo caminho: a app reenvia a
    // entidade inteira, não só o campo que mudou.
    final dados = await _dadosDaReserva(cliente, idDaReserva);
    expect(dados['notes'], 'Entregar na obra da Sé');
    expect(dados['expectedValueCents'], 18000);
    expect((dados['machineIds'] as List).length, 2);

    // ---- recolher --------------------------------------------------------
    await ateQue(
      tester,
      () => find.text('RECOLHER HOJE').evaluate().isNotEmpty,
      porque: 'a reserva entregue não passou para as recolhas de hoje',
    );
    await tester.tap(find.text('Recolher').first);

    final recolhida = await ateQueOServidor(
      tester,
      () => _estadoDaReserva(cliente, idDaReserva),
      (e) => e == 'completed',
      porque: 'a reserva não fechou no servidor',
    );
    expect(recolhida, 'completed');
    await _ateQueAsMaquinasFiquem(
      tester,
      cliente,
      'available',
      porque: 'as máquinas tinham de voltar a disponíveis',
    );

    // ---- criar um cliente, pelo formulário -------------------------------
    // O operador cria clientes na rua, com o cliente à frente dele. É a única
    // coisa que ele traz de novo ao sistema, e por isso é a que mais interessa
    // ver a chegar ao servidor pelo caminho de sempre.
    final nomeNovo = 'Prova UI ${DateTime.now().millisecondsSinceEpoch}';
    await _irPara(tester, 'Clientes');
    await _criarClientePeloFormulario(
      tester,
      nome: nomeNovo,
      telemovel: '912345678',
      contribuinte: '501234567',
      morada: 'Rua das Flores, 12',
      localidade: 'Vila do Conde',
    );

    final noServidor = await ateQueOServidor(
      tester,
      () => _clientesComNome(cliente, nomeNovo),
      (quantos) => quantos == 1,
      porque: 'o cliente criado no formulário não chegou ao servidor',
    );
    expect(noServidor, 1);

    // O nome chegar não prova que o resto chegou. O contribuinte e a morada
    // viajam dentro do `dados`, com os nomes do Punho do gestor — e se
    // subissem com outro nome, ninguém dava por nada: o cliente aparecia
    // criado, e os campos abriam vazios do lado dele.
    final ficha = await _dadosDoCliente(cliente, nomeNovo);
    expect(ficha['taxId'], '501234567');
    expect(ficha['address'], 'Rua das Flores, 12');
    expect(ficha['locality'], 'Vila do Conde');

    // E aparece-lhe na lista: criar sem ver criado é criar às escuras.
    await ateQue(
      tester,
      () => find.text(nomeNovo).evaluate().isNotEmpty,
      porque: 'o cliente novo não apareceu na lista',
    );
  });

  testWidgets('o que ele não pode fazer, o servidor recusa', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    final cliente = Supabase.instance.client;
    if (cliente.auth.currentSession == null) {
      await cliente.auth.signInWithPassword(email: _email, password: _senha);
    }

    // Esconder um botão é cortesia; a barreira é a política do servidor. Se
    // esta passar a deixar, a app do operador ganha poderes que ninguém lhe
    // deu — e isso não pode acontecer em silêncio.
    for (final proibido in [
      ('expense', {'amountCents': 5000}),
      ('vehicle', {'plate': 'AA-00-BB'}),
      ('collaborator', {'name': 'Alguém'}),
      ('inventada', <String, Object?>{}),
    ]) {
      await expectLater(
        _operar(cliente, proibido.$1, 'x${DateTime.now().microsecondsSinceEpoch}', proibido.$2),
        throwsA(
          isA<PostgrestException>().having((e) => e.code, 'code', '42501'),
        ),
        reason: 'o servidor devia ter recusado ${proibido.$1}',
      );
    }

    // E ninguém escreve directamente nas tabelas de leitura.
    await expectLater(
      cliente.from('punho_clientes').insert({
        'empresa_id': _empresa,
        'nome': 'Intruso',
        'telemovel': '000',
      }),
      throwsA(isA<PostgrestException>().having((e) => e.code, 'code', '42501')),
    );
  });

  testWidgets('sem rede fica guardado, e sobe sozinho quando ela volta', (
    tester,
  ) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));
    final cliente = Supabase.instance.client;
    if (cliente.auth.currentSession == null) {
      await cliente.auth.signInWithPassword(email: _email, password: _senha);
    }
    await ateQue(
      tester,
      () => find.byType(TabBar).evaluate().isNotEmpty,
      porque: 'não chegou à casa',
    );
    await _irPara(tester, 'Clientes');

    // ---- cortar a rede a sério -------------------------------------------
    // Rádio desligado, não um cliente HTTP a fingir. O que se quer saber é o
    // que a app faz num telemóvel numa obra sem cobertura.
    await _mudarARede(tester, cliente, ligada: false);

    final nomeOffline = 'Prova Offline ${DateTime.now().millisecondsSinceEpoch}';
    await _criarClientePeloFormulario(
      tester,
      nome: nomeOffline,
      telemovel: '913000111',
      localidade: 'Barcelos',
    );

    // A app tem de o dizer. Um visto verde aqui seria uma mentira: o cliente
    // ainda não existe para mais ninguém, e ele precisa de saber isso.
    await ateQue(
      tester,
      () => find.byIcon(Icons.cloud_off).evaluate().isNotEmpty,
      porque: 'a app não avisou que ficou alguma coisa por enviar',
    );

    // ---- repor a rede -----------------------------------------------------
    await _mudarARede(tester, cliente, ligada: true);

    // Duas portas para a mesma coisa, e o teste aceita qualquer uma. Se a app
    // ficou no ecrã de «não consigo falar com o servidor», volta-se por ali; se
    // ficou na lista de clientes, escoa-se na primeira escrita que passe, que é
    // como a fila é feita para escoar. O que se afirma é o resultado, não o
    // caminho — prender o teste a um dos dois era inventar uma regra que a app
    // nunca prometeu.
    final voltar = find.text('Tentar outra vez');
    final novo = find.widgetWithText(FloatingActionButton, 'Novo cliente');
    await ateQue(
      tester,
      () => voltar.evaluate().isNotEmpty || novo.evaluate().isNotEmpty,
      porque: 'não havia por onde voltar a falar com o servidor',
    );
    if (voltar.evaluate().isNotEmpty) {
      await tester.tap(voltar);
    } else {
      await _criarClientePeloFormulario(
        tester,
        nome: 'Prova Boleia ${DateTime.now().millisecondsSinceEpoch}',
        telemovel: '913000222',
        localidade: 'Esposende',
      );
    }

    final subiu = await ateQueOServidor(
      tester,
      () => _clientesComNome(cliente, nomeOffline),
      (quantos) => quantos == 1,
      prazo: const Duration(seconds: 90),
      porque: 'o cliente feito sem rede nunca chegou ao servidor',
    );
    expect(subiu, 1);

    // E uma só vez. A fila reenvia; se reenviasse a criar em vez de a repor,
    // ficavam dois clientes iguais e o operador é que os ia apagar à mão.
    await tester.pump(const Duration(seconds: 3));
    expect(await _clientesComNome(cliente, nomeOffline), 1);

    // Fila vazia: o aviso tem de desaparecer sozinho.
    await ateQue(
      tester,
      () => find.byIcon(Icons.cloud_off).evaluate().isEmpty,
      porque: 'o aviso de «por enviar» ficou lá depois de a fila escoar',
    );
  });
}

/// Toca num separador da barra de cima.
Future<void> _irPara(WidgetTester tester, String separador) async {
  await tester.tap(find.text(separador));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(seconds: 1));
}

/// Cria um cliente carregando no que ele carrega: o botão, os campos, o Criar.
Future<void> _criarClientePeloFormulario(
  WidgetTester tester, {
  required String nome,
  required String telemovel,
  required String localidade,
  String contribuinte = '',
  String morada = '',
}) async {
  // A mensagem da acção anterior fica por cima do botão e come o toque — o
  // botão sobe para lhe dar lugar e o dedo cai onde ele já não está. Um
  // operador tentava outra vez sem pensar; o teste faz o mesmo, em vez de
  // acusar a app de uma coisa que ela não tem.
  final botao = find.widgetWithText(FloatingActionButton, 'Novo cliente');
  final campos = find.byType(TextFormField);
  for (var tentativa = 0; tentativa < 4; tentativa++) {
    await ateQue(
      tester,
      () => find.byType(SnackBar).evaluate().isEmpty,
      prazo: const Duration(seconds: 10),
      porque: 'a mensagem anterior não saiu da frente do botão',
    );
    await tester.tap(botao, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 600));
    if (campos.evaluate().length >= 5) break;
  }
  // Cinco: nome, telemóvel, contribuinte, morada, localidade. Esperar por
  // três deixava o teste avançar com o formulário meio construído e escrever
  // a localidade no campo do contribuinte — que rejeita o que não sejam nove
  // algarismos, e o «Criar» ficava a recusar sem se perceber porquê.
  await ateQue(
    tester,
    () => campos.evaluate().length >= 5,
    porque: 'o formulário de cliente novo não abriu com os cinco campos',
  );

  // Por posição, na ordem em que estão no ecrã. Se alguém acrescentar um campo
  // pelo meio sem mexer aqui, o teste escreve nos sítios errados — e é por
  // isso que o contribuinte valida o formato: falha alto em vez de gravar
  // lixo.
  await tester.enterText(campos.at(0), nome);
  await tester.enterText(campos.at(1), telemovel);
  await tester.enterText(campos.at(2), contribuinte);
  await tester.enterText(campos.at(3), morada);
  await tester.enterText(campos.at(4), localidade);
  await tester.pump();

  await tester.tap(find.widgetWithText(FilledButton, 'Criar'));
  await tester.pump(const Duration(seconds: 1));
}

/// Liga ou desliga o rádio do aparelho.
///
/// De dentro do teste não há como lhe tocar — quem mexe é o `adb` do
/// computador. Combina-se por linhas impressas, que o guião do outro lado está
/// à espera de ver, e depois espera-se pelo que interessa mesmo: que o servidor
/// deixe (ou volte) a responder. Esperar pelo rádio não chegava — o Android diz
/// que a interface subiu muito antes de haver rota para lá fora.
Future<void> _mudarARede(
  WidgetTester tester,
  SupabaseClient cliente, {
  required bool ligada,
}) async {
  // ignore: avoid_print
  print(ligada ? '>>> LIGA A REDE' : '>>> CORTA A REDE');
  await ateQueOServidor(
    tester,
    () => _servidorResponde(cliente),
    (responde) => responde == ligada,
    prazo: const Duration(seconds: 120),
    porque: ligada ? 'a rede não voltou' : 'a rede não caiu',
  );
}

Future<bool> _servidorResponde(SupabaseClient cliente) async {
  try {
    await cliente
        .from('punho_maquinas')
        .select('id_local')
        .limit(1)
        .timeout(const Duration(seconds: 8));
    return true;
  } catch (_) {
    return false;
  }
}

/// O `dados` do cliente, tal como ficou gravado no servidor.
Future<Map<String, dynamic>> _dadosDoCliente(
  SupabaseClient cliente,
  String nome,
) async {
  final linha = await cliente
      .from('punho_clientes')
      .select('dados')
      .eq('empresa_id', _empresa)
      .eq('nome', nome)
      .single();
  return Map<String, dynamic>.from(linha['dados'] as Map);
}

Future<int> _clientesComNome(SupabaseClient cliente, String nome) async {
  final linhas = await cliente
      .from('punho_clientes')
      .select('id')
      .eq('empresa_id', _empresa)
      .eq('nome', nome);
  return (linhas as List).length;
}

/// Deixa o cenário como o operador o encontraria: máquinas disponíveis, um
/// cliente, e uma reserva confirmada para hoje.
Future<void> _arrumarOCenario(SupabaseClient cliente, String idDaReserva) async {
  final hoje = DateTime.now();
  DateTime as(int hora) => DateTime(hoje.year, hoje.month, hoje.day, hora);

  // Fechar o que ficou aberto de corridas anteriores. Sem isto o ecrã tem
  // vários «Entregar» e o `find.text(...).first` carrega no cartão errado — foi
  // o que aconteceu, e o teste acusou uma reserva que ninguém tinha tocado.
  final abertas = await cliente
      .from('punho_reservas')
      .select('id_local, dados')
      .eq('empresa_id', _empresa)
      .not('estado', 'in', '(completed,cancelled)');
  for (final l in abertas as List) {
    final linha = Map<String, dynamic>.from(l as Map);
    await _operar(cliente, 'booking', linha['id_local'] as String, {
      ...Map<String, dynamic>.from(linha['dados'] as Map),
      'status': 'completed',
    });
  }

  for (final maquina in _maquinas) {
    final linha = await cliente
        .from('punho_maquinas')
        .select('dados')
        .eq('id_local', maquina)
        .single();
    final dados = Map<String, dynamic>.from(linha['dados'] as Map);
    if (dados['status'] != 'available') {
      await _operar(cliente, 'machine', maquina, {
        ...dados,
        'status': 'available',
      });
    }
  }

  await _operar(cliente, 'customer', 'c1786143233147358', {
    'id': 'c1786143233147358',
    'name': 'Cliente da Prova OP',
    'phone': '911222333',
    'companyId': 'local-company',
    'archived': false,
  });

  await _operar(cliente, 'booking', idDaReserva, {
    'id': idDaReserva,
    'customerId': 'c1786143233147358',
    'customerNameSnapshot': 'Cliente da Prova OP',
    'machineIds': _maquinas,
    'startsAt': as(9).toUtc().toIso8601String(),
    'endsAt': as(18).toUtc().toIso8601String(),
    'status': 'confirmed',
    'expectedValueCents': 18000,
    'notes': 'Entregar na obra da Sé',
  });
}

/// Um uuid v4. A coluna `id` de `punho_operacoes` não tem `default`: é a app que
/// o gera, para poder repetir o envio sem duplicar a operação.
String _uuid() {
  final r = Random();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i, int j) =>
      b.sublist(i, j).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

Future<void> _operar(
  SupabaseClient cliente,
  String entidade,
  String idLocal,
  Map<String, Object?> payload,
) => cliente.from('punho_operacoes').insert({
  'id': _uuid(),
  'empresa_id': _empresa,
  'entidade': entidade,
  'entidade_id': idLocal,
  'payload': {'id': idLocal, ...payload},
  'feito_em': DateTime.now().toUtc().toIso8601String(),
  'por_utilizador': cliente.auth.currentUser?.id,
  'por_dispositivo': 'teste-de-integracao',
});

Future<String> _estadoDaReserva(SupabaseClient cliente, String idLocal) async {
  final linha = await cliente
      .from('punho_reservas')
      .select('estado')
      .eq('id_local', idLocal)
      .maybeSingle();
  return (linha?['estado'] as String?) ?? 'sem linha';
}

Future<Map<String, dynamic>> _dadosDaReserva(
  SupabaseClient cliente,
  String idLocal,
) async {
  final linha = await cliente
      .from('punho_reservas')
      .select('dados')
      .eq('id_local', idLocal)
      .single();
  return Map<String, dynamic>.from(linha['dados'] as Map);
}

/// Espera que as máquinas da reserva assentem no estado pedido.
///
/// Não se lê de uma vez: a app manda a reserva primeiro e cada máquina a
/// seguir, em operações separadas. Entre a reserva mudar e as máquinas mudarem
/// há uns dois décimos de segundo, e uma leitura única acertava ou falhava
/// conforme o dia estivesse. Falhou.
Future<void> _ateQueAsMaquinasFiquem(
  WidgetTester tester,
  SupabaseClient cliente,
  String estado, {
  required String porque,
}) async {
  await ateQueOServidor(
    tester,
    () => _estadosDasMaquinas(cliente),
    (estados) => estados.length == _maquinas.length &&
        estados.every((e) => e == estado),
    porque: porque,
  );
}

Future<List<String>> _estadosDasMaquinas(SupabaseClient cliente) async {
  final linhas = await cliente
      .from('punho_maquinas')
      .select('dados')
      .inFilter('id_local', _maquinas);
  return [
    for (final l in linhas as List)
      (Map<String, dynamic>.from(l as Map)['dados'] as Map)['status'] as String,
  ];
}
