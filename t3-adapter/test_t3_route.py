import unittest
from t3_route import thread_url


class RouteTests(unittest.TestCase):
    def test_exact_ids_are_distinct_even_with_same_thread(self):
        for origin in ("http://127.0.0.1:3773", "https://[::1]:3773"):
            for env in ("e-one", "e_two"):
                self.assertEqual(thread_url("0.1.7", origin, env, "thread"), origin + "/threads/" + env + "/thread")

    def test_scope_is_fail_closed(self):
        for origin in ("https://app.t3.codes", "https://0.0.0.0:80", "http://localhost:80", "http://127.0.0.1:80.evil", "http://127.0.0.1:80@elsewhere", "http://127.0.0.1:80?token=", "http://127.0.0.1:80/private", "http://127.0.0.1:80#"):
            with self.subTest(origin=origin), self.assertRaises(ValueError):
                thread_url("0.1.7", origin, "env", "thread")
        for key in ("", "../foo", "slash/path", "encoded%2fpath", "thread?x", "한글"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                thread_url("0.1.7", "http://127.0.0.1:80", "env", key)
        with self.assertRaises(ValueError):
            thread_url("0.1.8", "http://127.0.0.1:80", "env", "thread")
