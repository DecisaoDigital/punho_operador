import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../casa/casa_do_operador.dart';

/// A inscrição deste utilizador numa empresa.
///
/// **Não é a identificação do operador.** São coisas distintas e vale a pena
/// não as confundir: a identificação é quem ele é (a sessão, o `user_id`); a
/// inscrição é o vínculo dele a uma empresa e o perfil que lá tem. A primeira
/// é dele; a segunda é da empresa, e é o servidor que a concede — o Control
/// aprova, e `punho_membros` é a única prova.
class Inscricao {
  const Inscricao({required this.empresaId, required this.perfil});

  final String empresaId;
  final String perfil;

  bool get eGestor => perfil == 'gestor';
}

/// Lê a inscrição de quem está autenticado.
///
/// `null` quer dizer "não tem inscrição activa" — não é erro, é o caso de
/// alguém que se registou e ainda não foi aprovado.
Future<Inscricao?> lerInscricao() async {
  final cliente = Supabase.instance.client;
  final utilizador = cliente.auth.currentUser;
  if (utilizador == null) return null;

  final linha = await cliente
      .from('punho_membros')
      .select('empresa_id, perfil')
      .eq('user_id', utilizador.id)
      .eq('ativo', true)
      .maybeSingle();
  if (linha == null) return null;

  return Inscricao(
    empresaId: linha['empresa_id'] as String,
    perfil: linha['perfil'] as String,
  );
}

/// Decide o que mostrar a quem já tem sessão.
class PortaDaEmpresa extends StatefulWidget {
  const PortaDaEmpresa({super.key});

  @override
  State<PortaDaEmpresa> createState() => _PortaDaEmpresaState();
}

class _PortaDaEmpresaState extends State<PortaDaEmpresa> {
  late Future<Inscricao?> _inscricao;

  @override
  void initState() {
    super.initState();
    _inscricao = lerInscricao();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Inscricao?>(
    future: _inscricao,
    builder: (context, estado) {
      if (estado.connectionState != ConnectionState.done) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      }
      if (estado.hasError) {
        return _Aviso(
          icone: Icons.cloud_off,
          titulo: 'Não consegui falar com o servidor.',
          detalhe: 'Verifique a ligação e volte a abrir a app.',
          aoSair: _sair,
        );
      }
      final inscricao = estado.data;
      if (inscricao == null) {
        return _Aviso(
          icone: Icons.hourglass_empty,
          titulo: 'Ainda não tem acesso a nenhuma empresa.',
          detalhe:
              'Quem gere a empresa tem de o autorizar. Assim que autorizar, '
              'entra por aqui sem fazer mais nada.',
          aoSair: _sair,
        );
      }
      return CasaDoOperador(inscricao: inscricao);
    },
  );

  Future<void> _sair() => Supabase.instance.client.auth.signOut();
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.icone,
    required this.titulo,
    required this.detalhe,
    required this.aoSair,
  });

  final IconData icone;
  final String titulo, detalhe;
  final Future<void> Function() aoSair;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48),
            const SizedBox(height: 16),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(detalhe, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton(onPressed: aoSair, child: const Text('Sair')),
          ],
        ),
      ),
    ),
  );
}
