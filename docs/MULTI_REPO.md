# Configuración multi-repositorio

Estructura objetivo:

```
codigo_si2_p2/                 ← repo PLATAFORMA (raíz)
├── .gitmodules
├── docker-compose.yml
├── database/
├── docs/
├── infra/
├── scripts/
├── backend/                   ← submodule → repo emergencias-backend
├── web/                       ← submodule → repo emergencias-web
└── mobile/                    ← submodule → repo emergencias-mobile
```

La raíz orquesta **infraestructura y documentación**; cada app tiene su propio historial Git y su propio remoto (GitHub/GitLab).

---

## Paso 1 — Crear 4 repositorios vacíos en GitHub/GitLab

| Repositorio | Contenido |
|-------------|-----------|
| `emergencias-platform` (o `codigo_si2_p2`) | Raíz: Docker, SQL, docs, compose |
| `emergencias-backend` | FastAPI |
| `emergencias-web` | Angular |
| `emergencias-mobile` | Flutter |

Anota las URLs HTTPS, por ejemplo:
- `https://github.com/TU_USUARIO/emergencias-backend.git`
- `https://github.com/TU_USUARIO/emergencias-web.git`
- `https://github.com/TU_USUARIO/emergencias-mobile.git`
- `https://github.com/TU_USUARIO/emergencias-platform.git`

---

## Paso 2 — Publicar backend, web y mobile (primer push)

Desde la carpeta del proyecto, **una vez por cada app**:

```powershell
# Backend
cd backend
git init
git add .
git commit -m "Initial commit: FastAPI backend"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/emergencias-backend.git
git push -u origin main
cd ..

# Web
cd web
git init
git add .
git commit -m "Initial commit: Angular web"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/emergencias-web.git
git push -u origin main
cd ..

# Mobile
cd mobile
git init
git add .
git commit -m "Initial commit: Flutter mobile"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/emergencias-mobile.git
git push -u origin main
cd ..
```

---

## Paso 3 — Repo raíz con submódulos

Los submódulos enlazan la raíz con un **commit concreto** de cada repo hijo.

### 3a. Renombrar carpetas actuales (solo la primera vez)

```powershell
cd D:\Universidad\Proyectos\si2\S_P_V3\codigo_si2_p2
Rename-Item backend backend.bak
Rename-Item web web.bak
Rename-Item mobile mobile.bak
```

### 3b. Inicializar repo plataforma

```powershell
git init
git add docker-compose.yml database docs infra scripts README.md .gitignore .gitattributes .gitmodules.example
git commit -m "Initial commit: platform (docker, database, docs)"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/emergencias-platform.git
```

### 3c. Añadir submódulos

```powershell
git submodule add https://github.com/TU_USUARIO/emergencias-backend.git backend
git submodule add https://github.com/TU_USUARIO/emergencias-web.git web
git submodule add https://github.com/TU_USUARIO/emergencias-mobile.git mobile

git add .gitmodules backend web mobile
git commit -m "Add backend, web, mobile submodules"
git push -u origin main
```

Puedes borrar `backend.bak`, `web.bak`, `mobile.bak` cuando compruebes que los clones están bien.

---

## Paso 4 — Clonar el proyecto completo (otro PC o compañero)

```powershell
git clone --recurse-submodules https://github.com/TU_USUARIO/emergencias-platform.git
cd emergencias-platform
docker compose up -d --build
```

Si ya clonaste sin submódulos:

```powershell
git submodule update --init --recursive
```

---

## Trabajo diario

| Acción | Comando |
|--------|---------|
| Cambios solo en backend | `cd backend` → commit → push |
| Actualizar puntero en raíz | `cd ..` → `git add backend` → commit "Bump backend" → push |
| Traer último backend | `git submodule update --remote backend` |
| Ver estado submódulos | `git submodule status` |

Flujo típico tras cambiar el API:

1. Commit y push en `emergencias-backend`.
2. En la raíz: `git submodule update --remote backend` y commit del nuevo SHA.

---

## Docker Compose

No cambia nada: `docker-compose.yml` sigue usando `./backend`, `./web`. Solo asegúrate de tener los submódulos inicializados antes de `docker compose build`.

---

## Alternativa sin submódulos (repos hermanos)

Si prefieres **no** anidar repos:

```
proyectos/
├── emergencias-platform/   # solo docker + database + docs
├── emergencias-backend/
├── emergencias-web/
└── emergencias-mobile/
```

Tendrías que ajustar `docker-compose.yml` con rutas absolutas o variables:

```yaml
backend:
  build:
    context: ${BACKEND_PATH:-../emergencias-backend}
```

Los submódulos son más cómodos para entregar **un solo clone** con todo alineado.

---

## Script automático

Edita las URLs en `scripts/repos.config.ps1` y ejecuta:

```powershell
.\scripts\setup-multi-repo.ps1
```

Modo solo documentación (sin ejecutar git): `.\scripts\setup-multi-repo.ps1 -WhatIf`
