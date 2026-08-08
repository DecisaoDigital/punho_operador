package pt.decisaodigital.punho_operador;

import androidx.test.rule.ActivityTestRule;
import dev.flutter.plugins.integration_test.FlutterTestRunner;
import org.junit.Rule;
import org.junit.runner.RunWith;

/**
 * A ponte entre o `am instrument` do Android e os testes escritos em Dart.
 *
 * <p>Não tem lógica nenhuma: levanta a {@code MainActivity} e deixa o
 * {@code FlutterTestRunner} correr o que está no ficheiro de integração que foi
 * compilado como ponto de entrada da app.
 *
 * <p>Existe por causa do MIUI. O caminho normal — {@code flutter test
 * integration_test/...} — desinstala a app quando acaba, e no Redmi cada
 * instalação de raiz volta a pôr no ecrã uma caixa de confirmação que expira
 * sozinha ao fim de segundos e que não há maneira de confirmar por adb. Por
 * aqui a app fica instalada, e todas as corridas seguintes são actualizações
 * por cima, que passam sem caixa nenhuma.
 */
@RunWith(FlutterTestRunner.class)
public class MainActivityTest {
    @Rule
    public ActivityTestRule<MainActivity> rule =
            new ActivityTestRule<>(MainActivity.class, true, false);
}
