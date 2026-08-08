import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/supabase_config.dart';
import 'core/tema/punho_tema.dart';
import 'dados/actualizacoes.dart';
import 'features/actualizacoes/aviso_de_versao.dart';
import 'features/sessao/inscricao.dart';
import 'features/sessao/entrada_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **Esta app é vertical e mais nada.**
  //
  // A trava a sério está no manifesto (`android:screenOrientation="portrait"`),
  // que é o que o Android respeita mesmo antes de o Flutter arrancar. Isto
  // aqui é a segunda volta à chave, para o dia em que a app correr noutro sítio
  // que não tenha manifesto.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  if (SupabaseConfig.enabled) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // `publishableKey` e não `anonKey`: é o nome novo da mesma chave, e é o
      // que o Punho já usa. `anonKey` está a caminho de desaparecer.
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  runApp(const AppDoOperador());
}

class AppDoOperador extends StatefulWidget {
  const AppDoOperador({super.key});

  @override
  State<AppDoOperador> createState() => _AppDoOperadorState();
}

class _AppDoOperadorState extends State<AppDoOperador> {
  /// Vive acima de tudo de propósito: quem tem a app velha é precisamente quem
  /// pode estar preso no ecrã de entrada, e é a esse que o aviso faz falta.
  final _actualizacoes = Actualizacoes();

  @override
  void initState() {
    super.initState();
    _actualizacoes.comecar();
  }

  @override
  void dispose() {
    _actualizacoes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Punho OP',
    debugShowCheckedModeBanner: false,
    theme: PunhoTema.claro,
    // Sem configuração não há app. Mostrar-lhe uma casa vazia era pior do que
    // dizer-lhe o que falta: ele ficava a pensar que a empresa não tem nada.
    home: AvisoDeVersao(
      actualizacoes: _actualizacoes,
      child: SupabaseConfig.enabled ? const Porta() : const _SemConfiguracao(),
    ),
  );
}

/// Quem entra e o que se lhe mostra.
///
/// Ter sessão não chega — como no Punho, quem decide é a inscrição activa em
/// `punho_membros`. Um utilizador autenticado sem inscrição não é operador de
/// empresa nenhuma, e não pode ver nada.
class Porta extends StatelessWidget {
  const Porta({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: Supabase.instance.client.auth.onAuthStateChange,
    builder: (context, _) {
      final sessao = Supabase.instance.client.auth.currentSession;
      if (sessao == null) return const EntradaScreen();
      return const PortaDaEmpresa();
    },
  );
}

class _SemConfiguracao extends StatelessWidget {
  const _SemConfiguracao();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.link_off, size: 48),
            SizedBox(height: 16),
            Text(
              'Esta cópia da app foi compilada sem ligação ao servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 8),
            Text(
              'Falta SUPABASE_URL e SUPABASE_ANON_KEY no --dart-define.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );
}
