' -----------------------------------------------------------------------------
' Enterprise Architect VBScript
' Implementacion: arquitectura del sistema de Emergencias Vehiculares.
' Basado en CapturaDeRequisitos.md, DetalleCasosDeUso.md y Analisis.md.
' Crea/actualiza: Implementacion / 01 - Arquitectura de Implementacion
' -----------------------------------------------------------------------------

Dim repo
Set repo = GetEARepository()

If repo Is Nothing Then
    Log "No se pudo obtener Repository. Abra Enterprise Architect e intente nuevamente."
Else
    BuildImplementationArchitecture repo
End If

Function GetEARepository()
    On Error Resume Next
    Set GetEARepository = Nothing
    Err.Clear

    Dim candidateRepository
    Set candidateRepository = Repository
    If Err.Number = 0 And Not candidateRepository Is Nothing Then
        Set GetEARepository = candidateRepository
        On Error GoTo 0
        Exit Function
    End If

    Err.Clear
    Dim eaApp
    Set eaApp = GetObject(, "EA.App")
    If Err.Number = 0 And Not eaApp Is Nothing Then Set GetEARepository = eaApp.Repository
    On Error GoTo 0
End Function

Sub BuildImplementationArchitecture(repository)
    Dim rootPackage, implementationPackage, sectionPackage
    Set rootPackage = GetOrCreateRootPackage(repository)
    Set implementationPackage = GetOrCreateChildPackage(rootPackage, "Implementacion")

    DeleteChildPackage implementationPackage, "01 - Arquitectura de Implementacion"
    Set sectionPackage = implementationPackage.Packages.AddNew("01 - Arquitectura de Implementacion", "")
    sectionPackage.Notes = "Diagramas de implementacion de la plataforma de emergencias vehiculares."
    sectionPackage.Update
    implementationPackage.Packages.Refresh

    CreateSystemImplementationDiagram repository, sectionPackage
    CreateSubsystemUsuarios repository, sectionPackage
    CreateSubsystemIncidentes repository, sectionPackage
    CreateSubsystemIA repository, sectionPackage
    CreateSubsystemTalleres repository, sectionPackage
    CreateSubsystemPagos repository, sectionPackage
    CreateSubsystemTiempoReal repository, sectionPackage

    Log "Creado: Implementacion / 01 - Arquitectura de Implementacion"
End Sub

