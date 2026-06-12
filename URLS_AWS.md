# URLs desplegadas en AWS (EC2)

Stack desplegado con **Docker Compose** en una instancia EC2 (región `us-east-1`).

> IP pública (Elastic IP): **`32.196.207.97`**  
> Fuente: `infra/aws-deploy.env`

---

## Servicios públicos

| Servicio | URL | Descripción |
|----------|-----|-------------|
| **Web Angular** | http://32.196.207.97 | Panel taller / admin (puerto 80) |
| **API Backend** | http://32.196.207.97:8000 | REST FastAPI |
| **Swagger / Docs** | http://32.196.207.97:8000/docs | Documentación interactiva |
| **Health API** | http://32.196.207.97:8000/health | Estado del backend |
| **AcquireMock** | http://32.196.207.97:8001 | Mock de pagos (Stripe-like) |
| **WebSocket** | ws://32.196.207.97:8000 | Tracking en tiempo real |

### Recursos AWS (infra)

| Recurso | Valor |
|---------|--------|
| Región | `us-east-1` |
| Elastic IP | `32.196.207.97` |
| Security Group | `sg-0b3240cae14732a1a` |
| Key pair EC2 | `sw1-examen` |
| Bucket S3 evidencias | `emergencias-evidencias` |

Puertos abiertos en el security group (según `docs/08_AWS_EC2_DEPLOY.md`): **22**, **80**, **8000**, **8001**.

PostgreSQL, Redis y OSRM **no** están expuestos públicamente (solo red interna Docker).

---

## Flutter móvil (APK / Samsung)

```powershell
cd mobile
flutter run -d <DEVICE_ID> `
  --dart-define=API_URL=http://32.196.207.97:8000 `
  --dart-define=WS_URL=ws://32.196.207.97:8000
```

APK release:

```powershell
flutter build apk --release `
  --dart-define=API_URL=http://32.196.207.97:8000 `
  --dart-define=WS_URL=ws://32.196.207.97:8000
```

---

## Flutter Web (Chrome) → backend AWS

**Sí, puedes usar Chrome** apuntando al backend de AWS con `--dart-define`:

```powershell
cd mobile
flutter run -d chrome `
  --dart-define=API_URL=http://32.196.207.97:8000 `
  --dart-define=WS_URL=ws://32.196.207.97:8000
```

### CORS (importante)

Chrome sirve la app en un origen como `http://localhost:65360`. El backend en AWS, por defecto, solo permite CORS desde la web Angular:

```
http://32.196.207.97
```

Para que **Flutter web en tu PC** pueda llamar a la API AWS, en el servidor EC2 añade en `.env.aws`:

```env
CORS_ORIGIN_REGEX=http://(localhost|127\.0\.0\.1):\d+
```

Y reinicia el backend:

```bash
docker compose -f docker-compose.yml -f docker-compose.aws.yml --env-file .env.aws up -d backend
```

Sin eso verás errores de CORS en la consola del navegador.

### Push en Chrome + AWS

- **Notificaciones in-app** (polling cada 6 s): funcionan en web sin configuración extra.
- **Push FCM nativo en Chrome**: requiere registrar app Web en Firebase y pasar `FIREBASE_WEB_APP_ID` + `FIREBASE_VAPID_KEY` (ver `backend/secrets/README.md`).
- En **Android físico** contra AWS: push FCM sí funciona si el backend tiene `firebase-service-account.json`.

---

## Usuarios demo

Ver [`USUARIOS_DEMO.md`](USUARIOS_DEMO.md). Ejemplos:

| Rol | Email | Password |
|-----|-------|----------|
| Conductor | `carlos@mail.com` | `password123` |
| Técnico | `luis@auxilionorte.com` | `password123` |
| Taller | `centro@auxilionorte.com` | `password123` |
| Admin tenant | `ana@auxilionorte.com` | `password123` |

---

## Verificación rápida

Desde tu PC:

```powershell
curl.exe http://32.196.207.97:8000/health
curl.exe -I http://32.196.207.97/
```

Respuesta esperada del health: JSON con estado OK.

Si no responde: comprobar que la instancia EC2 está **running** y el security group permite tu IP en los puertos 80/8000.

---

## Actualizar el despliegue

En la instancia EC2:

```bash
cd ~/si2_p2_platform
git pull --recurse-submodules
docker compose -f docker-compose.yml -f docker-compose.aws.yml --env-file .env.aws up -d --build
```

Documentación completa: [`docs/08_AWS_EC2_DEPLOY.md`](docs/08_AWS_EC2_DEPLOY.md)
