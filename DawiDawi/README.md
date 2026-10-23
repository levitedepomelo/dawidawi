# DawiDawi 🐾📼

App nativa de iOS (Swift + SwiftUI) para **coleccionar las criaturas que encuentras en la vida real**.
Haces una foto → la app la convierte en un **modelo 3D low-poly con estética PS1/N64** → recibe una
**rareza aleatoria** con una revelación espectacular → se guarda en **tu colección personal**.

La app **no identifica, no clasifica y no nombra** nada: la foto es solo la referencia visual del modelo.
No hay Pokédex ni catálogo de especies; tu colección es solo lo que tú fotografías.

---

## 1. Cómo conseguir la app (sin Mac)

Cada `git push` a `main` lanza **GitHub Actions → "DawiDawi CI"**, que en un Mac en la nube:
compila la app, la **ejecuta en un iPhone simulado** recorriendo todo el flujo y publica en la
pestaña *Actions → (última ejecución) → Artifacts*:

| Artefacto | Para qué |
|---|---|
| `DawiDawi-ipa` → `DawiDawi.ipa` | Instalarla en **tu iPhone** (Release, sin firmar) |
| `DawiDawi-simulator-appetize` → `DawiDawi-simulator.zip` | **Probarla en el navegador** desde Windows |
| `DawiDawi-screenshots` | Capturas de cada pantalla y vídeo de una revelación legendaria |

### A) Probarla en el navegador (Windows, sin iPhone)
1. Entra en **https://appetize.io/upload** (cuenta gratuita).
2. Sube `DawiDawi-simulator.zip` tal cual (plataforma iOS).
3. Abre el enlace que te da: es un iPhone simulado en el navegador. El simulador no tiene cámara,
   así que en *Capturar* usa el botón **Importar foto** (puedes arrastrar fotos a la galería del simulador).

### B) Instalarla en tu iPhone desde Windows (gratis, con tu Apple ID)
1. Instala **iTunes** (versión web de Apple, no la de Microsoft Store) y **Sideloadly** (https://sideloadly.io).
2. Conecta el iPhone por cable y pulsa "Confiar" en el iPhone.
3. Arrastra `DawiDawi.ipa` a Sideloadly, escribe tu Apple ID y pulsa **Start**.
   Sideloadly firma la app con tu cuenta (si da error de bundle ID, activa *Advanced → Change bundle ID*).
4. En el iPhone: **Ajustes → Privacidad y seguridad → Modo de desarrollador → Activar** (reinicia),
   y luego **Ajustes → General → VPN y gestión de dispositivos → tu Apple ID → Confiar**.
5. Abre DawiDawi. Con una Apple ID gratuita la firma dura **7 días**: después, repite el paso 3
   (tus criaturas se conservan). Con una cuenta de desarrollador de pago (99 €/año) dura 1 año.

### C) Con un Mac
Abre `DawiDawi/DawiDawi.xcodeproj` en Xcode 16 o posterior, elige tu *Team* en *Signing & Capabilities*
y pulsa **Run**. Requisitos: iOS 17.0 o posterior. No hace falta ningún paquete externo, solo frameworks de Apple.

---|---|
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
| Recortar al sujeto | **Vision** `VNGenerateForegroundInstanceMaskRequest` + segmentador propio por color | Separa figura/fondo **sin reconocer qué es**; si Vision no está disponible (simulador), modela el fondo desde los bordes de la foto |
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

Hay tres motores (**Ajustes → Motor de generación**). Todos producen un muñeco low-poly estilo PS1/N64
texturizado con la propia foto, sobre un escenario de cielo y césped:

| Motor | Qué hace | Necesita |
|---|---|---|
| **Local** (por defecto) | Recorta al animal (Vision o, si no está disponible, segmentación por color), analiza la **forma** de la silueta (alargada → cuadrúpedo; alta → muñeco erguido; apéndices arriba → orejas; lateral → cola) y arma un muñeco de bloques: cabeza con la cara de la foto, cuerpo, patas/brazos, orejas y cola animadas. | Nada (sin conexión) |
| **Escultor IA** | Claude (`claude-opus-5-5`) mira la foto y devuelve, como JSON validado por esquema, un muñeco de 6–20 piezas (cajas, cuñas, pirámides, cilindros, conos, esferas low-poly) con la **región de la foto** que texturiza cada pieza: la cara va al frente de la cabeza, el pelaje al cuerpo, el hocico, las orejas, las alas, el pico… Se guarda como `rig.json`. | API key de Anthropic |
| **IA imagen** | Un servicio de imagen redibuja la foto con estilo PS1 y después se modela en local. | API key compatible con `/v1/images/edits` |

Si un motor con IA falla (sin conexión, sin key, error del servicio), **se usa el motor local automáticamente**
y se avisa en la revelación. Ningún motor nombra ni clasifica al animal: solo se trabaja con formas y colores.

En **Ajustes → Gráficos** eliges **HD** (por defecto: texturas de la foto en alta resolución con
filtrado suave, bloques con bordes redondeados, extremidades en cápsula, render nativo con antialiasing 4x
a 60 fps) o **Retro** (texturas pixeladas, bloques duros y render 240p a 30 fps).

En **Ajustes → Estilo del modelo 3D** puedes elegir entre "Muñeco" (bloques, por defecto) y "Silueta"
(la silueta inflada, más orgánica). Por criatura se guardan `photo.jpg`, `sprite.png`, `thumb.png` y,
con el escultor, `rig.json`.

---

## 4. Configurar los motores con IA (opcional)

### Escultor IA (recomendado para los modelos más fieles)
1. Crea una API key en **console.anthropic.com → API Keys** (necesita saldo; cada criatura cuesta céntimos).
2. En la app: **Ajustes → Motor de generación → "Escultor IA"**, pega la key y pulsa **GUARDAR KEY**
   (se guarda cifrada en el Llavero del iPhone).
3. Captura: mientras la app recorta la foto, Claude diseña el muñeco (unos segundos). El prompt está en
   `Generation/SculptorService.swift` y el constructor en `Generation/RigBuilder.swift`.

### IA imagen
1. API key de un servicio compatible con `https://api.openai.com/v1/images/edits` (modelo `gpt-image-1` por defecto).
2. **Ajustes → Motor de generación → "IA imagen"**, pega la key y, si quieres, cambia **Modelo** y **Endpoint**.

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

- Se compila y se prueba en cada push con GitHub Actions (Xcode 26): un iPhone grande y el iPhone más
  pequeño disponible. El repositorio es público, así que los minutos de Mac de Actions son gratuitos.
  Los artefactos se guardan 3 días; el vídeo de la revelación solo se graba al lanzar el workflow a mano
  con la opción *record_video*.
- Modo demo (solo para CI): argumentos `-demoScene`, `-demoImages`, `-demoRarity` y `-demoRig` (ver `App/DemoMode.swift`).
  La CI renderiza un rig de ejemplo (`.github/demo/cat-rig.json`) para probar el escultor sin API key.
- Rendimiento: el render 3D va a 30 fps y a ~0,8× de resolución interna, la malla tiene pocos
  triángulos y las texturas son diminutas, así que funciona bien incluso en iPhones antiguos con iOS 17.
