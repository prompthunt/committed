import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('appstore_apply', Path(__file__).with_name('appstore_apply.py'))
appstore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appstore)

METADATA = Path(__file__).resolve().parent.parent / 'appstore' / 'metadata'


def listing():
    return appstore.load_listing(METADATA)


class ListingFileTests(unittest.TestCase):
    """The repo's App Store listing fits Apple's limits before anything reaches App Store Connect."""

    def test_repo_listing_has_no_problems(self):
        self.assertEqual(appstore.listing_problems(listing()), [])

    def test_listing_points_at_the_site_pages(self):
        files = listing()
        self.assertEqual(files['app-info/en-US.json']['privacyPolicyUrl'], 'https://gitcommitted.app/privacy')
        self.assertEqual(files['version/1.0/en-US.json']['supportUrl'], 'https://gitcommitted.app/support')
        self.assertEqual(files['version/1.0/en-US.json']['marketingUrl'], 'https://gitcommitted.app')
        self.assertEqual(files['categories.json'], {'primaryCategory': 'DEVELOPER_TOOLS', 'secondaryCategory': 'PRODUCTIVITY'})

    def test_review_notes_send_the_reviewer_to_the_sample_board(self):
        review = listing()['review-information.json']
        self.assertIs(review['demoAccountRequired'], False)
        self.assertIn('Try a sample board', review['notes'].splitlines()[0])
        self.assertIn("GitHub's device flow", review['notes'])

    def test_contact_details_stay_out_of_the_public_repo(self):
        review = listing()['review-information.json']
        for field in ('contactFirstName', 'contactLastName', 'contactPhone', 'contactEmail'):
            self.assertNotIn(field, review)

    def test_every_age_rating_answer_is_none_or_false(self):
        answers = listing()['age-rating.json']
        self.assertEqual(len(answers), 27)  # 11 booleans, 13 frequencies, 3 overrides
        self.assertTrue(all(value in (False, 'NONE') for value in answers.values()))

    def test_limits_are_apples(self):
        cases = [
            ('app-info/en-US.json', 'subtitle', 'x' * 31, 'subtitle'),
            ('app-info/en-US.json', 'name', 'x' * 31, 'name'),
            ('version/1.0/en-US.json', 'keywords', 'é' * 51, 'keywords'),  # 51 characters, 102 bytes
            ('version/1.0/en-US.json', 'promotionalText', 'x' * 171, 'promotionalText'),
            ('version/1.0/en-US.json', 'description', 'x' * 4001, 'description'),
            ('review-information.json', 'notes', 'Try a sample board\n' + 'x' * 4000, 'notes'),
        ]
        for name, field, value, expected in cases:
            with self.subTest(field=field):
                files = copy.deepcopy(listing())
                files[name][field] = value
                self.assertIn(expected, ' '.join(appstore.listing_problems(files)))
        files = copy.deepcopy(listing())
        files['app-info/en-US.json']['subtitle'] = 'x' * 30
        files['version/1.0/en-US.json']['keywords'] = 'x' * 100
        self.assertEqual(appstore.listing_problems(files), [])

    def test_keywords_are_a_comma_list_without_spaces_or_repeats(self):
        for keywords in ('rank, team', 'rank,,team', 'rank,team,rank'):
            with self.subTest(keywords=keywords):
                files = copy.deepcopy(listing())
                files['version/1.0/en-US.json']['keywords'] = keywords
                self.assertIn('keywords', ' '.join(appstore.listing_problems(files)))

    def test_copy_avoids_words_the_glossary_rules_out(self):
        for phrase in ('demo account', 'Guest mode', 'Sign in with GitHub', 'log in'):
            with self.subTest(phrase=phrase):
                files = copy.deepcopy(listing())
                files['version/1.0/en-US.json']['description'] += ' ' + phrase
                self.assertIn('glossary', ' '.join(appstore.listing_problems(files)))

    def test_listing_text_has_no_email_address(self):
        files = copy.deepcopy(listing())
        files['version/1.0/en-US.json']['description'] += ' Write to someone@example.com.'
        self.assertIn('email', ' '.join(appstore.listing_problems(files)))


class ReviewContactTests(unittest.TestCase):
    """The App Review contact is the one already on the app's TestFlight beta review details."""

    def test_contact_comes_from_the_beta_review_details(self):
        beta = {'data': [{'type': 'betaAppReviewDetails', 'attributes': {
            'contactFirstName': 'Ada', 'contactLastName': 'Lovelace', 'contactPhone': '+1 4085550100',
            'contactEmail': 'ada@example.com', 'notes': 'TestFlight notes', 'demoAccountRequired': False}}]}
        self.assertEqual(appstore.review_contact(beta), {
            'contactFirstName': 'Ada', 'contactLastName': 'Lovelace',
            'contactPhone': '+1 4085550100', 'contactEmail': 'ada@example.com'})

    def test_missing_contact_is_an_error(self):
        beta = {'data': [{'attributes': {'contactFirstName': 'Ada', 'contactPhone': None}}]}
        with self.assertRaises(SystemExit):
            appstore.review_contact(beta)


if __name__ == '__main__':
    unittest.main()
