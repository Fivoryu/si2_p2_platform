' Script para Enterprise Architect
' Crea el diagrama de analisis de paquetes.
' No agrega "pkg" al nombre del diagrama; EA lo muestra automaticamente.

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
	Dim modelPackage, rootPackage, generatedPackage

	If repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Analisis")
	Set generatedPackage = rootPackage.Packages.AddNew("Analisis de Paquetes " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	CreatePackageAnalysisDiagram repository, generatedPackage

	repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagrama de analisis de paquetes generado."
End Sub

Sub CreatePackageAnalysisDiagram(repository, parentPackage)
	Dim diagramObj, elements

	Set diagramObj = parentPackage.Diagrams.AddNew("Diagrama General de Paquetes", "Package")
	diagramObj.Update
	parentPackage.Diagrams.Refresh

	Set elements = CreateObject("Scripting.Dictionary")

	AddPackage parentPackage, diagramObj, elements, "Usuarios y acceso", 60, 80, 270, 115
	AddPackage parentPackage, diagramObj, elements, "Clientes y vehiculos", 430, 80, 285, 115
	AddPackage parentPackage, diagramObj, elements, "Incidentes y evidencias", 800, 80, 330, 115
	AddPackage parentPackage, diagramObj, elements, "Talleres y atencion del servicio", 60, 330, 330, 115
	AddPackage parentPackage, diagramObj, elements, "Procesamiento inteligente y asignacion", 500, 330, 395, 115
	AddPackage parentPackage, diagramObj, elements, "Pagos, notificaciones y repartos", 1005, 330, 365, 115
	AddPackage parentPackage, diagramObj, elements, "Offline y sincronizacion", 130, 610, 330, 115
	AddPackage parentPackage, diagramObj, elements, "Analitica y KPIs", 610, 610, 285, 115
	AddPackage parentPackage, diagramObj, elements, "Multi-tenant", 1080, 610, 285, 115

	AddUse elements("Usuarios y acceso"), elements("Clientes y vehiculos")
	AddUse elements("Usuarios y acceso"), elements("Incidentes y evidencias")
	AddUse elements("Clientes y vehiculos"), elements("Incidentes y evidencias")
	AddUse elements("Talleres y atencion del servicio"), elements("Incidentes y evidencias")
	AddUse elements("Incidentes y evidencias"), elements("Procesamiento inteligente y asignacion")
	AddUse elements("Procesamiento inteligente y asignacion"), elements("Pagos, notificaciones y repartos")
	AddUse elements("Pagos, notificaciones y repartos"), elements("Offline y sincronizacion")
	AddUse elements("Incidentes y evidencias"), elements("Analitica y KPIs")
	AddUse elements("Talleres y atencion del servicio"), elements("Analitica y KPIs")
	AddUse elements("Pagos, notificaciones y repartos"), elements("Analitica y KPIs")
	AddUse elements("Offline y sincronizacion"), elements("Multi-tenant")
	AddUse elements("Analitica y KPIs"), elements("Multi-tenant")

	AddUse elements("Usuarios y acceso"), elements("Multi-tenant")
	AddUse elements("Clientes y vehiculos"), elements("Multi-tenant")
	AddUse elements("Incidentes y evidencias"), elements("Multi-tenant")
	AddUse elements("Talleres y atencion del servicio"), elements("Multi-tenant")
	AddUse elements("Procesamiento inteligente y asignacion"), elements("Multi-tenant")
	AddUse elements("Pagos, notificaciones y repartos"), elements("Multi-tenant")

	SaveDiagram repository, diagramObj
End Sub

Sub AddPackage(parentPackage, diagramObj, elements, packageName, leftPosition, topPosition, width, height)
	Dim packageEl
	Set packageEl = parentPackage.Elements.AddNew(packageName, "Package")
	packageEl.Update
	parentPackage.Elements.Refresh
	elements.Add packageName, packageEl
	Place diagramObj, packageEl, leftPosition, topPosition, width, height
End Sub

Sub AddUse(sourceEl, targetEl)
	Dim conn
	Set conn = sourceEl.Connectors.AddNew("", "Dependency")
	conn.SupplierID = targetEl.ElementID
	conn.ClientID = sourceEl.ElementID
	conn.Direction = "Source -> Destination"
	conn.Stereotype = "use"
	conn.StereotypeEx = "use"
	conn.Update
	sourceEl.Connectors.Refresh
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
	RouteDiagramLinks diagramObj, "2"
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
