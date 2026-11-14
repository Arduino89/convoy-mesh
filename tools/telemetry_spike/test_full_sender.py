"""Real HTTP fixture compatibility and unchanged independent privacy oracle."""
import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from ci_full_sender import FixtureReceiver, OkReceiver, OK
from test_wire_audit_receiver import payload, RUN
from wire_audit_receiver import AuditReceiver

class HTTPFixtureTests(unittest.TestCase):
    def request(self, cls, body, kind=None):
        with tempfile.TemporaryDirectory() as tmp:
            observer=(cls(Path(tmp)/'wire',RUN,kind,port=0) if kind else cls(Path(tmp)/'wire',RUN,port=0))
            thread=threading.Thread(target=observer.server.serve_forever,kwargs={'poll_interval':.01});thread.start()
            try:
                c=http.client.HTTPConnection('127.0.0.1',observer.server.server_port,timeout=3)
                c.request('POST','/batch/',json.dumps(body),{'Content-Type':'application/json','Accept-Encoding':'identity'})
                response=c.getresponse(); data=response.read(); c.close()
                audit=json.loads((Path(tmp)/'wire/summary.json').read_text())
                return response.status,data,audit
            finally:
                observer.server.shutdown(); observer.close();thread.join(3)

    def test_actual_http_response_hook_preserves_original_and_finite_fixtures(self):
        self.assertEqual(self.request(AuditReceiver,payload())[1],b'{"status":1}')
        self.assertEqual(self.request(OkReceiver,payload())[1],OK)
        for kind,expected in FixtureReceiver.BODIES.items():
            if kind == "truncated": continue
            with self.subTest(kind=kind):
                status,body,audit=self.request(FixtureReceiver,payload(),kind)
                self.assertEqual((status,body),(200,expected)); self.assertEqual(audit['audit_status'],'PASS')

    def test_ok_response_cannot_turn_invalid_identity_into_privacy_pass(self):
        body=payload();body['batch'][0]['distinct_id']='11111111-2222-4333-8444-555555555555'
        status,_,audit=self.request(OkReceiver,body)
        self.assertEqual(status,200); self.assertEqual(audit['audit_status'],'FAIL')

    def test_truncated_http200_closes_before_declared_body_length(self):
        with self.assertRaises(http.client.IncompleteRead):
            self.request(FixtureReceiver,payload(),'truncated')
