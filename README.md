# test-workflow — laboratorio de CI/CD (EnergiAI)

Réplica funcional del pipeline CI/CD propuesto para
[G9-LATAM-TEAM-09](https://github.com/No-Country-simulation/G9-LATAM-TEAM-09):
**CI en runners de GitHub + CD self-hosted** con staging y producción en
paralelo. Sirve como herramienta de demostración: todo lo que hay acá se probó
de punta a punta contra una VM real (OCI Ampere, ARM64).

## El modelo

| Evento | Workflow | Dónde corre | Qué hace |
|--------|----------|-------------|----------|
| PR / push a `develop` o `main` | `ci.yml` | GitHub (`ubuntu-latest`) | Build + tests + package del backend, validación del compose |
| Merge a `develop` | `deploy-backend.yml` | runner self-hosted (label `oci`) | Deploy **staging** — `compose -p energiai-staging`, puerto 8081 |
| Merge a `main` | `deploy-backend.yml` | runner self-hosted (label `oci`) | Deploy **producción** — `compose -p energiai-prod`, puerto 8080 |
| Cambios en `data-science/**` | `deploy-ml.yml` | runner self-hosted (label `oci`) | Placeholder (se activa cuando el servicio ML tenga build) |

Puntos de diseño:

- Los deploys disparan **solo con `push`** (merge) — un PR jamás ejecuta código
  en la infraestructura.
- Staging y prod conviven en la misma VM: proyectos compose separados, cada uno
  con su `.env` (en `~/energiai-envs/` de la VM, nunca en el repo).
- Filtros de `paths`: cada sector despliega solo cuando cambia su carpeta.
- `backend/Dockerfile` usa imágenes **multi-arch** (las variantes alpine de
  maven/temurin no publican ARM64) y no tiene healthcheck de actuator (el pom
  no lo incluye); el smoke test del deploy pega a `/v3/api-docs`.

## Workflows utilitarios (workflow_dispatch)

- `vm-inspeccion.yml` — radiografía de solo lectura de la VM: docker, puertos,
  recursos, rastros.
- `vm-setup.yml` — instala Docker + compose plugin y habilita el runner para
  usarlos (idempotente).
- `vm-limpieza.yml` — baja los despliegues de prueba y desmantela el runner de
  la VM (autodesmantelamiento programado con systemd-run).

## Estado actual

**Sin runners registrados.** El CI hosted funciona siempre; los `deploy-*` y
utilitarios quedan a la espera de un runner con label `oci`. Para re-armar el
laboratorio: registrar un runner self-hosted en una VM con Docker
(Settings → Actions → Runners), correr `Setup VM` si falta Docker, y mergear
cualquier cambio de `backend/**` a `develop` o `main`.
