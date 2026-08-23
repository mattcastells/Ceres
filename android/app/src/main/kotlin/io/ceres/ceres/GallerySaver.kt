package io.ceres.ceres

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import java.io.IOException

/**
 * Guarda una foto de la app en la galería del teléfono.
 *
 * Se hace con `MediaStore` y no con un plugin porque así **no hace falta ningún
 * permiso**: desde Android 10 una app puede insertar en la galería lo que ella
 * misma produjo sin pedir acceso al almacenamiento. Eso importa acá más que la
 * comodidad: el manifest saca a propósito los permisos de lectura de fotos,
 * videos y audio (`tools:node="remove"`), y pedir `WRITE_EXTERNAL_STORAGE` para
 * bajar una imagen contradiría lo que la pantalla de Privacidad promete.
 *
 * Antes de Android 10 no hay forma de escribir en la galería sin ese permiso,
 * así que ahí devuelve `unsupported` y la app ofrece compartir la foto, que
 * llega al mismo lugar por la puerta que ya está abierta.
 */
object GallerySaver {

    const val CHANNEL = "io.ceres.app/gallery"

    /** El álbum propio evita mezclar las fotos de comida con el carrete. */
    private const val ALBUM = "Ceres"
    private const val JPEG = "image/jpeg"

    fun canSave(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun save(context: Context, bytes: ByteArray, fileName: String): String =
        if (canSave()) insert(context, bytes, fileName) else "unsupported"

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insert(context: Context, bytes: ByteArray, fileName: String): String {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, JPEG)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/" + ALBUM,
            )
            // Mientras esté pendiente, la galería no la muestra: nadie ve una
            // foto a medio escribir.
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }

        val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: return "insert_failed"

        return try {
            val stream = resolver.openOutputStream(uri)
                ?: throw IOException("MediaStore no devolvió dónde escribir.")
            stream.use {
                it.write(bytes)
                it.flush()
            }
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            "ok"
        } catch (_: Exception) {
            // Una entrada a medias en la galería es peor que ninguna: queda una
            // foto rota que nadie sabe de dónde salió.
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
                // Si tampoco se puede borrar, sigue pendiente y la galería no
                // la muestra.
            }
            "write_failed"
        }
    }
}
