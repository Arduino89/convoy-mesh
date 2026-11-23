package com.example.convoy_mesh

/** Main-looper scope shared by Android callbacks and deferred Flutter events. */
internal class WifiDirectSession(val id: String) {
    var isActive = true
        private set

    private val addressToPeer = linkedMapOf<String, String>()
    private val peerToAddress = linkedMapOf<String, String>()
    var wasGroupFormed = false

    fun peerForAddress(address: String): String? {
        if (!isActive || address.isBlank()) return null
        return addressToPeer.getOrPut(address) {
            val id = "peer-${(addressToPeer.size + 1).toString().padStart(2, '0')}"
            peerToAddress[id] = address
            id
        }
    }

    fun addressForPeer(peerId: String): String? = peerToAddress[peerId]

    fun invalidate() {
        isActive = false
        wasGroupFormed = false
        addressToPeer.clear()
        peerToAddress.clear()
    }

    fun post(enqueue: (Runnable) -> Boolean, action: () -> Unit) {
        if (!isActive) return
        enqueue(Runnable {
            if (isActive) action()
        })
    }
}
