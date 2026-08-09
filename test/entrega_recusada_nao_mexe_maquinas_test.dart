import 'package:flutter_test/flutter_test.dart';
import 'package:punho_operador/dados/escrita.dart';
import 'package:punho_operador/dados/estado.dart';
import 'package:punho_operador/dados/servidor.dart';
import 'package:punho_operador/features/sessao/inscricao.dart';

/// Uma reserva recusada pelo servidor não pode deixar as máquinas noutro estado.
///
/// Entregar e recolher mexem em duas coisas: o estado da reserva e o estado das
/// máquinas. Se o servidor recusa a reserva — uma sobreposição, uma política —
/// e as máquinas mudam à mesma, fica um cliente com a betoneira que o calendário
/// do gestor diz estar livre. O operador lê a recusa da reserva sem saber que as
/// máquinas se mexeram.
class _ServidorVazio implements FonteDeDados {
  _ServidorVazio(this._maquinas);
  final List<Maquina> _maquinas;
  @override
  Future<int> porEmDia() async => 0;
  @override
  Future<List<Maquina>> maquinas() async => _maquinas;
  @override
  Future<List<Reserva>> reservasEntre(DateTime de, DateTime ate) async =>
      const [];
  @override
  Future<List<Reserva>> pedidos() async => const [];
  @override
  Future<List<Cliente>> clientes() async => const [];
  @override
  Future<List<Cobranca>> cobrancas() async => const [];
  @override
  Future<List<Lead>> leads() async => const [];
  @override
  Future<List<Despesa>> despesasDeHoje() async => const [];
}

/// Recusa a reserva, aceita tudo o resto — e regista cada escrita tentada.
class _CanalQueRecusaReserva implements Canal {
  final tentativas = <String>[];
  @override
  Future<Resultado> guardar(
    String entidade,
    String idLocal,
    Map<String, Object?> payload,
  ) async {
    tentativas.add(entidade);
    if (entidade == 'booking') {
      return const Resultado.recusado('A Betoneira já está com outro cliente.');
    }
    return const Resultado.feito();
  }

  @override
  Future<int> escoarFila() async => 0;
  @override
  int get porEnviar => 0;
}

Maquina _maquina(String idLocal) => Maquina(
  id: 'uuid-$idLocal',
  idLocal: idLocal,
  cru: {'id': idLocal, 'name': 'Betoneira'},
  nome: 'Betoneira',
  referencia: '',
  categoria: '',
  estado: 'available',
  arquivada: false,
);

Reserva _reserva() => Reserva(
  id: 'uuid-b1',
  idLocal: 'b1',
  cru: {'id': 'b1', 'machineIds': ['m1']},
  clienteId: 'uuid-c1',
  clienteIdLocal: 'c1',
  clienteNome: 'Sr. Costa',
  inicio: DateTime.now(),
  fim: DateTime.now().add(const Duration(hours: 8)),
  estado: 'confirmed',
  maquinaIdsLocais: const ['m1'],
);

void main() {
  test('entregar recusada não tenta mexer em nenhuma máquina', () async {
    final canal = _CanalQueRecusaReserva();
    final estado = EstadoDoOperador(
      _ServidorVazio([_maquina('m1')]),
      canal,
      inscricao: const Inscricao(
        empresaId: 'e1',
        perfil: 'colaborador',
        colaboradorId: 'ficha-1',
      ),
    );
    await estado.recarregar();

    final resultado = await estado.entregar(_reserva());

    expect(resultado.recusado, isTrue, reason: 'o operador tem de ouvir a recusa');
    // A prova: tentou-se escrever a reserva, e mais nada. Nenhuma máquina mudou.
    expect(canal.tentativas, ['booking']);
    expect(canal.tentativas.contains('machine'), isFalse);
  });

  test('recolher recusada também não mexe nas máquinas', () async {
    final canal = _CanalQueRecusaReserva();
    final estado = EstadoDoOperador(
      _ServidorVazio([_maquina('m1')]),
      canal,
      inscricao: const Inscricao(
        empresaId: 'e1',
        perfil: 'colaborador',
        colaboradorId: 'ficha-1',
      ),
    );
    await estado.recarregar();

    final resultado = await estado.recolher(_reserva());

    expect(resultado.recusado, isTrue);
    expect(canal.tentativas, ['booking']);
  });
}