' -----------------------------------------------------------------------------
' Arquitectura General del Sistema
' -----------------------------------------------------------------------------
Sub CreateSystemImplementationDiagram(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")

    AddPackageElement parentPackage, elements, "FE", "Frontend (Flutter + Angular)"
    AddPackageElement parentPackage, elements, "BE", "Backend (FastAPI)"
    AddPackageElement parentPackage, elements, "IA", "Pipeline IA"
    AddPackageElement parentPackage, elements, "WS", "WebSocket Manager"
    AddPackageElement parentPackage, elements, "SYNC", "Sincronizacion Offline"

    AddComponent parentPackage, elements, "DB", "PostgreSQL (emergencias)", "database"
    AddComponent parentPackage, elements, "STOR", "Storage (fotos, audio)", "external"

    AddComponent parentPackage, elements, "YOLO", "YOLOv8 Models", "external"
    AddComponent parentPackage, elements, "OPENAI", "OpenAI (Whisper)", "external"
    AddComponent parentPackage, elements, "MAPS", "Google Maps / OSM", "external"
    AddComponent parentPackage, elements, "PAY", "Stripe / Mercado Pago", "external"
    AddComponent parentPackage, elements, "FCM", "Firebase Cloud Messaging", "external"

    LinkDependency elements, "FE", "BE", "REST / WebSocket"
    LinkDependency elements, "BE", "IA", "CU-17..CU-21"
    LinkDependency elements, "BE", "WS", "CU-33..CU-37"
    LinkDependency elements, "BE", "SYNC", "CU-38..CU-41"
    LinkAssociation elements, "BE", "DB", "SQL"
    LinkAssociation elements, "BE", "STOR", "Archivos"

    LinkAssociation elements, "IA", "YOLO", "imagenes"
    LinkAssociation elements, "IA", "OPENAI", "audio"
    LinkAssociation elements, "BE", "MAPS", "geolocalizacion"
    LinkAssociation elements, "BE", "PAY", "transacciones"
    LinkAssociation elements, "WS", "FCM", "push"

    Set diagram = parentPackage.Diagrams.AddNew("Implementacion de la Arquitectura del Sistema", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh

    Place diagram, elements("FE"), 80, 50, 250, 95
    Place diagram, elements("BE"), 410, 50, 250, 95
    Place diagram, elements("IA"), 740, 50, 220, 95
    Place diagram, elements("WS"), 80, 200, 250, 95
    Place diagram, elements("SYNC"), 410, 200, 250, 95

    Place diagram, elements("DB"), 210, 400, 700, 120
    Place diagram, elements("STOR"), 210, 580, 340, 100
    Place diagram, elements("PAY"), 570, 580, 340, 100

    Place diagram, elements("YOLO"), 740, 200, 220, 80
    Place diagram, elements("OPENAI"), 740, 310, 220, 80
    Place diagram, elements("MAPS"), 80, 380, 80, 280
    Place diagram, elements("FCM"), 950, 520, 80, 200

    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Usuarios y Acceso
' -----------------------------------------------------------------------------
Sub CreateSubsystemUsuarios(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Usuarios y Acceso (CU-01..CU-04, CU-46..CU-48)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "login-page, register-page, admin-tenants-page", "interface"
    AddComponent parentPackage, elements, "CTRL", "auth.py / tenants.py / users.py", "controller"
    AddComponent parentPackage, elements, "SVC", "auth.service.ts / security.py / tenant_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "Usuario / Tenant / Plan / Rol", "entity"
    AddComponent parentPackage, elements, "DB", "usuario, tenant, plan, token_revocado", "database"
    AddComponent parentPackage, elements, "JWT", "JWT / bcrypt", "external"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""
    LinkDependency elements, "SVC", "JWT", ""

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - Usuarios y Acceso", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    Place diagram, elements("JWT"), 710, 400, 210, 80
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Incidentes y Evidencias
' -----------------------------------------------------------------------------
Sub CreateSubsystemIncidentes(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Incidentes y Evidencias (CU-05..CU-16)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "new-incident-screen, history-screen, vehicle-page", "interface"
    AddComponent parentPackage, elements, "CTRL", "incidentes.py / vehiculos.py / evidencias.py", "controller"
    AddComponent parentPackage, elements, "SVC", "incidente_service.py / evidencia_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "Incidente / Vehiculo / Evidencia / ClasificacionIA", "entity"
    AddComponent parentPackage, elements, "DB", "incidente, vehiculo, evidencia, clasificacion_ia", "database"
    AddComponent parentPackage, elements, "GPS", "GPS / Geolocalizacion", "external"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""
    LinkDependency elements, "CTRL", "GPS", ""

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - Incidentes y Evidencias", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    Place diagram, elements("GPS"), 710, 400, 210, 80
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Procesamiento IA y Asignacion
' -----------------------------------------------------------------------------
Sub CreateSubsystemIA(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Procesamiento IA y Asignacion (CU-17..CU-23)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "ai-classification-view, assignment-dashboard", "interface"
    AddComponent parentPackage, elements, "CTRL", "ia.py / asignacion.py", "controller"
    AddComponent parentPackage, elements, "SVC", "services/ai.py / asignacion_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "ClasificacionIA / TallerCandidato / Asignacion", "entity"
    AddComponent parentPackage, elements, "DB", "clasificacion_ia, taller_candidato, asignacion", "database"
    AddComponent parentPackage, elements, "YOLO", "YOLOv8 (dashboard + cardd)", "external"
    AddComponent parentPackage, elements, "OPENAI", "OpenAI Whisper", "external"
    AddComponent parentPackage, elements, "MAPS", "Google Maps API", "external"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""
    LinkDependency elements, "SVC", "YOLO", ""
    LinkDependency elements, "SVC", "OPENAI", ""
    LinkDependency elements, "SVC", "MAPS", ""

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - IA y Asignacion", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    Place diagram, elements("YOLO"), 710, 200, 210, 80
    Place diagram, elements("OPENAI"), 710, 330, 210, 80
    Place diagram, elements("MAPS"), 710, 460, 210, 80
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Talleres y Cotizaciones
' -----------------------------------------------------------------------------
Sub CreateSubsystemTalleres(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Talleres y Cotizaciones (CU-07..CU-09, CU-24..CU-29)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "taller-dashboard, solicitudes-page, cotizacion-page", "interface"
    AddComponent parentPackage, elements, "CTRL", "talleres.py / cotizaciones.py", "controller"
    AddComponent parentPackage, elements, "SVC", "taller_service.py / cotizacion_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "Taller / Tecnico / Cotizacion / Tarifa", "entity"
    AddComponent parentPackage, elements, "DB", "taller, tecnico, cotizacion, tarifa, especialidad_taller", "database"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - Talleres y Cotizaciones", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Pagos y Facturacion
' -----------------------------------------------------------------------------
Sub CreateSubsystemPagos(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Pagos y Facturacion (CU-30..CU-32, CU-49)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "pago-page, factura-view, calificacion-page", "interface"
    AddComponent parentPackage, elements, "CTRL", "pagos.py / facturas.py", "controller"
    AddComponent parentPackage, elements, "SVC", "pago_service.py / factura_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "Pago / Factura / Calificacion", "entity"
    AddComponent parentPackage, elements, "DB", "pago, factura, calificacion", "database"
    AddComponent parentPackage, elements, "PAY", "Stripe / Mercado Pago", "external"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""
    LinkDependency elements, "SVC", "PAY", ""

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - Pagos y Facturacion", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    Place diagram, elements("PAY"), 710, 400, 210, 80
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Subsistema: Tiempo Real, Notificaciones y Offline
' -----------------------------------------------------------------------------
Sub CreateSubsystemTiempoReal(repository, parentPackage)
    Dim diagram, elements
    Set elements = CreateObject("Scripting.Dictionary")
    AddSubsystemContainer parentPackage, elements, "SUB", "Tiempo Real, Notificaciones y Offline (CU-33..CU-41)"
    AddInterfacePoint parentPackage, elements, "IFACE", ""
    AddComponent parentPackage, elements, "UI", "tracking-map, seguimiento-page, sync-status", "interface"
    AddComponent parentPackage, elements, "CTRL", "websocket.py / sync.py / notificaciones.py", "controller"
    AddComponent parentPackage, elements, "SVC", "ws_manager.py / sync_service.dart / fcm_service.py", "service"
    AddComponent parentPackage, elements, "ENT", "ConexionWS / SyncMapping / Notificacion / UbicacionTracking", "entity"
    AddComponent parentPackage, elements, "DB", "conexion_ws, sync_mapping, notificacion, ubicacion_tracking", "database"
    AddComponent parentPackage, elements, "SQLITE", "SQLite Local (incidente_local)", "entity"
    AddComponent parentPackage, elements, "FCM", "Firebase Cloud Messaging", "external"

    LinkAssociation elements, "UI", "IFACE", ""
    LinkDependency elements, "IFACE", "CTRL", ""
    LinkDependency elements, "CTRL", "SVC", ""
    LinkDependency elements, "SVC", "ENT", ""
    LinkDependency elements, "ENT", "DB", ""
    LinkDependency elements, "SVC", "SQLITE", "offline"
    LinkDependency elements, "SVC", "FCM", "push"

    Set diagram = parentPackage.Diagrams.AddNew("Subsistema - Tiempo Real y Sincronizacion", "Component")
    diagram.Update
    parentPackage.Diagrams.Refresh
    DrawSubsystemVertical diagram, elements, "SUB", "UI", "IFACE", "CTRL", "SVC", "ENT", "DB"
    Place diagram, elements("SQLITE"), 710, 180, 210, 80
    Place diagram, elements("FCM"), 710, 310, 210, 80
    SaveDiagram repository, diagram
End Sub

' -----------------------------------------------------------------------------
' Helpers
' -----------------------------------------------------------------------------
Sub DrawSubsystemVertical(diagram, elements, containerId, uiId, ifaceId, ctrlId, serviceId, entityId, dbId)
    Place diagram, elements(containerId), 70, 70, 520, 780
    Place diagram, elements(uiId), 205, 145, 250, 90
    Place diagram, elements(ifaceId), 312, 255, 36, 36
    Place diagram, elements(ctrlId), 205, 310, 250, 90
    Place diagram, elements(serviceId), 205, 455, 250, 90
    Place diagram, elements(entityId), 205, 600, 250, 90
    Place diagram, elements(dbId), 205, 735, 250, 80
End Sub

Sub AddPackageElement(parentPackage, elements, elementId, elementName)
    Dim element
    Set element = parentPackage.Elements.AddNew(elementName, "Package")
    element.Alias = elementId
    element.Update
    parentPackage.Elements.Refresh
    elements.Add elementId, element
End Sub

Sub AddSubsystemContainer(parentPackage, elements, elementId, elementName)
    Dim element
    Set element = parentPackage.Elements.AddNew(elementName, "Component")
    element.Alias = elementId
    On Error Resume Next
    element.SetAppearance 1, 0, RGB(245, 226, 226)
    element.SetAppearance 1, 1, RGB(0, 0, 0)
    element.SetAppearance 1, 2, RGB(185, 135, 145)
    On Error GoTo 0
    element.Update
    parentPackage.Elements.Refresh
    elements.Add elementId, element
End Sub

Sub AddInterfacePoint(parentPackage, elements, elementId, elementName)
    Dim element
    Set element = parentPackage.Elements.AddNew(elementName, "Interface")
    element.Alias = elementId
    On Error Resume Next
    element.SetAppearance 1, 0, RGB(255, 230, 170)
    element.SetAppearance 1, 1, RGB(0, 0, 0)
    element.SetAppearance 1, 2, RGB(120, 100, 70)
    On Error GoTo 0
    element.Update
    parentPackage.Elements.Refresh
    elements.Add elementId, element
End Sub

Sub AddComponent(parentPackage, elements, elementId, elementName, stereotypeName)
    Dim element
    Set element = parentPackage.Elements.AddNew(elementName, "Component")
    element.Alias = elementId
    element.Stereotype = stereotypeName
    element.StereotypeEx = stereotypeName
    On Error Resume Next
    If LCase(stereotypeName) = "interface" Then
        element.SetAppearance 1, 0, RGB(224, 214, 246)
        element.SetAppearance 1, 1, RGB(0, 0, 0)
        element.SetAppearance 1, 2, RGB(150, 130, 190)
    Else
        element.SetAppearance 1, 0, RGB(245, 226, 226)
        element.SetAppearance 1, 1, RGB(0, 0, 0)
        element.SetAppearance 1, 2, RGB(185, 135, 145)
    End If
    On Error GoTo 0
    element.Update
    parentPackage.Elements.Refresh
    elements.Add elementId, element
End Sub

Sub LinkDependency(elements, sourceId, targetId, label)
    Dim connector
    Set connector = elements(sourceId).Connectors.AddNew(label, "Dependency")
    connector.SupplierID = elements(targetId).ElementID
    connector.ClientID = elements(sourceId).ElementID
    connector.Direction = "Source -> Destination"
    connector.Update
    elements(sourceId).Connectors.Refresh
End Sub

Sub LinkAssociation(elements, sourceId, targetId, label)
    Dim connector
    Set connector = elements(sourceId).Connectors.AddNew(label, "Association")
    connector.SupplierID = elements(targetId).ElementID
    connector.ClientID = elements(sourceId).ElementID
    connector.Direction = "Unspecified"
    connector.Update
    elements(sourceId).Connectors.Refresh
End Sub

Function GetOrCreateRootPackage(repository)
    If repository.Models.Count > 0 Then
        Set GetOrCreateRootPackage = repository.Models.GetAt(0)
    Else
        Set GetOrCreateRootPackage = repository.Models.AddNew("Modelo de Implementacion", "Package")
        GetOrCreateRootPackage.Update
        repository.Models.Refresh
    End If
End Function

Function GetOrCreateChildPackage(parentPackage, packageName)
    Dim i, currentPackage
    For i = 0 To parentPackage.Packages.Count - 1
        Set currentPackage = parentPackage.Packages.GetAt(i)
        If currentPackage.Name = packageName Then
            Set GetOrCreateChildPackage = currentPackage
            Exit Function
        End If
    Next

    Set GetOrCreateChildPackage = parentPackage.Packages.AddNew(packageName, "")
    GetOrCreateChildPackage.Update
    parentPackage.Packages.Refresh
End Function

Sub DeleteChildPackage(parentPackage, packageName)
    Dim i, currentPackage
    For i = parentPackage.Packages.Count - 1 To 0 Step -1
        Set currentPackage = parentPackage.Packages.GetAt(i)
        If currentPackage.Name = packageName Then
            parentPackage.Packages.DeleteAt i, True
            parentPackage.Packages.Refresh
            Exit Sub
        End If
    Next
End Sub

Sub Place(diagram, element, leftPosition, topPosition, width, height)
    Dim diagramObject, geometry
    geometry = "l=" & leftPosition & ";r=" & (leftPosition + width) & ";t=-" & topPosition & ";b=-" & (topPosition + height) & ";"
    Set diagramObject = diagram.DiagramObjects.AddNew(geometry, "")
    diagramObject.ElementID = element.ElementID
    diagramObject.Update
    diagram.DiagramObjects.Refresh
End Sub

Sub SaveDiagram(repository, diagram)
    diagram.Update
    repository.ReloadDiagram diagram.DiagramID
    RouteDiagramLinks diagram
    repository.SaveDiagram diagram.DiagramID
End Sub

Sub RouteDiagramLinks(diagram)
    Dim i, diagramLink
    diagram.DiagramLinks.Refresh
    For i = 0 To diagram.DiagramLinks.Count - 1
        Set diagramLink = diagram.DiagramLinks.GetAt(i)
        diagramLink.Style = SetStyleValue(diagramLink.Style, "Mode", "2")
        diagramLink.Update
    Next
    diagram.DiagramLinks.Refresh
End Sub

Function SetStyleValue(styleText, key, value)
    Dim parts, i, item, prefix, result, found
    parts = Split(styleText, ";")
    prefix = key & "="
    result = ""
    found = False

    For i = 0 To UBound(parts)
        item = Trim(parts(i))
        If Len(item) > 0 Then
            If LCase(Left(item, Len(prefix))) = LCase(prefix) Then
                item = prefix & value
                found = True
            End If
            result = result & item & ";"
        End If
    Next

    If Not found Then result = result & prefix & value & ";"
    SetStyleValue = result
End Function

Sub Log(message)
    On Error Resume Next
    Session.Output message
    If Err.Number <> 0 Then
        Err.Clear
        WScript.Echo message
    End If
    On Error GoTo 0
End Sub
