' Script para Enterprise Architect
' Crea un diagrama individual por paquete de analisis.
' No agrega prefijos como pkg en los nombres; EA los muestra automaticamente.

Sub Main()
	Dim modelPackage, rootPackage, generatedPackage, packages, i

	If Repository.Models.Count = 0 Then
		MsgBox "No hay un modelo abierto en Enterprise Architect."
		Exit Sub
	End If

	Set modelPackage = Repository.Models.GetAt(0)
	Set rootPackage = GetOrCreatePackage(modelPackage, "Diagramas de Analisis")
	Set generatedPackage = rootPackage.Packages.AddNew("Paquetes Individuales " & TimestampName(), "")
	generatedPackage.Update
	rootPackage.Packages.Refresh

	packages = BuildPackages()
	For i = 0 To UBound(packages)
		CreateSinglePackageDiagram generatedPackage, packages(i)
	Next

	Repository.RefreshModelView generatedPackage.PackageID
	MsgBox "Diagramas individuales de paquetes generados."
End Sub

Function BuildPackages()
	BuildPackages = Array( _
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
End Function

Sub CreateSinglePackageDiagram(packageObj, packageName)
	Dim diagramObj, packageEl

	Set diagramObj = packageObj.Diagrams.AddNew(packageName, "Package")
	diagramObj.Update
	packageObj.Diagrams.Refresh

	Set packageEl = packageObj.Elements.AddNew(packageName, "Package")
	packageEl.Update
	AddElementToDiagram diagramObj, packageEl.ElementID, 140, 120, 520, 300

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
