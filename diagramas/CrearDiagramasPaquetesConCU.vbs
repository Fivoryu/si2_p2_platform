' Script para Enterprise Architect
' Crea un diagrama por paquete y conecta el paquete con sus casos de uso mediante trace.
' No agrega prefijos como custom/pkg en los nombres; EA los muestra automaticamente.

Sub Main()
	Dim modelPackage, rootPackage, generatedPackage, mappings, useCases, i

	If Repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = Repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Analisis")
	Set generatedPackage = rootPackage.Packages.AddNew("Paquetes con CU " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	mappings = BuildPackageMappings()
	Set useCases = BuildUseCaseNames()

	For i = 0 To UBound(mappings)
		CreatePackageTraceDiagram generatedPackage, mappings(i), useCases
	Next

	Repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas de paquetes conectados con CU generados."
End Sub

Function BuildPackageMappings()
	BuildPackageMappings = Array( _
		Array("Usuarios y acceso", "CU-01,CU-02,CU-03"), _
		Array("Clientes y vehiculos", "CU-04,CU-05,CU-06,CU-07,CU-08,CU-09"), _
		Array("Incidentes y evidencias", "CU-10,CU-11,CU-12,CU-13,CU-14,CU-15,CU-16"), _
		Array("Talleres y atencion del servicio", "CU-09,CU-24,CU-25,CU-26,CU-36,CU-37"), _
		Array("Procesamiento inteligente y asignacion", "CU-17,CU-18,CU-19,CU-20,CU-21,CU-22,CU-23,CU-24,CU-25,CU-26,CU-27,CU-28,CU-29"), _
		Array("Pagos, notificaciones y repartos", "CU-30,CU-31,CU-32,CU-33,CU-34,CU-35,CU-36,CU-37,CU-49"), _
		Array("Offline y sincronizacion", "CU-38,CU-40,CU-41"), _
		Array("Analitica y KPIs", "CU-42,CU-43,CU-44,CU-45"), _
		Array("Multi-tenant", "CU-46,CU-47,CU-48") _
	)
End Function

Function BuildUseCaseNames()
	Dim d
	Set d = CreateObject("Scripting.Dictionary")
	d.Add "CU-01", "Iniciar Sesion"
	d.Add "CU-02", "Cerrar Sesion"
	d.Add "CU-03", "Recuperar Contrasena"
	d.Add "CU-04", "Registrar Cuenta de Conductor"
	d.Add "CU-05", "Registrar Vehiculo"
	d.Add "CU-06", "Editar Perfil de Conductor"
	d.Add "CU-07", "Registrar Taller"
	d.Add "CU-08", "Registrar Tecnico"
	d.Add "CU-09", "Gestionar Disponibilidad del Taller"
	d.Add "CU-10", "Reportar Nueva Emergencia"
	d.Add "CU-11", "Adjuntar Imagenes al Reporte"
	d.Add "CU-12", "Adjuntar Audio al Reporte"
	d.Add "CU-13", "Enviar Ubicacion GPS"
	d.Add "CU-14", "Visualizar Estado de Emergencia"
	d.Add "CU-15", "Cancelar Emergencia"
	d.Add "CU-16", "Ver Historial de Emergencias"
	d.Add "CU-17", "Transcribir Audio a Texto"
	d.Add "CU-18", "Clasificar por Imagenes"
	d.Add "CU-19", "Clasificar por Texto"
	d.Add "CU-20", "Generar Resumen"
	d.Add "CU-21", "Determinar Prioridad"
	d.Add "CU-22", "Buscar Talleres Candidatos"
	d.Add "CU-23", "Asignar Taller Optimo"
	d.Add "CU-24", "Notificar a Taller"
	d.Add "CU-25", "Aceptar Solicitud"
	d.Add "CU-26", "Rechazar Solicitud"
	d.Add "CU-27", "Generar Oferta"
	d.Add "CU-28", "Calcular Tiempo Estimado"
	d.Add "CU-29", "Seleccionar Oferta"
	d.Add "CU-30", "Efectuar Pago"
	d.Add "CU-31", "Consultar Comision"
	d.Add "CU-32", "Generar Factura"
	d.Add "CU-33", "Conectar WebSocket"
	d.Add "CU-34", "Visualizar Ubicacion en Mapa"
	d.Add "CU-35", "Notificar Cambio de Estado"
	d.Add "CU-36", "Actualizar Estado"
	d.Add "CU-37", "Transmitir Llegada"
	d.Add "CU-38", "Guardar Emergencia Localmente"
	d.Add "CU-40", "Sincronizar Automaticamente"
	d.Add "CU-41", "Resolver Conflictos"
	d.Add "CU-42", "Visualizar Dashboard KPIs"
	d.Add "CU-43", "Filtrar KPIs por Tenant"
	d.Add "CU-44", "Exportar Reporte KPIs"
	d.Add "CU-45", "Configurar SLA"
	d.Add "CU-46", "Crear Nuevo Tenant"
	d.Add "CU-47", "Asignar Administrador"
	d.Add "CU-48", "Configurar Plan"
	d.Add "CU-49", "Calificar Servicio"
	Set BuildUseCaseNames = d
End Function

Sub CreatePackageTraceDiagram(packageObj, mapping, useCases)
	Dim diagramObj, packageEl, ids, i, col, row, useCaseEl, conn, xCase, yCase, code, displayName

	Set diagramObj = packageObj.Diagrams.AddNew(mapping(0), "Custom")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set packageEl = packageObj.Elements.AddNew(mapping(0), "Package")
	packageEl.Update
	AddElementToDiagram diagramObj, packageEl.ElementID, 60, 300, 350, 470

	ids = Split(mapping(1), ",")
	For i = 0 To UBound(ids)
		code = Trim(ids(i))
		If useCases.Exists(code) Then
			displayName = code & " " & useCases(code)
		Else
			displayName = code
		End If
		col = i Mod 3
		row = Int(i / 3)
		xCase = 470 + (col * 285)
		yCase = 70 + (row * 135)

		Set useCaseEl = packageObj.Elements.AddNew(displayName, "UseCase")
		useCaseEl.Update
		AddElementToDiagram diagramObj, useCaseEl.ElementID, xCase, yCase, xCase + 230, yCase + 90

		Set conn = packageEl.Connectors.AddNew("", "Dependency")
		conn.SupplierID = useCaseEl.ElementID
		conn.Stereotype = "trace"
		conn.Update
		packageEl.Connectors.Refresh
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

Function TimestampName()
	Dim value
	value = Year(Now) & Right("0" & Month(Now), 2) & Right("0" & Day(Now), 2)
	value = value & " " & Right("0" & Hour(Now), 2) & Right("0" & Minute(Now), 2) & Right("0" & Second(Now), 2)
	TimestampName = value
End Function

Main
