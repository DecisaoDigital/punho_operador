import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../dados/actualizacoes.dart';

/// Distâncias com nome, para não haver números soltos pelo meio do ecrã.
const _margemDoAviso = 12.0;
const _folgaInterna = 16.0;
const _folgaEntreLinhas = 8.0;

/// Põe o aviso de versão nova por cima de qualquer ecrã.
///
/// Envolve a app inteira e não só a casa: quem tem a app desactualizada é
/// precisamente quem pode estar preso no ecrã de entrada, e é a esse que o
/// aviso faz mais falta.
class AvisoDeVersao extends StatefulWidget {
  const AvisoDeVersao({
    super.key,
    required this.actualizacoes,
    required this.child,
  });

  final Actualizacoes actualizacoes;
  final Widget child;

  @override
  State<AvisoDeVersao> createState() => _AvisoDeVersaoState();
}

class _AvisoDeVersaoState extends State<AvisoDeVersao> {
  @override
  void initState() {
    super.initState();
    widget.actualizacoes.addListener(_aoMudar);
  }

  @override
  void dispose() {
    widget.actualizacoes.removeListener(_aoMudar);
    super.dispose();
  }

  void _aoMudar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.actualizacoes;
    final versao = estado.versao;
    if (versao == null || estado.dispensado) return widget.child;

    // Obrigatória tapa tudo: não é um aviso, é uma porta fechada. E só uma
    // resposta viva do servidor chega aqui com `obrigatoria` — o que vem do
    // cache local nunca bloqueia.
    if (versao.obrigatoria) {
      return _PortaFechada(estado: estado, versao: versao);
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: _margemDoAviso,
          right: _margemDoAviso,
          bottom: _margemDoAviso,
          child: SafeArea(
            top: false,
            child: _Cartao(estado: estado, versao: versao),
          ),
        ),
      ],
    );
  }
}

/// O aviso em si.
class _Cartao extends StatelessWidget {
  const _Cartao({required this.estado, required this.versao});
  final Actualizacoes estado;
  final VersaoPublicada versao;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cores.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(_folgaInterna),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.system_update, color: cores.onSecondaryContainer),
                const SizedBox(width: _folgaEntreLinhas),
                Expanded(
                  child: Text(
                    'Punho OP ${versao.versao} disponível',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: estado.dispensar,
                  icon: const Icon(Icons.close),
                  tooltip: 'Agora não',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if ((versao.notas ?? '').isNotEmpty) ...[
              const SizedBox(height: _folgaEntreLinhas),
              Text(versao.notas!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: _folgaEntreLinhas),
            _Accao(estado: estado, versao: versao),
          ],
        ),
      ),
    );
  }
}

/// O que se pode fazer, conforme a fase.
class _Accao extends StatelessWidget {
  const _Accao({required this.estado, required this.versao});
  final Actualizacoes estado;
  final VersaoPublicada versao;

  @override
  Widget build(BuildContext context) {
    // Sem hash publicado a app não se instala a si própria. Sobra o browser —
    // e diz-se isso, em vez de oferecer um botão que não faz nada.
    if (!versao.podeInstalarSozinha) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: () => launchUrl(
            Uri.parse(versao.url),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Descarregar no browser'),
        ),
      );
    }

    return switch (estado.fase) {
      FaseDaActualizacao.aDescarregar => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: estado.progresso),
          const SizedBox(height: _folgaEntreLinhas),
          Text(
            'A descarregar… ${(estado.progresso * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      FaseDaActualizacao.pronta => Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: estado.instalar,
          child: const Text('Instalar agora'),
        ),
      ),
      FaseDaActualizacao.aInstalar ||
      FaseDaActualizacao.aguardaConfirmacao => Text(
        'A instalar. Confirma no ecrã do Android, se ele perguntar.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      FaseDaActualizacao.falhou => Row(
        children: [
          Expanded(
            child: Text(
              estado.erro ?? 'Falhou.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: estado.descarregarAgora,
            child: const Text('Tentar outra vez'),
          ),
        ],
      ),
      // Ainda não se mexeu nela: a descarga automática só acontece em Wi-Fi, e
      // o botão é para quem não quer esperar por ele.
      FaseDaActualizacao.disponivel => Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: estado.descarregarAgora,
          child: const Text('Descarregar'),
        ),
      ),
    };
  }
}

/// Actualização obrigatória: a app não abre sem ela.
class _PortaFechada extends StatelessWidget {
  const _PortaFechada({required this.estado, required this.versao});
  final Actualizacoes estado;
  final VersaoPublicada versao;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.system_update, size: 48),
            const SizedBox(height: _folgaInterna),
            Text(
              'É preciso actualizar para a ${versao.versao}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: _folgaEntreLinhas),
            Text(
              versao.notas?.isNotEmpty == true
                  ? versao.notas!
                  : 'Esta versão deixou de funcionar com o servidor.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            _Accao(estado: estado, versao: versao),
          ],
        ),
      ),
    ),
  );
}
