import unittest
from t3_route import native_thread_url


class NativeRouteTests(unittest.TestCase):
    def test_exact_ids_are_distinct_even_with_same_thread(self):
        self.assertEqual(native_thread_url("0.1.7", "env-A", "thread_1"),
                         "t3code://threads/env-A/thread_1")
        self.assertEqual(native_thread_url("0.1.7", "env_B", "thread_1"),
                         "t3code://threads/env_B/thread_1")

    def test_rejects_reserved_chars_in_both_segments(self):
        for value in ("", ".", "..", "a/b", "a?prompt=x", "a#b", "a%2Fb", "a@b",
                      "a\\b", "a:b", "a\n", "한글", "a" * 129, None):
            for env, thread in ((value, "thread"), ("env", value)):
                with self.subTest(env=env, thread=thread), self.assertRaises(ValueError):
                    native_thread_url("0.1.7", env, thread)

    def test_rejects_unverified_installed_versions(self):
        for version in ("0.1.6", "0.1.8", "0.1.7-beta"):
            with self.assertRaises(ValueError):
                native_thread_url(version, "env", "thread")
