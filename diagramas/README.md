# Diagramas de casos de uso para Enterprise Architect

Esta carpeta contiene el script `CrearDiagramasCasosUso.vbs`.
Tambien contiene `CrearDiagramasPorCicloYGeneral.vbs`, que genera diagramas agrupados.

## Como ejecutarlo en Enterprise Architect

1. Abre tu proyecto `.eap`, `.eapx` o repositorio en Enterprise Architect.
2. Ve a `Specialize > Tools > Scripting`.
3. Crea un script de tipo `VBScript`.
4. Pega el contenido de `CrearDiagramasCasosUso.vbs`.
5. Ejecuta el script.

El script crea un paquete llamado `Diagramas de Casos de Uso` y dentro un subpaquete `Generado AAAAMMDD HHMMSS`.

Si ejecutas `CrearDiagramasPorCicloYGeneral.vbs`, crea un subpaquete `Por Ciclos AAAAMMDD HHMMSS`.

## Contenido generado

- 48 diagramas individuales, uno por caso de uso.
- 1 diagrama general ordenado por ciclos.
- Cada diagrama individual muestra los elementos sin rectangulo/boundary alrededor.
- Si el caso de uso tiene un solo actor, el actor se conecta directamente al caso de uso.
- Si el caso de uso tiene varios actores, muestra actor general arriba, actores especificos debajo, caso de uso a la derecha y asociacion.
- Los actores especificos se conectan al actor general con relaciones de generalizacion, como `Taller`, `Cliente`, `Administrador` hacia `Usuario`.
- Las etiquetas visibles de actores son cortas para que el diagrama quede limpio.

## Script por ciclos

`CrearDiagramasPorCicloYGeneral.vbs` genera:

- `uc Ciclo 1 - Casos de Uso`
- `uc Ciclo 2 - Casos de Uso`
- `uc Ciclo 3 - Casos de Uso`
- `uc Ciclo 4 - Casos de Uso`
- `uc Ciclo 5 - Casos de Uso`
- `uc General - Todos los Casos de Uso`

En estos diagramas se usa un marco de sistema como en la referencia. Los actores quedan cerca del centro y los casos de uso se reparten a ambos lados en una grilla simple, para que sea sencillo moverlos y ordenarlos manualmente.

## Scripts de analisis

`CrearDiagramasPaquetesIndividuales.vbs`

- Genera un diagrama por cada paquete de analisis.
- Los nombres no incluyen el prefijo `pkg`.

`CrearDiagramaGeneralPaquetes.vbs`

- Genera el diagrama general de paquetes.
- Conecta paquetes con dependencias `use`.
- Los nombres no incluyen el prefijo `pkg`.

`CrearAnalisisDePaquetes.vbs`

- Genera el diagrama de analisis de paquetes con una distribucion parecida al modelo de referencia.
- Usa paquetes UML conectados con dependencias `use`.
- No agrega `pkg` al nombre del diagrama.

`CrearDiagramasPaquetesConCU.vbs`

- Genera un diagrama por paquete.
- Conecta cada paquete con sus CU mediante dependencias `trace`.
- Los nombres no incluyen el prefijo `custom`.

`CrearDiagramasComunicacion.vbs`

- Genera diagramas de comunicacion para los CU mas importantes: CU-10, CU-23, CU-25, CU-33, CU-36, CU-40, CU-42 y CU-46.
- No agrega mensajes ni numeracion; solo deja los elementos y conectores para completarlos a mano.
- Los nombres no incluyen el prefijo `sd`.
- Usa `Object` con estereotipos `boundary`, `control` y `entity`, igual que el ejemplo de EA, para que se rendericen con las formas correctas.

`CrearDiagramasDespliegueYLogico.vbs`

- Genera `Despliegue del Sistema`.
- Genera `Diseno Logico Organizado en Capas`.
- Usa nodos/artefactos para despliegue y paquetes con dependencias `use` para el diseno logico.

Notas:

- CU-39 no se genera porque en `CapturaDeRequisitos.md` fue fusionado con CU-38.
- Se usan nombres sin tildes para evitar problemas de codificacion al pegar el script en Enterprise Architect.
