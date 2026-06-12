' Script para Enterprise Architect
' Crea diagramas de comunicacion para CU importantes.
' Usa el mismo estilo del ejemplo: Actor + Object con estereotipo boundary/control/entity.
' No agrega prefijo sd en los nombres; EA lo muestra automaticamente si corresponde.
' No crea mensajes ni numeracion; solo deja elementos y conectores para completarlos a mano.

Dim repo
Set repo = GetEARepository()

If repo Is Nothing Then
	MsgBox "No se pudo obtener Repository. Abra Enterprise Architect e intente nuevamente."
Else
	Main repo
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
	If Err.Number = 0 And Not eaApp Is Nothing Then
		Set GetEARepository = eaApp.Repository
	End If
	On Error GoTo 0
End Function

Sub Main(repository)
	Dim modelPackage, rootPackage, generatedPackage, diagrams, i

	If repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Analisis")
	Set generatedPackage = rootPackage.Packages.AddNew("Comunicacion " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	diagrams = BuildCommunicationDiagrams()
	For i = 0 To UBound(diagrams)
		CreateCommunicationDiagram repository, generatedPackage, diagrams(i)
	Next

	repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas de comunicacion generados."
End Sub

Function BuildCommunicationDiagrams()
	BuildCommunicationDiagrams = Array( _
		Array("CU-10 Reportar Nueva Emergencia", "Conductor|Actor", "UI. Reportar Emergencia|Boundary,EmergenciaController|Control,Incidente|Entity,SistemaIA|Entity"), _
		Array("CU-23 Asignar Taller Optimo", "Sistema IA|Actor", "AsignacionController|Control,ServicioMapas|Entity,Taller|Entity,ServicioPush|Entity"), _
		Array("CU-25 Aceptar Solicitud", "Taller|Actor", "UI. Solicitud|Boundary,ServicioController|Control,Incidente|Entity,Cliente|Entity"), _
		Array("CU-33 Conectar a WebSocket", "Cliente|Actor", "UI. Seguimiento|Boundary,WebSocketController|Control,Seguridad|Entity,GestorSesiones|Entity"), _
		Array("CU-36 Actualizar Estado del Incidente", "Taller|Actor", "UI. Servicio|Boundary,ServicioController|Control,Incidente|Entity,GestorWebSocket|Entity"), _
		Array("CU-40 Sincronizar Automaticamente", "Sistema|Actor", "DetectorConectividad|Control,RepositorioLocal|Entity,SyncController|Control,BackendSync|Control,BaseDatos|Entity"), _
		Array("CU-42 Visualizar Dashboard KPIs", "Administrador|Actor", "PanelWeb|Boundary,KPIController|Control,BaseDatos|Entity,DashboardKPIs|Entity"), _
		Array("CU-46 Crear Nuevo Tenant", "Administrador|Actor", "PanelAdmin|Boundary,TenantController|Control,AuthMiddleware|Control,BaseDatos|Entity,Tenant|Entity") _
	)
End Function

Sub CreateCommunicationDiagram(repository, parentPackage, diagramData)
	Dim pkg, diagramObj, participants, elements

	Set pkg = parentPackage.Packages.AddNew(diagramData(0), "")
	pkg.Update
	parentPackage.Packages.Refresh

	participants = BuildParticipants(diagramData(1), diagramData(2))
	Set elements = CreateParticipants(pkg, participants)

	Set diagramObj = pkg.Diagrams.AddNew(diagramData(0), "Collaboration")
	diagramObj.Update
	pkg.Diagrams.Refresh

	PlaceParticipants diagramObj, elements, participants
	CreateCommunicationLinks elements, participants
	SaveDiagram repository, diagramObj
End Sub

Function BuildParticipants(actorDef, nodeDefs)
	Dim nodes, result(), i
	nodes = Split(nodeDefs, ",")
	ReDim result(UBound(nodes) + 1)
	result(0) = actorDef
	For i = 0 To UBound(nodes)
		result(i + 1) = Trim(nodes(i))
	Next
	BuildParticipants = result
End Function

Function CreateParticipants(pkg, participants)
	Dim dict, i, parts, element, kind
	Set dict = CreateObject("Scripting.Dictionary")

	For i = 0 To UBound(participants)
		parts = Split(participants(i), "|")
		kind = CommunicationElementKind(parts(0), parts(1))

		If kind = "Actor" Then
			Set element = pkg.Elements.AddNew(parts(0), "Actor")
		Else
			Set element = pkg.Elements.AddNew(parts(0), "Object")
			element.Stereotype = LCase(kind)
			element.StereotypeEx = LCase(kind)
		End If

		element.Update
		pkg.Elements.Refresh
		dict.Add CStr(i), element
	Next

	Set CreateParticipants = dict
End Function

Function CommunicationElementKind(elementName, requestedType)
	If requestedType = "Actor" Then
		CommunicationElementKind = "Actor"
	ElseIf requestedType = "Boundary" Or requestedType = "Control" Or requestedType = "Entity" Then
		CommunicationElementKind = requestedType
	ElseIf Left(elementName, 3) = "UI." Or InStr(elementName, "Panel") > 0 Then
		CommunicationElementKind = "Boundary"
	ElseIf InStr(elementName, "Controller") > 0 Or InStr(elementName, "Service") > 0 Or InStr(elementName, "Sync") > 0 Or InStr(elementName, "Middleware") > 0 Then
		CommunicationElementKind = "Control"
	Else
		CommunicationElementKind = "Entity"
	End If
End Function

Sub PlaceParticipants(diagramObj, elements, participants)
	Dim i, parts, kind, x, y, width, height
	y = 145

	For i = 0 To UBound(participants)
		parts = Split(participants(i), "|")
		kind = CommunicationElementKind(parts(0), parts(1))

		If kind = "Actor" Then
			x = 70
			Place diagramObj, elements(CStr(i)), x, 190, 150, 110
		Else
			x = 330 + ((i - 1) * 280)
			If kind = "Boundary" Then
				width = 165
				height = 190
				Place diagramObj, elements(CStr(i)), x, 95, width, height
			ElseIf kind = "Control" Then
				width = 145
				height = 145
				Place diagramObj, elements(CStr(i)), x, 115, width, height
			Else
				width = 175
				height = 190
				Place diagramObj, elements(CStr(i)), x, 95, width, height
			End If
		End If
	Next
End Sub

Sub CreateCommunicationLinks(elements, participants)
	Dim i, connector

	For i = 0 To UBound(participants) - 1
		Set connector = elements(CStr(i)).Connectors.AddNew("", "Association")
		connector.SupplierID = elements(CStr(i + 1)).ElementID
		connector.ClientID = elements(CStr(i)).ElementID
		connector.Direction = "Unspecified"
		connector.Update
		elements(CStr(i)).Connectors.Refresh
	Next
End Sub

Sub Place(diagramObj, element, leftPosition, topPosition, width, height)
	Dim diagramObject, geometry
	geometry = "l=" & leftPosition & ";r=" & (leftPosition + width) & ";t=-" & topPosition & ";b=-" & (topPosition + height) & ";"
	Set diagramObject = diagramObj.DiagramObjects.AddNew(geometry, "")
	diagramObject.ElementID = element.ElementID
	diagramObject.Update
	diagramObj.DiagramObjects.Refresh
End Sub

Sub SaveDiagram(repository, diagramObj)
	diagramObj.Update
	repository.ReloadDiagram diagramObj.DiagramID
	RouteDiagramLinks diagramObj, "1"
	repository.SaveDiagram diagramObj.DiagramID
End Sub

Sub RouteDiagramLinks(diagramObj, routeMode)
	Dim i, diagramLink
	diagramObj.DiagramLinks.Refresh
	For i = 0 To diagramObj.DiagramLinks.Count - 1
		Set diagramLink = diagramObj.DiagramLinks.GetAt(i)
		diagramLink.Style = SetStyleValue(diagramLink.Style, "Mode", routeMode)
		diagramLink.Update
	Next
	diagramObj.DiagramLinks.Refresh
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

Function GetOrCreatePackage(parentPackage, packageName)
	Dim i, pkg
	For i = 0 To parentPackage.Packages.Count - 1
		Set pkg = parentPackage.Packages.GetAt(i)
		If pkg.Name = packageName Then
			Set GetOrCreatePackage = pkg
			Exit Function
		End If
	Next
	Set pkg = parentPackage.Packages.AddNew(packageName, "")
	pkg.Update
	parentPackage.Packages.Refresh
	Set GetOrCreatePackage = pkg
End Function

Function TimestampName()
	Dim value
	value = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2)
	value = value & " " & Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)
	TimestampName = value
End Function
