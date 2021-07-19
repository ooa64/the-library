import unittest, sys, os, threading

from http.server import HTTPServer
from http.client import HTTPConnection

sys.path.append(os.path.dirname(__file__)+'/..')

import library

library.DBFILE = os.path.dirname(__file__)+'/test.db'
library.DBSCHEMA = os.path.dirname(__file__)+'/../library.sql'
library.PAGEROOT = os.path.dirname(__file__)+'/../pages'
library.HTTPPORT = 9997


class TestWww(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.httpd = HTTPServer(("", library.HTTPPORT), library.Handler)
        cls.thread = threading.Thread(target = lambda: (library.init(library.DBSCHEMA,library.DBFILE), cls.httpd.serve_forever(), library.done()))
        cls.thread.start()
        cls.conn = HTTPConnection("localhost",library.HTTPPORT)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join()

    def getbody(self, path, user=None):
        self.conn.request("GET", path, None, {"Cookie": f"libraryuser={user}"} if user else {})
        return self.conn.getresponse().read().decode()

    def test_01_empty(self):
        self.assertRegex(self.getbody(""), ".*library login.*")

    def test_02_admin(self):
        self.assertRegex(self.getbody("","admin"), ".*library admin.*")


if __name__ == '__main__':
    unittest.main()
