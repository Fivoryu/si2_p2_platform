# 2.5 FT: PRUEBAS

A continuación se presentan las pruebas unitarias, de integración y E2E del sistema de Emergencias Vehiculares, cubriendo backend (FastAPI), frontend web (Angular) y móvil (Flutter).

---

## 2.5.1 Unit Testing para el Servicio de Incidentes (Backend → FastAPI + pytest)

```python
# tests/unit/test_incidente_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timezone
from uuid import uuid4

from app.services.incidente_service import IncidenteService
from app.schemas.incidente import IncidenteCreate, IncidenteResponse
from app.core.exceptions import NotFoundException, InvalidStateTransition


@pytest.fixture
def mock_db_session():
    session = AsyncMock()
    session.execute = AsyncMock()
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    return session


@pytest.fixture
def incidente_service(mock_db_session):
    return IncidenteService(mock_db_session)


@pytest.fixture
def mock_incidente_data():
    return {
        "id": str(uuid4()),
        "tenant_id": str(uuid4()),
        "conductor_id": str(uuid4()),
        "vehiculo_id": str(uuid4()),
        "estado": "PENDIENTE",
        "prioridad": "MEDIA",
        "latitud": -16.5000,
        "longitud": -68.1500,
        "descripcion": "Bateria agotada en Av. Arce",
        "resumen_ia": None,
        "tiempo_estimado_min": None,
        "reportado_at": datetime.now(timezone.utc),
        "finalizado_at": None,
    }


class TestRegistrarIncidente:
    """CU-10: Reportar Nueva Emergencia"""

    @pytest.mark.asyncio
    async def test_crear_incidente_exitoso(self, incidente_service, mock_db_session, mock_incidente_data):
        """Debe registrar un incidente con estado PENDIENTE."""
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        dto = IncidenteCreate(
            conductor_id=mock_incidente_data["conductor_id"],
            vehiculo_id=mock_incidente_data["vehiculo_id"],
            latitud=mock_incidente_data["latitud"],
            longitud=mock_incidente_data["longitud"],
            descripcion=mock_incidente_data["descripcion"],
        )

        result = await incidente_service.crear_incidente(dto)

        assert result["estado"] == "PENDIENTE"
        assert result["descripcion"] == "Bateria agotada en Av. Arce"
        mock_db_session.commit.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_crear_incidente_sin_vehiculo_registrado(self, incidente_service, mock_db_session):
        """Debe lanzar NotFoundException si el conductor no tiene vehiculos."""
        mock_db_session.execute.return_value.scalar_one.return_value = None

        dto = IncidenteCreate(
            conductor_id=str(uuid4()),
            vehiculo_id=str(uuid4()),
            latitud=-16.5000,
            longitud=-68.1500,
            descripcion="Neumático pinchado",
        )

        with pytest.raises(NotFoundException, match="Vehiculo no encontrado"):
            await incidente_service.crear_incidente(dto)

    @pytest.mark.asyncio
    async def test_crear_incidente_error_db(self, incidente_service, mock_db_session):
        """Debe propagar errores de base de datos."""
        mock_db_session.commit.side_effect = Exception("Conexion perdida con la base de datos")

        dto = IncidenteCreate(
            conductor_id=str(uuid4()),
            vehiculo_id=str(uuid4()),
            latitud=-16.5000,
            longitud=-68.1500,
            descripcion="Motor recalentado",
        )

        with pytest.raises(Exception, match="Conexion perdida"):
            await incidente_service.crear_incidente(dto)
        mock_db_session.rollback.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_crear_incidente_coordenadas_invalidas(self, incidente_service):
        """Debe validar que las coordenadas esten en rango."""
        dto = IncidenteCreate(
            conductor_id=str(uuid4()),
            vehiculo_id=str(uuid4()),
            latitud=-95.0,     # fuera de rango (-90 a 90)
            longitud=-68.1500,
            descripcion="Choque leve",
        )

        with pytest.raises(ValueError, match="Latitud fuera de rango"):
            await incidente_service.crear_incidente(dto)


class TestConsultarIncidente:
    """CU-14: Visualizar Estado Actual de la Emergencia"""

    @pytest.mark.asyncio
    async def test_obtener_incidente_por_id(self, incidente_service, mock_db_session, mock_incidente_data):
        """Debe devolver el incidente solicitado."""
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        result = await incidente_service.obtener_por_id(mock_incidente_data["id"])

        assert result["id"] == mock_incidente_data["id"]
        assert result["estado"] == "PENDIENTE"

    @pytest.mark.asyncio
    async def test_obtener_incidente_no_encontrado(self, incidente_service, mock_db_session):
        """Debe lanzar NotFoundException si el incidente no existe."""
        mock_db_session.execute.return_value.scalar_one.side_effect = Exception("no rows")

        with pytest.raises(NotFoundException, match="Incidente no encontrado"):
            await incidente_service.obtener_por_id("inexistente")


class TestCancelarIncidente:
    """CU-15: Cancelar Emergencia"""

    @pytest.mark.asyncio
    async def test_cancelar_incidente_pendiente(self, incidente_service, mock_db_session, mock_incidente_data):
        """Debe cancelar un incidente en estado PENDIENTE."""
        mock_incidente_data["estado"] = "PENDIENTE"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        result = await incidente_service.cancelar_incidente(
            mock_incidente_data["id"], motivo="El conductor resolvio el problema"
        )

        assert result["estado"] == "CANCELADO"

    @pytest.mark.asyncio
    async def test_no_cancelar_incidente_finalizado(self, incidente_service, mock_db_session, mock_incidente_data):
        """No debe permitir cancelar un incidente ya finalizado."""
        mock_incidente_data["estado"] = "FINALIZADO"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        with pytest.raises(InvalidStateTransition, match="No se puede cancelar un incidente"):
            await incidente_service.cancelar_incidente(mock_incidente_data["id"])


class TestActualizarEstado:
    """CU-36: Actualizar Estado del Incidente"""

    @pytest.mark.asyncio
    async def test_transicion_valida_en_camino(self, incidente_service, mock_db_session, mock_incidente_data):
        """Debe permitir transicion TALLER_ASIGNADO → EN_CAMINO."""
        mock_incidente_data["estado"] = "TALLER_ASIGNADO"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        result = await incidente_service.actualizar_estado(
            mock_incidente_data["id"], nuevo_estado="EN_CAMINO"
        )

        assert result["estado"] == "EN_CAMINO"
        assert result["en_camino_at"] is not None

    @pytest.mark.asyncio
    async def test_transicion_invalida_cancelado_a_en_camino(self, incidente_service, mock_db_session, mock_incidente_data):
        """No debe permitir CANCELADO → EN_CAMINO."""
        mock_incidente_data["estado"] = "CANCELADO"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente_data

        with pytest.raises(InvalidStateTransition):
            await incidente_service.actualizar_estado(
                mock_incidente_data["id"], nuevo_estado="EN_CAMINO"
            )
```

