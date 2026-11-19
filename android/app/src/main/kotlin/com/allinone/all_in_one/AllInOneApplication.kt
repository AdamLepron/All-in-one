package com.allinone.all_in_one

import android.app.Application

class AllInOneApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NativeCrash.install(this)
    }
}
