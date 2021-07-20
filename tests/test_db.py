import unittest, sys, os

sys.path.append(os.path.dirname(__file__)+'/..')

import library

library.DBFILE = os.path.dirname(__file__)+'/test.db'
library.DBSCHEMA = os.path.dirname(__file__)+'/../library.sql'


class TestDb(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        if os.path.isfile(library.DBFILE):
            os.remove(library.DBFILE)
        library.init(library.DBSCHEMA, library.DBFILE)

    @classmethod
    def tearDownClass(cls):
        library.done()
        os.remove(library.DBFILE)

    def test_01_empty(self):
        self.assertEqual(library.get_role(""), "")

    def test_02_unknown(self):
        self.assertEqual(library.get_role("xxx"), "")

    def test_03_admin(self):
        self.assertEqual(library.get_role("admin"), "admin")

    def test_04_reader(self):
        library.new_user("reader")
        self.assertEqual(library.get_role("reader"), "reader")


if __name__ == '__main__':
    unittest.main()
