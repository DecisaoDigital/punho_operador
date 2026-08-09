import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/identidade/machine_id.dart';
import '../../core/identidade/nif.dart';
import '../marca/marca.dart';

/// Inscrever-se na app do operador.
///
/// **Inscrever-se não é entrar.** O que isto cria é um pedido pendente: a conta
/// nasce, o Control vê-a, e só a aprovação lhe dá acesso a uma empresa. Sem ela
/// a pessoa entra e encontra o aviso de que ainda não tem acesso — que é o que
/// já acontecia antes de haver este ecrã.
///
/// É por isso que a app do operador pode ter registo sem abrir uma porta: quem
/// decide continua a ser quem gere. O que muda é que a pessoa passa a poder
/// pedir, em vez de depender de alguém a registar por ela noutra app.
///
/// O **nome** é o motivo de este ecrã existir. Sem ele o operador é um UUID:
/// dentro da empresa ninguém sabe quem atendeu, quem marcou, quem recebeu. O
/// email não serve — é da conta, não da pessoa, e ninguém reconhece um colega
/// por ele.
///
/// O `perfil` não é perguntado: quem se inscreve por aqui é colaborador. Fundar
/// uma empresa ou ser gestor faz-se no Punho. Mesmo que alguém forje o pedido,
/// o servidor força `colaborador` para tudo o que venha com `app: punho_op`.
class RegistoScreen extends StatefulWidget {
  const RegistoScreen({super.key});

  @override
  State<RegistoScreen> createState() => _RegistoScreenState();
}

