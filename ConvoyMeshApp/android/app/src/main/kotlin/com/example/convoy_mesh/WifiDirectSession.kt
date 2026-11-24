package com.example.convoy_mesh

/** Main-looper scope shared by Android callbacks and deferred Flutter events. */
internal class WifiDirectSession(val id: String) {
    var isActive = true
        private set

    private val addressToPeer = linkedMapOf<String, String>()
    private val peerToAddress = linkedMapOf<String, String>()
    private val declaredNames = mutableMapOf<String, String>()
    var wasGroupFormed = false
    var nameDiscoveryAllowed = false
    var nameQueryStarted = false
    var nameDiscoveryRevision = 0
        private set
    var advertisementRevision = 0
    var requestedName: String? = null

    fun beginNameDiscovery() {
        nameDiscoveryRevision++
        nameDiscoveryAllowed = true
        nameQueryStarted = false
        declaredNames.clear()
    }

    fun receiveDeclaredName(address: String, name: String?): Boolean {
        if (!isActive || !nameDiscoveryAllowed || address !in addressToPeer) return false
        val clean = cleanDeclaredName(name) ?: return false
        return declaredNames.put(address, clean) != clean
    }

    fun declaredNameForAddress(address: String): String? = declaredNames[address]

    companion object {
        fun cleanDeclaredName(value: String?): String? {
            // Keep the Convoy limit of ten code points, with a narrower radio
            // alphabet that excludes control characters and address syntax.
            if (value == null || value.length > 64) return null
            val trimmed = value.trim()
            if (trimmed.startsWith("DIRECT-", ignoreCase = true) ||
                Regex("(?i)^(?:[0-9a-f]{2}-){5}[0-9a-f]{2}$").matches(trimmed)
            ) return null
            val clean = StringBuilder()
            val codePoints = trimmed.codePoints().iterator()
            var length = 0
            while (codePoints.hasNext()) {
                val cp = codePoints.nextInt()
                if (!Character.isLetterOrDigit(cp) && cp != 32 && cp != 45 && cp != 39) return null
                if (++length <= 10) clean.appendCodePoint(cp)
            }
            return clean.toString().trim().takeIf { it.isNotEmpty() }
        }
    }

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
        declaredNames.clear()
        requestedName = null
        nameDiscoveryAllowed = false
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
