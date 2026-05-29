# 05 — Web App (Angular, workshop + admin)

Target: workshop operators (TALLER), tenant admins (ADT), platform admin (ADM).
Covers CU-01..CU-03, CU-07..CU-09, CU-14, CU-24..CU-26, CU-31, CU-36, CU-42..CU-48.

## 1. Setup
```bash
ng new web --routing --style=scss
cd web
npm i echarts ngx-echarts jwt-decode
ng add @angular/material
```
`src/environments/environment.ts` — see doc 00 §6.

## 2. App structure (`src/app/`)
```
app/
├── core/
│   ├── auth.service.ts        # login, token, role/tenant
│   ├── auth.interceptor.ts    # attach Bearer
│   ├── auth.guard.ts          # route guard by role
│   └── api.service.ts         # base HttpClient wrapper
├── features/
│   ├── auth/login.component.ts
│   ├── requests/requests.component.ts     # workshop inbox (real-time table)
│   ├── status/status-dialog.component.ts  # update incident status
│   ├── availability/availability.component.ts
│   ├── kpis/kpis.component.ts             # ECharts dashboard
│   ├── sla/sla.component.ts
│   └── admin/tenants.component.ts
└── app.routes.ts
```

## 3. Auth (core)
`auth.service.ts`:
```ts
@Injectable({providedIn:'root'})
export class AuthService {
  private base = environment.apiUrl;
  constructor(private http: HttpClient) {}

  login(email: string, password: string) {
    return this.http.post<any>(`${this.base}/auth/login`, {email, password})
      .pipe(tap(r => localStorage.setItem('jwt', r.access_token)));
  }
  get claims(): any { const t = localStorage.getItem('jwt'); return t ? jwtDecode(t) : null; }
  get role(): string { return this.claims?.rol; }
  get tenantId(): string { return this.claims?.tenant; }
  logout(){ this.http.post(`${this.base}/auth/logout`,{}).subscribe(); localStorage.removeItem('jwt'); }
}
```
`auth.interceptor.ts`: clone request adding `Authorization: Bearer <jwt>`.
`auth.guard.ts`: `canActivate` checks `AuthService.role` ∈ allowed roles.

## 4. Workshop inbox (real-time table) — CU-14, CU-24, CU-25, CU-26, CU-36
`requests.component.ts`:
```ts
export class RequestsComponent implements OnInit, OnDestroy {
  incidentes: any[] = [];
  private sockets = new Map<string, WebSocket>();

  constructor(private api: ApiService, private auth: AuthService) {}

  ngOnInit() {
    this.api.get('/incidentes?estado=TALLER_ASIGNADO').subscribe(r => {
      this.incidentes = r.items;
      this.incidentes.forEach(i => this.openWs(i.id));
    });
  }
  openWs(incidentId: string) {
    const url = `${environment.wsUrl}/ws/${this.auth.tenantId}/${incidentId}?token=${localStorage.getItem('jwt')}`;
    const ws = new WebSocket(url);
    ws.onmessage = ev => {
      const msg = JSON.parse(ev.data);
      if (msg.type === 'STATUS_CHANGED') this.patchRow(incidentId, msg.data.estado_nuevo);
    };
    this.sockets.set(incidentId, ws);
  }
  aceptar(a: any){ this.api.post(`/asignaciones/${a.asignacion_id}/aceptar`, {tecnico_id: a.tecnico_id}).subscribe(); }
  rechazar(a: any){ this.api.post(`/asignaciones/${a.asignacion_id}/rechazar`, {motivo: a.motivo}).subscribe(); }
  ngOnDestroy(){ this.sockets.forEach(s => s.close()); }
}
```
Template: `mat-table` with columns `[resumen_ia, tipo, prioridad, estado, acciones]`; Accept/Reject buttons; status chips colored by `estado`.

## 5. Status update — CU-36, CU-37
`status-dialog.component.ts`: a `mat-select` showing only valid next states (mirror doc 00 §5). On confirm:
```ts
this.api.patch(`/incidentes/${id}/estado`, {estado: next, comentario}).subscribe();
// backend broadcasts via WS → driver app + other web clients update
```

