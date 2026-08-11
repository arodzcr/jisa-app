# Calculador de Fletes JISA — App Android

App interna de JISA para cotizar fletes de equipo de construcción.

**Distrito + Fecha + Hora = Precio del flete.**

---

## Qué es este proyecto

Una cáscara Android que ejecuta el calculador dentro de un WebView. El motor de
reglas, la base de 183 distritos del GAM, el catálogo territorial de Costa Rica
y toda la interfaz viven en un único archivo: `assets/www/index.html`.

Se hizo así a propósito. Ese archivo ya está verificado con 61 pruebas del motor
y 23 de interfaz. Reescribirlo en Dart habría significado empezar la validación
desde cero sin ganar nada para el usuario final.

```
lib/main.dart              Cáscara: WebView + puente nativo
assets/www/index.html      La app completa (motor, datos, interfaz)
.github/workflows/         Compilación automática del APK
```

## El puente nativo

El HTML detecta si corre dentro del APK (`window.JisaBridge`) y en ese caso
delega tres cosas en Android:

| Acción | Para qué |
|---|---|
| `saveFile` | Guardar el Excel y abrir el selector para compartirlo |
| `pickFile` | Escoger el Excel a importar |
| `httpPost` | Consultar OpenRouteService sin restricciones de origen |

En el navegador el puente no existe y la app usa las APIs web de siempre. El
mismo archivo funciona en los dos entornos.

## Compilar el APK

### Con GitHub Actions (recomendado, no instala nada)

1. Suba el contenido de esta carpeta a un repositorio.
2. El workflow corre solo. Si no aparece, cree
   `.github/workflows/build-apk.yml` desde la web de GitHub y pegue el
   contenido de ese archivo.
3. **Actions → último build → Artifacts → `calculador-fletes-jisa-apk`**.

### En su computadora

```bash
flutter create --platforms=android --org cr.jisa --project-name jisa_fletes .
flutter pub get
flutter build apk --release
```

APK resultante: `build/app/outputs/flutter-apk/app-release.apk`

> `flutter create` solo agrega la carpeta `android/`. No toca `lib/` ni `assets/`.
> Después de generarla, verifique que el manifiesto tenga el permiso de INTERNET
> (el workflow lo inserta automáticamente).

## Actualizar el calculador

Reemplace `assets/www/index.html` y vuelva a compilar. No hay que tocar Dart.

## Notas

- El APK se firma con la llave de depuración de Flutter. Sirve para uso interno;
  para Google Play habría que generar una llave propia.
- Los datos se guardan en el almacenamiento local del WebView. Se carga con un
  origen propio (`https://calculador.jisa.local/`) en vez de `file://` para que
  esa persistencia sea confiable.
- PIN inicial de configuración: **1975**.

---

*"El equipo correcto. En el momento correcto. Sin complicaciones."*
