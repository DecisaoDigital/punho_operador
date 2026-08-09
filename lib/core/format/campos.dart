/// Conversões entre o texto de um campo e o valor guardado.
///
/// Existe uma cópia canónica desta regra na app do gestor
/// (`punho/lib/core/format/campos.dart`) e outra no portal do contabilista
/// (`supabase/functions/portal-contabilista/euros.ts`). **Têm de decidir o
/// mesmo.** O operador, o gestor e o contabilista escrevem euros no mesmo
/// histórico, e um `1.200` que valesse coisas diferentes conforme quem o
/// escreveu era o mesmo campo com dois significados.
library;

/// Lê euros escritos à portuguesa ("1.234,56" ou "1234.56") em cêntimos.
/// Devolve `null` para vazio ou impossível — nunca um zero inventado.
///
/// O caso que obrigou a olhar para isto foi `1.200` sem casas decimais: mil e
/// duzentos euros, ou um euro e vinte? A versão anterior aqui na OP tratava
/// qualquer ponto como decimal, portanto lia `1.200` como 1,20 € — cem vezes
/// menos — e passava-o no validador sem nada avisar. Um recibo de mil e
/// duzentos entrava como um euro e vinte, e o cliente continuava a dever.
///
/// A regra que decide, e que é a mesma dos outros dois sítios:
///
///  * há vírgula → a vírgula é o decimal e os pontos são milhares;
///  * só pontos, a separar grupos de exactamente três dígitos → são milhares;
///  * qualquer outro ponto → é decimal, que é como escreve quem copiou de uma
///    folha de cálculo inglesa.
///
/// [permitirNegativo] fica desligado por omissão: num recibo ou num gasto do
/// dia um negativo é engano, e recusá-lo é melhor do que guardá-lo.
int? centsDeTexto(String valor, {bool permitirNegativo = false}) {
  final cru = valor.replaceAll(RegExp(r'[\s €]'), '');
  if (cru.isEmpty) return null;

  final String normalizado;
  if (cru.contains(',')) {
    normalizado = cru.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(cru)) {
    normalizado = cru.replaceAll('.', '');
  } else {
    normalizado = cru;
  }

  final montante = double.tryParse(normalizado);
  if (montante == null || !montante.isFinite) return null;
  if (montante < 0 && !permitirNegativo) return null;
  // Arredonda em vez de truncar: `(12.35 * 100).toInt()` dá 1234 em vírgula
  // flutuante, e um cêntimo a menos por cada recibo é uma caixa que não fecha.
  return (montante * 100).round();
}
