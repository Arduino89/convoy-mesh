package com.example.convoy_mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WifiDirectSessionTest {
    @Test
    fun invalidatedSessionDropsQueuedEventsAndCannotRecreateAliases() {
        val old = WifiDirectSession("old")
        val queue = mutableListOf<Runnable>()
        val delivered = mutableListOf<String>()

        assertEquals("peer-01", old.peerForAddress("first"))
        old.post(queue::add) { delivered.add("old ready") }
        queue.removeAt(0).run()
        old.post(queue::add) { delivered.add("old queued group") }

        old.invalidate()
        assertNull(old.peerForAddress("late"))
        assertNull(old.addressForPeer("peer-01"))
        old.post(queue::add) { delivered.add("old late disconnect") }

        val current = WifiDirectSession("new")
        assertEquals("peer-01", current.peerForAddress("second"))
        assertNull(old.peerForAddress("later"))
        assertEquals("second", current.addressForPeer("peer-01"))
        current.post(queue::add) { delivered.add("new group") }
        queue.forEach(Runnable::run)

        assertEquals(listOf("old ready", "new group"), delivered)
    }
}
