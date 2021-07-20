import unittest, sys, os

sys.path.append(os.path.dirname(__file__))

import test_utils, test_db, test_api, test_www

loader = unittest.TestLoader()
suite  = unittest.TestSuite()

suite.addTests(loader.loadTestsFromModule(test_utils))
suite.addTests(loader.loadTestsFromModule(test_db))
suite.addTests(loader.loadTestsFromModule(test_api))
suite.addTests(loader.loadTestsFromModule(test_www))

runner = unittest.TextTestRunner(verbosity=2)
result = runner.run(suite)