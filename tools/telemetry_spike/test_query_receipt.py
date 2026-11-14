import unittest

from query_receipt import COLUMNS, normalize


class QueryReceiptControls(unittest.TestCase):
    def receipt(self, rows):
        return {'results': '|'.join(COLUMNS) + '\n' + '\n'.join(rows)}

    row = '1.0|synthetic-query|synthetic-query-000001|1.0|cm_lab_probe|True|True'

    def test_duplicates_survive_normalization(self):
        rows = normalize(self.receipt([self.row, self.row]))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], rows[1])

    def test_cap_is_not_silently_treated_as_complete(self):
        with self.assertRaises(ValueError):
            normalize(self.receipt([self.row] * 500))

    def test_fractional_id_is_not_rounded(self):
        with self.assertRaises(ValueError):
            normalize(self.receipt([self.row.replace('|1.0|cm_', '|1.5|cm_')]))

    def test_privacy_control_must_be_true(self):
        with self.assertRaises(ValueError):
            normalize(self.receipt([self.row.removesuffix('True') + 'False']))

    def test_provider_warning_requires_inspection(self):
        with self.assertRaises(ValueError):
            normalize({'results': '<taxonomy_warnings>missing property</taxonomy_warnings>'})


if __name__ == '__main__':
    unittest.main()
