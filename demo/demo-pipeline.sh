#!/usr/bin/env bash
# =============================================================================
# demo-pipeline.sh — Demo guiada del pipeline CI/CD de EnergiAI
# =============================================================================
# Recorre, prueba por prueba y esperando Enter entre cada una, las propiedades
# del pipeline (réplica 1:1 del propuesto para el repo oficial):
#
#   1. Un cambio que solo toca docs/ no dispara ningún workflow.
#   2. Un PR que toca backend/** dispara SOLO "CI Backend" (build + tests
#      reales con ./mvnw -B verify en el runner `ci` del servidor local).
#   3. Mergear a develop despliega STAGING en la VM (nunca producción).
#   4. Promover develop→main despliega PRODUCCIÓN — solo el componente que
#      cambió, en el runner `oci` de la VM de OCI.
#   5. (opcional) data-science/** tiene su propio carril: CI ML → Deploy ML.
#   6. (opcional) Gotcha: un PR con conflictos no dispara NINGÚN workflow.
#
# Requisitos: `gh` autenticado con permisos de push sobre el repo, `git`.
# Uso:        bash demo/demo-pipeline.sh
# El script trabaja sobre un clon temporal propio: no toca tu copia local.
# =============================================================================
set -euo pipefail

REPO="Neo236/test-workflow"
TS="$(date +%H%M%S)"
WORKDIR="$(mktemp -d /tmp/demo-cicd.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

C_CMD=$'\e[36m'; C_TIT=$'\e[1;33m'; C_OK=$'\e[1;32m'; C_TXT=$'\e[2m'; C_RST=$'\e[0m'

titulo()  { echo; echo "${C_TIT}══════════════════════════════════════════════════════════${C_RST}"
            echo "${C_TIT}  $*${C_RST}"
            echo "${C_TIT}══════════════════════════════════════════════════════════${C_RST}"; }
explica() { echo "${C_TXT}$*${C_RST}"; }
ok()      { echo "${C_OK}✔ $*${C_RST}"; }
pausa()   { echo; read -rp "▶ Enter para continuar... "; echo; }
run()     { echo "${C_CMD}\$ $*${C_RST}"; "$@"; }
# Igual que run(), pero reintenta hasta 3 veces (la API de GitHub a veces
# devuelve errores transitorios; que un hipo no mate la demo en vivo).
rungh()   { echo "${C_CMD}\$ $*${C_RST}"
            local i
            for i in 1 2 3; do
              "$@" && return 0
              echo "  ⚠ intento $i falló; reintentando en $((i*10)) s..."
              sleep $((i*10))
            done
            echo "  ✖ GitHub sigue fallando tras 3 intentos (¿incidente? ver githubstatus.com)"
            return 1; }

ultima_run() { gh run list -R "$REPO" --limit 1 --json databaseId --jq '.[0].databaseId // 0'; }

# $1 = id de run previa. Espera hasta 60 s a que aparezca una run nueva.
# Imprime la id nueva, o vacío si no apareció (eso también es un resultado).
espera_nueva_run() {
  local prev="$1" id=""
  for _ in $(seq 1 12); do
    sleep 5
    id="$(ultima_run)"
    if [ "$id" != "$prev" ]; then echo "$id"; return 0; fi
  done
  echo ""
}

muestra_job() {  # $1 = run id → workflow, estado y en qué runner corrió
  gh api "repos/$REPO/actions/runs/$1" \
    --jq '"   Workflow: \(.name)  |  rama: \(.head_branch)  |  \(.status)/\(.conclusion // "en curso")"'
  gh api "repos/$REPO/actions/runs/$1/jobs" \
    --jq '.jobs[] | "   Job \"\(.name)\" → runner: \(.runner_name // "?")  (labels pedidas: \(.labels | join(", ")))"'
}

