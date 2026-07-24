# 🧪 test-workflow — Réplica del pipeline CI/CD de EnergiAI

Repo de práctica de [@Neo236](https://github.com/Neo236) que replica **1:1** el pipeline
CI/CD propuesto para [`No-Country-simulation/G9-LATAM-TEAM-09`](https://github.com/No-Country-simulation/G9-LATAM-TEAM-09)
(propuesta "CI/CD por Sector, runners self-hosted", julio 2026). Mismos workflows,
mismos nombres de runner, mismas etiquetas: lo único que cambia es la URL del repo
al registrar los runners.

## Runners (idénticos al plan oficial)

| Runner | Máquina | Label | Corre |
|--------|---------|-------|-------|
| `energiai-ci-01` | Servidor local del equipo (Debian x64) | `ci` | CI de los PRs: build + tests |
| `energiai-oci-01` | VM OCI `energiai-app-01` (Ubuntu 24.04 ARM64) | `oci` | CD: deploys al mergear a `main` |

## Workflows

| Evento | Workflow | Runner |
|--------|----------|--------|
| PR a `develop`/`main` que toca `backend/**` | `ci-backend` — **`./mvnw -B verify` real** (el backend Spring Boot es copia del repo oficial) | `ci` |
| PR a `develop`/`main` que toca `data-science/**` | `ci-ml` (placeholders, igual que el oficial hoy) | `ci` |
| Merge a `develop` (→ **staging**) o `main` (→ **prod**) que toca `backend/**` | `deploy-backend` | `oci` |
| Merge a `develop`/`main` que toca `data-science/**` | `deploy-ml` | `oci` |
| Merge a `develop`/`main` que toca `docker-compose.yml` | `deploy-full` | `oci` |
| Solo `docs/**` / `README.md` | ninguno | — |

Los `deploy-*` mantienen los pasos placeholder del template oficial (los comandos
`docker compose` reales quedan bloqueados por pendientes del repo oficial,
documentados en la propuesta de CI/CD).

## Flujo de ramas

`feature/*` → PR → `develop` (→ despliega **staging**) → PR → `main` (→ despliega
**producción**). Los deploys nunca se disparan desde PRs: código de PRs jamás corre
en el runner de la VM. Ambos ambientes conviven en la VM como proyectos compose
separados (`energiai-staging` / `energiai-prod`), cada uno con su `.env` y puertos.

## Demo guiada paso a paso

`demo/demo-pipeline.sh` recorre cada propiedad del pipeline pausando con **Enter**
entre pruebas (pensado para mostrarlo en vivo): filtros de `paths`, CI real en el
runner `ci`, integración a `develop` sin deploy, deploy selectivo en el runner
`oci` de la VM, carril propio de ML (opcional) y el gotcha de PRs con conflicto
(opcional). Requiere `gh` autenticado con push al repo:

```bash
bash demo/demo-pipeline.sh
```

## Diferencias deliberadas con el oficial

- El backend acá está commiteado con `mvnw` **con** bit de ejecución (el fix
  definitivo); el workflow conserva el `chmod +x` defensivo del template.
- Sin revisión de PR obligatoria (repo de una sola persona); el oficial exige
  1 aprobación.
