import unittest, sys, os

sys.path.append(os.path.dirname(__file__)+'/..')

import library


class TestUtils(unittest.TestCase):

    # def test_01_parse_path(self):
    #     for i in [
    #         ["/",         ('/',  {})],
    #         ["/X",        ('/X', {})],
    #         ["/&",        ('/&', {})],
    #         ["/?",        ('/',  {})],
    #         ["/?&",       ('/',  {})],
    #         ["/?X",       ('/',  {})],
    #         ["/?X& ",     ('/',  {})],
    #         ["/?X=",      ('/',  {})],
    #         ["/?X=x",     ('/',  {'X': ['x']})],
    #         ["/?X=x&",    ('/',  {'X': ['x']})],
    #         ["/?X=x&Y=y", ('/',  {'X': ['x'], 'Y': ['y']})],
    #     ]:
    #         print(i[0])
    #         self.assertEqual(library.parse_path(
    #             i[0]), i[1], f"{i[0]} => {i[1]}")

    def test_02_parse_user(self):
        for i in [
            ["",       ""],
            ["X",      "X"],
            ["+",      " "],
            ["%20",    " "],
            ["%2B",    "+"],
            ["%2b",    "+"],
            ["%D0%B9", "й"],
            ["X+%D0%B9%2b%d1%86", "X й+ц"],
        ]:
            self.assertEqual(library.parse_user(i[0]), i[1])


if __name__ == '__main__':
    unittest.main()
