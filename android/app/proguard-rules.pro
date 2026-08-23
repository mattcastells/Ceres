# Reglas de R8 para el build de release.
#
# Flutter ya trae las suyas; acá solo van las de los plugins que usan
# reflexión. Si aparece un ClassNotFoundException en release y no en debug,
# el culpable casi siempre es una clase que R8 quitó: agregala acá.

# Motor de Flutter.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter referencia Play Core para "deferred components", que esta app no
# usa. Sin esto R8 corta el build por clases que nunca se van a ejecutar.
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# image_picker usa el proveedor de archivos de AndroidX.
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.lifecycle.** { *; }

# El widget de la pantalla de inicio. Es un BroadcastReceiver que el sistema
# instancia **por nombre** desde el manifest: ningún código de la app lo
# referencia, así que es exactamente el caso que R8 no puede ver. Sin esto el
# síntoma sería un widget que anda en debug y en release no se puede agregar.
-keep class io.ceres.ceres.CaloriesWidget { *; }

# No romper las anotaciones de nulabilidad que usan los plugins.
-keepattributes *Annotation*
-keepattributes Signature