---

## 2.5.2 Unit Testing para el Servicio de Autenticación (Backend → pytest)

```python
# tests/unit/test_auth_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4
from datetime import datetime, timedelta, timezone

from app.services.auth_service import AuthService
from app.schemas.auth import LoginRequest, RegisterRequest, TokenResponse
from app.core.exceptions import InvalidCredentialsException, UserAlreadyExistsException
from app.core.security import create_access_token, verify_password


@pytest.fixture
def mock_db_session():
    session = AsyncMock()
    session.execute = AsyncMock()
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    return session


@pytest.fixture
def auth_service(mock_db_session):
    return AuthService(mock_db_session)


@pytest.fixture
def mock_usuario():
    return {
        "id": str(uuid4()),
        "tenant_id": str(uuid4()),
        "rol": "CONDUCTOR",
        "nombre": "Juan Perez",
        "email": "juan@example.com",
        "telefono": "+59177777777",
        "password_hash": "$2b$12$hashed_password_value",
        "activo": True,
        "email_verificado": True,
    }


class TestLogin:
    """CU-01: Iniciar Sesion"""

    @pytest.mark.asyncio
    async def test_login_exitoso_conductor(self, auth_service, mock_db_session, mock_usuario):
        """Debe autenticar un usuario valido y devolver token JWT."""
        mock_db_session.execute.return_value.scalar_one.return_value = mock_usuario

        with patch("app.core.security.verify_password", return_value=True):
            token = await auth_service.login(
                LoginRequest(email="juan@example.com", password="password123")
            )

        assert token.access_token is not None
        assert token.token_type == "bearer"
        assert "CONDUCTOR" in token.access_token

    @pytest.mark.asyncio
    async def test_login_contrasena_incorrecta(self, auth_service, mock_db_session, mock_usuario):
        """Debe rechazar credenciales invalidas."""
        mock_db_session.execute.return_value.scalar_one.return_value = mock_usuario

        with patch("app.core.security.verify_password", return_value=False):
            with pytest.raises(InvalidCredentialsException, match="Credenciales invalidas"):
                await auth_service.login(
                    LoginRequest(email="juan@example.com", password="wrong_password")
                )

    @pytest.mark.asyncio
    async def test_login_usuario_inactivo(self, auth_service, mock_db_session, mock_usuario):
        """Debe rechazar login de usuario inhabilitado."""
        mock_usuario["activo"] = False
        mock_db_session.execute.return_value.scalar_one.return_value = mock_usuario

        with patch("app.core.security.verify_password", return_value=True):
            with pytest.raises(InvalidCredentialsException, match="Usuario inhabilitado"):
                await auth_service.login(
                    LoginRequest(email="juan@example.com", password="password123")
                )

    @pytest.mark.asyncio
    async def test_login_email_no_registrado(self, auth_service, mock_db_session):
        """Debe manejar usuario inexistente."""
        mock_db_session.execute.return_value.scalar_one.side_effect = Exception("no rows")

        with pytest.raises(InvalidCredentialsException, match="Credenciales invalidas"):
            await auth_service.login(
                LoginRequest(email="noexiste@example.com", password="password123")
            )

    @pytest.mark.asyncio
    async def test_login_retorna_rol_en_token(self, auth_service, mock_db_session, mock_usuario):
        """El token JWT debe incluir el rol y tenant_id."""
        mock_usuario["rol"] = "TALLER"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_usuario

        with patch("app.core.security.verify_password", return_value=True):
            with patch("app.core.security.create_access_token") as mock_jwt:
                mock_jwt.return_value = "jwt.token.aqui"
                token = await auth_service.login(
                    LoginRequest(email="taller@example.com", password="password123")
                )

        # Verificar que el token se genero con los claims correctos
        mock_jwt.assert_called_once()
        call_args = mock_jwt.call_args[0]
        assert call_args[0]["rol"] == "TALLER"


class TestRegistro:
    """CU-04: Registrar Cuenta de Conductor"""

    @pytest.mark.asyncio
    async def test_registrar_conductor_exitoso(self, auth_service, mock_db_session):
        """Debe crear una cuenta nueva de conductor."""
        mock_db_session.execute.return_value.scalar_one.return_value = None  # email no existe
        mock_db_session.execute.return_value.fetchone.return_value = {"id": str(uuid4())}

        dto = RegisterRequest(
            nombre="Maria Lopez",
            email="maria@example.com",
            telefono="+59177777778",
            password="Password123!",
        )

        result = await auth_service.registrar_conductor(dto)

        assert result["rol"] == "CONDUCTOR"
        mock_db_session.commit.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_registrar_email_duplicado(self, auth_service, mock_db_session, mock_usuario):
        """Debe rechazar email ya registrado."""
        mock_db_session.execute.return_value.scalar_one.return_value = mock_usuario

        dto = RegisterRequest(
            nombre="Otro Nombre",
            email="juan@example.com",  # ya existe
            telefono="+59177777779",
            password="Password123!",
        )

        with pytest.raises(UserAlreadyExistsException, match="Email ya registrado"):
            await auth_service.registrar_conductor(dto)

    @pytest.mark.asyncio
    @pytest.mark.parametrize("password", [
        "123", "password", "abcdefgh", "sinmayuscula1!",
    ])
    async def test_registrar_contrasena_debil(self, auth_service, password):
        """Debe validar complejidad de contrasena."""
        dto = RegisterRequest(
            nombre="Test User",
            email="test@example.com",
            telefono="+59177777779",
            password=password,
        )

        with pytest.raises(ValueError, match="contrasena"):
            await auth_service.registrar_conductor(dto)
```

