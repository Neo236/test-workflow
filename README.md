# 🧪 Demo — CI/CD con runner self-hosted

Repo de demostración para el equipo de **EnergiAI**. Muestra cómo un runner de
GitHub instalado en nuestra máquina (en el proyecto real: la VM de OCI)
despliega automáticamente **solo el componente que cambió** en cada merge a
`main` o `develop`.

## La idea en 30 segundos

- Hay 4 workflows en `.github/workflows/`, uno por componente:

| Workflow | Se dispara cuando cambia... |
|---|---|
| `deploy-backend.yml` | `backend/**` |
| `deploy-frontend.yml` | `frontend/**` |
| `deploy-ml.yml` | `data-science/**` |
| `deploy-full.yml` | `docker-compose.yml` |

- Un push que solo toca `docs/` o este README **no dispara nada**.
- Los workflows corren en un **runner self-hosted**: un agente instalado en
  nuestra máquina que ejecuta los comandos localmente. En el proyecto real,
  ese agente vive en la VM de OCI y el paso simulado se reemplaza por
  `docker compose up -d --build <servicio>`.

## Preparar la demo (una sola vez, ~5 min)

1. En este repo: **Settings → Actions → Runners → New self-hosted runner**.
2. Elegir el OS de tu máquina y seguir los comandos que muestra GitHub
   (descargar, `./config.sh` con el token, `./run.sh`).
3. Cuando pregunte por **labels**, agregar `demo` (los workflows usan
   `runs-on: [self-hosted, demo]`).
4. Dejar la terminal con `./run.sh` corriendo y visible: ahí se ve al runner
   trabajar en vivo.

## Guion de la demo

Con la pestaña **Actions** del repo abierta en el navegador y la terminal del
runner al lado:

1. **Cambio en backend** (en rama `develop`):
   ```bash
   echo "backend v2" > backend/version.txt
   git add . && git commit -m "cambio en backend" && git push
   ```
   → Se dispara **solo** `Deploy Backend`. Verlo correr en la terminal.

2. **Cambio en docs**:
   ```bash
   echo "mas notas" >> docs/notas.md
   git add . && git commit -m "solo docs" && git push
   ```
   → **No se dispara nada.** Este es el punto clave del filtro `paths`.

3. **Cambio en frontend y en data-science juntos**:
   → Se disparan **los dos** workflows, cada uno con su componente.

4. **Merge de develop a main**:
   → El mismo workflow corre de nuevo, ahora con `Rama: main`. En el
   proyecto real, acá se elegiría el entorno (prod vs staging) según
   `github.ref_name`.

5. Mostrar el historial de "despliegues" acumulado en la máquina:
   ```bash
   cat ~/demo-deploys.log
   ```

## Qué cambia en el proyecto real

| Demo | Real |
|---|---|
| Runner en mi PC | Runner en la VM de OCI (binario ARM64) |
| `echo` + `sleep` | `docker compose up -d --build <servicio>` |
| `~/demo-deploys.log` | Los contenedores actualizados corriendo |
| Label `demo` | Label `oci` |

**Nota de seguridad para el repo real (público):** en Settings → Actions,
verificar que los workflows de PRs de forks requieran aprobación antes de
correr, para que código ajeno nunca se ejecute en nuestra VM.
