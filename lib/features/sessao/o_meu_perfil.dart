import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O que a pessoa diz sobre si própria: nome e contribuinte.
///
/// **Existe porque o nome não tinha por onde ser corrigido.** Vinha do pedido
/// de acesso, escrito uma vez no momento da inscrição, e ficava assim para
/// sempre — mal escrito se tivesse sido mal escrito. E metade dos membros de
/// hoje entrou por outra via, sem pedido nenhum: para esses não havia sequer um
/// nome errado, havia nada.
///
/// O contribuinte é o da PESSOA, não o da empresa. São dois números diferentes
/// e não se misturam: o da empresa vai nas facturas, este vai na ficha de
/// colaborador. Fica opcional de propósito — um ecrã que recusa gravar o nome
/// porque falta o contribuinte é um ecrã que ninguém preenche. Mas se for
/// escrito, tem de estar certo: o servidor confere o dígito de controlo e
/// recusa uma gralha em vez de a guardar para dar erro num documento, meses
/// depois.
class OMeuPerfil extends StatefulWidget {
  const OMeuPerfil({super.key, this.nomeActual, this.nifActual});

  final String? nomeActual;
  final String? nifActual;

  @override
  State<OMeuPerfil> createState() => _OMeuPerfilState();
}

class _OMeuPerfilState extends State<OMeuPerfil> {
  late final TextEditingController _nome = TextEditingController(
    text: widget.nomeActual ?? '',
  );
  late final TextEditingController _nif = TextEditingController(
    text: widget.nifActual ?? '',
  );
  final _formulario = GlobalKey<FormState>();
  bool _aGravar = false;
  String? _erro;

  @override
  void dispose() {
    _nome.dispose();
    _nif.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _aGravar = true;
      _erro = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'punho_guardar_o_meu_perfil',
        params: {
          'p_nome': _nome.text.trim(),
          // Vazio vai como nulo, não como string vazia: "não pus" e "pus nada"
          // são a mesma coisa para quem preenche, e devem ser a mesma coisa na
          // base.
          'p_nif': _nif.text.trim().isEmpty ? null : _nif.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      // As RPCs levantam P0001 com a mensagem já escrita para quem a vai ler
      // ("O contribuinte não é válido."). O resto é técnico e não ajuda
      // ninguém — mas também não se inventa um motivo.
      if (mounted) {
        setState(
          () => _erro = e.code == 'P0001'
              ? e.message
              : 'Não consegui guardar. O servidor respondeu: ${e.message}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _erro = 'Não consegui falar com o servidor.');
      }
    } finally {
      if (mounted) setState(() => _aGravar = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Os meus dados')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formulario,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'É assim que os colegas o identificam no trabalho registado.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'O seu nome',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 2) ? 'Falta o nome.' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nif,
                keyboardType: TextInputType.number,
                // Só dígitos: poupa o servidor a recusar por causa de um ponto
                // que o teclado sugeriu.
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: 'Contribuinte (opcional)',
                  helperText: 'O seu, não o da empresa.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final texto = (v ?? '').trim();
                  if (texto.isEmpty) return null;
                  // Só a forma. O dígito de controlo é o servidor que confere —
                  // uma regra destas escrita em dois sítios acaba por divergir
                  // num deles.
                  return texto.length == 9 ? null : 'São 9 algarismos.';
                },
              ),
              if (_erro != null) ...[
                const SizedBox(height: 16),
                Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _aGravar ? null : _guardar,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _aGravar
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
