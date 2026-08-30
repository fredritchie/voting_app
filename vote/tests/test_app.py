import pathlib
import sys
import unittest
from unittest.mock import MagicMock, patch


VOTE_DIRECTORY = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(VOTE_DIRECTORY))

import app as vote_app  # noqa: E402


class VoteApplicationTests(unittest.TestCase):
    def setUp(self):
        vote_app.app.config.update(TESTING=True)
        self.client = vote_app.app.test_client()

    def test_get_renders_voting_page_and_sets_voter_cookie(self):
        response = self.client.get("/")

        self.assertEqual(response.status_code, 200)
        self.assertIn(b"Cats", response.data)
        self.assertIn(b"Dogs", response.data)
        self.assertIn("voter_id=", response.headers["Set-Cookie"])

    def test_post_queues_vote_in_redis(self):
        redis = MagicMock()

        with patch.object(vote_app, "get_redis", return_value=redis):
            response = self.client.post("/", data={"vote": "a"})

        self.assertEqual(response.status_code, 200)
        redis.rpush.assert_called_once()
        queue, payload = redis.rpush.call_args.args
        self.assertEqual(queue, "votes")
        self.assertIn('"vote": "a"', payload)


if __name__ == "__main__":
    unittest.main()