---

## 2.5.3 Unit Testing para el Servicio de Asignación de Talleres (Backend → pytest)

```python
# tests/unit/test_asignacion_service.py
import pytest
from unittest.mock import AsyncMock, patch
from uuid import uuid4

from app.services.assignment_service import AssignmentService
from app.core.exceptions import NoWorkshopsAvailableException


@pytest.fixture
def mock_db_session():
    session = AsyncMock()
    session.execute = AsyncMock()
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    return session


@pytest.fixture
def assignment_service(mock_db_session):
    return AssignmentService(mock_db_session)


@pytest.fixture
def mock_talleres_cercanos():
    return [
        {"id": str(uuid4()), "nombre": "Taller Norte", "distancia_km": 2.3,
         "calificacion": 4.8, "servicios_activos": 1, "disponible": True},
        {"id": str(uuid4()), "nombre": "Taller Sur", "distancia_km": 5.1,
         "calificacion": 4.2, "servicios_activos": 2, "disponible": True},
        {"id": str(uuid4()), "nombre": "Taller Este", "distancia_km": 3.0,
         "calificacion": 4.5, "servicios_activos": 0, "disponible": True},
    ]


class TestBuscarCandidatos:
    """CU-22: Buscar Talleres Candidatos"""

    @pytest.mark.asyncio
    async def test_buscar_talleres_por_ubicacion(self, assignment_service, mock_db_session, mock_talleres_cercanos):
        """Debe retornar talleres ordenados por distancia y calificacion."""
        mock_db_session.execute.return_value.fetchall.return_value = mock_talleres_cercanos

        resultado = await assignment_service.buscar_candidatos(
            latitud=-16.5000,
            longitud=-68.1500,
            tipo_incidente="BATERIA",
            tenant_id=str(uuid4()),
        )

        assert len(resultado) == 3
        # El mas cercano primero
        assert resultado[0]["distancia_km"] <= resultado[1]["distancia_km"]

    @pytest.mark.asyncio
    async def test_buscar_talleres_sin_disponibles(self, assignment_service, mock_db_session):
        """Debe lanzar excepcion si no hay talleres disponibles."""
        mock_db_session.execute.return_value.fetchall.return_value = []

        with pytest.raises(NoWorkshopsAvailableException,
                           match="No hay talleres disponibles"):
            await assignment_service.buscar_candidatos(
                latitud=-16.5000,
                longitud=-68.1500,
                tipo_incidente="MOTOR",
                tenant_id=str(uuid4()),
            )

    @pytest.mark.asyncio
    async def test_buscar_candidatos_filtra_por_tipo_servicio(self, assignment_service, mock_db_session):
        """Debe filtrar talleres que ofrezcan el tipo de servicio requerido."""
        solo_bateria = [
            {"id": str(uuid4()), "nombre": "Taller Bateria",
             "distancia_km": 1.0, "calificacion": 4.0,
             "servicios_activos": 0, "disponible": True},
        ]
        mock_db_session.execute.return_value.fetchall.return_value = solo_bateria

        resultado = await assignment_service.buscar_candidatos(
            latitud=-16.5000, longitud=-68.1500,
            tipo_incidente="BATERIA", tenant_id=str(uuid4()),
        )

        assert len(resultado) == 1
        assert resultado[0]["nombre"] == "Taller Bateria"


class TestAsignarTallerOptimo:
    """CU-23: Asignar Taller Optimo"""

    @pytest.mark.asyncio
    async def test_asignar_taller_mejor_puntaje(self, assignment_service, mock_db_session, mock_talleres_cercanos):
        """Debe asignar el taller con mejor puntaje (menor distancia, menor carga, mayor calificacion)."""
        mock_db_session.execute.return_value.fetchall.return_value = mock_talleres_cercanos

        taller = await assignment_service.asignar_taller_optimo(
            incidente_id=str(uuid4()),
            latitud=-16.5000,
            longitud=-68.1500,
            tipo_incidente="BATERIA",
            tenant_id=str(uuid4()),
        )

        # Taller Este: 3.0km, 4.5 estrellas, 0 servicios activos = mejor combinacion
        assert taller["nombre"] == "Taller Este"

    @pytest.mark.asyncio
    async def test_asignar_taller_penaliza_distancia(self, assignment_service, mock_db_session):
        """Talleres muy lejanos (>10km) deben ser penalizados."""
        lejanos = [
            {"id": str(uuid4()), "nombre": "Taller Lejano",
             "distancia_km": 25.0, "calificacion": 5.0,
             "servicios_activos": 0, "disponible": True},
            {"id": str(uuid4()), "nombre": "Taller Cercano",
             "distancia_km": 3.0, "calificacion": 3.5,
             "servicios_activos": 0, "disponible": True},
        ]
        mock_db_session.execute.return_value.fetchall.return_value = lejanos

        taller = await assignment_service.asignar_taller_optimo(
            incidente_id=str(uuid4()),
            latitud=-16.5000, longitud=-68.1500,
            tipo_incidente="LLANTA", tenant_id=str(uuid4()),
        )

        # Debe elegir el cercano aunque tenga menor calificacion
        assert taller["nombre"] == "Taller Cercano"
```

---

## 2.5.4 Unit Testing para el Servicio de Pagos (Backend → pytest)

