import unittest
import sys, os, threading
import json, re

from http.server import HTTPServer
from http.client import HTTPConnection

sys.path.append(os.path.dirname(__file__)+'/..')

import library

library.DBFILE = os.path.dirname(__file__)+'/test.db'
library.DBSCHEMA = os.path.dirname(__file__)+'/../library.sql'
library.PAGEROOT = os.path.dirname(__file__)+'/../pages'
library.HTTPPORT = os.getenv('TEST_HTTPPORT', 9999)
library.DEBUG = os.getenv('TEST_DEBUG', 0)


class TestApi(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        if os.path.isfile(library.DBFILE):
            os.remove(library.DBFILE)
        cls.httpd = HTTPServer(("", library.HTTPPORT), library.Handler)
        cls.thread = threading.Thread(target=lambda: (library.init(
            library.DBSCHEMA, library.DBFILE), cls.httpd.serve_forever(), library.done()))
        cls.thread.start()
        cls.conn = HTTPConnection("localhost", library.HTTPPORT)

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()
        cls.httpd.shutdown()
        cls.httpd.server_close()
        cls.thread.join()
        os.remove(library.DBFILE)

    def get(self, path, user=None):
        self.conn.request("GET", path, None, {
                          "Cookie": f"libraryuser={user}"} if user else {})
        resp = self.conn.getresponse()
        return str(resp.status) + " " + resp.reason + "\n" + resp.read().decode()

    # request translates "" to "/"
    # def test_01_invalid(self):
    #     self.assertRegex(self.get("", "xxx"), '^500 .*\nbad request$')

    def test_02_invalid(self):
        self.assertRegex(self.get("bla", "admin"), '^500 .*\nbad request$')

    def test_03_invalid(self):
        self.assertRegex(self.get("/bla", "admin"), '^500 .*\nbad request$')

    def test_04_getuser(self):
        self.assertRegex(self.get("/getuser&bla", "admin"),
                         '^500 .*\nbad request$')

    def test_05_getuser(self):
        self.assertRegex(self.get("/getuser", "admin"),
                         '^200 OK\n{"name":"admin","role":"admin","state":"active"}$')

    def test_06_getusers(self):
        self.assertRegex(self.get("/getusers", "admin"),
                         '^200 OK\n\[{"name":"admin","role":"admin","state":"active"}\]$')

    def test_07_getusers(self):
        self.assertRegex(self.get("/getusers?name=admin", "admin"),
                         '^200 OK\n\[{"name":"admin","role":"admin","state":"active"}\]$')

    def test_08_getusers(self):
        self.assertRegex(self.get("/getusers?role=admin", "admin"),
                         '^200 OK\n\[{"name":"admin","role":"admin","state":"active"}\]$')

    def test_09_newuser(self):
        self.assertRegex(
            self.get("/getuser", "reader"),
            '^200 OK\n{"name":"reader","role":"reader","state":"active"}$')

    def test_10_getusers(self):
        self.assertRegex(
            self.get("/getusers?name=reader", "admin"),
            '^200 OK\n\[{"name":"reader","role":"reader","state":"active"}\]$')

    def test_11_blockuser(self):
        self.assertRegex(
            self.get("/setreader?name=reader&state=blocked", "admin"),
            '^200 ',
            "setreader")
        self.assertRegex(
            self.get("/getusers?name=reader", "admin"),
            '^200 OK\n\[{"name":"reader","role":"reader","state":"blocked"}\]$',
            "getusers")

    def test_12_unblockuser(self):
        self.assertRegex(
            self.get("/setreader?name=reader&state=active", "admin"),
            '^200 ',
            "setreader")
        self.assertRegex(
            self.get("/getusers?name=reader", "admin"),
            '^200 OK\n\[{"name":"reader","role":"reader","state":"active"}\]$',
            "getusers")
            
    def test_13_addlibrarian(self):
        self.assertRegex(
            self.get("/addlibrarian?name=librarian", "admin"),
            '^200 ',
            "addlibrarian")
        self.assertRegex(
            self.get("/getusers?name=librarian", "admin"),
            '^200 OK\n\[{"name":"librarian","role":"librarian","state":"active"}\]$',
            "getusers")

    def test_14_newlibrarian(self):
        self.assertRegex(
            self.get("/addlibrarian?name=yyy", "admin"),
            '^200 OK\n.*"name":"yyy"',
            "addlibrarian")
        self.assertRegex(
            self.get("/dellibrarian?name=yyy", "admin"),
            '^200 OK\n.*"name":"yyy"',
            "dellibrarian")
        self.assertRegex(
            self.get("/getusers?name=yyy", "admin"),
            '^200 OK\n\[\]$',
            "getusers")

    def test_15_getbooks(self):
        self.assertRegex(
            self.get("/getbooks", "admin"),
            '^200 OK\n\[\]$')

    def test_16_setbookerror(self):
        self.assertRegex(
            self.get("/setbook", "admin"),
            '^500 .*\nno data$')

    def test_17_setbook(self):
        self.assertRegex(
            self.get("/setbook?title=t&author=a", "admin"),
            '^200 OK\n{.*"id":1.*}$',
            "setbook")
        self.assertRegex(
            self.get("/getbooks", "admin"),
            '^200 OK\n\[{"id":1,"title":"t","author":"a","publisher":null,"published":null,"inuse":0}\]$',
            "getbooks")

    def test_18_setbook(self):
        self.assertRegex(
            self.get("/getbooks?id=1", "admin"),
            '^200 OK\n\[{"id":1,"title":"t","author":"a","publisher":null,"published":null,"inuse":0}\]$')

    def test_19_setbook(self):
        self.assertRegex(
            self.get("/setbook?id=1&title=T&author=A", "admin"),
            '^200 OK\n{.*"id":1.*}$',
            "setbook")
        self.assertRegex(
            self.get("/getbooks?id=1", "admin"),
            '^200 OK\n\[{"id":1,"title":"T","author":"A","publisher":null,"published":null,"inuse":0}\]$',
            "getbooks")

    def test_20_setbook(self):
        self.assertRegex(
            self.get("/setbook?title=t&author=a&publisher=p&published=2001-01-01", "admin"),
            '^200 OK\n.*"title":"t","author":"a","publisher":"p","published":"2001-01-01"',
            "setbook")
        self.assertRegex(
            self.get("/getbooks?title=t&author=a&publisher=p&published=2001-01-01", "admin"),
            '^200 OK\n.*"title":"t","author":"a","publisher":"p","published":"2001-01-01"',
            "getbooks")

    def test_21_setbook(self):
        s = self.get("/setbook?title=x&author=y", "admin")
        self.assertRegex(
            s,
            '^200 OK\n.*"id":.*,"title":"x","author":"y"',
            "addbook")
        j = json.loads(re.sub('^200 OK\n', '', s))
        self.assertRegex(
            self.get("/getbooks?id=%s" % j["id"], "admin"),
            '^200 OK\n.*"title":"x","author":"y"',
            "getbooks one")
        self.assertRegex(
            self.get("/delbook?id=%s" % j["id"], "admin"),
            '^200 OK\n.*"title":"x","author":"y"',
            "delbook")
        self.assertRegex(
            self.get("/getbooks?id=%s" % j["id"], "admin"),
            '^200 OK\n\[\]',
            "getbooks none")

    def test_22_setbookcyr(self):
        self.assertRegex(
            self.get("/setbook?title=%D0%B9&author=%D1%86", "admin"),
            '^200 OK\n.*"title":"й","author":"ц"',
            "addbook cyr")
        self.assertRegex(
            self.get("/getbooks?title=%D0%B9&author=%D1%86", "admin"),
            '^200 OK\n.*"title":"й","author":"ц"',
            "getbook cyr")

    def test_23_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?title=nonexistant", "admin"),
            '^200 OK\n\[\]')

    def test_24_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?title=nonexistant", "librarian"),
            '^200 OK\n\[\]')

    def test_25_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?title=nonexistant", "reader"),
            '^200 OK\n\[\]')

    def test_26_querybooks(self):
        self.assertRegex(
            self.get("/querybooks", "admin"),
            '^200 OK\n.*"title":"T","author":"A".*"title":"t","author":"a"')

    def test_27_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?title=T", "admin"),
            '^200 OK\n\[{"title":"T","author":"A","publisher":null,"published":null}\]$')

    def test_28_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?author=a", "admin"),
            '^200 OK\n\[{"title":"t","author":"a","publisher":"p","published":"2001-01-01"}\]$')

    def test_29_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?order=title", "admin"),
            '^200 OK\n\[{"title":"T",.*},{"title":"t",.*},{"title":"й",.*}\]$')

    def test_30_querybooks(self):
        self.assertRegex(
            self.get("/querybooks?order=title&reverse=1", "admin"),
            '^200 OK\n\[{"title":"й",.*},{"title":"t",.*},{"title":"T",.*}\]$')

    def test_31_addrequest(self):
        self.assertRegex(
            self.get("/addrequest", "reader"),
            '^500 .*\nno data$')

    def test_32_addrequest(self):
        self.assertRegex(
            self.get("/addrequest?author=a", "reader"),
            '^500 .*\nNOT NULL constraint failed: request.title$')

    def test_33_addrequest(self):
        self.assertRegex(
            self.get("/addrequest?title=t&author=a", "reader"),
            '^200 OK\n.*"id":1')
        self.assertRegex(
            self.get("/getrequests?title=t&author=a", "reader"),
            '^200 OK\n\[{"id":1,"bookid":null,"readername":"reader","title":"t","author":"a","publisher":null,"published":null,"returnterm":null,"returned":null,"state":"requested"}\]')

    def test_34_setrequest(self):
        self.assertRegex(
            self.get("/setrequest?id=1&bookid=1", "librarian"),
            '^200 OK\n.*"id":1')
        self.assertRegex(
            self.get("/getrequests?id=1", "librarian"),
            '^200 OK\n\[{"id":1,"bookid":1,"readername":"reader","title":"t","author":"a","publisher":null,"published":null,"returnterm":null,"returned":null,"state":"reading"}\]')

    def test_35_bookinuse(self):
        self.assertRegex(
            self.get("/getbooks?id=1", "admin"),
            '^200 OK\n\[{"id":1,.*,"inuse":1}\]$')

    def test_36_bookinuse(self):
        self.assertRegex(
            self.get("/getbooks?inuse=1", "admin"),
            '^200 OK\n\[{"id":1,.*,"inuse":1}\]$')

    def test_37_bookinuse(self):
        self.assertRegex(
            self.get("/getbooks?inuse=0", "admin"),
            '^200 OK\n\[{"id":2,.*},{"id":3,.*}\]$')

    def test_38_bookinuse(self):
        self.assertRegex(
            self.get("/delbook?id=1", "admin"),
            '^500 .*\nFOREIGN KEY constraint failed$')

    def test_39_delrequest(self):
        self.assertRegex(
            self.get("/delrequest?id=1", "reader"),
            '^500 .*\nwrong state$')

    def test_40_closerequest(self):
        self.assertRegex(
            self.get("/closerequest?id=1", "librarian"),
            '^200 OK\n.*"id":1',
            "closerequest")
        self.assertRegex(
            self.get("/getrequests?id=1", "librarian"),
            '^200 OK\n\[{"id":1,"bookid":null,"readername":"reader","title":"t","author":"a","publisher":null,"published":null,"returnterm":null,"returned":"....-..-..","state":"returned"}\]',
            "getrequest")

    def test_41delrequest(self):
        s = self.get("/addrequest?title=t&author=a", "reader")
        self.assertRegex(
            s,
            '^200 OK\n.*"id":',
            "addrequest")
        j = json.loads(re.sub('^200 OK\n', '', s))
        self.assertRegex(
            self.get("/getrequests?state=requested", "reader"),
            '^200 OK\n\[{"id":%s,"bookid":null,"readername":"reader","title":"t","author":"a","publisher":null,"published":null,"returnterm":null,"returned":null,"state":"requested"}\]' % j["id"],
            "getrequest new")
        self.assertRegex(
            self.get("/delrequest?id=%s" % j["id"], "reader"),
            '^200 OK\n.*"id":%s' % j["id"],
            "delrequest")
        self.assertRegex(
            self.get("/getrequests?state=requested", "reader"),
            '^200 OK\n\[\]',
            "getrequest none")


if __name__ == '__main__':
    unittest.main()
