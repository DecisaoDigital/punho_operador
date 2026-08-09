/// O contribuinte português, conferido no telemóvel.
///
/// **O servidor confere na mesma** — `punho_nif_valido` faz esta conta antes de
/// gravar seja o que for, e é ela que manda. Isto existe para o engano ser
/// apanhado enquanto o teclado ainda está aberto: um dígito trocado só
/// descoberto depois de submeter obriga a pessoa a voltar a um ecrã que já
/// fechou, e no caso da inscrição obriga-a a criar a conta outra vez.
///
/// A conta é a oficial: os oito primeiros dígitos pesados de 9 a 2, o resto da
/// divisão por 11 subtraído a 11, e 10 ou 11 valem zero.
bool nifValido(String? nif) {
  final n = (nif ?? '').replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d{9}$').hasMatch(n)) return false;

  var soma = 0;
  for (var i = 0; i < 8; i++) {
    soma += int.parse(n[i]) * (9 - i);
  }
  var controlo = 11 - (soma % 11);
  if (controlo >= 10) controlo = 0;
  return controlo == int.parse(n[8]);
}
