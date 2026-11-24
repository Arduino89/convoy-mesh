package com.example.convoy_mesh

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    @Test
    fun declaredNamesOnlyDecorateKnownPeersInTheDiscoverySession() {
        val session = WifiDirectSession("old")
        session.beginNameDiscovery()
        assertFalse(session.receiveDeclaredName("unknown", "Convoy"))
        assertEquals("peer-01", session.peerForAddress("first"))
        assertEquals("peer-02", session.peerForAddress("second"))
        assertTrue(session.receiveDeclaredName("first", "Nome Finto"))
        assertTrue(session.receiveDeclaredName("second", "Nome Finto"))
        assertEquals("Nome Finto", session.declaredNameForAddress("first"))
        assertEquals("first", session.addressForPeer("peer-01"))
        assertEquals("second", session.addressForPeer("peer-02"))
        assertFalse(session.receiveDeclaredName("first", "bad\u202ename"))
        assertNull(WifiDirectSession.cleanDeclaredName("192.168.1.1"))
        assertEquals("Nome Origi", WifiDirectSession.cleanDeclaredName("Nome Origine Lungo"))
        session.beginNameDiscovery()
        assertNull(session.declaredNameForAddress("first"))
        session.nameDiscoveryAllowed = false
        assertFalse(session.receiveDeclaredName("first", "Convoy"))
        session.invalidate()
        assertFalse(session.receiveDeclaredName("first", "Convoy"))
        val next = WifiDirectSession("new")
        next.beginNameDiscovery()
        assertEquals("peer-01", next.peerForAddress("first"))
        assertNull(next.declaredNameForAddress("first"))
    }
}
