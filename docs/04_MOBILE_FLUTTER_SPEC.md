# 04 — Mobile App (Flutter, driver)

Target: Android (emulator + APK). Offline-first. Covers CU-01..CU-16, CU-29, CU-30, CU-33..CU-40.

## 1. Setup & dependencies
```bash
flutter create mobile
cd mobile
flutter pub add dio flutter_riverpod go_router sqflite path \
    connectivity_plus geolocator image_picker record \
    web_socket_channel google_maps_flutter flutter_secure_storage \
    firebase_core firebase_messaging uuid intl
```
Android config:
- `android/app/src/main/AndroidManifest.xml`: permissions `INTERNET, ACCESS_FINE_LOCATION, CAMERA, RECORD_AUDIO`; Google Maps API key meta-data.
- `minSdkVersion 23` (for some plugins) in `android/app/build.gradle`.
- Add `google-services.json` (Firebase) under `android/app/`.
- Emulator reaches host backend at `http://10.0.2.2:8000`.

## 2. Folder structure (`lib/`)
```
lib/
├── main.dart
├── core/        config.dart, dio_client.dart, router.dart, theme.dart
├── data/
│   ├── local_db.dart           # sqflite (offline)
│   ├── api/                    # auth_api, incidente_api, taller_api, pago_api
│   └── models/                 # Incidente, Vehiculo, Taller, ...
├── services/    auth_service.dart, sync_service.dart, location_service.dart, ws_service.dart, push_service.dart
├── providers/   riverpod providers
└── screens/     login, register, home_map, new_incident, tracking, history, vehicles, profile
```

## 3. Config & HTTP client
`lib/core/config.dart` — see doc 00 §6.

`lib/core/dio_client.dart`:
```dart
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'config.dart';

final _storage = const FlutterSecureStorage();

Dio buildDio() {
  final dio = Dio(BaseOptions(baseUrl: Config.apiUrl, connectTimeout: const Duration(seconds: 10)));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) async {
    final token = await _storage.read(key: 'jwt');
    if (token != null) o.headers['Authorization'] = 'Bearer $token';
    h.next(o);
  }));
  return dio;
}
```

## 4. Local DB (offline) — `lib/data/local_db.dart` (CU-38)
```dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDb {
  static Database? _db;
  static Future<Database> get db async => _db ??= await _open();

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'emergencias.db');
    return openDatabase(path, version: 1, onCreate: (d, v) async {
      await d.execute('''
        CREATE TABLE incidente_local(
          id_local TEXT PRIMARY KEY,
          vehiculo_id TEXT,
          descripcion TEXT,
          latitud REAL, longitud REAL, direccion TEXT,
          evidencias TEXT,                 -- JSON array
          estado_sync TEXT DEFAULT 'PENDIENTE',  -- PENDIENTE|SINCRONIZADO|ERROR
          id_servidor TEXT,
          client_created_at TEXT,
          client_updated_at TEXT
        )''');
    });
  }

  static Future<void> insertPending(Map<String, dynamic> row) async =>
      (await db).insert('incidente_local', row, conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<List<Map<String, dynamic>>> pending() async =>
      (await db).query('incidente_local', where: "estado_sync = 'PENDIENTE'");

  static Future<void> markSynced(String idLocal, String idServidor) async =>
      (await db).update('incidente_local',
          {'estado_sync': 'SINCRONIZADO', 'id_servidor': idServidor},
          where: 'id_local = ?', whereArgs: [idLocal]);
}
```

## 5. New incident — offline-first (CU-10..CU-13)
`lib/screens/new_incident.dart` (logic excerpt):
```dart
final idLocal = const Uuid().v4();
final pos = await LocationService.current();          // geolocator
final photos = await ImagePicker().pickMultiImage();  // base64 small or upload later
final audioPath = await recorder.stop();              // record pkg, <=60s

final row = {
  'id_local': idLocal,
  'vehiculo_id': selectedVehicleId,
  'descripcion': descCtrl.text,
  'latitud': pos.latitude, 'longitud': pos.longitude, 'direccion': address,
  'evidencias': jsonEncode(evidenceList),
  'client_created_at': DateTime.now().toUtc().toIso8601String(),
  'client_updated_at': DateTime.now().toUtc().toIso8601String(),
};
await LocalDb.insertPending(row);          // ALWAYS local first (CU-38)

if (await Connectivity().checkConnectivity() != ConnectivityResult.none) {
  await SyncService.syncNow();             // try immediately
}
// UI: show "guardado, se sincronizará" with a clock icon if still PENDIENTE (CU-38)
```

