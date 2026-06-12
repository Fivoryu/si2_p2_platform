' Script para Enterprise Architect
' Crea diagramas de secuencia para los CU mas relevantes.
' Misma estructura y nombres que CrearDiagramasComunicacion.vbs.
' Sin estereotipos Boundary/Control/Entity, solo Actor y Object.
'
' No agrega prefijo sd en los nombres; EA lo muestra automaticamente.

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
	Set generatedPackage = rootPackage.Packages.AddNew("Secuencia " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	diagrams = BuildSequenceDiagrams()
	For i = 0 To UBound(diagrams)
		CreateSequenceDiagram repository, generatedPackage, diagrams(i)
	Next

	repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas de secuencia generados."
End Sub

Function BuildSequenceDiagrams()
	BuildSequenceDiagrams = Array( _
		Array("CU-10 Reportar Nueva Emergencia", "Conductor|Actor", "UI. Reportar Emergencia,EmergenciaController,Incidente,SistemaIA"), _
		Array("CU-17-20 Procesar con IA", "Sistema IA|Actor", "IAController,TranscripcionService,ClasificacionService,Incidente,ModelosExternos"), _
		Array("CU-22-23 Asignar Taller Optimo", "Sistema IA|Actor", "AsignacionController,ServicioMapas,Taller,ServicioPush"), _
		Array("CU-25-29 Aceptar Solicitud y Elegir Oferta", "Taller|Actor", "UI. Solicitud,ServicioController,Cotizacion,Incidente,Conductor"), _
		Array("CU-30 Efectuar Pago", "Conductor|Actor", "UI. Pago,PagoController,Pago,PasarelaPagos"), _
		Array("CU-35-36 Actualizar Estado en Tiempo Real", "Taller|Actor", "UI. Servicio,ServicioController,Incidente,GestorWebSocket") _
	)
End Function

Sub CreateSequenceDiagram(repository, parentPackage, diagramData)
	Dim pkg, diagramObj, participants, elements

	Set pkg = parentPackage.Packages.AddNew(diagramData(0), "")
	pkg.Update
	parentPackage.Packages.Refresh

	participants = BuildParticipants(diagramData(1), diagramData(2))
	Set elements = CreateParticipants(pkg, participants)

	Set diagramObj = pkg.Diagrams.AddNew(diagramData(0), "Sequence")
	diagramObj.Update
	pkg.Diagrams.Refresh

	PlaceSequenceParticipants diagramObj, elements, participants
	CreateSequenceLinks elements, participants
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
	Dim dict, i, parts, element
	Set dict = CreateObject("Scripting.Dictionary")

	For i = 0 To UBound(participants)
		parts = Split(participants(i), "|")
		If UBound(parts) >= 1 Then
			If parts(1) = "Actor" Then
				Set element = pkg.Elements.AddNew(parts(0), "Actor")
			Else
				Set element = pkg.Elements.AddNew(parts(0), "Object")
			End If
		Else
			Set element = pkg.Elements.AddNew(participants(i), "Object")
		End If

		element.Update
		pkg.Elements.Refresh
		dict.Add CStr(i), element
	Next

	Set CreateParticipants = dict
End Function

Sub PlaceSequenceParticipants(diagramObj, elements, participants)
	Dim i
	For i = 0 To UBound(participants)
		Place diagramObj, elements(CStr(i)), 60 + (i * 280), 120, 210, 90
	Next
End Sub

Sub CreateSequenceLinks(elements, participants)
	Dim i, connector, srcName, tgtName

	For i = 0 To UBound(participants) - 1
		srcName = elements(CStr(i)).Name
		tgtName = elements(CStr(i + 1)).Name
		Set connector = elements(CStr(i)).Connectors.AddNew( _
			"1." & (i + 1) & ": enviar(" & tgtName & ")", "Sequence")
		connector.SupplierID = elements(CStr(i + 1)).ElementID
		connector.ClientID = elements(CStr(i)).ElementID
		connector.Direction = "Source -> Destination"
		connector.Update
		elements(CStr(i)).Connectors.Refresh
	Next

	For i = UBound(participants) To 1 Step -1
		srcName = elements(CStr(i)).Name
		tgtName = elements(CStr(i - 1)).Name
		Set connector = elements(CStr(i)).Connectors.AddNew( _
			"2." & (UBound(participants) - i + 1) & ": responder(" & tgtName & ")", "Sequence")
		connector.SupplierID = elements(CStr(i - 1)).ElementID
		connector.ClientID = elements(CStr(i)).ElementID
		connector.Direction = "Source -> Destination"
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

Main
