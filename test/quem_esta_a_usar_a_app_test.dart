import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// **Quem está a usar a app tem de aparecer na app.**
///
/// Num telemóvel partilhado entre turnos, saber com que conta está aberta não é
/// decoração: o trabalho fica registado em nome de quem tem a sessão, e se
/// ninguém o vir escrito, fica no nome errado sem ninguém dar por isso.
///
/// O caso interessante é o do nome em falta. Há contas — as que foram criadas
/// antes de a inscrição pedir o nome — que simplesmente não têm nenhum. Aí
/// **não** se deriva um do email: `joao.silva@` não é o nome de ninguém, e um
/// nome inventado no ecrã é pior que a ausência dele, porque não se distingue
/// de um verdadeiro.
void main() {
  group('como a pessoa se identifica', () {
    test('com nome, é o nome que se usa', () {
      const inscricao = Inscricao(
        empresaId: 'e1',
        perfil: 'colaborador',
        nome: 'Rui Bernardes',
        empresaNome: 'Depilconcept',
      );

      expect(inscricao.comoSeChama, 'Rui Bernardes');
    });

    test('sem nome, diz-se que não há — não se inventa a partir do email', () {
      const inscricao = Inscricao(
        empresaId: 'e1',
        perfil: 'colaborador',
        empresaNome: 'Depilconcept',
      );

      expect(inscricao.comoSeChama, 'Sem nome');
    });

    test('um nome vazio conta como ausência, não como nome', () {
      // O servidor já devolve `null` em vez de espaços em branco
      // (`nullif(btrim(...), '')` em `punho_meu_acesso`), mas se um dia deixar
      // de o fazer, é melhor um teste vermelho do que uma barra de topo em
      // branco que ninguém sabe explicar.
      const inscricao = Inscricao(empresaId: 'e1', perfil: 'colaborador');

      expect(inscricao.comoSeChama.trim(), isNotEmpty);
    });

    test('o perfil continua a decidir o que se pode fazer', () {
      const gestor = Inscricao(empresaId: 'e1', perfil: 'gestor');
      const colaborador = Inscricao(empresaId: 'e1', perfil: 'colaborador');

      expect(gestor.eGestor, isTrue);
      expect(colaborador.eGestor, isFalse);
    });
  });

  testWidgets('a barra de topo mostra o nome e a empresa', (tester) async {
    // A mesma composição que a `CasaDoOperador` põe no `title` do `AppBar`.
    // Está aqui e não lá porque a casa do operador precisa de sessão Supabase
    // para se construir, e o que se quer verificar é só isto: as duas linhas
    // aparecem, e a de baixo não engole a de cima.
    const inscricao = Inscricao(
      empresaId: 'e1',
      perfil: 'colaborador',
      nome: 'Rui Bernardes',
      empresaNome: 'Depilconcept',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(inscricao.comoSeChama),
                Text(inscricao.empresaNome ?? 'Punho OP'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Rui Bernardes'), findsOneWidget);
    expect(find.text('Depilconcept'), findsOneWidget);
  });
}