command -v gh  >/dev/null || { echo "✖ Falta gh (GitHub CLI)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "✖ gh no está autenticado (gh auth login)"; exit 1; }

# =============================================================================
titulo "Demo del pipeline CI/CD — EnergiAI (réplica del plan oficial)"
explica "Cada prueba muestra en cyan los comandos que ejecuta y pausa con Enter."
explica "Recomendado: tener abierta la pestaña Actions en el navegador:"
explica "  https://github.com/$REPO/actions"
pausa

titulo "Estado inicial — los dos runners del plan"
run gh api "repos/$REPO/actions/runners" --jq '.runners[] | "  \(.name): \(.status)  [\([.labels[].name] | join(", "))]"'
explica ""
explica "energiai-ci-01  (label ci)  → CI en el servidor local: valida los PRs."
explica "energiai-oci-01 (label oci) → CD en la VM de OCI (ARM64): despliega main."
explica "En el repo oficial se registran igual; solo cambia la URL en config.sh."
pausa

explica "Clonando el repo en un directorio temporal de trabajo..."
run git clone -q "https://github.com/$REPO" "$WORKDIR/repo"
cd "$WORKDIR/repo"
run git checkout -q develop

# =============================================================================
titulo "PRUEBA 1 — Un cambio solo de docs NO dispara ningún workflow"
explica "Los workflows filtran por paths: docs/** y README.md quedan afuera."
explica "Ni CI ni deploy deben aparecer en Actions."
pausa
PREV="$(ultima_run)"
run git checkout -q -b "feature/demo-docs-$TS"
echo "nota de demo $TS" >> docs/notas.md
run git add docs/notas.md
run git commit -q -m "docs: nota de demo $TS"
run git push -q -u origin "feature/demo-docs-$TS"
rungh gh pr create -R "$REPO" --base develop --head "feature/demo-docs-$TS" \
  --title "docs: demo $TS" --body "Prueba 1: no debería disparar ningún workflow."
explica "Esperando 30 s para confirmar que NO se creó ninguna run..."
sleep 30
if [ "$(ultima_run)" = "$PREV" ]; then
  ok "Ningún workflow se disparó. El filtro de paths funciona."
else
  echo "⚠ Apareció una run inesperada — revisar la pestaña Actions."
fi
run gh pr merge -R "$REPO" "feature/demo-docs-$TS" --merge --delete-branch
run git checkout -q develop
run git pull -q
pausa

# =============================================================================
titulo "PRUEBA 2 — Un PR que toca backend/** dispara SOLO 'CI Backend'"
explica "El CI compila y corre los tests reales del backend (./mvnw -B verify)"
explica "en el runner 'ci'. ci-ml no debe aparecer: el PR no toca data-science/."
pausa
PREV="$(ultima_run)"
run git checkout -q -b "feature/demo-backend-$TS"
echo "demo-$TS" > backend/version.txt
run git add backend/version.txt
run git commit -q -m "feat(backend): bump de demo $TS"
run git push -q -u origin "feature/demo-backend-$TS"
rungh gh pr create -R "$REPO" --base develop --head "feature/demo-backend-$TS" \
  --title "feat(backend): demo $TS" --body "Prueba 2: debe correr SOLO CI Backend."
explica "Esperando que arranque la run de CI (segunda corrida ≈ 30-40 s por la caché)..."
RUN_ID="$(espera_nueva_run "$PREV")"
[ -n "$RUN_ID" ] || { echo "✖ No apareció ninguna run de CI"; exit 1; }
run gh run watch -R "$REPO" "$RUN_ID" --exit-status
muestra_job "$RUN_ID"
ok "CI Backend en verde en el servidor local. ci-ml en silencio (filtro de paths)."
pausa

# =============================================================================
titulo "PRUEBA 3 — Mergear a develop despliega STAGING (nunca producción)"
explica "develop alimenta el ambiente de staging: misma VM, proyecto compose"
explica "separado (energiai-staging). Producción solo se toca desde main."
pausa
PREV="$(ultima_run)"
run gh pr merge -R "$REPO" "feature/demo-backend-$TS" --merge --delete-branch
explica "Esperando el deploy de staging disparado por el push a develop..."
DEPLOY_ID="$(espera_nueva_run "$PREV")"
[ -n "$DEPLOY_ID" ] || { echo "✖ No apareció el deploy de staging"; exit 1; }
run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status
muestra_job "$DEPLOY_ID"
ok "Deploy Backend en STAGING, dentro de la VM. Producción (main) intacta."
run git checkout -q develop
run git pull -q
pausa

# =============================================================================
titulo "PRUEBA 4 — Promoción develop→main: deploy selectivo a PRODUCCIÓN"
explica "Al abrir el PR, el CI corre de nuevo (también protege a main)."
explica "Al mergearlo, el push a main dispara SOLO Deploy Backend con entorno"
explica "prod, en el runner 'oci' de la VM. deploy-ml y deploy-full, en silencio."
pausa
PREV="$(ultima_run)"
rungh gh pr create -R "$REPO" --base main --head develop \
  --title "release: demo $TS" --body "Prueba 4: al mergear debe correr SOLO Deploy Backend, en la VM."
explica "Esperando el CI del PR de release..."
RUN_ID="$(espera_nueva_run "$PREV")"
if [ -n "$RUN_ID" ]; then
  run gh run watch -R "$REPO" "$RUN_ID" --exit-status
  ok "CI en verde sobre el merge-ref del PR."
else
  explica "(No corrió CI: el diff develop→main no toca backend/** ni data-science/**.)"
fi
pausa
PREV="$(ultima_run)"
run gh pr merge -R "$REPO" develop --merge
explica "Esperando el deploy disparado por el push a main..."
DEPLOY_ID="$(espera_nueva_run "$PREV")"
[ -n "$DEPLOY_ID" ] || { echo "✖ No apareció el deploy"; exit 1; }
run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status
muestra_job "$DEPLOY_ID"
ok "Deploy Backend (entorno prod) ejecutado por energiai-oci-01 (VM OCI, ARM64)."
ok "Circuito completo: feature → PR+CI → develop (staging) → PR+CI → main (prod)."
pausa

# =============================================================================
titulo "PRUEBA 5 (opcional) — data-science/** tiene su propio carril"
read -rp "¿Correr la prueba del pipeline ML? [s/N] " R5
if [[ "${R5,,}" == "s" ]]; then
  PREV="$(ultima_run)"
  run git checkout -q develop
  run git pull -q
  run git checkout -q -b "feature/demo-ml-$TS"
  echo "demo-ml-$TS" > data-science/version.txt
  run git add data-science/version.txt
  run git commit -q -m "feat(ml): bump de demo $TS"
  run git push -q -u origin "feature/demo-ml-$TS"
  rungh gh pr create -R "$REPO" --base develop --head "feature/demo-ml-$TS" \
    --title "feat(ml): demo $TS" --body "Prueba 5: debe correr SOLO CI ML."
  RUN_ID="$(espera_nueva_run "$PREV")"
  [ -n "$RUN_ID" ] || { echo "✖ No apareció la run de CI ML"; exit 1; }
  run gh run watch -R "$REPO" "$RUN_ID" --exit-status
  muestra_job "$RUN_ID"
  ok "CI ML corrió (hoy con placeholders, igual que en el plan oficial). CI Backend en silencio."
  PREV="$(ultima_run)"
  run gh pr merge -R "$REPO" "feature/demo-ml-$TS" --merge --delete-branch
  explica "El merge a develop despliega el ML en STAGING..."
  DEPLOY_ID="$(espera_nueva_run "$PREV")"
  if [ -n "$DEPLOY_ID" ]; then
    run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status
    muestra_job "$DEPLOY_ID"
  fi
  pausa
  PREV="$(ultima_run)"
  rungh gh pr create -R "$REPO" --base main --head develop \
    --title "release: demo ml $TS" --body "Al mergear debe correr SOLO Deploy ML."
  RUN_ID="$(espera_nueva_run "$PREV")"
  if [ -n "$RUN_ID" ]; then run gh run watch -R "$REPO" "$RUN_ID" --exit-status; fi
  PREV="$(ultima_run)"
  run gh pr merge -R "$REPO" develop --merge
  DEPLOY_ID="$(espera_nueva_run "$PREV")"
  [ -n "$DEPLOY_ID" ] || { echo "✖ No apareció el deploy de ML"; exit 1; }
  run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status
  muestra_job "$DEPLOY_ID"
  ok "Deploy ML en PRODUCCIÓN. El backend no se re-desplegó: cada sector viaja solo."
  pausa
fi

# =============================================================================
titulo "PRUEBA 6 (opcional) — Gotcha: un PR con conflictos NO dispara workflows"
explica "Descubierto probando este pipeline: si un PR está CONFLICTING, GitHub no"
explica "puede construir el commit de merge de prueba y los workflows de"
explica "pull_request NI SIQUIERA SE ENCOLAN. Silencio total en Actions."
read -rp "¿Correr la prueba del gotcha de conflictos? [s/N] " R6
if [[ "${R6,,}" == "s" ]]; then
  explica "Paso A: un commit directo a main (simula un hotfix indisciplinado)..."
  PREV="$(ultima_run)"
  SHA="$(gh api "repos/$REPO/contents/backend/version.txt" --jq .sha)"
  run gh api -X PUT "repos/$REPO/contents/backend/version.txt" \
    -f message="hotfix directo en main (demo conflicto $TS)" \
    -f content="$(printf 'conflicto-main-%s\n' "$TS" | base64 -w0)" \
    -f sha="$SHA" --jq '.commit.sha'
  explica "⚠ Ojo: ese push directo a main YA disparó un deploy — el pipeline no"
  explica "distingue cómo llegó el commit. Por eso el plan oficial protege las ramas."
  DEPLOY_ID="$(espera_nueva_run "$PREV")"
  if [ -n "$DEPLOY_ID" ]; then run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status; fi
  pausa
  explica "Paso B: el mismo archivo, editado distinto en develop..."
  run git checkout -q develop
  run git pull -q
  PREV="$(ultima_run)"
  echo "conflicto-develop-$TS" > backend/version.txt
  run git add backend/version.txt
  run git commit -q -m "feat(backend): edición en develop (demo conflicto $TS)"
  run git push -q origin develop
  explica "(Este push a develop dispara su deploy de staging; lo dejamos terminar...)"
  DEPLOY_ID="$(espera_nueva_run "$PREV")"
  if [ -n "$DEPLOY_ID" ]; then run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status; fi
  pausa
  explica "Paso C: PR develop→main... que nace en conflicto."
  PREV="$(ultima_run)"
  rungh gh pr create -R "$REPO" --base main --head develop \
    --title "release: demo conflicto $TS" --body "Prueba 6: PR CONFLICTING — no debe disparar CI."
  explica "Esperando 30 s..."
  sleep 30
  if [ "$(ultima_run)" = "$PREV" ]; then
    ok "Ninguna run creada, y sin ningún error visible en Actions."
  fi
  run gh pr view -R "$REPO" develop --json mergeable,mergeStateStatus \
    --jq '"   mergeable: \(.mergeable)  |  estado: \(.mergeStateStatus)"'
  explica "Diagnóstico: si un PR \"no dispara el CI\", revisar PRIMERO si está CONFLICTING."
  pausa
  explica "Paso D: resolver mergeando main en develop → el CI revive solo..."
  PREV="$(ultima_run)"
  run git fetch -q origin
  git merge -q origin/main 2>/dev/null || true
  echo "resuelto-$TS" > backend/version.txt
  run git add backend/version.txt
  run git commit -q -m "merge: resolver conflicto de demo $TS"
  run git push -q origin develop
  RUN_ID="$(espera_nueva_run "$PREV")"
  [ -n "$RUN_ID" ] || { echo "✖ No se disparó nada tras resolver"; exit 1; }
  explica "(El push dispara DOS runs: el CI del PR revivido y el deploy de staging.)"
  run gh run watch -R "$REPO" "$RUN_ID" --exit-status
  run gh run list -R "$REPO" --limit 2
  ok "Resuelto el conflicto, el CI del PR revivió (evento synchronize)."
  PREV="$(ultima_run)"
  run gh pr merge -R "$REPO" develop --merge
  DEPLOY_ID="$(espera_nueva_run "$PREV")"
  if [ -n "$DEPLOY_ID" ]; then run gh run watch -R "$REPO" "$DEPLOY_ID" --exit-status; fi
  ok "Y el merge a main desplegó normalmente. Fin del gotcha."
  pausa
fi

# =============================================================================
titulo "Fin de la demo"
explica "Quedó demostrado:"
explica "  • Filtros de paths: docs no dispara nada; cada sector, solo su carril."
explica "  • CI real (build + tests) en el runner del servidor local, con caché."
explica "  • develop despliega staging; main despliega producción — en paralelo,"
explica "    misma VM, proyectos compose separados, y solo lo que cambió."
explica "  • Los deploys corren en el runner de la VM de OCI (nunca código de PRs)."
explica "  • Gotcha documentado: PR con conflictos = CI en silencio."
explica ""
explica "Para el repo oficial: mismos workflows, mismos runners; solo cambia la"
explica "URL al registrar los runners. Propuesta completa en el Notion del equipo."
