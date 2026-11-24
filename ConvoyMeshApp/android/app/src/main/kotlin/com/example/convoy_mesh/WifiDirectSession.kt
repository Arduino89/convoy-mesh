package com.example.convoy_mesh

/** Main-looper scope shared by Android callbacks and deferred Flutter events. */
internal class WifiDirectSession(val id: String) {
    var isActive = true
        private set

    private val addressToPeer = linkedMapOf<String, String>()
    private val peerToAddress = linkedMapOf<String, String>()
    private val declaredNames = mutableMapOf<String, String>()
    private val pendingNames = linkedMapOf<String, String>()
    private var txtReceived = 0
    private var domainMatched = 0
    private var mapped = 0
    var wasGroupFormed = false
    var nameDiscoveryAllowed = false
    var nameQueryStarted = false
    var nameDiscoveryRevision = 0
        private set
    var advertisementRevision = 0
    var requestedName: String? = null

    fun beginNameDiscovery(clearNames: Boolean = true) {
        nameDiscoveryRevision++
        nameDiscoveryAllowed = true
        nameQueryStarted = false
        txtReceived = 0
        domainMatched = 0
        mapped = 0
        pendingNames.clear()
        if (clearNames) declaredNames.clear()
    }

    enum class NameMapping(val wireName: String) {
        MAPPED("mapped"),
        UNCHANGED("unchanged"),
        WAITING_PEER("waiting_peer"),
        INVALID_LABEL("invalid_label"),
    }

    fun receiveDeclaredName(address: String, name: String?): Boolean =
        mapDeclaredName(address, name) == NameMapping.MAPPED

    fun mapDeclaredName(address: String, name: String?): NameMapping {
        if (!isActive || !nameDiscoveryAllowed || address.isBlank()) return NameMapping.INVALID_LABEL
        val clean = cleanDeclaredName(name) ?: return NameMapping.INVALID_LABEL
        if (address !in addressToPeer) {
            if (pendingNames.size < 32 || address in pendingNames) pendingNames[address] = clean
            return NameMapping.WAITING_PEER
        }
        return if (declaredNames.put(address, clean) != clean) NameMapping.MAPPED else NameMapping.UNCHANGED
    }

    fun countTxt(domainMatches: Boolean, mapping: NameMapping?): Map<String, Any?>? {
        txtReceived++
        if (domainMatches) domainMatched++
        if (mapping == NameMapping.MAPPED || mapping == NameMapping.UNCHANGED) mapped++
        // Bound exported diagnostics even if a nearby device floods TXT responses.
        if (txtReceived > 32) return null
        return mapOf(
            "txt_received" to txtReceived,
            "domain_matched" to domainMatched,
            "peer_mapped" to mapped,
            "mapping" to (mapping?.wireName ?: "other_domain"),
        )
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
            if (nameDiscoveryAllowed) pendingNames.remove(address)?.let { declaredNames[address] = it }
            id
        }
    }

    fun addressForPeer(peerId: String): String? = peerToAddress[peerId]

    fun invalidate() {
        pendingNames.clear()
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
