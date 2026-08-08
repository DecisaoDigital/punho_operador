import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// O símbolo do Punho OP, o mesmo desenho do ícone do lançador.
///
/// A app abria sem o mostrar em lado nenhum: quem a instalava tocava num
/// símbolo e entrava num ecrã que não se parecia com ele.
class SimboloPunhoOp extends StatelessWidget {
  const SimboloPunhoOp({super.key, this.lado = 96});
  final double lado;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/ic_launcher_512.png',
    width: lado,
    height: lado,
    // O ícone é quadrado com cantos rectos; arredondá-los aqui é o que o
    // aproxima do que o Android desenha no lançador.
    filterQuality: FilterQuality.medium,
  );
}

/// A versão instalada, em letra pequena.
///
/// Vem do `PackageInfo` e não de uma constante escrita à mão: a única versão
/// que interessa é a do APK que está mesmo no telemóvel. Uma constante mente
/// no dia em que alguém se esquece de a mudar — e é precisamente no dia da
/// dúvida que se vai olhar para ela.
class VersaoInstalada extends StatefulWidget {
  const VersaoInstalada({super.key, this.alinhamento = TextAlign.center});
  final TextAlign alinhamento;

  @override
  State<VersaoInstalada> createState() => _VersaoInstaladaState();
}

class _VersaoInstaladaState extends State<VersaoInstalada> {
  String? _texto;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _texto = 'versão ${info.version} (${info.buildNumber})');
    } catch (_) {
      // Sem versão é melhor não dizer nada do que dizer "desconhecida": o
      // espaço fica vazio e ninguém fica com um valor errado na cabeça.
      if (mounted) setState(() => _texto = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = _texto;
    // Enquanto não sabe, ocupa a altura de uma linha. Sem isto o resto do
    // ecrã salta para cima quando a versão chega.
    if (texto == null) return const SizedBox(height: 16);
    return Text(
      texto,
      textAlign: widget.alinhamento,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Quem é esta app e que versão está instalada.
///
/// Chega-se aqui pelo símbolo na barra de cima. Existe porque a versão só
/// estava no ecrã de entrada, e para lá voltar era preciso sair da sessão —
/// pedir a alguém que se desautentique para saber que versão tem é absurdo.
Future<void> mostrarSobre(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SimboloPunhoOp(lado: 72),
        const SizedBox(height: 12),
        Text('Punho OP', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const VersaoInstalada(),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fechar'),
      ),
    ],
  ),
);
