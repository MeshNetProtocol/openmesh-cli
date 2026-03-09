package com.meshnetprotocol.android.vpn

import android.content.Context
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import android.util.Log
import androidx.annotation.RequiresApi
import libbox.ExchangeContext
import libbox.LocalDNSTransport
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.runBlocking
import java.net.InetAddress
import java.net.UnknownHostException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlin.coroutines.suspendCoroutine

object LocalResolver : LocalDNSTransport {

    var appContext: Context? = null
    private const val TAG = "LocalResolver"
    private const val RCODE_NXDOMAIN = 3

    override fun raw(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    private fun requireNetwork(): Network? {
        return OpenMeshDefaultNetworkMonitor.currentOrSelect(appContext)
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: ExchangeContext, message: ByteArray) {
        return runBlocking {
            Log.d(TAG, "exchange started")
            val defaultNetwork = requireNetwork()
            if (defaultNetwork == null) {
                Log.e(TAG, "exchange failed: no network")
                ctx.errorCode(RCODE_NXDOMAIN)
                return@runBlocking
            }
            try {
                suspendCoroutine { continuation ->
                    val signal = CancellationSignal()
                    ctx.onCancel { signal.cancel() }
                    val callback = object : DnsResolver.Callback<ByteArray> {
                        override fun onAnswer(answer: ByteArray, rcode: Int) {
                            Log.d(TAG, "exchange onAnswer rcode=$rcode")
                            if (rcode == 0) {
                                ctx.rawSuccess(answer)
                            } else {
                                ctx.errorCode(rcode)
                            }
                            continuation.resume(Unit)
                        }

                        override fun onError(error: DnsResolver.DnsException) {
                            Log.e(TAG, "exchange onError: ${error.message}")
                            when (val cause = error.cause) {
                                is ErrnoException -> {
                                    ctx.errnoCode(cause.errno)
                                    continuation.resume(Unit)
                                    return
                                }
                            }
                            continuation.resumeWithException(error)
                        }
                    }
                    DnsResolver.getInstance().rawQuery(
                        defaultNetwork,
                        message,
                        DnsResolver.FLAG_NO_RETRY,
                        Dispatchers.IO.asExecutor(),
                        signal,
                        callback
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "exchange exception: ${e.message}")
                ctx.errorCode(RCODE_NXDOMAIN)
            }
        }
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) {
        return runBlocking {
            Log.d(TAG, "lookup domain=$domain network=$network")
            val defaultNetwork = requireNetwork()
            if (defaultNetwork == null) {
                Log.e(TAG, "lookup failed: no network")
                ctx.errorCode(RCODE_NXDOMAIN)
                return@runBlocking
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    suspendCoroutine { continuation ->
                        val signal = CancellationSignal()
                        ctx.onCancel { signal.cancel() }
                        val callback = object : DnsResolver.Callback<Collection<InetAddress>> {
                            override fun onAnswer(answer: Collection<InetAddress>, rcode: Int) {
                                Log.d(TAG, "lookup onAnswer domain=$domain rcode=$rcode")
                                if (rcode == 0) {
                                    ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
                                } else {
                                    ctx.errorCode(rcode)
                                }
                                continuation.resume(Unit)
                            }

                            override fun onError(error: DnsResolver.DnsException) {
                                Log.e(TAG, "lookup onError domain=$domain: ${error.message}")
                                when (val cause = error.cause) {
                                    is ErrnoException -> {
                                        ctx.errnoCode(cause.errno)
                                        continuation.resume(Unit)
                                        return
                                    }
                                }
                                continuation.resumeWithException(error)
                            }
                        }
                        val type = when {
                            network.endsWith("4") -> DnsResolver.TYPE_A
                            network.endsWith("6") -> DnsResolver.TYPE_AAAA
                            else -> null
                        }
                        if (type != null) {
                            DnsResolver.getInstance().query(
                                defaultNetwork,
                                domain,
                                type,
                                DnsResolver.FLAG_NO_RETRY,
                                Dispatchers.IO.asExecutor(),
                                signal,
                                callback
                            )
                        } else {
                            DnsResolver.getInstance().query(
                                defaultNetwork,
                                domain,
                                DnsResolver.FLAG_NO_RETRY,
                                Dispatchers.IO.asExecutor(),
                                signal,
                                callback
                            )
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "lookup exception domain=$domain: ${e.message}")
                    ctx.errorCode(RCODE_NXDOMAIN)
                }
            } else {
                val answer = try {
                    defaultNetwork.getAllByName(domain)
                } catch (e: UnknownHostException) {
                    Log.e(TAG, "lookup native failed for domain=$domain")
                    ctx.errorCode(RCODE_NXDOMAIN)
                    return@runBlocking
                }
                Log.d(TAG, "lookup native success for domain=$domain")
                ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
            }
        }
    }
}
