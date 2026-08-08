#!/usr/bin/env bash
# Atualiza de forma idempotente o catálogo Supabase depois de os assets da
# release já existirem. Pode ser repetido isoladamente após uma falha.
#
# É o único passo da publicação que não dá erro nenhum quando falta: sem esta
# linha a Release existe, o APK descarrega-se à mão, e a app simplesmente
# nunca fica a saber que há versão nova.

set -Eeuo pipefail

readonly REPOSITORY="DecisaoDigital/punho_operador"
readonly PROJECT_REF="oefqbkhioncakojipqyx"
readonly SUPABASE_URL="https://${PROJECT_REF}.supabase.co"
readonly APP="punho_op"
readonly PLATAFORMA="android"

die() {
  printf 'ERRO: %s\n' "$*" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  printf 'Uso: %s <versão> <build_number>\n' "$0" >&2
  exit 2
fi

version="${1#v}"
build="$2"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  die "versão inválida: $version"
[[ "$build" =~ ^[0-9]+$ ]] || die "build inválido: $build"
((build > 0)) || die "build fora do intervalo suportado: $build"

for command in gh curl jq supabase; do
  command -v "$command" >/dev/null 2>&1 ||
    die "comando em falta: $command"
done

tag="v${version}"
asset="punho-op-android-v${version}.apk"
release_json="$(
  gh release view "$tag" \
    --repo "$REPOSITORY" \
    --json isDraft,isPrerelease,url,assets
)"
jq -e \
  --arg asset "$asset" \
  '(.isDraft == false) and
   (.isPrerelease == false) and
   ([.assets[].name] | index($asset) != null)' \
  <<< "$release_json" >/dev/null ||
  die "release sem o asset Android ($asset)"

keys_json="$(
  supabase projects api-keys \
    --project-ref "$PROJECT_REF" \
    --reveal \
    --output json
)"
admin_key="$(
  jq -r '.[] | select(.id == "service_role") | .api_key' <<< "$keys_json"
)"
anon_key="$(
  jq -r '.[] | select(.id == "anon") | .api_key' <<< "$keys_json"
)"
[[ "$admin_key" == eyJ* ]] || die "service_role não disponível"
[[ "$anon_key" == eyJ* ]] || die "anon key não disponível"

api="${SUPABASE_URL}/rest/v1/versoes_apps"
url_download="https://github.com/${REPOSITORY}/releases/download/${tag}/${asset}"

# O instalador automático (descarregarAgora) recusa-se a correr sem um sha256
# publicado, e cai para o browser. Calcula-se aqui a partir do próprio asset
# da release — não do ficheiro local —, para o hash provar o que o GitHub
# realmente serve.
apk_tmp="$(mktemp)"
trap 'rm -f "$apk_tmp"' EXIT
gh release download "$tag" \
  --repo "$REPOSITORY" \
  --pattern "$asset" \
  --output "$apk_tmp" \
  --clobber
sha256="$(sha256sum "$apk_tmp" | cut -d' ' -f1)"

payload="$(
  jq -nc \
    --arg app "$APP" \
    --arg platform "$PLATAFORMA" \
    --arg version "$version" \
    --argjson build "$build" \
    --arg url "$url_download" \
    --arg sha "$sha256" \
    '{
      app: $app,
      plataforma: $platform,
      versao: $version,
      build_number: $build,
      url_download: $url,
      obrigatoria: false,
      notas_lancamento: "Nova versão Android do Punho OP.",
      activa: true,
      sha256: $sha
    }'
)"

