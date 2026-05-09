Video de demostración: https://drive.google.com/file/d/1jgjhB-aSDG6PHIniq0ps5C1710mpRoRg/view?usp=sharing


Heartbeat es una aplicación de flutter que permite adquirir y visualizar una señal de ECG recibida por Bluetooth Low Energy (BLE) desde un ESP32, el cuál está configurado para aparecer como "ECG_Device". Además, calcula la frecuencia cardiaca aproximada y la clasifica por zonas.

La arquitectura dentro de lib es la siguiente:
```text

lib/

+-- main.dart

+-- app.dart

+-- features/

    +-- ecg/

        +-- data/

        |   +-- domain/

        |   |   +-- heart_rate_calculator.dart

        |   +-- services/

        |       +-- ble_ecg_service.dart

        +-- presentation/

            +-- screens/

                +-- profile_screen.dart

                +-- ecg_screen.dart

```

Estos archivos se dividen de la siguiente manera:

main - Inicializa flutter y ejecuta "My App"
app - Configura el tema y título, así como otros parámetros de estilo por medio de materialApp.
profile_screen - Pantalla inicial, donde se hace la captura de datos del usuario. Cuenta con un StatefulWidget, ya que debe de reflejar el texto cambiante. Su variable relevante es únicamente sex, ya que se utiliza para calcular las zonas de FC.
ecg_screen - Pantalla donde se muestra el ECG de forma gráfica, se hace la conexión BLE, se muestra frecuencia cardiaca, y la zona de frecuencia en la que está el usuario. Cuenta con un StatefulWidget, ya que constantemente cambia por los valores de FC calculados, así como la gráfica. 
ble_ecg_service - Comunicación BLE con ESP32 llamado ECG_Device. Considera que el máximo del ADC es de 12 bits, es decir, 4095.
heart_rate_calculator - Algoritmo de detección de picos, FC (frecuencia cardiaca) y clasificación de zonas, por medio de _hrCalc._ El treshold del pico R está dado por _peakTreshold_, en 2800.
Las zonas cardiacas, por su lado, se dividen de la siguiente forma: 
- `< 50%`: `rest` - Reposo

- `50-60%`: `zone1` -Muy ligero

- `60-70%`: `zone2` - Quema de grasa

- `70-80%`: `zone3` - Aeróbico

- `80-90%`: `zone4` - Anaeróbico

- `>= 90%`: `zone5` - Máximo esfuerzo.

Los otros dos archivos relevantes son pubspec.yaml, donde están las dependencias, versión, assets; y AndroidManifest.xml ta que es donde se piden los permisos de BLE.

El flujo de la aplicación es el siguiente:
main abre el widget correspondiente que corre MyApp, el widget principal. Posteriormente, usa app.dart para construir el entorno visual de la aplicación. Profile_screen permite la captura de nombre, sexo y edad, y al presionar iniciar, se ejecuta _goToEcg_, el cuál realiza el cambio de pantalla.

El botón de conectar manda llamar a _connect_. En caso de ser la primera vez, se solicitan los permisos para utilizar bluetooth por medio de _bluetoothScan_ y _bluetoothConnect_. Se manda llamar _pickDevice_, el cuál despliega la lista de dispositivos encontrados en el escaneo bluetooth para seleccionar el dispositivo que se conectará por _bleServiceconnectToDevice_.

Los bytes recibidos por ecgStream se vuelven ints, desplegados en EcgScreen gracias a _spots._ Además, HeartRateCalculator los recibe para calcular FC. La gráfica considera una frecuencia cardiaca de 250 Hz.

Además, arriba a la derecha hay un switch para activar las alertas referentes a las zonas cardiacas, mismas que se presentan cuando la zona nueva es diferente a la calculada anteriormente.
