# DawiDawi 🐾📼

App nativa de iOS (Swift + SwiftUI) para **coleccionar las criaturas que encuentras en la vida real**.
Haces una foto → la app la convierte en un **modelo 3D low-poly con estética PS1/N64** → recibe una
**rareza aleatoria** con una revelación espectacular → se guarda en **tu colección personal**.

La app **no identifica, no clasifica y no nombra** nada: la foto es solo la referencia visual del modelo.
No hay Pokédex ni catálogo de especies; tu colección es solo lo que tú fotografías.

---

## 1. Requisitos y cómo abrirlo

| Requisito | Versión |
|---|---|
| Mac con **Xcode 16** o posterior | (el proyecto usa carpetas sincronizadas, formato de Xcode 16) |
| iOS mínimo | **17.0** (SwiftData, Vision "lift subject", MapKit para SwiftUI) |
| Dispositivo | iPhone real recomendado (la cámara y el recorte de Vision no funcionan en el simulador) |

1. Copia la carpeta `DawiDawi/` a un Mac y abre **`DawiDawi.xcodeproj`**.
2. En *Signing & Capabilities*, elige tu **Team** (una Apple ID gratuita sirve para tu propio iPhone)
   y, si hace falta, cambia el *Bundle Identifier* (`com.dawidawi.app`) por uno único.
3. Conecta el iPhone y pulsa **Run (⌘R)**.

> En el **simulador** la app funciona entera usando **📷 Importar foto** (botón de la izquierda del visor),
> pero Vision no recorta el sujeto y usa un recorte ovalado de respaldo.

No hace falta ningún paquete externo: solo frameworks de Apple.

---

## 2. Análisis de tecnologías

| Necesidad | Tecnología elegida | Por qué |
|---|---|---|
| UI | **SwiftUI** + componentes retro propios | Nativo, se adapta a todos los iPhone (SE → Pro Max) |
| Cámara | **AVFoundation** (`AVCaptureSession`, `AVCapturePhotoOutput`) | Visor a pantalla completa con HUD de videojuego, no la cámara estándar |
| Importar foto | **PhotosPicker** | No requiere permiso de fototeca |
| Recortar al sujeto | **Vision** `VNGenerateForegroundInstanceMaskRequest` | Separa figura/fondo **sin reconocer qué es** (sin etiquetas ni especies) |
| Textura retro | Procesado propio de píxeles (CoreGraphics) | Baja resolución, color de 15 bits con tramado Bayer 4×4 como la PS1, contorno oscuro |
| Modelo 3D | **Malla generada por código** + **SceneKit** | Silueta “inflada” → malla facetada de ~1–3 k triángulos, normales planas, texturas *nearest* |
| Render 240p | `SCNView` con `contentScaleFactor` < 1 y filtro *nearest* | Pixelado auténtico en cualquier pantalla, a 30 fps (ahorra batería) |
| Persistencia | **SwiftData** + ficheros en *Application Support* | 100 % offline; foto, sprite y miniatura por criatura |
| Rarezas | `SystemRandomNumberGenerator` + pesos configurables | Probabilidades editables y simulador de 1000 tiradas |
| Sonido | **AVAudioEngine** con sintetizador chiptune propio | Cuadrada/triangular/ruido LFSR; sin ficheros de audio |
| Hápticos | `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator` | Ráfaga proporcional a la rareza |
| Ubicación (opcional) | **CoreLocation** + geocodificación inversa | El permiso solo se pide al activar la opción |
| Estadísticas | **Swift Charts** | Gráficas por rareza y actividad |
| IA remota (opcional) | API HTTP compatible con `POST /v1/images/edits` | Redibuja el sujeto con estética PS1; la API key va al **Llavero** |

---

## 3. Cómo funciona la generación

```
Foto ──► (opcional) IA remota: "redibuja este sujeto como personaje PS1/N64"
     ──► Vision: recorte del sujeto (máscara de primer plano, sin clasificar)
     ──► Sprite retro 48–112 px: saturación, paleta reducida + tramado Bayer, borde duro, contorno
     ──► Malla 3D: rejilla de 18–42 celdas → transformada de distancia → cúpula delante/detrás
                    → triángulos con normales planas + “jitter” (facetas de modelado a mano)
     ──► Escenario SceneKit: suelo de ajedrez, pared de madera, niebla, luz por vértice,
                              aura de color según rareza y partículas pixeladas
```

- **Motor local (por defecto)**: no necesita internet ni cuentas. Es la alternativa funcional siempre disponible.
- **IA remota + local**: si está configurada, la foto se manda al servicio de IA para obtener un render
  estilo videojuego y **después** se modela en 3D en el iPhone. Si falla (sin conexión, sin key, error del
  servicio), **se usa el motor local automáticamente** y se avisa en la revelación.

La malla se reconstruye al mostrar cada criatura a partir de su sprite (es determinista gracias a su
`seed`), así que la colección ocupa poco: `photo.jpg`, `sprite.png` y `thumb.png` por criatura.

---

## 4. Configurar la IA remota (opcional)

