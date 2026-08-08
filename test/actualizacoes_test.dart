import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:punho_operador/dados/actualizacoes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Guarda o que a app **pediu**, não só o que lhe responderam.
///
/// É o pedido que erra em silêncio: uma app mandada ao catálogo com o nome
/// errado recebe `app inválida`, o `procurar` engole a excepção e o operador
/// nunca fica a saber que há versão nova. Uma resposta de mentira bem montada
/// escondia isso.
class _Rede {
  final pedidos = <Map<String, dynamic>>[];
  final cabecalhosVistos = <Map<String, String>?>[];
  Object? resposta;

  Future<FunctionResponse> invocar(
    Map<String, dynamic> corpo,
    Map<String, String>? cabecalhos,
  ) async {
    pedidos.add(corpo);
    cabecalhosVistos.add(cabecalhos);
    return FunctionResponse(data: resposta, status: 200);
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Punho OP',
      packageName: 'pt.decisaodigital.punho_operador',
      version: '0.0.1',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('o pedido que sobe', () {
    test('pergunta pela app punho_op, com o build instalado', () async {
      final rede = _Rede()..resposta = {'actualizacao_disponivel': false};
      await ProcuraDeVersoes.comInvocador(rede.invocar).procurar();

      final pedido = rede.pedidos.single;
      // 'punho' aqui trazia as notas e o APK do gestor para o telemóvel do
      // operador. É a mesma casa, não é a mesma app.
      expect(pedido['app'], 'punho_op');
      expect(pedido['build_number_local'], 1);
      expect(pedido['plataforma'], isNotNull);
    });

    test('sem sessão não manda header de autorização', () async {
      final rede = _Rede()..resposta = {'actualizacao_disponivel': false};
      await ProcuraDeVersoes.comInvocador(rede.invocar).procurar();

      // É o caso de quem está preso no ecrã de entrada — precisamente quem tem
      // mais probabilidade de ter a app velha. A chave pública do projecto
      // chega para a Edge Function responder.
      expect(rede.cabecalhosVistos.single, isNull);
    });
  });

  group('o que se faz com a resposta', () {
    test('sem novidade não se anuncia nada', () async {
      final rede = _Rede()..resposta = {'actualizacao_disponivel': false};
      expect(
        await ProcuraDeVersoes.comInvocador(rede.invocar).procurar(),
        isNull,
      );
    });

    test('uma resposta estranha não rebenta a app', () async {
      final rede = _Rede()..resposta = 'isto não é um mapa';
      expect(
        await ProcuraDeVersoes.comInvocador(rede.invocar).procurar(),
        isNull,
      );
    });

    test('com novidade traz versão, build, url e hash', () async {
      final rede = _Rede()
        ..resposta = {
          'actualizacao_disponivel': true,
          'versao_actual': '0.0.2',
          'build_number': 2,
          'url_download':
              'https://github.com/DecisaoDigital/punho_operador/releases/download/v0.0.2/punho-op.apk',
          'obrigatoria': false,
          'notas_lancamento': 'Nada de especial.',
          'sha256': 'abc123',
        };

      final versao = await ProcuraDeVersoes.comInvocador(
        rede.invocar,
      ).procurar();

      expect(versao!.versao, '0.0.2');
      expect(versao.build, 2);
      expect(versao.sha256, 'abc123');
      expect(versao.podeInstalarSozinha, isTrue);
    });
  });

  group('a barreira do hash', () {
    test('sem sha256 publicado a app não se instala a si própria', () {
      const semHash = VersaoPublicada(
        versao: '0.0.2',
        build: 2,
        url: 'https://exemplo/punho-op.apk',
        obrigatoria: false,
      );
      // O `url_download` vem de uma coluna editável. Sem confirmar o ficheiro,
      // uma linha errada instalava outra coisa qualquer com a confiança de ser
      // uma actualização legítima.
      expect(semHash.podeInstalarSozinha, isFalse);
    });

    test('sha256 vazio conta como não haver', () {
      const vazio = VersaoPublicada(
        versao: '0.0.2',
        build: 2,
        url: 'https://exemplo/punho-op.apk',
        obrigatoria: false,
        sha256: '',
      );
      expect(vazio.podeInstalarSozinha, isFalse);
    });
  });

  test('o que vem do cache nunca pode prender a app', () {
    const doServidor = VersaoPublicada(
      versao: '0.0.2',
      build: 2,
      url: 'https://exemplo/punho-op.apk',
      obrigatoria: true,
      sha256: 'abc',
    );
    // Só uma resposta viva tem autoridade para bloquear. Se a linha for
    // retirada de `versoes_apps`, um `obrigatoria: true` guardado localmente
    // deixava o telemóvel trancado para sempre.
    expect(doServidor.semBloqueio().obrigatoria, isFalse);
    expect(doServidor.semBloqueio().sha256, 'abc');
  });
}
