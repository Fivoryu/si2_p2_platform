' Script para Enterprise Architect
' Genera diagramas de casos de uso por ciclo y un diagrama general.
'
' Uso:
' 1. Abrir el proyecto en Enterprise Architect.
' 2. Ir a Specialize > Tools > Scripting.
' 3. Crear un script VBScript y pegar este contenido.
' 4. Ejecutar Main.

Dim ACTOR_ADM, ACTOR_ADT, ACTOR_CLI, ACTOR_TAL, ACTOR_TEC, ACTOR_SIA, ACTOR_PAG, ACTOR_MAP
ACTOR_ADM = "Administrador"
ACTOR_ADT = "Administrador T"
ACTOR_CLI = "Cliente"
ACTOR_TAL = "Taller"
ACTOR_TEC = "Tecnico"
ACTOR_SIA = "Sistema IA"
ACTOR_PAG = "Pasarela Pagos"
ACTOR_MAP = "Mapas"

Sub Main()
	Dim modelPackage, rootPackage, generatedPackage, useCases, cycleNumber

	If Repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = Repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Casos de Uso")
	Set generatedPackage = rootPackage.Packages.AddNew("Por Ciclos " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	useCases = BuildUseCases()

	For cycleNumber = 1 To 5
		CreateCycleDiagram generatedPackage, useCases, cycleNumber
	Next

	CreateAllUseCasesDiagram generatedPackage, useCases

	Repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas por ciclo y general generados en: " & rootPackage.Name & " / " & generatedPackage.Name
End Sub

Function BuildUseCases()
	Dim items(47)
	items(0) = Array("CU-01", "Iniciar Sesion", "CLI,TAL,ADT,ADM", "1")
	items(1) = Array("CU-02", "Cerrar Sesion", "CLI,TAL,ADT,ADM", "1")
	items(2) = Array("CU-03", "Recuperar Contrasena", "CLI,TAL,ADT,ADM", "1")
	items(3) = Array("CU-04", "Registrar Cuenta de Conductor", "CLI", "1")
	items(4) = Array("CU-05", "Registrar Vehiculo", "CLI", "1")
	items(5) = Array("CU-06", "Editar Perfil de Conductor", "CLI", "1")
	items(6) = Array("CU-07", "Registrar Taller", "ADT", "1")
	items(7) = Array("CU-08", "Registrar Tecnico", "ADT,TAL", "1")
	items(8) = Array("CU-09", "Gestionar Disponibilidad del Taller", "TAL", "1")
	items(9) = Array("CU-10", "Reportar Nueva Emergencia", "CLI,SIA", "2")
	items(10) = Array("CU-11", "Adjuntar Imagenes al Reporte", "CLI,SIA", "2")
	items(11) = Array("CU-12", "Adjuntar Audio al Reporte", "CLI,SIA", "2")
	items(12) = Array("CU-13", "Enviar Ubicacion GPS al Reportar", "CLI,MAP", "2")
	items(13) = Array("CU-14", "Visualizar Estado Actual de la Emergencia", "CLI,TAL", "2")
	items(14) = Array("CU-15", "Cancelar Emergencia", "CLI", "2")
	items(15) = Array("CU-16", "Ver Historial de Emergencias del Conductor", "CLI", "2")
	items(16) = Array("CU-17", "Transcribir Audio a Texto (IA)", "SIA", "2")
	items(17) = Array("CU-18", "Clasificar Incidente por Imagenes (IA)", "SIA", "2")
	items(18) = Array("CU-19", "Clasificar Incidente por Texto (IA)", "SIA", "2")
	items(19) = Array("CU-20", "Generar Resumen Estructurado del Incidente", "SIA", "2")
	items(20) = Array("CU-21", "Determinar Prioridad del Incidente", "SIA", "2")
	items(21) = Array("CU-22", "Buscar Talleres Candidatos", "SIA,MAP", "3")
	items(22) = Array("CU-23", "Asignar Taller Optimo", "SIA", "3")
	items(23) = Array("CU-24", "Notificar a Taller sobre Nueva Solicitud", "TAL", "3")
	items(24) = Array("CU-25", "Aceptar Solicitud con Oferta Editable", "TAL", "3")
	items(25) = Array("CU-26", "Rechazar Solicitud", "TAL", "3")
	items(26) = Array("CU-27", "Generar Oferta/Cotizacion Competitiva", "CLI,TAL,SIA", "3")
	items(27) = Array("CU-28", "Calcular Tiempo Estimado de Llegada y Reparacion", "SIA,TAL,MAP", "3")
	items(28) = Array("CU-29", "Seleccionar Oferta de Taller", "CLI", "3")
	items(29) = Array("CU-30", "Efectuar Pago del Servicio", "CLI,PAG", "3")
	items(30) = Array("CU-31", "Consultar Comision del Taller", "TAL,ADT", "3")
	items(31) = Array("CU-32", "Generar Factura / Comprobante", "CLI,TAL", "3")
	items(32) = Array("CU-33", "Conectar a WebSocket para Seguimiento en Vivo", "CLI,TAL", "4")
	items(33) = Array("CU-34", "Visualizar Ubicacion del Taller en Mapa", "CLI", "4")
	items(34) = Array("CU-35", "Recibir Notificacion Inmediata de Cambio de Estado", "CLI,TAL", "4")
	items(35) = Array("CU-36", "Actualizar Estado del Incidente", "TAL", "4")
	items(36) = Array("CU-37", "Transmitir Llegada del Tecnico", "TAL", "4")
	items(37) = Array("CU-38", "Guardar Emergencia Localmente y Marcar como Pendiente de Sincronizacion", "CLI", "5")
	items(38) = Array("CU-40", "Sincronizar Automaticamente al Recuperar Conexion", "CLI,SIA", "5")
	items(39) = Array("CU-41", "Resolver Conflictos de Sincronizacion", "Sistema", "5")
	items(40) = Array("CU-42", "Visualizar Dashboard de KPIs", "ADM,ADT", "5")
	items(41) = Array("CU-43", "Filtrar KPIs por Tenant", "ADM,ADT", "5")
	items(42) = Array("CU-44", "Exportar Reporte de KPIs", "ADM,ADT", "5")
	items(43) = Array("CU-45", "Configurar Umbrales de SLA", "ADM", "5")
	items(44) = Array("CU-46", "Crear Nuevo Tenant", "ADM", "5")
	items(45) = Array("CU-47", "Asignar Administrador a un Tenant", "ADM", "5")
	items(46) = Array("CU-48", "Configurar Plan de Servicio por Tenant", "ADM", "5")
	items(47) = Array("CU-49", "Calificar Servicio Post-Atencion", "CLI", "3")
	BuildUseCases = items
End Function

Sub CreateCycleDiagram(packageObj, useCases, cycleNumber)
	Dim diagramObj, actorElements, i, row, useCaseData, title
	Dim xCase, yCase, actorCodes, actorCode, j, actorEl, useCaseEl, conn
	Dim leftCount, rightCount, centerX, topY, boundaryEl

	title = "uc Ciclo " & cycleNumber & " - Casos de Uso"
	Set diagramObj = packageObj.Diagrams.AddNew(title, "Use Case")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set boundaryEl = packageObj.Elements.AddNew(title, "Boundary")
	boundaryEl.Update
	AddElementToDiagram diagramObj, boundaryEl.ElementID, 20, 20, 1360, 900

	centerX = 610
	topY = 250
	Set actorElements = CreateActorsForDiagram(packageObj, diagramObj, useCases, CStr(cycleNumber), centerX, topY, 115, 4)

	row = 0
	leftCount = 0
	rightCount = 0
	For i = 0 To UBound(useCases)
		useCaseData = useCases(i)
		If useCaseData(3) = CStr(cycleNumber) Then
			If (row Mod 2) = 0 Then
				xCase = 95 + ((leftCount Mod 2) * 245)
				yCase = 75 + (Int(leftCount / 2) * 145)
				leftCount = leftCount + 1
			Else
				xCase = 865 + ((rightCount Mod 2) * 245)
				yCase = 75 + (Int(rightCount / 2) * 145)
				rightCount = rightCount + 1
			End If

			Set useCaseEl = packageObj.Elements.AddNew(useCaseData(0) & " " & useCaseData(1), "UseCase")
			useCaseEl.Notes = "Ciclo " & cycleNumber
			useCaseEl.Update
			AddElementToDiagram diagramObj, useCaseEl.ElementID, xCase, yCase, xCase + 220, yCase + 92

			actorCodes = Split(useCaseData(2), ",")
			For j = 0 To UBound(actorCodes)
				actorCode = Trim(actorCodes(j))
				If actorElements.Exists(actorCode) Then
					Set actorEl = actorElements(actorCode)
					Set conn = actorEl.Connectors.AddNew("", "Association")
					conn.SupplierID = useCaseEl.ElementID
					conn.Update
					actorEl.Connectors.Refresh
				End If
			Next

			row = row + 1
		End If
	Next

	diagramObj.Update
	Repository.ReloadDiagram diagramObj.DiagramID
End Sub

Sub CreateAllUseCasesDiagram(packageObj, useCases)
	Dim diagramObj, actorElements, i, row, col, useCaseData
	Dim xCase, yCase, actorCodes, actorCode, j, actorEl, useCaseEl, conn
	Dim boundaryEl

	Set diagramObj = packageObj.Diagrams.AddNew("uc General - Todos los Casos de Uso", "Use Case")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set boundaryEl = packageObj.Elements.AddNew("uc General - Todos los Casos de Uso", "Boundary")
	boundaryEl.Update
	AddElementToDiagram diagramObj, boundaryEl.ElementID, 20, 20, 2550, 1750

	Set actorElements = CreateActorsForDiagram(packageObj, diagramObj, useCases, "ALL", 1130, 520, 125, 5)

	For i = 0 To UBound(useCases)
		useCaseData = useCases(i)
		row = i
		If i < 24 Then
			col = i Mod 3
			xCase = 85 + (col * 315)
			yCase = 70 + (Int(i / 3) * 150)
		Else
			col = (i - 24) Mod 3
			xCase = 1450 + (col * 315)
			yCase = 70 + (Int((i - 24) / 3) * 150)
		End If

		Set useCaseEl = packageObj.Elements.AddNew(useCaseData(0) & " " & useCaseData(1), "UseCase")
		useCaseEl.Notes = "Ciclo " & useCaseData(3)
		useCaseEl.Update
		AddElementToDiagram diagramObj, useCaseEl.ElementID, xCase, yCase, xCase + 255, yCase + 92

		actorCodes = Split(useCaseData(2), ",")
		For j = 0 To UBound(actorCodes)
			actorCode = Trim(actorCodes(j))
			If actorElements.Exists(actorCode) Then
				Set actorEl = actorElements(actorCode)
				Set conn = actorEl.Connectors.AddNew("", "Association")
				conn.SupplierID = useCaseEl.ElementID
				conn.Update
				actorEl.Connectors.Refresh
			End If
		Next
	Next

	diagramObj.Update
	Repository.ReloadDiagram diagramObj.DiagramID
End Sub

Function CreateActorsForDiagram(packageObj, diagramObj, useCases, cycleFilter, startX, startY, yGap, maxPerColumn)
	Dim actorElements, actorOrder, usedActors, i, j, useCaseData, actorCodes, actorCode
	Dim actorEl, actorIndex, xActor, yActor, actorColumn, actorRow

	Set actorElements = CreateObject("Scripting.Dictionary")
	Set usedActors = CreateObject("Scripting.Dictionary")
	actorOrder = Array("CLI", "TAL", "TEC", "ADT", "ADM", "SIA", "MAP", "PAG", "Sistema")

	For i = 0 To UBound(useCases)
		useCaseData = useCases(i)
		If cycleFilter = "ALL" Or useCaseData(3) = cycleFilter Then
			actorCodes = Split(useCaseData(2), ",")
			For j = 0 To UBound(actorCodes)
				actorCode = Trim(actorCodes(j))
				If Not usedActors.Exists(actorCode) Then
					usedActors.Add actorCode, True
				End If
			Next
		End If
	Next

	actorIndex = 0
	For i = 0 To UBound(actorOrder)
		actorCode = actorOrder(i)
		If usedActors.Exists(actorCode) Then
			Set actorEl = packageObj.Elements.AddNew(ActorName(actorCode), "Actor")
			actorEl.Update
			actorColumn = Int(actorIndex / maxPerColumn)
			actorRow = actorIndex Mod maxPerColumn
			xActor = startX + (actorColumn * 150)
			yActor = startY + (actorRow * yGap)
			AddElementToDiagram diagramObj, actorEl.ElementID, xActor, yActor, xActor + 170, yActor + 95
			actorElements.Add actorCode, actorEl
			actorIndex = actorIndex + 1
		End If
	Next

	Set CreateActorsForDiagram = actorElements
End Function

Sub AddElementToDiagram(diagramObj, elementID, leftPos, topPos, rightPos, bottomPos)
	Dim diagramObject, position
	position = "l=" & leftPos & ";r=" & rightPos & ";t=" & topPos & ";b=" & bottomPos & ";"
	Set diagramObject = diagramObj.DiagramObjects.AddNew(position, "")
	diagramObject.ElementID = elementID
	diagramObject.Update
	diagramObj.DiagramObjects.Refresh
End Sub

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

Function ActorName(code)
	Select Case code
		Case "ADM"
			ActorName = ACTOR_ADM
		Case "ADT"
			ActorName = ACTOR_ADT
		Case "CLI"
			ActorName = ACTOR_CLI
		Case "TAL"
			ActorName = ACTOR_TAL
		Case "TEC"
			ActorName = ACTOR_TEC
		Case "SIA"
			ActorName = ACTOR_SIA
		Case "PAG"
			ActorName = ACTOR_PAG
		Case "MAP"
			ActorName = ACTOR_MAP
		Case "Sistema"
			ActorName = "Sistema"
		Case Else
			ActorName = code
	End Select
End Function

Function TimestampName()
	Dim value
	value = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2)
	value = value & " " & Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)
	TimestampName = value
End Function

Main
