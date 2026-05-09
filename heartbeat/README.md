# Heartbeat

Aplicacion Flutter para adquirir, visualizar y monitorear una senal ECG recibida por Bluetooth Low Energy (BLE). La app permite capturar datos basicos del usuario, conectarse a un dispositivo BLE llamado `ECG_Device`, graficar muestras ECG en vivo, calcular frecuencia cardiaca aproximada y clasificarla por zonas cardiacas.

## Tabla de contenido

- [Descripcion general](#descripcion-general)
- [Estado actual del proyecto](#estado-actual-del-proyecto)
- [Tecnologias y dependencias](#tecnologias-y-dependencias)
- [Estructura de archivos](#estructura-de-archivos)
- [Arquitectura](#arquitectura)
- [Flujos principales](#flujos-principales)
- [Pantallas](#pantallas)
- [Servicio BLE](#servicio-ble)
- [Calculo de frecuencia cardiaca](#calculo-de-frecuencia-cardiaca)
- [Permisos y plataformas](#permisos-y-plataformas)
- [Como ejecutar](#como-ejecutar)
- [Pruebas y analisis](#pruebas-y-analisis)
- [Notas tecnicas y posibles mejoras](#notas-tecnicas-y-posibles-mejoras)

## Descripcion general

Heartbeat esta pensada para trabajar con un dispositivo externo, probablemente basado en ESP32, que envia muestras ADC de una senal ECG por BLE. La aplicacion:

- Muestra una pantalla inicial de perfil.
- Recibe nombre, sexo y edad del usuario.
- Entra a una pantalla de electrocardiograma.
- Solicita permisos de Bluetooth y ubicacion.
- Escanea dispositivos BLE cercanos.
- Permite seleccionar un dispositivo desde un dialogo.
- Se conecta al dispositivo elegido.
- Busca un servicio y una caracteristica BLE especificos.
- Se suscribe a notificaciones de la caracteristica ECG.
- Decodifica las muestras recibidas.
- Grafica la senal con `fl_chart`.
- Detecta picos R para estimar BPM.
- Clasifica el BPM en zonas cardiacas.
- Muestra alertas cuando cambia la zona cardiaca.

## Estado actual del proyecto

El proyecto principal esta dentro de la carpeta:

```text
Taller-de-Apps_equipo4/
+-- heartbeat/
```

La logica propia de la aplicacion esta principalmente en:

```text
lib/
+-- main.dart
+-- app.dart
+-- features/
    +-- ecg/
        +-- data/
        |   +-- domain/
        |   |   +-- heart_rate_calculator.dart
        |   +-- services/
        |       +-- ble_ecg_service.dart
        +-- presentation/
            +-- screens/
                +-- profile_screen.dart
                +-- ecg_screen.dart
```

Tambien existen carpetas generadas por Flutter para Android, iOS, macOS, Windows, Linux y Web. Esas carpetas contienen configuracion nativa, manifiestos, iconos y archivos de arranque de cada plataforma.

## Tecnologias y dependencias

El archivo `pubspec.yaml` define:

- SDK de Dart: `^3.11.4`.
- Flutter Material: base visual de la aplicacion.
- `fl_chart: ^0.66.0`: graficacion de la senal ECG.
- `flutter_blue_plus: ^1.32.0`: escaneo, conexion y comunicacion BLE.
- `permission_handler: ^12.0.1`: solicitud de permisos en runtime.
- `cupertino_icons: ^1.0.8`: iconos estilo Cupertino, aunque la UI usa principalmente Material Icons.
- `flutter_lints: ^6.0.0`: reglas recomendadas de analisis estatico.

Assets declarados:

```yaml
assets:
  - assets/logo.png
```

El asset `assets/logo.png` se usa en la pantalla de perfil como imagen circular.

## Estructura de archivos

### Archivos de aplicacion

- `lib/main.dart`: punto de entrada. Inicializa bindings de Flutter y ejecuta `MyApp`.
- `lib/app.dart`: configura `MaterialApp`, tema, titulo y pantalla inicial.
- `lib/features/ecg/presentation/screens/profile_screen.dart`: pantalla inicial para capturar datos del usuario.
- `lib/features/ecg/presentation/screens/ecg_screen.dart`: pantalla principal de ECG, conexion BLE, grafica, BPM, zonas y alertas.
- `lib/features/ecg/data/services/ble_ecg_service.dart`: capa de comunicacion BLE.
- `lib/features/ecg/data/domain/heart_rate_calculator.dart`: algoritmo de deteccion de picos, BPM y clasificacion de zonas.

### Archivos de configuracion

- `pubspec.yaml`: dependencias, version, assets y configuracion Flutter.
- `analysis_options.yaml`: reglas de lint heredadas de `flutter_lints`.
- `android/app/src/main/AndroidManifest.xml`: permisos BLE/ubicacion y configuracion Android.
- `web/manifest.json`: configuracion PWA/web generada por Flutter.
- `test/widget_test.dart`: test inicial generado por Flutter. Actualmente no representa la app real.

### Carpetas nativas generadas

- `android/`: proyecto Android, Gradle, manifiestos, recursos e iconos.
- `ios/`: proyecto iOS, Xcode, Info.plist, storyboards e iconos.
- `macos/`: proyecto macOS generado.
- `windows/`: runner Windows generado.
- `linux/`: runner Linux generado.
- `web/`: archivos base para compilar la app a Web.

## Arquitectura

La app usa una separacion simple por feature:

- `presentation`: pantallas y widgets.
- `data/services`: comunicacion con hardware externo.
- `data/domain`: logica de dominio para interpretar la senal ECG.

El flujo de datos principal es:

```text
Dispositivo BLE
    -> notificaciones BLE
BleEcgService
    -> Stream<int> ecgStream
EcgScreen
    -> addSample()
HeartRateCalculator
    -> BPM + zona
UI: grafica, frecuencia, zona y alertas
```

No se usa gestor de estado externo. El estado vive dentro de `StatefulWidget` con `setState`.

## Flujos principales

### 1. Inicio de la app

Archivo: `lib/main.dart`

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}
```

Este flujo:

1. Asegura que Flutter este inicializado.
2. Ejecuta el widget raiz `MyApp`.

### 2. Configuracion de la app

Archivo: `lib/app.dart`

`MyApp` construye un `MaterialApp` con:

- Titulo: `Heartbeat`.
- Banner debug oculto.
- Tema claro con Material 3.
- Color semilla rosa `0xFFF78B94`.
- Pantalla inicial: `ProfileScreen`.

### 3. Flujo de perfil

Archivo: `profile_screen.dart`

La pantalla de perfil permite capturar:

- Nombre.
- Sexo.
- Edad.

Al presionar `Iniciar`, se ejecuta `_goToEcg()`, que navega a `EcgScreen` pasando los valores capturados:

```dart
EcgScreen(
  name: _nameController.text.trim(),
  sex: _sex,
  age: _ageController.text.trim(),
)
```

Nota: actualmente estos datos se usan principalmente para inicializar el calculo por edad. El nombre y sexo se pasan a la pantalla ECG, pero no se muestran ni participan en otra logica.

### 4. Flujo de conexion BLE

Archivo: `ecg_screen.dart`

Al tocar `Conectar`:

1. `_connect()` cambia el estado a "Pidiendo permisos...".
2. `_requestPermissions()` solicita permisos:
   - `bluetoothScan`
   - `bluetoothConnect`
   - `locationWhenInUse`
3. Se abre `_pickDevice()`.
4. `_pickDevice()` inicia un escaneo BLE de 15 segundos.
5. Se muestra un `AlertDialog` con dispositivos encontrados.
6. El usuario selecciona un dispositivo.
7. Se detiene el escaneo.
8. `_bleService.connectToDevice()` conecta al dispositivo.
9. Se descubren servicios BLE.
10. Se busca la caracteristica ECG.
11. Se activan notificaciones.
12. La app se suscribe a `ecgStream`.

### 5. Flujo de recepcion ECG

Cuando llega una muestra ECG:

1. `BleEcgService` recibe bytes desde la caracteristica BLE.
2. `_decodeSample()` convierte los bytes a `int`.
3. El valor entra al stream `_ecgController`.
4. `EcgScreen` escucha `ecgStream`.
5. La muestra se agrega a `_spots` para graficarse.
6. El contador `_x` avanza.
7. Si hay mas de 1250 muestras visibles, se elimina la mas antigua.
8. La muestra se manda a `HeartRateCalculator.addSample()`.
9. Si se actualiza el BPM, se actualiza la UI.
10. Si cambia la zona cardiaca y las alertas estan activadas, aparece un `SnackBar`.

### 6. Flujo de desconexion

Al tocar `Desconectar`:

1. `_disconnect()` cancela la suscripcion ECG.
2. Llama a `_bleService.disconnect()`.
3. Apaga notificaciones BLE si estaban activas.
4. Desconecta el dispositivo.
5. Limpia la grafica.
6. Reinicia BPM, zona, contador y calculadora.
7. El estado vuelve a "Desconectado".

### 7. Flujo de alertas

La pantalla ECG tiene un `endDrawer` con:

- Switch para activar/desactivar alertas.
- Leyenda de zonas cardiacas.

Las alertas se muestran cuando:

- El calculador actualiza BPM.
- La zona nueva es distinta de la anterior.
- La zona no es `none`.
- La zona anterior tampoco era `none`.
- Las alertas estan activadas.
- Han pasado al menos 5 segundos desde la ultima alerta.

## Pantallas

### `ProfileScreen`

Tipo: `StatefulWidget`

Responsabilidades:

- Mostrar el logo.
- Recibir datos del usuario.
- Mantener controladores de texto.
- Permitir elegir sexo con `DropdownButton`.
- Navegar a la pantalla ECG.

Estado interno:

- `_nameController`: controlador del campo nombre.
- `_ageController`: controlador del campo edad.
- `_sex`: opcion seleccionada.

Funciones:

- `dispose()`: libera controladores.
- `_goToEcg()`: navega hacia `EcgScreen`.
- `build()`: construye la interfaz.

Widget auxiliar:

- `_InfoRow`: fila reutilizable con etiqueta y contenido. Se usa para nombre, sexo y edad.

### `EcgScreen`

Tipo: `StatefulWidget`

Parametros recibidos:

- `name`: nombre del usuario.
- `sex`: sexo del usuario.
- `age`: edad del usuario.

Responsabilidades:

- Pedir permisos.
- Escanear dispositivos BLE.
- Mostrar dialogo de seleccion.
- Conectar/desconectar.
- Escuchar muestras ECG.
- Dibujar grafica en vivo.
- Calcular BPM.
- Mostrar zona cardiaca.
- Manejar alertas.

Constantes visuales:

- `_primary`: rosa principal.
- `_soft`: rosa suave.
- `_pale`: rosa palido.
- `_white`: blanco.

Configuracion ECG:

- `_sampleRateHz = 250`: frecuencia de muestreo asumida.
- `_visibleSeconds = 5`: ventana visible en grafica.
- `_maxVisibleSamples = 1250`: 250 muestras/segundo * 5 segundos.
- `_adcMin = 0`: minimo del ADC.
- `_adcMax = 4095`: maximo del ADC de 12 bits.

Estado BLE:

- `_bleService`: instancia de `BleEcgService`.
- `_ecgSub`: suscripcion al stream de muestras.
- `_status`: texto de estado.
- `_isConnecting`: indica operacion en progreso.
- `_isConnected`: indica conexion activa.

Estado ECG/BPM:

- `_spots`: puntos de la grafica.
- `_x`: indice de muestra.
- `_hrCalc`: calculadora de frecuencia cardiaca.
- `_bpm`: BPM actual.
- `_zone`: zona cardiaca actual.

Estado de alertas:

- `_alertsEnabled`: permite activar/desactivar alertas.
- `_lastAlertTime`: evita mostrar alertas demasiado seguido.

Funciones principales:

- `initState()`: crea `BleEcgService` con `deviceName: 'ECG_Device'` y crea `HeartRateCalculator`.
- `dispose()`: cancela suscripcion ECG y libera el servicio BLE.
- `_requestPermissions()`: solicita permisos Bluetooth y ubicacion.
- `_deviceName(ScanResult r)`: obtiene nombre visible del dispositivo.
- `_hasName(ScanResult r)`: indica si el dispositivo tiene nombre.
- `_isTarget(ScanResult r)`: indica si el dispositivo coincide con `ECG_Device`.
- `_sorted(List<ScanResult> raw)`: elimina duplicados y ordena resultados por prioridad.
- `_pickDevice()`: escanea y muestra dialogo para elegir dispositivo.
- `_connect()`: coordina permisos, escaneo, seleccion, conexion y suscripcion.
- `_disconnect()`: corta conexion y limpia estado.
- `_showZoneAlert(HeartRateZone zone)`: muestra `SnackBar` al cambiar zona.
- `build()`: construye pantalla principal.
- `_buildConnectPanel()`: panel cuando no hay conexion.
- `_buildChart()`: grafica ECG cuando hay conexion.
- `_buildAlertDrawer()`: drawer lateral de alertas.

Widgets auxiliares:

- `_InfoTile`: fila de informacion para BPM y zona.
- `_ZoneLegend`: leyenda de colores por zona.

## Servicio BLE

Archivo: `ble_ecg_service.dart`

Clase: `BleEcgService`

Esta clase encapsula la comunicacion con `flutter_blue_plus`.

### UUID esperados

Servicio ECG:

```text
12345678-1234-1234-1234-123456789abc
```

Caracteristica ECG:

```text
abcd1234-5678-1234-5678-123456789abc
```

El dispositivo externo debe exponer estos UUID para que la app encuentre la caracteristica correcta.

### Propiedades

- `deviceName`: nombre esperado del dispositivo BLE.
- `ecgStream`: stream publico de muestras ECG ya decodificadas como `int`.
- `scanResults`: stream publico de resultados de escaneo, con throttling.
- `_device`: dispositivo actualmente conectado.
- `_characteristic`: caracteristica ECG encontrada.
- `_scanSub`: suscripcion interna al escaneo.
- `_valueSub`: suscripcion interna a notificaciones BLE.

### Funciones

#### `_throttleScanResults()`

Reduce la frecuencia con la que se emiten resultados de escaneo. En la app se usa un intervalo de 1200 ms para evitar que el dialogo se reconstruya excesivamente.

#### `ensureBluetoothReady()`

Verifica:

1. Que el equipo soporte BLE.
2. Que el adaptador Bluetooth este encendido.

Si no hay soporte BLE, lanza una excepcion. Si Bluetooth esta apagado, espera hasta que el estado sea `on`.

#### `scanAndConnect()`

Escanea automaticamente buscando un dispositivo cuyo `platformName` o `advName` coincida con `deviceName`. Si lo encuentra:

1. Detiene el escaneo.
2. Conecta al dispositivo.
3. Descubre servicios.
4. Se suscribe a la caracteristica ECG.

En la UI actual, el flujo principal usa seleccion manual con `_pickDevice()` y `connectToDevice()`. Esta funcion queda disponible como alternativa automatica.

#### `scanForDevices()`

Escanea durante un tiempo definido, acumula dispositivos por `remoteId`, los ordena por RSSI y devuelve una lista. Actualmente no es el flujo principal de la pantalla, pero sirve para escaneo manual no reactivo.

#### `startDeviceScan()`

Inicia un escaneo BLE en vivo con:

- `continuousUpdates: true`
- `continuousDivisor: 4`
- `androidScanMode: AndroidScanMode.balanced`
- `androidUsesFineLocation: true`
- `androidCheckLocationServices: true`

La pantalla ECG usa esta funcion antes de abrir el dialogo de dispositivos.

#### `stopDeviceScan()`

Detiene el escaneo y cancela la suscripcion interna.

#### `connectToDevice(BluetoothDevice device)`

Conecta al dispositivo seleccionado. Si ya habia otro dispositivo conectado, llama a `disconnect()`. Luego:

1. Intenta conectar con timeout de 15 segundos.
2. Si la conexion lanza error pero el dispositivo queda conectado, continua.
3. Llama a `_discoverAndSubscribe()`.
4. Devuelve el dispositivo conectado.

#### `_discoverAndSubscribe()`

Busca el servicio ECG y la caracteristica ECG. La caracteristica debe permitir `notify` o `indicate`.

Cuando la encuentra:

1. Guarda la caracteristica.
2. Cancela una suscripcion anterior si existe.
3. Escucha `onValueReceived`.
4. Decodifica cada paquete con `_decodeSample()`.
5. Emite la muestra por `ecgStream`.
6. Activa notificaciones con `setNotifyValue(true)`.

Si no encuentra la caracteristica esperada, lanza una excepcion.

#### `_decodeSample(List<int> value)`

Convierte los bytes recibidos a una muestra numerica:

- Si la lista esta vacia, devuelve `0`.
- Si hay 4 bytes o mas, interpreta los primeros 4 bytes como `int32` little-endian.
- Si hay menos de 4 bytes, intenta decodificar como texto UTF-8 y convertirlo a entero.
- Si no puede convertir, devuelve `0`.

Esto permite trabajar con dos formatos de envio:

- Binario little-endian.
- Texto numerico.

#### `disconnect()`

Limpia la comunicacion BLE:

1. Cancela suscripcion de valores.
2. Cancela suscripcion de escaneo.
3. Apaga notificaciones si estaban activas.
4. Desconecta el dispositivo.
5. Espera 500 ms.

#### `dispose()`

Llama a `disconnect()` y cierra el `StreamController` de ECG.

## Calculo de frecuencia cardiaca

Archivo: `heart_rate_calculator.dart`

Clase: `HeartRateCalculator`

La calculadora recibe muestras ADC del ECG y estima BPM detectando picos R.

### Supuestos de la senal

El codigo documenta estos supuestos:

- ADC de 12 bits: rango `0-4095`.
- Baseline aproximada: `2000`.
- Pico R aproximado: `3700-3900`.
- Sample rate: `250 Hz`.
- Periodo refractario fisiologico: `200 ms`.

### Parametros

- `_refractoryMs = 200`: minimo tiempo entre picos aceptados.
- `_rrWindowSize = 6`: cantidad maxima de intervalos RR para promedio movil.
- `_peakThreshold = 2800`: umbral fijo para detectar pico R.
- `_maxHr = 220 - age`: frecuencia cardiaca maxima estimada.
- `_refractorySamples`: periodo refractario convertido a muestras.

### Estado interno

- `_prev2` y `_prev1`: muestras previas para detectar maximos locales.
- `_sampleCount`: contador total de muestras procesadas.
- `_lastPeakIdx`: indice del ultimo pico detectado.
- `_rrIntervals`: intervalos RR validos.
- `_bpm`: frecuencia cardiaca actual.
- `_zone`: zona cardiaca actual.

### `addSample(double sample)`

Agrega una muestra y devuelve `true` si se actualizo el BPM.

Proceso:

1. Incrementa contador de muestras.
2. Espera tener al menos 3 muestras.
3. Detecta maximo local:
   - La muestra anterior supera `_peakThreshold`.
   - La muestra anterior es mayor que la anterior a ella.
   - La muestra anterior es mayor o igual que la muestra actual.
4. Aplica periodo refractario.
5. Calcula intervalo RR entre picos.
6. Valida que el RR este entre 300 ms y 2000 ms.
7. Guarda el RR en una ventana de maximo 6 intervalos.
8. Llama a `_updateBpm()`.
9. Actualiza `_lastPeakIdx`.

### `_updateBpm()`

Promedia los intervalos RR guardados y calcula:

```text
BPM = sampleRateHz * 60 / promedioRR
```

Luego valida que el resultado este entre 30 y 220 BPM. Si es valido:

1. Actualiza `_bpm`.
2. Clasifica la zona con `_classifyZone()`.

### `_classifyZone(int bpm)`

Calcula el porcentaje respecto a la frecuencia maxima:

```text
pct = bpm / (220 - edad) * 100
```

Clasificacion:

- `< 50%`: `rest`
- `50-60%`: `zone1`
- `60-70%`: `zone2`
- `70-80%`: `zone3`
- `80-90%`: `zone4`
- `>= 90%`: `zone5`

### `reset()`

Limpia todo el estado interno y vuelve a:

- BPM `0`.
- Zona `none`.
- Sin picos previos.
- Sin intervalos RR.

### `HeartRateZone`

Enum con zonas:

- `none`: sin dato.
- `rest`: reposo.
- `zone1`: muy ligero.
- `zone2`: quema de grasa.
- `zone3`: aerobico.
- `zone4`: anaerobico.
- `zone5`: maximo esfuerzo.

La extension `HeartRateZoneExt` agrega:

- `label`: texto mostrado en UI.
- `colorValue`: color usado en UI y alertas.

## Permisos y plataformas

### Android

El manifiesto Android declara:

- `android.hardware.bluetooth_le`, no obligatorio (`required="false"`).
- `BLUETOOTH_SCAN` para Android 12+.
- `BLUETOOTH_CONNECT` para Android 12+.
- `BLUETOOTH` hasta Android 11.
- `BLUETOOTH_ADMIN` hasta Android 11.
- `ACCESS_FINE_LOCATION`.

En runtime, la app solicita:

- `Permission.bluetoothScan`
- `Permission.bluetoothConnect`
- `Permission.locationWhenInUse`

Esto es necesario porque el escaneo BLE en Android puede depender de permisos Bluetooth y/o ubicacion segun version del sistema.

### iOS, macOS, Windows, Linux y Web

El proyecto contiene carpetas generadas para estas plataformas. La logica BLE esta escrita con `flutter_blue_plus`; la disponibilidad real depende del soporte del plugin y de los permisos/configuracion nativa de cada plataforma.

La app esta mas claramente preparada para Android por los permisos declarados en `AndroidManifest.xml`.

## Como ejecutar

Desde la carpeta del proyecto:

```bash
cd Taller-de-Apps_equipo4/heartbeat
flutter pub get
flutter run
```

Para Android, se recomienda ejecutar en un dispositivo fisico con Bluetooth encendido. Un emulador normalmente no sirve para probar BLE real.

El dispositivo ECG esperado debe:

- Estar encendido y anunciandose por BLE.
- Usar nombre `ECG_Device`, o ser seleccionado manualmente desde la lista.
- Exponer el servicio `12345678-1234-1234-1234-123456789abc`.
- Exponer la caracteristica `abcd1234-5678-1234-5678-123456789abc`.
- Permitir `notify` o `indicate`.
- Enviar muestras como `int32` little-endian o como texto numerico.

## Pruebas y analisis

Comandos utiles:

```bash
flutter analyze
flutter test
```

Durante esta revision, ambos comandos se intentaron ejecutar, pero no terminaron dentro de 120 segundos en el entorno actual. Por eso el README documenta el estado observado del codigo, pero no afirma que el analisis o las pruebas pasen.

Nota importante: `test/widget_test.dart` todavia contiene el test inicial de contador generado por Flutter. Ese test busca textos `0`, `1` y un icono `+`, elementos que ya no existen en Heartbeat. Conviene reemplazarlo por pruebas acordes al flujo actual, por ejemplo:

- Que `MyApp` muestre `ProfileScreen`.
- Que aparezca el titulo `Heartbeat`.
- Que existan los campos `Nombre`, `Sexo` y `Edad`.
- Que el boton `Iniciar` navegue hacia `EcgScreen`.
- Tests unitarios para `HeartRateCalculator`.

## Notas tecnicas y posibles mejoras

- El nombre y sexo del usuario se capturan y se pasan a `EcgScreen`, pero actualmente no se muestran ni se usan para decisiones de logica.
- La edad si se usa para calcular `FCmax = 220 - edad`; si la edad no es valida, se usa `25`.
- El umbral de pico R es fijo (`2800`). Puede funcionar con una senal conocida, pero podria necesitar calibracion si cambia el sensor, ganancia, ruido o posicion de electrodos.
- El calculo de BPM depende de una frecuencia de muestreo constante de `250 Hz`. Si el dispositivo envia datos a otra frecuencia, el BPM calculado sera incorrecto.
- La grafica muestra una ventana de 5 segundos, equivalente a 1250 muestras.
- El servicio BLE tiene funciones no usadas directamente por la pantalla actual (`scanAndConnect()` y `scanForDevices()`), pero son utiles como alternativas de escaneo automatico o manual.
- La descripcion de `pubspec.yaml` y `web/manifest.json` todavia dice "A new Flutter project."; seria ideal actualizarla a una descripcion real del proyecto.
- Algunos textos del codigo muestran caracteres mal codificados en ciertos entornos. Si se edita el proyecto, conviene guardar los archivos como UTF-8.
- Las pruebas automatizadas deberian actualizarse antes de considerar estable el proyecto.