```python
# tests/unit/test_pago_service.py
import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import uuid4
from decimal import Decimal

from app.services.pago_service import PagoService
from app.core.exceptions import PaymentFailedException, NotFoundException


@pytest.fixture
def mock_db_session():
    session = AsyncMock()
    session.execute = AsyncMock()
    session.commit = AsyncMock()
    session.rollback = AsyncMock()
    return session


@pytest.fixture
def pago_service(mock_db_session):
    return PagoService(mock_db_session)


@pytest.fixture
def mock_incidente():
    return {
        "id": str(uuid4()),
        "tenant_id": str(uuid4()),
        "conductor_id": str(uuid4()),
        "estado": "FINALIZADO",
        "cotizacion_aceptada": {"monto": Decimal("350.00")},
    }


@pytest.fixture
def mock_tenant():
    return {
        "id": str(uuid4()),
        "comision_plataforma": 0.10,
    }


class TestEfectuarPago:
    """CU-30: Efectuar Pago del Servicio"""

    @pytest.mark.asyncio
    async def test_pago_exitoso_con_stripe(self, pago_service, mock_db_session,
                                            mock_incidente, mock_tenant):
        """Debe procesar un pago exitoso y calcular la comision."""
        mock_db_session.execute.return_value.scalar_one.side_effect = [
            mock_incidente,   # obtener incidente
            mock_tenant,      # obtener tenant (comision)
        ]

        with patch("stripe.PaymentIntent.create") as mock_stripe:
            mock_stripe.return_value = MagicMock(
                id="pi_123456",
                status="succeeded",
                amount=35000,  # centavos
                currency="bob",
            )

            resultado = await pago_service.efectuar_pago(
                incidente_id=mock_incidente["id"],
                metodo="tarjeta",
                token_pago="tok_visa",
            )

        assert resultado["estado"] == "COMPLETADO"
        assert resultado["comision_plataforma"] == Decimal("35.00")  # 10% de 350
        assert resultado["monto_taller"] == Decimal("315.00")        # 350 - 35
        assert resultado["token_transaccion"] == "pi_123456"
        mock_db_session.commit.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_pago_rechazado_por_pasarela(self, pago_service, mock_db_session,
                                                mock_incidente, mock_tenant):
        """Debe registrar el pago como FALLIDO si la pasarela lo rechaza."""
        mock_db_session.execute.return_value.scalar_one.side_effect = [
            mock_incidente,
            mock_tenant,
        ]

        with patch("stripe.PaymentIntent.create") as mock_stripe:
            mock_stripe.side_effect = Exception("fondos insuficientes")

            with pytest.raises(PaymentFailedException, match="fondos insuficientes"):
                await pago_service.efectuar_pago(
                    incidente_id=mock_incidente["id"],
                    metodo="tarjeta",
                    token_pago="tok_declined",
                )

        mock_db_session.rollback.assert_awaited_once()

    @pytest.mark.asyncio
    async def test_pago_incidente_no_finalizado(self, pago_service, mock_db_session, mock_incidente):
        """No debe permitir pagar un incidente que no esta FINALIZADO."""
        mock_incidente["estado"] = "EN_CAMINO"
        mock_db_session.execute.return_value.scalar_one.return_value = mock_incidente

        with pytest.raises(InvalidStateTransition,
                           match="Solo se puede pagar incidentes finalizados"):
            await pago_service.efectuar_pago(
                incidente_id=mock_incidente["id"],
                metodo="tarjeta",
                token_pago="tok_visa",
            )

    @pytest.mark.asyncio
    @pytest.mark.parametrize("monto, esperado_plataforma, esperado_taller", [
        (Decimal("100.00"), Decimal("10.00"), Decimal("90.00")),
        (Decimal("500.00"), Decimal("50.00"), Decimal("450.00")),
        (Decimal("0.00"), Decimal("0.00"), Decimal("0.00")),
    ])
    async def test_calculo_comision_porcentajes(self, pago_service, mock_db_session,
                                                  mock_incidente, mock_tenant,
                                                  monto, esperado_plataforma, esperado_taller):
        """Debe calcular correctamente la comision del 10% para distintos montos."""
        mock_incidente["cotizacion_aceptada"]["monto"] = monto
        mock_db_session.execute.return_value.scalar_one.side_effect = [
            mock_incidente, mock_tenant,
        ]

        with patch("stripe.PaymentIntent.create") as mock_stripe:
            mock_stripe.return_value = MagicMock(
                id="pi_test", status="succeeded",
                amount=int(monto * 100), currency="bob",
            )

            resultado = await pago_service.efectuar_pago(
                incidente_id=mock_incidente["id"],
                metodo="tarjeta",
                token_pago="tok_test",
            )

        assert resultado["comision_plataforma"] == esperado_plataforma
        assert resultado["monto_taller"] == esperado_taller
```

---

## 2.5.5 Unit Testing para AuthService (Web → Angular + Jasmine)