class _RegistoScreenState extends State<RegistoScreen> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _palavraPasse = TextEditingController();
  final _empresa = TextEditingController();
  final _convite = TextEditingController();
  final _contribuinte = TextEditingController();
  final _formulario = GlobalKey<FormState>();
  bool _aRegistar = false;
  String? _erro;
  bool _feito = false;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _palavraPasse.dispose();
    _empresa.dispose();
    _convite.dispose();
    _contribuinte.dispose();
    super.dispose();
  }

  Future<void> _registar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _aRegistar = true;
      _erro = null;
    });
    try {
      // O aparelho identifica-se sozinho. Não é um campo do formulário de
      // propósito: é uma propriedade do telemóvel, não uma afirmação que quem
      // se inscreve possa fazer sobre si próprio.
      final machineId = await resolverMachineId();

      final resposta = await Supabase.instance.client.auth.signUp(
        email: _email.text.trim(),
        password: _palavraPasse.text,
        data: {
          // `app` é o que faz o gatilho `punho_criar_pedido_ao_registar`
          // reparar neste registo. Sem ele a conta nascia e mais nada: sem
          // pedido, ninguém a via para aprovar.
          'app': 'punho_op',
          'nome': _nome.text.trim(),
          'empresa': _empresa.text.trim(),
          'perfil': 'colaborador',
          'machine_id': machineId,
          // **É o código que liga o pedido à empresa.** Sem ele o pedido nasce
          // com `empresa_id` nulo, e nulo quer dizer "não se sabe de que casa
          // é" — o gestor não o vê na lista dele e a pessoa fica à espera de
          // uma autorização que ninguém tem onde dar. Descobriu-se assim, a
          // fazer o percurso todo no aparelho.
          if (_convite.text.trim().isNotEmpty)
            'convite': _convite.text.trim().toUpperCase(),
          // O contribuinte **da pessoa**, nunca o da empresa.
          //
          // Vai aqui e não num ecrã a seguir porque é aqui que a ficha de
          // empregado nasce: quando o gestor aprova, o servidor cria a ficha
          // com o que a pessoa declarou. Sem este campo a ficha nascia com o
          // NIF vazio, e passava a ser mais uma coisa que alguém tinha de
          // andar a perguntar depois.
          if (_contribuinte.text.trim().isNotEmpty)
            'nif': _contribuinte.text.trim(),
        },
      );

      // Email já registado **não vem como erro**. Com a confirmação de email
      // ligada, o Supabase protege-se contra enumeração de contas: devolve
      // sucesso com a lista de identidades vazia. Sem isto, quem se tentasse
      // inscrever com um email que já tem conta ficava à espera de um email que
      // nunca chega.
      final identidades = resposta.user?.identities;
      if (identidades != null && identidades.isEmpty) {
        if (mounted) {
          setState(() {
            _erro = 'Já existe uma conta com este email. Entre em vez de se '
                'inscrever.';
          });
        }
        return;
      }

      if (mounted) setState(() => _feito = true);
    } on AuthException catch (e) {
      if (mounted) setState(() => _erro = _emPortugues(e));
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Não consegui falar com o servidor.');
      }
    } finally {
      if (mounted) setState(() => _aRegistar = false);
    }
  }

  /// As mensagens do fornecedor vêm em inglês e falam de coisas que não são do
  /// operador. Traduzem-se as que ele pode resolver; o resto fica genérico.
  ///
  /// **Traduz-se pelo código, não por procurar palavras na frase.** A primeira
  /// versão disto dizia "Esse email não é válido" a tudo o que tivesse a
  /// palavra `email` na mensagem — e apanhou-se no aparelho a dizê-lo a um
  /// `over_email_send_rate_limit`, que é o Supabase a recusar mandar mais
  /// emails de confirmação por agora. O endereço estava certo; a app é que
  /// mandava a pessoa procurar um erro que não existia, e nenhuma tentativa
  /// seguinte ia resolver o que ela julgava estar a corrigir.
  String _emPortugues(AuthException e) {
    switch (e.code) {
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Já foram enviados demasiados emails de confirmação nos últimos '
            'minutos. Espere um pouco e tente outra vez — o endereço está bem.';
      case 'weak_password':
        return 'A palavra-passe é demasiado fraca — use pelo menos 6 '
            'caracteres.';
      case 'email_address_invalid':
      case 'validation_failed':
        return 'Esse email não é válido.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Já existe uma conta com este email. Entre em vez de se '
            'inscrever.';
    }
    // Sem código conhecido diz-se que não foi, e diz-se o que o servidor
    // respondeu. Inventar um motivo é pior do que admitir que não se sabe:
    // manda a pessoa corrigir a coisa errada.
    return 'Não foi possível criar a conta. O servidor respondeu: ${e.message}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Inscrever-se')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _feito ? _Confirmacao(email: _email.text.trim()) : _formularioWidget(),
        ),
      ),
    ),
  );

  Widget _formularioWidget() => Form(
    key: _formulario,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SimboloPunhoOp(),
        const SizedBox(height: 24),
        const Text(
          'Use o código que recebeu. É ele que diz a que empresa pertence — '
          'sem ele ninguém tem onde autorizar o seu acesso.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextFormField(
          controller: _nome,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'O seu nome',
            helperText: 'É por aqui que os colegas o identificam.',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || v.trim().length < 2) ? 'Falta o nome.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _convite,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Código do convite',
            helperText: 'Veio na mensagem de quem o convidou.',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().length < 4)
              ? 'Falta o código do convite.'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _contribuinte,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Contribuinte',
            helperText: 'O seu, não o da empresa. Vai para a sua ficha.',
            border: OutlineInputBorder(),
          ),
          // Nove dígitos com dígito de controlo, a mesma conta que o servidor
          // faz em `punho_nif_valido`. Validar aqui poupa uma ida ao servidor e
          // apanha o engano enquanto o teclado ainda está aberto — mas quem
          // manda continua a ser o servidor.
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'Falta o contribuinte.';
            return nifValido(t) ? null : 'Esse contribuinte não é válido.';
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
          validator: (v) =>
              (v == null || !v.contains('@')) ? 'Falta o email.' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _palavraPasse,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Palavra-passe',
            border: OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.length < 6)
              ? 'Pelo menos 6 caracteres.'
              : null,
        ),
        if (_erro != null) ...[
          const SizedBox(height: 16),
          Text(
            _erro!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _aRegistar ? null : _registar,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _aRegistar
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Inscrever-me'),
          ),
        ),
      ],
    ),
  );
}

class _Confirmacao extends StatelessWidget {
  const _Confirmacao({required this.email});
  final String email;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.mark_email_read_outlined, size: 48),
      const SizedBox(height: 16),
      const Text(
        'Conta criada.',
        style: TextStyle(fontSize: 18),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      Text(
        'Confirme o email enviado para $email e depois entre. O acesso à '
        'empresa ainda tem de ser autorizado por quem a gere — sem isso, entra '
        'mas não vê trabalho nenhum.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Voltar à entrada'),
      ),
    ],
  );
}