# Um upsert simples não serve aqui. O gatilho
# `trg_versoes_apps_release_integrity` exige, no INSERT, que o build_number
# seja maior que o máximo já catalogado — e em Postgres o BEFORE INSERT
# dispara *antes* de o ON CONFLICT ser resolvido, por isso a linha rebenta em
# vez de cair no UPDATE. Resultado: repetir este comando para um build já
# catalogado morria com "tem que ser > max existente".
#
# Daí a bifurcação: se a linha já existe, actualizam-se só os campos que o
# gatilho deixa mexer (app, plataforma, versao e build_number são imutáveis).
# É isto que torna verdadeira a promessa de repetição lá em cima.
ja_existe="$(
  curl --fail-with-body --silent --show-error \
    "${api}?app=eq.${APP}&plataforma=eq.${PLATAFORMA}&build_number=eq.${build}&select=id" \
    -H "apikey: ${admin_key}" \
    -H "Authorization: Bearer ${admin_key}" | jq 'length'
)"

if [[ "$ja_existe" -gt 0 ]]; then
  printf 'A linha %s+%s já existia; a actualizar o que é mutável.\n' \
    "$version" "$build"
  curl --fail-with-body --silent --show-error \
    -X PATCH \
    "${api}?app=eq.${APP}&plataforma=eq.${PLATAFORMA}&build_number=eq.${build}" \
    -H "apikey: ${admin_key}" \
    -H "Authorization: Bearer ${admin_key}" \
    -H "Content-Type: application/json" \
    --data "$(jq 'del(.app, .plataforma, .versao, .build_number)' <<< "$payload")"
else
  # Primeiro ativa a versão nova; só depois desativa as antigas. Se a segunda
  # chamada falhar, a function escolhe na mesma o build mais alto e a
  # repetição deste comando conclui a limpeza.
  curl --fail-with-body --silent --show-error \
    -X POST "$api" \
    -H "apikey: ${admin_key}" \
    -H "Authorization: Bearer ${admin_key}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=minimal" \
    --data "$payload"
fi

curl --fail-with-body --silent --show-error \
  -X PATCH \
  "${api}?app=eq.${APP}&plataforma=eq.${PLATAFORMA}&build_number=neq.${build}" \
  -H "apikey: ${admin_key}" \
  -H "Authorization: Bearer ${admin_key}" \
  -H "Content-Type: application/json" \
  --data '{"activa":false}'

check_update() {
  local local_build="$1"
  local expected="$2"
  local response
  response="$(
    curl --fail-with-body --silent --show-error \
      "${SUPABASE_URL}/functions/v1/versao-mais-recente" \
      -H "Authorization: Bearer ${anon_key}" \
      -H "apikey: ${anon_key}" \
      -H "Content-Type: application/json" \
      --data "{
        \"app\":\"${APP}\",
        \"plataforma\":\"${PLATAFORMA}\",
        \"build_number_local\":${local_build}
      }"
  )"

  if [[ "$expected" == true ]]; then
    jq -e \
      --arg version "$version" \
      --arg url "$url_download" \
      --arg sha "$sha256" \
      --argjson build "$build" \
      '.actualizacao_disponivel == true and
       .versao_actual == $version and
       .build_number == $build and
       .url_download == $url and
       .sha256 == $sha' \
      <<< "$response" >/dev/null ||
      die "a function não anunciou ${version}+${build} a quem tem ${local_build}"
  else
    jq -e '.actualizacao_disponivel == false' <<< "$response" >/dev/null ||
      die "a function ofereceu actualização a quem já tem ${local_build}"
  fi
}

# Quem está atrás recebe; quem já lá está não recebe. O terceiro caso não é
# hipotético: a edge function normaliza versionCodes acima de 1000 porque o
# Flutter os prefixa com a arquitectura em builds --split-per-abi. O Punho OP
# não usa split hoje, mas se algum dia usar, um aparelho com 1001 tem de ser
# tratado como build 1 e não como um número astronómico que nunca mais
# actualiza.
check_update "$((build - 1))" true
check_update "$build" false
check_update "$((1000 + build))" false

unset admin_key anon_key keys_json
printf 'Catálogo Supabase atualizado e verificado para %s+%s.\n' \
  "$version" "$build"
