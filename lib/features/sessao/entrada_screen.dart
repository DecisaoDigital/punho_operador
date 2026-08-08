import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../marca/marca.dart';
import 'registo_screen.dart';

/// Entrar com a conta que o gestor autorizou.
///
/// Há inscrição, e não é contradição com o que aqui estava escrito antes.
/// Inscrever-se cria um **pedido pendente**, não uma entrada: quem cria a
/// empresa continua a ser o gestor, no Punho, e o acesso continua a ser
/// concedido, nunca reclamado. O que muda é que o operador passa a poder
/// pedir por si — antes dependia de alguém o registar noutra app, e o nome
/// dele não chegava a lado nenhum.
class EntradaScreen extends StatefulWidget {
  const EntradaScreen({super.key});

  @override
  State<EntradaScreen> createState() => _EntradaScreenState();
}

class _EntradaScreenState extends State<EntradaScreen> {
  final _email = TextEditingController();
  final _palavraPasse = TextEditingController();
  final _formulario = GlobalKey<FormState>();
  bool _aEntrar = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _palavraPasse.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _aEntrar = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: _email.text.trim(),
        password: _palavraPasse.text,
      );
    } on AuthException {
      // A mensagem do fornecedor vem em inglês e fala de coisas que não são do
      // operador ("Invalid login credentials"). O que ele precisa de saber é
      // que uma das duas está errada.
      if (mounted) setState(() => _erro = 'Email ou palavra-passe errados.');
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Não consegui falar com o servidor.');
      }
    } finally {
      if (mounted) setState(() => _aEntrar = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formulario,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SimboloPunhoOp(),
                const SizedBox(height: 12),
                Text(
                  'Punho OP',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                const VersaoInstalada(),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Falta o email.'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _palavraPasse,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Palavra-passe',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? 'Falta a palavra-passe.'
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
                  onPressed: _aEntrar ? null : _entrar,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _aEntrar
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _aEntrar
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RegistoScreen(),
                          ),
                        ),
                  child: const Text('Ainda não tenho conta'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
