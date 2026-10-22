package pro.nailu.client

import android.app.Application
import android.content.Context
import pro.nailu.client.common.GlobalState

class FlClashApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