## 6. Sync service — `lib/services/sync_service.dart` (CU-40, CU-41)
```dart
import 'package:connectivity_plus/connectivity_plus.dart';
class SyncService {
  static void start() {
    Connectivity().onConnectivityChanged.listen((r) {
      if (r != ConnectivityResult.none) syncNow();
    });
  }

  static Future<void> syncNow() async {
    final pend = await LocalDb.pending();
    if (pend.isEmpty) return;
    final body = {
      'dispositivo': 'flutter-android',
      'incidentes': pend.map((p) => {
        'external_id': p['id_local'],
        'vehiculo_id': p['vehiculo_id'],
        'descripcion': p['descripcion'],
        'latitud': p['latitud'], 'longitud': p['longitud'], 'direccion': p['direccion'],
        'client_created_at': p['client_created_at'],
        'client_updated_at': p['client_updated_at'],
        'evidencias': jsonDecode(p['evidencias'] ?? '[]'),
      }).toList(),
    };
    try {
      final res = await buildDio().post('/sync', data: body);
      for (final r in res.data['results']) {
        await LocalDb.markSynced(r['external_id'], r['incidente_id']);  // idempotent
      }
    } catch (_) {
      // keep PENDIENTE; exponential backoff retry on next connectivity event
    }
  }
}
```

## 7. Live tracking — `lib/services/ws_service.dart` (CU-33, CU-34)
```dart
import 'package:web_socket_channel/web_socket_channel.dart';
class WsService {
  WebSocketChannel? _ch;
  Stream connect(String tenantId, String incidentId, String token) {
    final url = '${Config.wsUrl}/ws/$tenantId/$incidentId?token=$token';
    _ch = WebSocketChannel.connect(Uri.parse(url));
    return _ch!.stream;     // listen: decode JSON, switch on data['type']
  }
  void close() => _ch?.sink.close();
}
```
In `tracking.dart`: on `STATE_SNAPSHOT`/`STATUS_CHANGED` update the status banner; on `TECH_LOCATION` move the `Marker` on `GoogleMap`; send `PING` every 20s.

## 8. GPS — `lib/services/location_service.dart`
```dart
import 'package:geolocator/geolocator.dart';
class LocationService {
  static Future<Position> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) throw 'GPS off';
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }
}
```

## 9. Push — `lib/services/push_service.dart` (CU-35)
```dart
import 'package:firebase_messaging/firebase_messaging.dart';
class PushService {
  static Future<void> init(Dio dio) async {
    final fm = FirebaseMessaging.instance;
    await fm.requestPermission();
    final token = await fm.getToken();
    if (token != null) await dio.post('/usuarios/me/fcm', data: {'fcm_token': token});
    FirebaseMessaging.onMessage.listen((m) {/* show in-app banner */});
  }
}
```

## 10. Payment (CU-30)
Use Stripe Checkout via webview, or `flutter_stripe`:
1. `POST /pagos/intent {incidente_id, cotizacion_id}` → `client_secret`.
2. Confirm card with Stripe SDK (test card `4242 4242 4242 4242`).
3. Stripe webhook hits backend → `pago` recorded, incident `PAGADO`.
4. App polls `GET /incidentes/{id}` until `PAGADO`, shows receipt.

## 11. Screen-by-screen checklist
| Screen | Use cases | Must do |
|--------|-----------|---------|
| Login/Register | CU-01,04 | store JWT, route by role |
| Vehicles | CU-05 | list/add, placa unique |
| Home (map) | CU-13 | show my location, "New emergency" button |
| New incident | CU-10..12 | photos+audio+GPS, offline-first save |
| Tracking | CU-14,33,34,35 | WS status + tech marker, push banner |
| History | CU-16 | list past incidents (server + local pending) |
| Profile | CU-06 | edit profile |
| Payment sheet | CU-30 | Stripe flow + receipt |

## 12. Acceptance
- Airplane mode → create 2 incidents → both show with clock icon; DB `incidente_local` has 2 PENDIENTE rows.
- Turn network on → both become SINCRONIZADO; server shows 2 incidents; re-run sync → no new rows.
- Open tracking while workshop updates status on web → banner updates live.
