' Script para Enterprise Architect
' Crea el diagrama general de paquetes del analisis.
' No agrega prefijo pkg en el nombre; EA lo muestra automaticamente.

Sub Main()
	Dim modelPackage, rootPackage, generatedPackage

	If Repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = Repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Analisis")
	Set generatedPackage = rootPackage.Packages.AddNew("General de Paquetes " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	CreateGeneralPackageDiagram generatedPackage

	Repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagrama general de paquetes generado."
End Sub

Sub CreateGeneralPackageDiagram(packageObj)
	Dim diagramObj, elements, names, positions, i

	Set diagramObj = packageObj.Diagrams.AddNew("Diagrama General de Paquetes", "Package")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set elements = CreateObject("Scripting.Dictionary")
	names = Array( _
		"Usuarios y acceso", _
		"Clientes y vehiculos", _
		"Incidentes y evidencias", _
		"Talleres y atencion del servicio", _
		"Procesamiento inteligente y asignacion", _
		"Pagos, notificaciones y repartos", _
		"Offline y sincronizacion", _
		"Analitica y KPIs", _
		"Multi-tenant" _
	)

	positions = Array( _
		Array(70, 80, 330, 210), _
		Array(430, 80, 720, 210), _
		Array(800, 80, 1120, 210), _
		Array(70, 340, 390, 470), _
		Array(520, 340, 890, 470), _
		Array(1010, 340, 1350, 470), _
		Array(150, 620, 470, 750), _
		Array(620, 620, 910, 750), _
		Array(1080, 620, 1350, 750) _
	)

	For i = 0 To UBound(names)
		Dim el
		Set el = packageObj.Elements.AddNew(names(i), "Package")
		el.Update
		elements.Add names(i), el
		AddElementToDiagram diagramObj, el.ElementID, positions(i)(0), positions(i)(1), positions(i)(2), positions(i)(3)
	Next

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

	For i = 0 To UBound(names)
		If names(i) <> "Multi-tenant" Then
			AddUse elements(names(i)), elements("Multi-tenant")
		End If
	Next

	diagramObj.Update
	Repository.ReloadDiagram diagramObj.DiagramID
End Sub

Sub AddUse(sourceEl, targetEl)
	Dim conn
	Set conn = sourceEl.Connectors.AddNew("", "Dependency")
	conn.SupplierID = targetEl.ElementID
	conn.Stereotype = "use"
	conn.Update
	sourceEl.Connectors.Refresh
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
