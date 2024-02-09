import unittest
from lambda_function import retrieve_data, increment_count, HTTP_OK 

class TestLambdaFunction(unittest.TestCase):
    def test_lambda_function(self):
        data = retrieve_data()

        self.assertEqual(data['statusCode'], HTTP_OK) 
        self.assertGreater(int(data['body']), 0)

        increment_count()
        incremented_data = retrieve_data()

        self.assertLess(int(data['body']), int(incremented_data['body']))

if __name__ == '__main__':
    unittest.main()