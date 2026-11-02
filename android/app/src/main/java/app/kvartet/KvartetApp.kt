package app.kvartet

import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import androidx.core.graphics.drawable.toBitmap
import app.kvartet.data.Item
import app.kvartet.media.USER_AGENT
import app.kvartet.reminders.Reminders
import coil.ImageLoader
import coil.ImageLoaderFactory
import coil.imageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import okhttp3.OkHttpClient

class KvartetApp : Application(), ImageLoaderFactory {
    override fun onCreate() {
        super.onCreate()
        Kvartet.init(this)
        Reminders.createChannel(this)
        Reminders.reschedule(this)
    }

    /** Wikimedia просит представляться: загрузчик картинок отправляет свой User-Agent. */
    override fun newImageLoader(): ImageLoader = ImageLoader.Builder(this)
        .okHttpClient {
            OkHttpClient.Builder()
                .addInterceptor { chain ->
                    chain.proceed(chain.request().newBuilder().header("User-Agent", USER_AGENT).build())
                }
                .build()
        }
        .crossfade(true)
        .build()
}

/** Загрузка изображений рекомендаций (через кэш Coil). */
object Artwork {
    suspend fun prefetch(context: Context, items: List<Item>) {
        for (item in items) {
            val url = Kvartet.media.artworkUrl(item) ?: continue
            context.imageLoader.execute(ImageRequest.Builder(context).data(url).size(1200).build())
        }
    }

    /** Картинка для виджета: небольшая и без аппаратного буфера. */
    suspend fun bitmap(context: Context, item: Item, size: Int = 700): Bitmap? {
        val url = Kvartet.media.artworkUrl(item) ?: return null
        val request = ImageRequest.Builder(context).data(url).size(size).allowHardware(false).build()
        val result = context.imageLoader.execute(request)
        return (result as? SuccessResult)?.drawable?.toBitmap()
    }
}
