import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/features/sessao/o_meu_perfil.dart';

/// O ecrã onde a pessoa se identifica.
///
/// Os testes param antes de gravar — o que se verifica aqui é o que o ecrã
/// recusa deixar passar, e isso decide-se sem servidor nenhum. A conferência do
/// dígito de controlo do contribuinte é do lado do servidor de propósito: uma
/// regra destas escrita em dois sítios acaba por divergir num deles, e o sítio
/// que conta é aquele que também apanha quem não passa pelo ecrã.
Future<void> _montar(WidgetTester tester, {String? nome, String? nif}) async {
  await tester.pumpWidget(
    MaterialApp(home: OMeuPerfil(nomeActual: nome, nifActual: nif)),
  );
  await tester.pumpAndSettle();
}

Finder _campo(String rotulo) => find.ancestor(
  of: find.text(rotulo),
  matching: find.byType(TextFormField),
);

void main() {
  testWidgets('abre com o que já lá está, para se corrigir e não reescrever', (
    tester,
  ) async {
    await _montar(tester, nome: 'Rui Bernardes', nif: '501442600');

    expect(find.text('Rui Bernardes'), findsOneWidget);
    expect(find.text('501442600'), findsOneWidget);
  });

  testWidgets('sem nome não guarda', (tester) async {
    await _montar(tester);

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Falta o nome.'), findsOneWidget);
  });

  testWidgets('o contribuinte é opcional — o nome sozinho chega', (
    tester,
  ) async {
    // Um ecrã que recusa gravar o nome porque falta o contribuinte é um ecrã
    // que ninguém preenche, e o nome é o que faz falta hoje.
    await _montar(tester);
    await tester.enterText(_campo('O seu nome'), 'Rui Bernardes');
    await tester.pump();

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('Falta o nome.'), findsNothing);
    expect(find.text('São 9 algarismos.'), findsNothing);
  });

  testWidgets('um contribuinte a meio é recusado antes de sair do telemóvel', (
    tester,
  ) async {
    await _montar(tester);
    await tester.enterText(_campo('O seu nome'), 'Rui Bernardes');
    await tester.enterText(_campo('Contribuinte (opcional)'), '5014');
    await tester.pump();

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(find.text('São 9 algarismos.'), findsOneWidget);
  });

  testWidgets('o campo do contribuinte não aceita letras nem pontuação', (
    tester,
  ) async {
    // O teclado numérico do Android ainda oferece vírgula e ponto, e um NIF
    // colado de uma mensagem vem muitas vezes com espaços. Filtrar aqui poupa
    // uma recusa do servidor por uma coisa que não é culpa de quem escreve.
    await _montar(tester);
    await tester.enterText(_campo('Contribuinte (opcional)'), '501.442-600 ab');
    await tester.pump();

    expect(find.text('501442600'), findsOneWidget);
  });

  testWidgets('não explica ao utilizador o que ele já sabe', (tester) async {
    // Esteve aqui um aviso a dizer que o contribuinte era o da pessoa e não o
    // da empresa. Saiu: ninguém preenche o nome de uma coisa com o número de
    // outra, e um campo que se explica de mais trata quem o lê como distraído.
    await _montar(tester);

    expect(find.textContaining('da empresa'), findsNothing);
  });
}