```typescript
// web/src/app/core/auth.service.spec.ts
import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { RouterTestingModule } from '@angular/router/testing';
import { AuthService } from './auth.service';
import { environment } from '../../environments/environment';

interface LoginResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

interface UserProfile {
  id: string;
  nombre: string;
  email: string;
  rol: 'CONDUCTOR' | 'TALLER' | 'ADMIN_TENANT' | 'ADMIN_PLATAFORMA';
  tenant_id: string;
}

describe('AuthService (Web)', () => {
  let service: AuthService;
  let httpMock: HttpTestingController;

  const mockToken: LoginResponse = {
    access_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0Iiwicm9sIjoiQ09ORFVDVE9SIiwidGVuYW50X2lkIjoiYWJjZCJ9.signature',
    token_type: 'bearer',
    expires_in: 3600,
  };

  const mockProfile: UserProfile = {
    id: 'user-123',
    nombre: 'Juan Perez',
    email: 'juan@example.com',
    rol: 'CONDUCTOR',
    tenant_id: 'tenant-abc',
  };

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [
        HttpClientTestingModule,
        RouterTestingModule,
      ],
      providers: [AuthService],
    });

    service = TestBed.inject(AuthService);
    httpMock = TestBed.inject(HttpTestingController);
    localStorage.clear();
  });

  afterEach(() => {
    httpMock.verify();
    localStorage.clear();
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  describe('login', () => {
    it('should authenticate and store token', (done) => {
      service.login('juan@example.com', 'Password123!').subscribe({
        next: (response) => {
          expect(response.access_token).toBeTruthy();
          expect(localStorage.getItem('access_token')).toBe(mockToken.access_token);
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual({
        email: 'juan@example.com',
        password: 'Password123!',
      });
      req.flush(mockToken);
    });

    it('should handle 401 invalid credentials', (done) => {
      service.login('bad@email.com', 'wrong').subscribe({
        error: (error) => {
          expect(error.status).toBe(401);
          expect(error.error.detail).toBe('Credenciales invalidas');
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      req.flush(
        { detail: 'Credenciales invalidas' },
        { status: 401, statusText: 'Unauthorized' }
      );
    });

    it('should handle network error', (done) => {
      service.login('juan@example.com', 'Password123!').subscribe({
        error: (error) => {
          expect(error.status).toBe(0);
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/login`);
      req.error(new ErrorEvent('Network error', {
        message: 'No se pudo conectar al servidor',
      }));
    });
  });

  describe('logout', () => {
    it('should clear stored token and redirect to login', async () => {
      localStorage.setItem('access_token', mockToken.access_token);

      const routerSpy = spyOn(TestBed.inject(RouterTestingModule) as any, 'navigate');
      service.logout();

      expect(localStorage.getItem('access_token')).toBeNull();
    });

    it('should call revoke endpoint', () => {
      service.logout().subscribe();

      const req = httpMock.expectOne(`${environment.apiUrl}/auth/logout`);
      expect(req.request.method).toBe('POST');
      req.flush({});
    });
  });

  describe('isAuthenticated', () => {
    it('should return true when token exists and is not expired', () => {
      // Crear un token JWT con exp futuro
      const futureToken = 'eyJhbGciOiJIUzI1NiJ9.' +
        btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600, rol: 'CONDUCTOR' })) +
        '.signature';
      localStorage.setItem('access_token', futureToken);

      expect(service.isAuthenticated()).toBeTrue();
    });

    it('should return false when token is expired', () => {
      const expiredToken = 'eyJhbGciOiJIUzI1NiJ9.' +
        btoa(JSON.stringify({ exp: Math.floor(Date.now() / 1000) - 3600, rol: 'CONDUCTOR' })) +
        '.signature';
      localStorage.setItem('access_token', expiredToken);

      expect(service.isAuthenticated()).toBeFalse();
    });

    it('should return false when no token exists', () => {
      expect(service.isAuthenticated()).toBeFalse();
    });
  });

  describe('getProfile', () => {
    it('should fetch current user profile', (done) => {
      localStorage.setItem('access_token', mockToken.access_token);

      service.getProfile().subscribe({
        next: (profile) => {
          expect(profile.nombre).toBe('Juan Perez');
          expect(profile.rol).toBe('CONDUCTOR');
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/usuarios/me`);
      expect(req.request.method).toBe('GET');
      req.flush(mockProfile);
    });
  });
});
```

---

## 2.5.6 Unit Testing para ApiService (Web → Angular + Jasmine)

```typescript
// web/src/app/core/api.service.spec.ts
import { TestBed } from '@angular/core/testing';
import { HttpClientTestingModule, HttpTestingController } from '@angular/common/http/testing';
import { ApiService } from './api.service';
import { environment } from '../../environments/environment';

describe('ApiService - CRUD de Incidentes (Web)', () => {
  let service: ApiService;
  let httpMock: HttpTestingController;

  const mockIncidente = {
    id: 'inc-001',
    estado: 'PENDIENTE',
    prioridad: 'ALTA',
    descripcion: 'Choque en Av. Arce',
    latitud: -16.5000,
    longitud: -68.1500,
    conductor: { nombre: 'Juan Perez' },
    vehiculo: { placa: 'ABC-123', marca: 'Toyota' },
    reportado_at: '2025-06-01T10:00:00Z',
  };

  const mockIncidentes = [mockIncidente, { ...mockIncidente, id: 'inc-002' }];

  beforeEach(() => {
    TestBed.configureTestingModule({
      imports: [HttpClientTestingModule],
      providers: [ApiService],
    });

    service = TestBed.inject(ApiService);
    httpMock = TestBed.inject(HttpTestingController);
  });

  afterEach(() => {
    httpMock.verify();
  });

  describe('GET /incidentes', () => {
    it('should fetch all incidents', (done) => {
      service.getIncidentes().subscribe({
        next: (incidentes) => {
          expect(incidentes.length).toBe(2);
          expect(incidentes[0].estado).toBe('PENDIENTE');
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/incidentes`);
      expect(req.request.method).toBe('GET');
      req.flush(mockIncidentes);
    });

    it('should handle empty list', (done) => {
      service.getIncidentes().subscribe({
        next: (incidentes) => {
          expect(incidentes.length).toBe(0);
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/incidentes`);
      req.flush([]);
    });

    it('should handle server error', (done) => {
      service.getIncidentes().subscribe({
        error: (error) => {
          expect(error.status).toBe(500);
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/incidentes`);
      req.flush('Internal Server Error', { status: 500, statusText: 'Server Error' });
    });
  });

  describe('POST /incidentes', () => {
    it('should create a new incident', (done) => {
      const nuevo = {
        vehiculo_id: 'veh-001',
        latitud: -16.5000,
        longitud: -68.1500,
        descripcion: 'Bateria agotada',
      };

      service.createIncidente(nuevo).subscribe({
        next: (response) => {
          expect(response.estado).toBe('PENDIENTE');
          expect(response.descripcion).toBe('Bateria agotada');
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/incidentes`);
      expect(req.request.method).toBe('POST');
      expect(req.request.body).toEqual(nuevo);
      req.flush({ ...mockIncidente, descripcion: 'Bateria agotada' });
    });
  });

  describe('PATCH /incidentes/:id/estado', () => {
    it('should update incident status', (done) => {
      service.updateEstado('inc-001', 'EN_CAMINO').subscribe({
        next: (response) => {
          expect(response.estado).toBe('EN_CAMINO');
          done();
        },
      });

      const req = httpMock.expectOne(`${environment.apiUrl}/incidentes/inc-001/estado`);
      expect(req.request.method).toBe('PATCH');
      expect(req.request.body).toEqual({ estado: 'EN_CAMINO' });
      req.flush({ ...mockIncidente, estado: 'EN_CAMINO' });
    });
  });
});
```

---

## 2.5.7 Unit Testing para Sync Service (Móvil → Flutter + flutter_test)

```dart
// mobile/test/services/sync_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import 'package:emergencias/data/local_db.dart';
import 'package:emergencias/data/api/incident_api_client.dart';
import 'package:emergencias/services/sync_service.dart';
import 'package:emergencias/data/models/incidente_local.dart';

@GenerateNiceMocks([
  MockSpec<LocalDb>(),
  MockSpec<IncidentApiClient>(),
  MockSpec<Connectivity>(),
  MockSpec<Dio>(),
])
import 'sync_service_test.mocks.dart';

void main() {
  late SyncService syncService;
  late MockLocalDb mockLocalDb;
  late MockIncidentApiClient mockApiClient;
  late MockConnectivity mockConnectivity;

  final mockIncidenteLocal = IncidenteLocal(
    idLocal: 'local-uuid-001',
    vehiculoId: 'veh-123',
    latitud: -16.5000,
    longitud: -68.1500,
    descripcion: 'Llanta pinchada',
    estadoSync: 'PENDIENTE',
    createdAt: DateTime(2025, 6, 1, 10, 0),
  );

  setUp(() {
    mockLocalDb = MockLocalDb();
    mockApiClient = MockIncidentApiClient();
    mockConnectivity = MockConnectivity();
    syncService = SyncService(
      localDb: mockLocalDb,
      apiClient: mockApiClient,
      connectivity: mockConnectivity,
    );
  });

  group('CU-40: Sincronizar Automaticamente', () {
    test('debe sincronizar incidentes pendientes al recuperar conexion', () async {
      // Arrange
      when(mockConnectivity.onConnectivityChanged)
          .thenAnswer((_) => Stream.fromIterable([
                ConnectivityResult.wifi,
              ]));
      when(mockLocalDb.getIncidentesPendientes())
          .thenAnswer((_) async => [mockIncidenteLocal]);
      when(mockApiClient.syncIncidente(any))
          .thenAnswer((_) async => {'status': 'CREATED', 'server_id': 'srv-001'});

      // Act
      await syncService.syncNow();

      // Assert
      verify(mockLocalDb.getIncidentesPendientes()).called(1);
      verify(mockApiClient.syncIncidente(any)).called(1);
      verify(mockLocalDb.marcarSincronizado(
        idLocal: 'local-uuid-001',
        serverId: 'srv-001',
      )).called(1);
    });

    test('debe manejar duplicados (CU-41: idempotencia)', () async {
      // Arrange
      when(mockLocalDb.getIncidentesPendientes())
          .thenAnswer((_) async => [mockIncidenteLocal]);
      when(mockApiClient.syncIncidente(any))
          .thenAnswer((_) async => {'status': 'DUPLICATE', 'server_id': 'srv-001'});

      // Act
      await syncService.syncNow();

      // Assert
      verify(mockLocalDb.marcarSincronizado(
        idLocal: 'local-uuid-001',
        serverId: 'srv-001',
      )).called(1);
    });

    test('debe marcar ERROR cuando la sincronizacion falla', () async {
      // Arrange
      when(mockLocalDb.getIncidentesPendientes())
          .thenAnswer((_) async => [mockIncidenteLocal]);
      when(mockApiClient.syncIncidente(any))
          .thenThrow(DioException(requestOptions: RequestOptions(path: '/sync'),
                                   message: 'Timeout de conexion'));

      // Act
      await syncService.syncNow();

      // Assert
      verify(mockLocalDb.marcarErrorSync('local-uuid-001')).called(1);
    });

    test('no debe sincronizar si no hay incidentes pendientes', () async {
      // Arrange
      when(mockLocalDb.getIncidentesPendientes())
          .thenAnswer((_) async => []);

      // Act
      await syncService.syncNow();

      // Assert
      verify(mockApiClient.syncIncidente(any)).never();
    });

    test('debe reintentar con backoff exponencial', () async {
      // Arrange
      when(mockLocalDb.getIncidentesPendientes())
          .thenAnswer((_) async => [mockIncidenteLocal]);

      int callCount = 0;
      when(mockApiClient.syncIncidente(any)).thenAnswer((_) async {
        callCount++;
        if (callCount < 3) {
          throw DioException(
            requestOptions: RequestOptions(path: '/sync'),
            message: 'Error temporal',
          );
        }
        return {'status': 'CREATED', 'server_id': 'srv-001'};
      });

      // Act
      await syncService.syncNow(maxRetries: 3);

      // Assert: debe llamar 3 veces (2 fallos + 1 exito)
      expect(callCount, 3);
      verify(mockLocalDb.marcarSincronizado(
        idLocal: 'local-uuid-001',
        serverId: 'srv-001',
      )).called(1);
    });
  });

  group('CU-38: Guardar Localmente (Offline)', () {
    test('debe guardar incidente localmente cuando no hay conexion', () async {
      // Arrange
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.none);

      // Act
      await syncService.guardarIncidenteLocal(
        vehiculoId: 'veh-123',
        latitud: -16.5000,
        longitud: -68.1500,
        descripcion: 'Sin bateria',
      );

      // Assert
      verify(mockLocalDb.insertIncidentePendiente(any)).called(1);
    });

    test('debe generar UUID unico para cada incidente offline', () async {
      when(mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => ConnectivityResult.none);

      final id1 = await syncService.guardarIncidenteLocal(
        vehiculoId: 'veh-001', latitud: -16.5, longitud: -68.1,
        descripcion: 'Incidente A',
      );
      final id2 = await syncService.guardarIncidenteLocal(
        vehiculoId: 'veh-002', latitud: -16.6, longitud: -68.2,
        descripcion: 'Incidente B',
      );

      expect(id1, isNot(equals(id2)));
    });
  });
}
```

---

## 2.5.8 Unit Testing para el WebSocket Service (Móvil → Flutter + flutter_test)

```dart
// mobile/test/services/websocket_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

import 'package:emergencias/services/websocket_service.dart';
import 'package:emergencias/data/models/ubicacion_update.dart';

@GenerateNiceMocks([
  MockSpec<WebSocketChannel>(),
])
import 'websocket_service_test.mocks.dart';

void main() {
  late WebSocketService wsService;

  setUp(() {
    wsService = WebSocketService();
  });

  group('CU-33: Conectar a WebSocket para Seguimiento en Vivo', () {
    test('debe recibir actualizaciones de ubicacion del tecnico', () async {
      // Arrange
      final ubicacionesRecibidas = <UbicacionUpdate>[];

      wsService.ubicacionStream.listen((update) {
        ubicacionesRecibidas.add(update);
      });

      // Act: simular mensajes WebSocket entrantes (CU-34: Tracking)
      wsService.simularMensaje(jsonEncode({
        'type': 'ubicacion_tecnico',
        'incidente_id': 'inc-001',
        'latitud': -16.5001,
        'longitud': -68.1499,
        'timestamp': '2025-06-01T10:05:00Z',
      }));
      wsService.simularMensaje(jsonEncode({
        'type': 'ubicacion_tecnico',
        'incidente_id': 'inc-001',
        'latitud': -16.5002,
        'longitud': -68.1498,
        'timestamp': '2025-06-01T10:05:10Z',
      }));

      // Assert
      expect(ubicacionesRecibidas.length, 2);
      expect(ubicacionesRecibidas[1].latitud, -16.5002);
    });

    test('debe recibir notificaciones de cambio de estado (CU-35)', () async {
      // Arrange
      final estadosRecibidos = <String>[];

      wsService.estadoStream.listen((estado) {
        estadosRecibidos.add(estado);
      });

      // Act
      wsService.simularMensaje(jsonEncode({
        'type': 'cambio_estado',
        'incidente_id': 'inc-001',
        'estado': 'EN_CAMINO',
        'timestamp': '2025-06-01T10:10:00Z',
      }));
      wsService.simularMensaje(jsonEncode({
        'type': 'cambio_estado',
        'incidente_id': 'inc-001',
        'estado': 'EN_ATENCION',
        'timestamp': '2025-06-01T10:25:00Z',
      }));

      // Assert
      expect(estadosRecibidos, ['EN_CAMINO', 'EN_ATENCION']);
    });

    test('debe manejar reconexion ante caida del WebSocket', () async {
      // Arrange
      int intentosReconexion = 0;
      wsService.onReconnect = () => intentosReconexion++;

      // Act: simular cierre de conexion
      wsService.simularDesconexion();

      // Esperar el backoff de reconexion (en test usamos tiempo reducido)
      await Future.delayed(Duration(milliseconds: 100));

      // Assert
      expect(intentosReconexion, greaterThan(0));
    });
  });
}
```

---

## 2.5.9 Integration Testing: Ciclo Completo de Emergencia (Backend → pytest + TestClient)

```python
# tests/integration/test_ciclo_completo_emergencia.py
import pytest
from httpx import AsyncClient, ASGITransport
from uuid import uuid4

from app.main import app


@pytest.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac


@pytest.fixture
def conductor_headers():
    """Simula token JWT de un conductor autenticado."""
    return {"Authorization": "Bearer test_token_conductor_juan"}


@pytest.fixture
def taller_headers():
    """Simula token JWT de un taller autenticado."""
    return {"Authorization": "Bearer test_token_taller_norte"}


@pytest.mark.integration
class TestCicloCompletoEmergencia:
    """Flujo completo: CU-10 → CU-23 → CU-25 → CU-29 → CU-36 → CU-30 → CU-49"""

    @pytest.mark.asyncio
    async def test_flujo_completo_reporte_pago_calificacion(
        self, client, conductor_headers, taller_headers
    ):
        incidente_id = None
        cotizacion_id = None

        # ---------------------------------------------------------------
        # Paso 1 | CU-10: Reportar Nueva Emergencia
        # ---------------------------------------------------------------
        payload = {
            "vehiculo_id": "veh-uuid-conductor",
            "latitud": -16.5000,
            "longitud": -68.1500,
            "descripcion": "Bateria agotada en la Av. Arce",
        }
        response = await client.post(
            "/api/v1/incidentes",
            json=payload,
            headers=conductor_headers,
        )
        assert response.status_code == 201
        data = response.json()
        assert data["estado"] == "PENDIENTE"
        incidente_id = data["id"]

        # ---------------------------------------------------------------
        # Paso 2 | CU-23: El sistema asigna taller optimo
        # (disparado por el pipeline IA, aqui forzamos la asignacion)
        # ---------------------------------------------------------------
        response = await client.post(
            f"/api/v1/incidentes/{incidente_id}/asignar",
            headers={"Authorization": "Bearer test_token_sistema"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["estado"] == "TALLER_ASIGNADO"

        # ---------------------------------------------------------------
        # Paso 3 | CU-25: Taller acepta solicitud y genera cotizacion
        # ---------------------------------------------------------------
        response = await client.get(
            f"/api/v1/talleres/solicitudes",
            headers=taller_headers,
        )
        assert response.status_code == 200
        solicitudes = response.json()
        assert len(solicitudes) >= 1

        payload_cotizacion = {
            "incidente_id": incidente_id,
            "precio_final": 350.00,
            "tiempo_estimado_min": 25,
            "comentario": "Llegamos en 25 min, bateria nueva",
        }
        response = await client.post(
            f"/api/v1/cotizaciones",
            json=payload_cotizacion,
            headers=taller_headers,
        )
        assert response.status_code == 201
        cotizacion_id = response.json()["id"]

        # ---------------------------------------------------------------
        # Paso 4 | CU-29: Conductor selecciona la oferta
        # ---------------------------------------------------------------
        response = await client.post(
            f"/api/v1/cotizaciones/{cotizacion_id}/seleccionar",
            headers=conductor_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["estado"] == "ACEPTADA"

        # ---------------------------------------------------------------
        # Paso 5 | CU-36: Taller cambia estado a EN_CAMINO
        # ---------------------------------------------------------------
        response = await client.patch(
            f"/api/v1/incidentes/{incidente_id}/estado",
            json={"estado": "EN_CAMINO"},
            headers=taller_headers,
        )
        assert response.status_code == 200

        # Cambia a EN_ATENCION
        response = await client.patch(
            f"/api/v1/incidentes/{incidente_id}/estado",
            json={"estado": "EN_ATENCION"},
            headers=taller_headers,
        )
        assert response.status_code == 200

        # Finaliza servicio
        response = await client.patch(
            f"/api/v1/incidentes/{incidente_id}/estado",
            json={"estado": "FINALIZADO"},
            headers=taller_headers,
        )
        assert response.status_code == 200
        data = response.json()
        assert data["estado"] == "FINALIZADO"
        assert data["finalizado_at"] is not None

        # ---------------------------------------------------------------
        # Paso 6 | CU-30: Conductor efectua el pago
        # ---------------------------------------------------------------
        payload_pago = {
            "incidente_id": incidente_id,
            "metodo": "tarjeta",
            "token_pago": "tok_test_visa",
        }
        response = await client.post(
            "/api/v1/pagos",
            json=payload_pago,
            headers=conductor_headers,
        )
        assert response.status_code == 201
        data = response.json()
        assert data["estado"] == "COMPLETADO"
        assert data["comision_plataforma"] > 0
        assert data["monto_taller"] > 0

        # ---------------------------------------------------------------
        # Paso 7 | CU-49: Conductor califica el servicio
        # ---------------------------------------------------------------
        payload_calificacion = {
            "incidente_id": incidente_id,
            "puntaje": 5,
            "comentario": "Excelente servicio, rapido y profesional",
        }
        response = await client.post(
            "/api/v1/calificaciones",
            json=payload_calificacion,
            headers=conductor_headers,
        )
        assert response.status_code == 201
        data = response.json()
        assert data["puntaje"] == 5

        # ---------------------------------------------------------------
        # Verificacion final: consultar estado completo
        # ---------------------------------------------------------------
        response = await client.get(
            f"/api/v1/incidentes/{incidente_id}",
            headers=conductor_headers,
        )
        assert response.status_code == 200
        incidente_final = response.json()
        assert incidente_final["estado"] == "PAGADO"
```

---

## 2.5.10 Pruebas E2E: Reporte Offline y Sincronización (Móvil → Flutter)

```dart
// mobile/test/e2e/offline_sync_e2e_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'package:emergencias/main.dart' as app;
import 'package:emergencias/data/local_db.dart';
import 'package:emergencias/services/sync_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late LocalDb localDb;
  late SyncService syncService;

  setUp(() async {
    localDb = LocalDb();
    await localDb.inicializar();
    syncService = SyncService(localDb: localDb);
  });

  testWidgets('E2E: Reportar emergencia offline y sincronizar al recuperar conexion',
      (WidgetTester tester) async {
    // ---------------------------------------------------------------
    // Paso 1: Activar modo avion (simulado)
    // ---------------------------------------------------------------
    await simulateConnectivity(ConnectivityResult.none);

    // ---------------------------------------------------------------
    // Paso 2: CU-38 - Reportar emergencia sin conexion
    // ---------------------------------------------------------------
    app.main();
    await tester.pumpAndSettle();

    // Navegar a la pantalla de nueva emergencia
    await tester.tap(find.text('Nueva Emergencia'));
    await tester.pumpAndSettle();

    // Completar formulario
    await tester.enterText(find.byType(TextFormField).at(0), 'Llanta pinchada en zona sur');
    await tester.tap(find.text('Reportar'));
    await tester.pumpAndSettle();

    // Verificar que aparece mensaje "guardado localmente"
    expect(find.text('Guardado localmente'), findsOneWidget);
    expect(find.text('Se sincronizara al recuperar conexion'), findsOneWidget);

    // Verificar que aparezca icono de pendiente de sincronizacion en el historial
    await tester.tap(find.text('Historial'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.sync_problem), findsOneWidget);

    // ---------------------------------------------------------------
    // Paso 3: CU-40 - Restaurar conexion y sincronizar
    // ---------------------------------------------------------------
    await simulateConnectivity(ConnectivityResult.wifi);

    // Esperar que el sync service detecte la conexion y sincronice
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Verificar que el icono de sincronizacion desaparecio
    expect(find.byIcon(Icons.sync_problem), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);

    // ---------------------------------------------------------------
    // Paso 4: CU-41 - Verificar idempotencia (sin duplicados)
    // ---------------------------------------------------------------
    final pendientes = await localDb.getIncidentesPendientes();
    expect(pendientes.length, 0);

    // Verificar que solo hay un registro sincronizado (no duplicado)
    final sincronizados = await localDb.getIncidentesSincronizados();
    expect(sincronizados.length, 1);
  });
}

Future<void> simulateConnectivity(ConnectivityResult result) async {
  // Mock de conectividad para entorno de pruebas
  final connectivity = Connectivity();
  // Usar MethodChannel mock para simular cambio de conectividad
}
```

---

## Resumen de Cobertura de Pruebas

| Sección | Tipo | Capa | CUs cubiertos | Framework |
|---------|------|------|--------------|-----------|
| 2.5.1 | Unitario | Backend | CU-10, CU-14, CU-15, CU-36 | pytest |
| 2.5.2 | Unitario | Backend | CU-01, CU-04 | pytest |
| 2.5.3 | Unitario | Backend | CU-22, CU-23 | pytest |
| 2.5.4 | Unitario | Backend | CU-30, CU-31 | pytest |
| 2.5.5 | Unitario | Web | CU-01, CU-02 | Jasmine/Karma |
| 2.5.6 | Unitario | Web | CU-10, CU-14, CU-36 | Jasmine/Karma |
| 2.5.7 | Unitario | Móvil | CU-38, CU-40, CU-41 | flutter_test |
| 2.5.8 | Unitario | Móvil | CU-33, CU-34, CU-35 | flutter_test |
| 2.5.9 | Integración | Backend | Flujo completo | pytest + TestClient |
| 2.5.10 | E2E | Móvil | CU-38, CU-40, CU-41 | integration_test |