1. Consigue una API key de un servicio de edición de imágenes compatible con la API de OpenAI
   (`https://api.openai.com/v1/images/edits`, modelo `gpt-image-1` por defecto).
2. En la app: **Ajustes → Motor de generación → "IA remota + local"**.
3. Pega la key y pulsa **GUARDAR KEY** (se guarda cifrada en el Llavero, nunca en texto plano).
4. Opcional: cambia **Modelo** y **Endpoint** si usas otro modelo o un proxy compatible
   (petición `multipart/form-data` con `model`, `prompt`, `image`, `size`; respuesta `data[0].b64_json` o `data[0].url`).

El prompt (en `RemoteRenderService.swift`) solo pide redibujar *"el sujeto principal de la foto"* con estilo
low-poly de 1997 manteniendo colores y forma: **no pide identificar ni nombrar** nada.
El coste por imagen depende del proveedor.

---

## 5. Rarezas

| Rareza | Peso por defecto | Probabilidad |
|---|---|---|
| Común | 60 | 60 % |
| Poco común | 25 | 25 % |
| Raro | 10 | 10 % |
| Épico | 4 | 4 % |
| Legendario | 0,9 | 0,9 % (1 de 111) |
| Mítico | 0,1 | 0,1 % (1 de 1000) |

Se editan en **Ajustes → Probabilidades de rareza** (deslizadores logarítmicos para ajustar valores
pequeños, botón *Restablecer* y *Simular 1000* tiradas).

**Revelación**: la cápsula cae y se sacude (más sacudidas cuanto más rara); con cada sacudida el brillo
puede subir de color (blanco → verde → azul → morado → dorado → rosa), lo que crea suspense. Luego viene el
destello, rayos giratorios, confeti pixelado, sacudida de pantalla (épico o más), fanfarria chiptune
distinta por rareza, hápticos, estrellas una a una, y la criatura 3D entra de un salto. Toca la pantalla
para saltarte el suspense.

---

## 6. Funciones

- **Captura**: visor con HUD retro, flash, cambio de cámara, importar de Fotos, ubicación opcional.
- **Colección**: cuadrícula adaptable, filtros por rareza y favoritas, búsqueda (nombre, título,
  hábitat, etiquetas, nº), 5 órdenes, menú contextual, marcos animados para legendario y mítico.
- **Ficha**: visor 3D (arrastra para girar) / sprite / foto original, fecha y hora de captura, lugar y
  mapa, atributos de juego (VIT/FUE/AGI/ENC), ficha personal editable, favorita, compartir tarjeta, liberar (borrar).
- **Edición manual**: nombre, título/apodo, hábitat, notas y etiquetas. La rareza y la fecha no se
  editan porque son el registro del hallazgo.
- **Estadísticas**: % completado de **tu** colección (50 % rarezas descubiertas + 50 % fichas rellenadas),
  capturas, rachas, lugares, gráficas por rareza y por día, "tu suerte" frente a la probabilidad, récords.
- **Ajustes**: probabilidades, motor, resolución de textura, densidad de polígonos, sonido, hápticos,
  efecto CRT, pantalla de título, ubicación y borrar todo.

---

## 7. Estructura del código

```
DawiDawi/
├─ DawiDawi.xcodeproj
└─ DawiDawi/
   ├─ App/DawiDawiApp.swift          Entrada, contenedor SwiftData
   ├─ Models/                        Creature (@Model), Rarity, AppSettings, CollectionStats
   ├─ Generation/                    SubjectExtractor, RetroStylizer, MeshBuilder, RetroStage,
   │                                 RemoteRenderService, CreatureGenerator
   ├─ Capture/                       CaptureFlow (orquestador), CaptureView (cámara/HUD),
   │                                 GeneratingView, RevealView (+ cápsula, rayos, confeti)
   ├─ Collection/                    CollectionView, CreatureCard, CreatureDetailView, EditCreatureView
   ├─ Services/                      CameraModel, LocationProvider, ChipSynth (+ Haptics),
   │                                 CreatureStore (ficheros), Keychain
   ├─ UI/                            RootView (+ barra, título), StatsView, SettingsView,
   │                                 RetroStyle (paleta, paneles, botones, CRT), RetroSceneView
   └─ Assets.xcassets                Icono pixel-art y color de acento
```

## 8. Permisos

| Permiso | Cuándo se pide | Si se deniega |
|---|---|---|
| Cámara | Al abrir el modo captura por primera vez | Botón a Ajustes + importar desde Fotos |
| Ubicación (en uso) | Solo al activar "Guardar lugar de captura" | La criatura se guarda sin lugar |
| Fotos | Nunca (PhotosPicker no lo necesita) | — |

## 9. Notas

- Este proyecto se ha escrito sin poder compilarlo (en Windows). Si Xcode muestra algún error
  puntual de compilación, suele ser trivial de corregir; las APIs usadas son estándar de iOS 17.
- Rendimiento: el render 3D va a 30 fps y a ~0,8× de resolución interna, la malla tiene pocos
  triángulos y las texturas son diminutas, así que funciona bien incluso en iPhones antiguos con iOS 17.