## 6. Availability — CU-09
`availability.component.ts`: toggle `disponible` + number input `capacidad_max` →
`PATCH /talleres/{id}/disponibilidad {disponible, capacidad_max}`.

## 7. KPI dashboard (ECharts) — CU-42, CU-43, CU-44
Register ngx-echarts in `app.config.ts`:
```ts
import { provideEcharts } from 'ngx-echarts';
export const appConfig = { providers: [ /* ... */ provideEcharts() ] };
```
`kpis.component.ts`:
```ts
export class KpisComponent implements OnInit {
  porTipoOpt:any; resumen:any; slaOpt:any; talleres:any[]=[];
  tenantSel?: string;   // only ADM can change (CU-43)
  isAdm = this.auth.role === 'ADMIN_PLATAFORMA';

  ngOnInit(){ this.load(); }
  load(){
    const q = this.isAdm && this.tenantSel ? `?tenant_id=${this.tenantSel}` : '';
    this.api.get(`/kpis/resumen${q}`).subscribe(r => this.resumen = r[0]);
    this.api.get(`/kpis/por-tipo${q}`).subscribe(r => this.porTipoOpt = {
      xAxis:{type:'category', data:r.map((x:any)=>x.tipo_nombre)},
      yAxis:{type:'value'},
      series:[{type:'bar', data:r.map((x:any)=>x.total)}]
    });
    this.api.get(`/kpis/sla${q}`).subscribe(r => this.slaOpt = {
      tooltip:{}, xAxis:{type:'category', data:r.map((x:any)=>x.tipo_nombre)},
      yAxis:{type:'value', max:100},
      series:[{type:'bar', name:'% cumplimiento', data:r.map((x:any)=>x.pct_cumplimiento)}]
    });
    this.api.get(`/kpis/talleres${q}`).subscribe(r => this.talleres = r);
  }
  refrescar(){ this.api.post('/kpis/refresh', {}).subscribe(() => this.load()); }
  exportCsv(){ /* build CSV from this.talleres etc., trigger download (CU-44) */ }
}
```
Template uses `<div echarts [options]="porTipoOpt"></div>`, number cards for `resumen.prom_min_asignacion` / `prom_min_llegada` / `pct_cancelacion`, a `mat-table` for `talleres`, a date-range filter, and (ADM only) a tenant `mat-select`.

Charts to render:
- **Bar** — incidents by type (`/kpis/por-tipo`).
- **Number cards** — avg assignment/arrival time, % cancellation (`/kpis/resumen`).
- **Bar** — SLA compliance % per type (`/kpis/sla`).
- **Table** — efficient workshops (`/kpis/talleres`).
- **Scatter on map / heat** — zones (`/kpis/zonas`) (optional).

## 8. SLA config — CU-45
`sla.component.ts`: table of `tipo_incidente` × `tiempo_max_min`, editable; `POST/PATCH /sla`. ADM only.

## 9. Admin / tenants — CU-46, CU-47, CU-48
`tenants.component.ts` (ADM only): create tenant form (`nombre,dominio,plan_id`); assign admin (`email`); change plan. Calls `/tenants*` (backend uses BYPASSRLS engine for ADM).

## 10. Routes — `app.routes.ts`
```ts
export const routes: Routes = [
  { path: 'login', component: LoginComponent },
  { path: 'requests', component: RequestsComponent, canActivate:[authGuard(['TALLER','ADMIN_TENANT'])] },
  { path: 'kpis', component: KpisComponent, canActivate:[authGuard(['ADMIN_TENANT','ADMIN_PLATAFORMA'])] },
  { path: 'sla', component: SlaComponent, canActivate:[authGuard(['ADMIN_PLATAFORMA'])] },
  { path: 'admin/tenants', component: TenantsComponent, canActivate:[authGuard(['ADMIN_PLATAFORMA'])] },
  { path: '', redirectTo: 'requests', pathMatch: 'full' },
];
```

## 11. Acceptance
- Login as `centro@auxilionorte.com` → see only Auxilio Norte requests.
- Click Accept on a request → status becomes `EN_CAMINO`, driver app updates live.
- Open `/kpis` as `ana@auxilionorte.com` → charts render with seeded data; cannot switch tenant.
- Login as `admin@plataforma.com` → tenant dropdown appears, can view any tenant's KPIs.
