package pt.decisaodigital.punho_operador

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Instala um APK a partir da própria app, sem passar pelo browser.
 *
 * Antes disto o botão do aviso abria o URL no browser e o utilizador percorria
 * notificação, aviso de ficheiro perigoso, ecrã de instalação e "Abrir" — seis
 * ou sete toques e uma saída da app.
 *
 * **Sobre "silencioso":** o Android só deixa uma app instalar-se a si própria
 * sem confirmação a partir do 12 (API 31), e mesmo aí só quando é ela o
 * *installer of record* — ou seja, quando foi ela a instalar a versão que está
 * a correr. A primeira actualização por esta via ainda mostra o ecrã do
 * sistema; da segunda em diante deixa de mostrar. Abaixo do 12 há sempre
 * confirmação, e não há volta a dar.
 *
 * Pedimos `USER_ACTION_NOT_REQUIRED` quando a versão permite e deixamos o
 * sistema decidir: se ele achar que precisa de perguntar, pergunta. Não há aqui
 * forma de contornar isso, nem deve haver.
 */
object InstaladorDeApk {

    private const val ACCAO_RESULTADO = "pt.decisaodigital.punho_operador.INSTALL_RESULT"

    /**
     * @param caminho ficheiro APK já descarregado e verificado pelo lado Dart.
     *   A verificação do SHA-256 é feita lá: aqui só se instala o que chega.
     */
    fun instalar(context: Context, caminho: String, resultado: MethodChannel.Result) {
        val ficheiro = File(caminho)
        if (!ficheiro.exists() || ficheiro.length() == 0L) {
            resultado.error("ficheiro_invalido", "APK não existe ou está vazio", null)
            return
        }

        val instalador = context.packageManager.packageInstaller
        val parametros = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Pedido, não garantia: o sistema instala sem perguntar se
                // reconhecer o Punho como quem instalou a versão anterior.
                setRequireUserAction(
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                )
            }
        }

        val sessaoId: Int
        try {
            sessaoId = instalador.createSession(parametros)
        } catch (erro: Exception) {
            resultado.error("sessao_falhou", erro.message, null)
            return
        }

        try {
            instalador.openSession(sessaoId).use { sessao ->
                // Copiado em blocos: um APK do Punho anda pelos 76 MB e lê-lo
                // todo para memória de uma vez é pedir um OutOfMemory num
                // telemóvel com pouca folga.
                sessao.openWrite("punho-op.apk", 0, ficheiro.length()).use { destino ->
                    ficheiro.inputStream().use { origem ->
                        origem.copyTo(destino, bufferSize = 64 * 1024)
                    }
                    sessao.fsync(destino)
                }

                val receptor = registarReceptor(context, resultado)
                val intent = Intent(ACCAO_RESULTADO).setPackage(context.packageName)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendente = PendingIntent.getBroadcast(context, sessaoId, intent, flags)
                sessao.commit(pendente.intentSender)
                // A partir daqui quem responde é o receptor. Se a instalação
                // correr bem o processo é morto pelo sistema antes disso — daí
                // o `resultado` poder nunca ser chamado, o que é normal.
                receptor.let { }
            }
        } catch (erro: Exception) {
            instalador.abandonSession(sessaoId)
            resultado.error("escrita_falhou", erro.message, null)
        }
    }

    /**
     * Ouve o desfecho da sessão. O caso que interessa mesmo é
     * [PackageInstaller.STATUS_PENDING_USER_ACTION]: é o sistema a dizer que
     * quer perguntar ao utilizador, e temos de abrir o ecrã dele.
     */
    private fun registarReceptor(
        context: Context,
        resultado: MethodChannel.Result,
    ): BroadcastReceiver {
        var respondido = false
        val receptor = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val estado = intent.getIntExtra(
                    PackageInstaller.EXTRA_STATUS,
                    PackageInstaller.STATUS_FAILURE,
                )
                when (estado) {
                    PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                        val confirmar = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                        }
                        confirmar?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        confirmar?.let { ctx.startActivity(it) }
                        if (!respondido) {
                            respondido = true
                            resultado.success("pediu_confirmacao")
                        }
                    }
                    PackageInstaller.STATUS_SUCCESS -> {
                        if (!respondido) {
                            respondido = true
                            resultado.success("instalado")
                        }
                        desregistar(ctx, this)
                    }
                    else -> {
                        val mensagem = intent.getStringExtra(
                            PackageInstaller.EXTRA_STATUS_MESSAGE,
                        )
                        if (!respondido) {
                            respondido = true
                            resultado.error("instalacao_falhou", mensagem, estado)
                        }
                        desregistar(ctx, this)
                    }
                }
            }
        }
        val filtro = IntentFilter(ACCAO_RESULTADO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receptor, filtro, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receptor, filtro)
        }
        return receptor
    }

    private fun desregistar(context: Context, receptor: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receptor)
        } catch (_: IllegalArgumentException) {
            // Já tinha sido removido. Não é erro.
        }
    }
}
