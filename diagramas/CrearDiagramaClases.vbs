' Script para Enterprise Architect
' Crea el diagrama de clases del sistema (max 6 clases).
' Basado en CapturaDeRequisitos.md, DetalleCasosDeUso.md y Analisis.md.
'
' Uso:
' 1. Abrir el proyecto en Enterprise Architect.
' 2. Ir a Specialize > Tools > Scripting.
' 3. Crear un script VBScript y pegar este contenido.
' 4. Ejecutar Main.

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
	Set generatedPackage = rootPackage.Packages.AddNew("Clases " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	CreateClassDiagram repository, generatedPackage

	repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagrama de clases generado en: " & rootPackage.Name & " / " & generatedPackage.Name
End Sub

Sub CreateClassDiagram(repository, parentPackage)
	Dim diagramObj, classes

	Set diagramObj = parentPackage.Diagrams.AddNew("Diagrama de Clases del Sistema", "Logical")
	diagramObj.Update
	parentPackage.Diagrams.Refresh

	Set classes = CreateObject("Scripting.Dictionary")

	AddClass parentPackage, diagramObj, classes, "Usuario", _
		"id: int" & vbLf & _
		"nombre: String" & vbLf & _
		"email: String" & vbLf & _
		"telefono: String" & vbLf & _
		"contrasena: String" & vbLf & _
		"rol: RolUsuario", _
		"+ iniciarSesion(email, contrasena): Boolean" & vbLf & _
		"+ cerrarSesion(): void" & vbLf & _
		"+ recuperarContrasena(email): Boolean" & vbLf & _
		"+ registrarConductor(datos): Boolean" & vbLf & _
		"+ editarPerfil(datos): void", _
		70, 55, 295, 285

	AddClass parentPackage, diagramObj, classes, "Vehiculo", _
		"id: int" & vbLf & _
		"placa: String" & vbLf & _
		"marca: String" & vbLf & _
		"modelo: String" & vbLf & _
		"anio: int" & vbLf & _
		"color: String" & vbLf & _
		"tipo_combustible: String", _
		"+ registrarVehiculo(datos): Boolean" & vbLf & _
		"+ editarVehiculo(datos): void" & vbLf & _
		"+ eliminarVehiculo(): void", _
		430, 55, 665, 275

	AddClass parentPackage, diagramObj, classes, "Taller", _
		"id: int" & vbLf & _
		"nombre: String" & vbLf & _
		"direccion: String" & vbLf & _
		"telefono: String" & vbLf & _
		"latitud: double" & vbLf & _
		"longitud: double" & vbLf & _
		"disponibilidad: Boolean" & vbLf & _
		"calificacion_promedio: double", _
		"+ registrarTaller(datos): Boolean" & vbLf & _
		"+ gestionarDisponibilidad(estado): void" & vbLf & _
		"+ registrarTecnico(datos): Boolean", _
		800, 55, 1065, 305

	AddClass parentPackage, diagramObj, classes, "Incidente", _
		"id: int" & vbLf & _
		"descripcion: String" & vbLf & _
		"ubicacion_lat: double" & vbLf & _
		"ubicacion_lng: double" & vbLf & _
		"estado: EstadoIncidente" & vbLf & _
		"prioridad: Prioridad" & vbLf & _
		"clasificacion_ia: String" & vbLf & _
		"resumen_ia: String" & vbLf & _
		"fecha_creacion: DateTime", _
		"+ reportarEmergencia(datos): Incidente" & vbLf & _
		"+ cancelar(): void" & vbLf & _
		"+ actualizarEstado(nuevoEstado): void" & vbLf & _
		"+ clasificarConIA(imagenes, audio, texto): Clasificacion" & vbLf & _
		"+ adjuntarEvidencia(archivo, tipo): void", _
		390, 400, 710, 630

	AddClass parentPackage, diagramObj, classes, "Cotizacion", _
		"id: int" & vbLf & _
		"precio_sugerido: double" & vbLf & _
		"precio_final: double" & vbLf & _
		"tiempo_estimado: int" & vbLf & _
		"comentario: String" & vbLf & _
		"estado: EstadoCotizacion", _
		"+ generarCotizacion(datos): Cotizacion" & vbLf & _
		"+ aceptarOferta(): void" & vbLf & _
		"+ rechazarOferta(motivo): void" & vbLf & _
		"+ calcularTiempoEstimado(distancia, tipo): int", _
		100, 400, 360, 580

	AddClass parentPackage, diagramObj, classes, "Pago", _
		"id: int" & vbLf & _
		"monto: double" & vbLf & _
		"comision_plataforma: double" & vbLf & _
		"fecha_pago: DateTime" & vbLf & _
		"estado: EstadoPago" & vbLf & _
		"token_pasarela: String", _
		"+ efectuarPago(metodo): Boolean" & vbLf & _
		"+ generarFactura(): Factura" & vbLf & _
		"+ consultarComision(): double" & vbLf & _
		"+ calificarServicio(puntaje, comentario): void", _
		740, 400, 1030, 580

	AddAssociation classes("Usuario"), classes("Vehiculo"), "posee", "1", "0..*", "Shared"
	AddAssociation classes("Usuario"), classes("Incidente"), "reporta", "1", "0..*", ""
	AddAssociation classes("Taller"), classes("Incidente"), "atiende", "", "", ""
	AddAssociation classes("Incidente"), classes("Cotizacion"), "recibe", "1", "0..*", ""
	AddAssociation classes("Taller"), classes("Cotizacion"), "emite", "1", "0..*", ""
	AddAssociation classes("Incidente"), classes("Pago"), "pagado con", "1", "0..1", ""

	AddGeneralization classes("Usuario"), classes("Taller"), "rol TALLER gestiona"

	SaveDiagram repository, diagramObj, "2"
End Sub

Sub AddClass(parentPackage, diagramObj, classes, className, attributesText, methodsText, leftPos, topPos, rightPos, bottomPos)
	Dim classEl, attrArray, methArray, i, attr, meth

	Set classEl = parentPackage.Elements.AddNew(className, "Class")
	classEl.Update
	parentPackage.Elements.Refresh

	If attributesText <> "" Then
		attrArray = Split(attributesText, vbLf)
		For i = 0 To UBound(attrArray)
			Dim attrParts, attrName, attrType
			attrParts = Split(attrArray(i), ": ")
			attrName = Trim(attrParts(0))
			If UBound(attrParts) >= 1 Then
				attrType = Trim(attrParts(1))
			Else
				attrType = "String"
			End If
			Set attr = classEl.Attributes.AddNew(attrName, attrType)
			attr.Update
		Next
		classEl.Attributes.Refresh
	End If

	If methodsText <> "" Then
		methArray = Split(methodsText, vbLf)
		For i = 0 To UBound(methArray)
			Dim methParts, methSignature, returnType
			methSignature = Trim(methArray(i))
			methParts = Split(methSignature, ": ")
			If UBound(methParts) >= 1 Then
				returnType = Trim(methParts(1))
			Else
				returnType = "void"
			End If

			Dim methName, parenPos
			parenPos = InStr(methParts(0), "(")
			If parenPos > 0 Then
				methName = Left(methParts(0), parenPos - 1)
			Else
				methName = methParts(0)
			End If

			Set meth = classEl.Methods.AddNew(methName, returnType)
			meth.Update
		Next
		classEl.Methods.Refresh
	End If

	classes.Add className, classEl

	Dim diagramObject, geometry, width, height
	width = rightPos - leftPos
	height = bottomPos - topPos
	geometry = "l=" & leftPos & ";r=" & rightPos & ";t=-" & topPos & ";b=-" & bottomPos & ";"
	Set diagramObject = diagramObj.DiagramObjects.AddNew(geometry, "")
	diagramObject.ElementID = classEl.ElementID
	diagramObject.Update
	diagramObj.DiagramObjects.Refresh
End Sub

Sub AddAssociation(sourceEl, targetEl, labelText, sourceMult, targetMult, aggregationKind)
	Dim conn

	Set conn = sourceEl.Connectors.AddNew(labelText, "Association")
	conn.SupplierID = targetEl.ElementID
	conn.ClientID = sourceEl.ElementID
	conn.Direction = "Source -> Destination"
	conn.Update

	If sourceMult <> "" Then
		conn.ClientEnd.Cardinality = sourceMult
	End If
	If targetMult <> "" Then
		conn.SupplierEnd.Cardinality = targetMult
	End If

	If aggregationKind = "Shared" Then
		conn.ClientEnd.Aggregation = 1
	ElseIf aggregationKind = "Composite" Then
		conn.ClientEnd.Aggregation = 2
	End If

	conn.Update
	sourceEl.Connectors.Refresh
End Sub

Sub AddGeneralization(sourceEl, targetEl, labelText)
	Dim conn
	Set conn = sourceEl.Connectors.AddNew(labelText, "Generalization")
	conn.SupplierID = targetEl.ElementID
	conn.ClientID = sourceEl.ElementID
	conn.Update
	sourceEl.Connectors.Refresh
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

Main
