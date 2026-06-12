' Script para Enterprise Architect
' Crea:
' 1. Diagrama de despliegue.
' 2. Diseno logico organizado por capas.
'
' No agrega prefijos deployment/pkg en los nombres; EA los muestra automaticamente.

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
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Diseno")
	Set generatedPackage = rootPackage.Packages.AddNew("Despliegue y Logico " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	CreateDeploymentDiagram repository, generatedPackage
	CreateLogicalLayerDiagram repository, generatedPackage

	repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas de despliegue y diseno logico generados."
End Sub

Sub CreateDeploymentDiagram(repository, parentPackage)
	Dim diagramObj, nodes

	Set diagramObj = parentPackage.Diagrams.AddNew("Despliegue del Sistema", "Deployment")
	diagramObj.Update
	parentPackage.Diagrams.Refresh

	Set nodes = CreateObject("Scripting.Dictionary")

	AddNode parentPackage, diagramObj, nodes, "Dispositivo Movil Cliente", 60, 70, 270, 170
	AddArtifact parentPackage, diagramObj, "App Movil Flutter", 95, 115, 205, 75

	AddNode parentPackage, diagramObj, nodes, "Navegador Web", 410, 70, 270, 170
	AddArtifact parentPackage, diagramObj, "Web Admin / Taller", 445, 115, 205, 75

	AddNode parentPackage, diagramObj, nodes, "Servidor de Aplicacion", 300, 335, 520, 300
	AddArtifact parentPackage, diagramObj, "Frontend Angular", 345, 385, 185, 80
	AddArtifact parentPackage, diagramObj, "Backend FastAPI", 565, 385, 185, 80
	AddArtifact parentPackage, diagramObj, "WebSocket Manager", 345, 505, 185, 80
	AddArtifact parentPackage, diagramObj, "Motor IA / Asignacion", 565, 505, 185, 80

	AddNode parentPackage, diagramObj, nodes, "Servidor PostgreSQL", 60, 780, 290, 170
	AddArtifact parentPackage, diagramObj, "BD Emergencias / Tenants", 95, 830, 225, 75

	AddNode parentPackage, diagramObj, nodes, "Servicio Mapas", 430, 780, 290, 170
	AddArtifact parentPackage, diagramObj, "Google Maps / OSM", 465, 830, 225, 75

	AddNode parentPackage, diagramObj, nodes, "Pasarela de Pagos", 800, 780, 290, 170
	AddArtifact parentPackage, diagramObj, "Stripe / Mercado Pago", 835, 830, 225, 75

	AddNode parentPackage, diagramObj, nodes, "Servicio IA Externo", 930, 335, 290, 170
	AddArtifact parentPackage, diagramObj, "OpenAI / Speech / Vision", 965, 385, 225, 75

	AddNode parentPackage, diagramObj, nodes, "Almacenamiento Evidencias", 930, 70, 290, 170
	AddArtifact parentPackage, diagramObj, "Fotos / Audio", 965, 120, 225, 75

	AddDependency nodes("Dispositivo Movil Cliente"), nodes("Servidor de Aplicacion"), "HTTPS / WebSocket"
	AddDependency nodes("Navegador Web"), nodes("Servidor de Aplicacion"), "HTTPS"
	AddDependency nodes("Servidor de Aplicacion"), nodes("Servidor PostgreSQL"), "SQL"
	AddDependency nodes("Servidor de Aplicacion"), nodes("Servicio Mapas"), "API Mapas"
	AddDependency nodes("Servidor de Aplicacion"), nodes("Pasarela de Pagos"), "API Pagos"
	AddDependency nodes("Servidor de Aplicacion"), nodes("Servicio IA Externo"), "API IA"
	AddDependency nodes("Servidor de Aplicacion"), nodes("Almacenamiento Evidencias"), "Archivos"

	SaveDiagram repository, diagramObj, "2"
End Sub

Sub CreateLogicalLayerDiagram(repository, parentPackage)
	Dim diagramObj, packages

	Set diagramObj = parentPackage.Diagrams.AddNew("Diseno Logico Organizado en Capas", "Package")
	diagramObj.Update
	parentPackage.Diagrams.Refresh

	Set packages = CreateObject("Scripting.Dictionary")

	AddPackage parentPackage, diagramObj, packages, "Usuarios y Acceso", 70, 65, 220, 100
	AddPackage parentPackage, diagramObj, packages, "Clientes y Vehiculos", 370, 65, 220, 100
	AddPackage parentPackage, diagramObj, packages, "Talleres y Servicio", 670, 65, 220, 100
	AddPackage parentPackage, diagramObj, packages, "KPIs y Administracion", 970, 65, 220, 100

	AddPackage parentPackage, diagramObj, packages, "Controladores API", 220, 290, 240, 110
	AddPackage parentPackage, diagramObj, packages, "Servicios de Dominio", 540, 290, 240, 110
	AddPackage parentPackage, diagramObj, packages, "Modulos IA / Asignacion", 860, 290, 260, 110

	AddPackage parentPackage, diagramObj, packages, "Persistencia PostgreSQL", 145, 540, 250, 105
	AddPackage parentPackage, diagramObj, packages, "Backend FastAPI", 505, 540, 250, 105
	AddPackage parentPackage, diagramObj, packages, "Frontend Angular / Flutter", 865, 540, 280, 105

	AddPackage parentPackage, diagramObj, packages, "Infraestructura Cloud", 360, 760, 260, 105
	AddPackage parentPackage, diagramObj, packages, "Servicios Externos", 760, 760, 260, 105

	AddUse packages("Usuarios y Acceso"), packages("Controladores API")
	AddUse packages("Clientes y Vehiculos"), packages("Controladores API")
	AddUse packages("Talleres y Servicio"), packages("Controladores API")
	AddUse packages("KPIs y Administracion"), packages("Controladores API")

	AddUse packages("Usuarios y Acceso"), packages("Servicios de Dominio")
	AddUse packages("Clientes y Vehiculos"), packages("Servicios de Dominio")
	AddUse packages("Talleres y Servicio"), packages("Servicios de Dominio")
	AddUse packages("KPIs y Administracion"), packages("Servicios de Dominio")

	AddUse packages("Talleres y Servicio"), packages("Modulos IA / Asignacion")
	AddUse packages("KPIs y Administracion"), packages("Modulos IA / Asignacion")

	AddUse packages("Controladores API"), packages("Backend FastAPI")
	AddUse packages("Servicios de Dominio"), packages("Backend FastAPI")
	AddUse packages("Modulos IA / Asignacion"), packages("Backend FastAPI")

	AddUse packages("Backend FastAPI"), packages("Persistencia PostgreSQL")
	AddUse packages("Frontend Angular / Flutter"), packages("Backend FastAPI")
	AddUse packages("Persistencia PostgreSQL"), packages("Infraestructura Cloud")
	AddUse packages("Backend FastAPI"), packages("Infraestructura Cloud")
	AddUse packages("Modulos IA / Asignacion"), packages("Servicios Externos")
	AddUse packages("Backend FastAPI"), packages("Servicios Externos")

	SaveDiagram repository, diagramObj, "2"
End Sub

Sub AddNode(parentPackage, diagramObj, nodes, nodeName, leftPosition, topPosition, width, height)
	Dim nodeEl
	Set nodeEl = parentPackage.Elements.AddNew(nodeName, "Node")
	nodeEl.Update
	parentPackage.Elements.Refresh
	nodes.Add nodeName, nodeEl
	Place diagramObj, nodeEl, leftPosition, topPosition, width, height
End Sub

Sub AddArtifact(parentPackage, diagramObj, artifactName, leftPosition, topPosition, width, height)
	Dim artifactEl
	Set artifactEl = parentPackage.Elements.AddNew(artifactName, "Artifact")
	artifactEl.Update
	parentPackage.Elements.Refresh
	Place diagramObj, artifactEl, leftPosition, topPosition, width, height
End Sub

Sub AddPackage(parentPackage, diagramObj, packages, packageName, leftPosition, topPosition, width, height)
	Dim packageEl
	Set packageEl = parentPackage.Elements.AddNew(packageName, "Package")
	packageEl.Update
	parentPackage.Elements.Refresh
	packages.Add packageName, packageEl
	Place diagramObj, packageEl, leftPosition, topPosition, width, height
End Sub

Sub AddDependency(sourceEl, targetEl, label)
	Dim conn
	Set conn = sourceEl.Connectors.AddNew(label, "Dependency")
	conn.SupplierID = targetEl.ElementID
	conn.ClientID = sourceEl.ElementID
	conn.Direction = "Source -> Destination"
	conn.Update
	sourceEl.Connectors.Refresh
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

Sub SaveDiagram(repository, diagramObj, routeMode)
	diagramObj.Update
	repository.ReloadDiagram diagramObj.DiagramID
	RouteDiagramLinks diagramObj, routeMode
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
