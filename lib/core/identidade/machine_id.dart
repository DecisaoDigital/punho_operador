import 'dart:convert';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Chave em SharedPreferences onde o identificador fica em cache.
const chaveMachineId = 'punho_op_machine_id';

/// Identificador estável deste aparelho.
///
/// É o mesmo esquema do Punho (`lib/core/licenca/machine_id.dart`): o SHA256 de
/// uma semente da plataforma, guardado em cache para não depender de o plugin
/// responder sempre o mesmo ao longo do tempo. Deliberadamente igual — é o par
/// (`machine_id`, `app`) que identifica um terminal, e dois esquemas diferentes
/// para a mesma casa davam dois terminais onde há um aparelho.
///
/// Sai daqui para o pedido de acesso e fica lá para sempre: a pessoa pode
/// trocar de telemóvel depois, mas a inscrição já nasceu ligada a este.
///
/// [semente] existe para os testes correrem sem plugins nativos.
Future<String> resolverMachineId({Future<String> Function()? semente}) async {
  final prefs = await SharedPreferences.getInstance();
  final emCache = prefs.getString(chaveMachineId);
  if (emCache != null && emCache.length >= 8) return emCache;

  final crua = await (semente ?? sementeDoDispositivo)();
  final hash = sha256.convert(utf8.encode(crua)).toString();
  await prefs.setString(chaveMachineId, hash);
  return hash;
}

/// Semente por plataforma. Nunca sai da app — só o hash é enviado.
///
/// Em Android é o ANDROID_ID e tem de ser: é único por (aparelho, chave de
/// assinatura da app) e sobrevive a uma reinstalação. Não usar o `Build.ID`,
/// que é o identificador da ROM — dois telemóveis com a mesma versão de MIUI
/// dariam o mesmo terminal. Esse erro já custou uma correcção no Punho, a 5 de
/// Agosto de 2026; não vale a pena repeti-lo aqui.
///
/// Como a OP é assinada com a sua própria keystore, o ANDROID_ID que ela vê é
/// diferente do que o Punho vê no mesmo telemóvel. É o comportamento certo: são
/// duas instalações distintas, e o `app` ao lado distingue-as na mesma.
Future<String> sementeDoDispositivo() async {
  if (Platform.isAndroid) {
    final androidId = await const AndroidId().getId();
    if (androidId != null && androidId.trim().isNotEmpty) {
      return 'android:${androidId.trim()}';
    }
    // Sem ANDROID_ID não se cai para nenhum valor partilhado: um valor único
    // gerado aqui fica em cache no primeiro arranque e nunca colide. Perde-se
    // numa reinstalação, o que é preferível a dois donos no mesmo terminal.
    return 'android:sem-android-id:'
        '${DateTime.now().microsecondsSinceEpoch}:'
        '${Object().hashCode}';
  }
  return 'desconhecido:${Platform.operatingSystem}:'
      '${DateTime.now().microsecondsSinceEpoch}';
}
