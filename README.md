# 🎵 NovaMusic (`v1.0.0+33`)

Aplicación multiplataforma de música personal (**Android**, **Aplicación Nativa de Escritorio Windows** y **Web**) sincronizada en tiempo real con **Supabase**.

---

## 💻 Cómo restaurar todo después de formatear tu Laptop

### Opción 1: Descargar la App de PC y el APK listos para usar (Sin instalar Flutter)
En la sección [**Releases (`v1.0.0+33`)**](https://github.com/AngelGuevara04/NovaMusic/releases/tag/v1.0.0+33) de este repositorio están respaldados los instaladores listos para abrir:
1. **`NovaMusic-PC-Escritorio-v1.0.0+33.zip`**: Descomprímelo en tu computadora y abre **`NovaMusic.exe`** (no requiere instalar nada adicional).
2. **`NovaMusic-v1.0.0+33.apk`**: Instalador directo para tu celular Android.

### Opción 2: Clonar el proyecto completo en el Escritorio
```powershell
cd "$env:USERPROFILE\Desktop"
git clone https://github.com/AngelGuevara04/NovaMusic.git "App Musica Personal"
cd "App Musica Personal"
```
- Para volver a crear el icono de **NovaMusic** en tu Escritorio ejecuta:
  ```powershell
  powershell -ExecutionPolicy Bypass -File .\Crear-Acceso-Directo-Escritorio.ps1
  ```
- Si descargaste `NovaMusic-PC-Escritorio-v1.0.0+33.zip` desde Releases, descomprime su contenido dentro de `Instaladores\PC\NovaMusic-App\`.

---

## ✨ Características Principales (`v1.0.0+33`)
- **Modo Descubrimiento Inteligente (`Descubrir ✨`)**: Recomienda y pre-descarga música nueva basada en tus artistas y canciones descargadas, con botones interactivos **`❤️ Me gusta (Guardar)`** y **`✕ Quitar`** directamente en la notificación del celular y dentro de la app.
- **Masterización de Estudio 320 kbps + Recorte de Silencios**: Elimina automáticamente el silencio inicial y final de las canciones descargadas.
- **Sincronización y Cambio de Salida de Audio entre Dispositivos**: Intercala la reproducción entre tu Celular y tu PC continuando exactamente en la canción y segundo en que iba el otro dispositivo.
- **Respaldo en la Nube (Supabase)**: Inicio de sesión con usuario y contraseña, recuperación por PIN o verificación de biblioteca, y sincronización de canciones, favoritas y listas de reproducción.
