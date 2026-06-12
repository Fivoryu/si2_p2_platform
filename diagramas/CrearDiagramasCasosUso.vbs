' Script para Enterprise Architect
' Genera diagramas individuales de casos de uso a partir de CapturaDeRequisitos.md
' y DetalleCasosDeUso.md.
'
' Uso:
' 1. Abrir el proyecto en Enterprise Architect.
' 2. Ir a Specialize > Tools > Scripting.
' 3. Crear un script VBScript o pegar este contenido en el editor.
' 4. Ejecutar Main.

Dim ACTOR_ADM, ACTOR_ADT, ACTOR_CLI, ACTOR_TAL, ACTOR_TEC, ACTOR_SIA, ACTOR_PAG, ACTOR_MAP
ACTOR_ADM = "Administrador"
ACTOR_ADT = "Administrador T"
ACTOR_CLI = "Cliente"
ACTOR_TAL = "Taller"
ACTOR_TEC = "Tecnico"
ACTOR_SIA = "Sistema de IA"
ACTOR_PAG = "Pasarela Pagos"
ACTOR_MAP = "Mapas"

Sub Main()
	Dim modelPackage, rootPackage, generatedPackage, useCases, i

	If Repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = Repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Casos de Uso")
	Set generatedPackage = rootPackage.Packages.AddNew("Generado " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	useCases = BuildUseCases()

	For i = 0 To UBound(useCases)
		CreateIndividualUseCaseDiagram generatedPackage, useCases(i)
	Next

	CreateGeneralDiagram generatedPackage, useCases

	Repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas generados en el paquete: " & rootPackage.Name & " / " & generatedPackage.Name
End Sub

Function BuildUseCases()
	Dim items(47)
	items(0) = Array("CU-01", "Iniciar Sesion", "CLI,TAL,ADT,ADM", "Ciclo 1")
	items(1) = Array("CU-02", "Cerrar Sesion", "CLI,TAL,ADT,ADM", "Ciclo 1")
	items(2) = Array("CU-03", "Recuperar Contrasena", "CLI,TAL,ADT,ADM", "Ciclo 1")
	items(3) = Array("CU-04", "Registrar Cuenta de Conductor", "CLI", "Ciclo 1")
	items(4) = Array("CU-05", "Registrar Vehiculo", "CLI", "Ciclo 1")
	items(5) = Array("CU-06", "Editar Perfil de Conductor", "CLI", "Ciclo 1")
	items(6) = Array("CU-07", "Registrar Taller", "ADT", "Ciclo 1")
	items(7) = Array("CU-08", "Registrar Tecnico", "ADT,TAL", "Ciclo 1")
	items(8) = Array("CU-09", "Gestionar Disponibilidad del Taller", "TAL", "Ciclo 1")
	items(9) = Array("CU-10", "Reportar Nueva Emergencia", "CLI,SIA", "Ciclo 2")
	items(10) = Array("CU-11", "Adjuntar Imagenes al Reporte", "CLI,SIA", "Ciclo 2")
	items(11) = Array("CU-12", "Adjuntar Audio al Reporte", "CLI,SIA", "Ciclo 2")
	items(12) = Array("CU-13", "Enviar Ubicacion GPS al Reportar", "CLI,MAP", "Ciclo 2")
	items(13) = Array("CU-14", "Visualizar Estado Actual de la Emergencia", "CLI,TAL", "Ciclo 2")
	items(14) = Array("CU-15", "Cancelar Emergencia", "CLI", "Ciclo 2")
	items(15) = Array("CU-16", "Ver Historial de Emergencias del Conductor", "CLI", "Ciclo 2")
	items(16) = Array("CU-17", "Transcribir Audio a Texto (IA)", "SIA", "Ciclo 2")
	items(17) = Array("CU-18", "Clasificar Incidente por Imagenes (IA)", "SIA", "Ciclo 2")
	items(18) = Array("CU-19", "Clasificar Incidente por Texto (IA)", "SIA", "Ciclo 2")
	items(19) = Array("CU-20", "Generar Resumen Estructurado del Incidente", "SIA", "Ciclo 2")
	items(20) = Array("CU-21", "Determinar Prioridad del Incidente", "SIA", "Ciclo 2")
	items(21) = Array("CU-22", "Buscar Talleres Candidatos", "SIA,MAP", "Ciclo 3")
	items(22) = Array("CU-23", "Asignar Taller Optimo", "SIA", "Ciclo 3")
	items(23) = Array("CU-24", "Notificar a Taller sobre Nueva Solicitud", "TAL", "Ciclo 3")
	items(24) = Array("CU-25", "Aceptar Solicitud con Oferta Editable", "TAL", "Ciclo 3")
	items(25) = Array("CU-26", "Rechazar Solicitud", "TAL", "Ciclo 3")
	items(26) = Array("CU-27", "Generar Oferta/Cotizacion Competitiva", "CLI,TAL,SIA", "Ciclo 3")
	items(27) = Array("CU-28", "Calcular Tiempo Estimado de Llegada y Reparacion", "SIA,TAL,MAP", "Ciclo 3")
	items(28) = Array("CU-29", "Seleccionar Oferta de Taller", "CLI", "Ciclo 3")
	items(29) = Array("CU-30", "Efectuar Pago del Servicio", "CLI,PAG", "Ciclo 3")
	items(30) = Array("CU-31", "Consultar Comision del Taller", "TAL,ADT", "Ciclo 3")
	items(31) = Array("CU-32", "Generar Factura / Comprobante", "CLI,TAL", "Ciclo 3")
	items(32) = Array("CU-33", "Conectar a WebSocket para Seguimiento en Vivo", "CLI,TAL", "Ciclo 4")
	items(33) = Array("CU-34", "Visualizar Ubicacion del Taller en Mapa", "CLI", "Ciclo 4")
	items(34) = Array("CU-35", "Recibir Notificacion Inmediata de Cambio de Estado", "CLI,TAL", "Ciclo 4")
	items(35) = Array("CU-36", "Actualizar Estado del Incidente", "TAL", "Ciclo 4")
	items(36) = Array("CU-37", "Transmitir Llegada del Tecnico", "TAL", "Ciclo 4")
	items(37) = Array("CU-38", "Guardar Emergencia Localmente y Marcar como Pendiente de Sincronizacion", "CLI", "Ciclo 5")
	items(38) = Array("CU-40", "Sincronizar Automaticamente al Recuperar Conexion", "CLI,SIA", "Ciclo 5")
	items(39) = Array("CU-41", "Resolver Conflictos de Sincronizacion", "Sistema", "Ciclo 5")
	items(40) = Array("CU-42", "Visualizar Dashboard de KPIs", "ADM,ADT", "Ciclo 5")
	items(41) = Array("CU-43", "Filtrar KPIs por Tenant", "ADM,ADT", "Ciclo 5")
	items(42) = Array("CU-44", "Exportar Reporte de KPIs", "ADM,ADT", "Ciclo 5")
	items(43) = Array("CU-45", "Configurar Umbrales de SLA", "ADM", "Ciclo 5")
	items(44) = Array("CU-46", "Crear Nuevo Tenant", "ADM", "Ciclo 5")
	items(45) = Array("CU-47", "Asignar Administrador a un Tenant", "ADM", "Ciclo 5")
	items(46) = Array("CU-48", "Configurar Plan de Servicio por Tenant", "ADM", "Ciclo 5")
	items(47) = Array("CU-49", "Calificar Servicio Post-Atencion", "CLI", "Ciclo 3")
	BuildUseCases = items
End Function

Sub CreateIndividualUseCaseDiagram(packageObj, ByVal useCaseData)
	Dim diagramName, diagramObj, useCaseEl, parentActorEl, actorEl, conn, actorCodes, i
	Dim actorCount, xStart, xStep, xActor

	diagramName = "uc " & useCaseData(0) & " " & useCaseData(1)
	Set diagramObj = packageObj.Diagrams.AddNew(diagramName, "Use Case")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set useCaseEl = packageObj.Elements.AddNew(useCaseData(0) & " " & useCaseData(1), "UseCase")
	useCaseEl.Notes = "Fuente: CapturaDeRequisitos.md y DetalleCasosDeUso.md. " & useCaseData(3) & "."
	useCaseEl.Update
	AddElementToDiagram diagramObj, useCaseEl.ElementID, 420, 105, 840, 265

	actorCodes = Split(useCaseData(2), ",")
	actorCount = UBound(actorCodes) + 1

	If actorCount = 1 Then
		Set actorEl = packageObj.Elements.AddNew(ActorName(Trim(actorCodes(0))), "Actor")
		actorEl.Notes = "Actor de " & useCaseData(0) & ". Actor original: " & useCaseData(2) & "."
		actorEl.Update
		AddElementToDiagram diagramObj, actorEl.ElementID, 120, 105, 270, 265

		Set conn = actorEl.Connectors.AddNew("", "Association")
		conn.SupplierID = useCaseEl.ElementID
		conn.Update
		actorEl.Connectors.Refresh

		diagramObj.Update
		Repository.ReloadDiagram diagramObj.DiagramID
		Exit Sub
	End If

	Set parentActorEl = packageObj.Elements.AddNew(UnifiedActorName(useCaseData(2)), "Actor")
	parentActorEl.Notes = "Actor general para " & useCaseData(0) & ". Actores originales: " & useCaseData(2) & "."
	parentActorEl.Update
	AddElementToDiagram diagramObj, parentActorEl.ElementID, 210, 75, 330, 170

	Set conn = parentActorEl.Connectors.AddNew("", "Association")
	conn.SupplierID = useCaseEl.ElementID
	conn.Update
	parentActorEl.Connectors.Refresh

	xStep = 135
	xStart = 210 - ((actorCount - 1) * xStep / 2)

	For i = 0 To UBound(actorCodes)
		xActor = xStart + (i * xStep)
		Set actorEl = packageObj.Elements.AddNew(ActorName(Trim(actorCodes(i))), "Actor")
		actorEl.Update
		AddElementToDiagram diagramObj, actorEl.ElementID, xActor, 220, xActor + 110, 315

		Set conn = actorEl.Connectors.AddNew("", "Generalization")
		conn.SupplierID = parentActorEl.ElementID
		conn.Update
		actorEl.Connectors.Refresh
	Next

	diagramObj.Update
	Repository.ReloadDiagram diagramObj.DiagramID
End Sub

Sub CreateGeneralDiagram(packageObj, useCases)
	Dim diagramObj, counters, useCaseData, i, cycleNumber, rowNumber
	Dim useCaseEl, actorEl, xBase, yBase, conn

	Set diagramObj = packageObj.Diagrams.AddNew("uc Vista General de Casos de Uso", "Use Case")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set counters = CreateObject("Scripting.Dictionary")
	counters.Add "1", 0
	counters.Add "2", 0
	counters.Add "3", 0
	counters.Add "4", 0
	counters.Add "5", 0

	For i = 0 To UBound(useCases)
		useCaseData = useCases(i)
		cycleNumber = CycleIndex(useCaseData(3))
		rowNumber = counters(CStr(cycleNumber))
		counters(CStr(cycleNumber)) = rowNumber + 1

		xBase = 40 + ((cycleNumber - 1) * 470)
		yBase = 40 + (rowNumber * 125)

		Set actorEl = packageObj.Elements.AddNew(ActorGroupName(useCaseData(2)), "Actor")
		actorEl.Notes = "Actor unificado para " & useCaseData(0) & ". Actores originales: " & useCaseData(2) & "."
		actorEl.Update
		AddElementToDiagram diagramObj, actorEl.ElementID, xBase, yBase, xBase + 145, yBase + 85

		Set useCaseEl = packageObj.Elements.AddNew(useCaseData(0) & " " & useCaseData(1), "UseCase")
		useCaseEl.Notes = useCaseData(3)
		useCaseEl.Update
		AddElementToDiagram diagramObj, useCaseEl.ElementID, xBase + 175, yBase, xBase + 440, yBase + 85

		Set conn = actorEl.Connectors.AddNew("", "Association")
		conn.SupplierID = useCaseEl.ElementID
		conn.Update
		actorEl.Connectors.Refresh
	Next

	diagramObj.Update
	Repository.ReloadDiagram diagramObj.DiagramID
End Sub

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

Function ActorGroupName(actorCodeList)
	Dim actorCodes, i, result
	actorCodes = Split(actorCodeList, ",")

	For i = 0 To UBound(actorCodes)
		If result <> "" Then
			result = result & ", "
		End If
		result = result & ActorName(Trim(actorCodes(i)))
	Next

	If UBound(actorCodes) = 0 Then
		ActorGroupName = result
	Else
		ActorGroupName = "Actor combinado: " & result
	End If
End Function

Function UnifiedActorName(actorCodeList)
	Dim actorCodes, i, code, hasHuman, hasTechnical, hasSystem
	actorCodes = Split(actorCodeList, ",")

	For i = 0 To UBound(actorCodes)
		code = Trim(actorCodes(i))
		If code = "ADM" Or code = "ADT" Or code = "CLI" Or code = "TAL" Or code = "TEC" Then
			hasHuman = True
		ElseIf code = "SIA" Or code = "PAG" Or code = "MAP" Then
			hasTechnical = True
		Else
			hasSystem = True
		End If
	Next

	If hasHuman And Not hasTechnical And Not hasSystem Then
		UnifiedActorName = "Usuario"
	ElseIf hasTechnical And Not hasHuman And Not hasSystem Then
		UnifiedActorName = "Servicio Externo / Sistema"
	ElseIf hasSystem And Not hasHuman And Not hasTechnical Then
		UnifiedActorName = "Sistema"
	Else
		UnifiedActorName = "Actor Participante"
	End If
End Function

Function CycleIndex(cycleName)
	If InStr(cycleName, "1") > 0 Then
		CycleIndex = 1
	ElseIf InStr(cycleName, "2") > 0 Then
		CycleIndex = 2
	ElseIf InStr(cycleName, "3") > 0 Then
		CycleIndex = 3
	ElseIf InStr(cycleName, "4") > 0 Then
		CycleIndex = 4
	Else
		CycleIndex = 5
	End If
End Function

Function TimestampName()
	Dim value
	value = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2)
	value = value & " " & Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)
	TimestampName = value
End Function

Main
