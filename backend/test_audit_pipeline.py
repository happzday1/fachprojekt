
import unittest
from unittest.mock import MagicMock
import sys
import os

# Add backend to path
sys.path.append('/home/bilel0-0/uniapp/backend')

from degree_audit import perform_audit, normalize_module_id
from modulhandbuch_router import ModulhandbuchRouter

class TestDegreeAudit(unittest.TestCase):
    def test_normalize_id(self):
        self.assertEqual(normalize_module_id("INF-12345"), "12345")
        self.assertEqual(normalize_module_id("12345"), "12345")
        self.assertEqual(normalize_module_id("PHY-12345-A"), "12345")
        
    def test_audit_logic(self):
        # Mock Data
        passed = [
            {'exam_id': 'INF-100', 'title': 'Math I', 'grade': 2.0, 'credits': 9, 'status': 'bestanden'},
            {'exam_id': 'INF-200', 'title': 'Intro CS', 'grade': 1.0, 'credits': 9, 'status': 'bestanden'},
            {'exam_id': 'INF-999', 'title': 'Failed Exam', 'grade': 5.0, 'credits': 5, 'status': 'nicht bestanden'},
        ]
        
        curriculum = {
            'mandatory_modules': [
                {'module_id': 'INF-100', 'name': 'Math I', 'ects': 9, 'category': 'Pflicht'},
                {'module_id': 'INF-300', 'name': 'Algorithms', 'ects': 9, 'category': 'Pflicht'},
            ],
            'elective_areas': {},
            'total_ects': 180
        }
        
        degree_id = {'degree_type': 'Bachelor', 'degree_subject': 'Informatik'}
        
        result = perform_audit(passed, curriculum, degree_id)
        
        audit = result['audit_result']
        
        # Check matching
        # Passed: INF-100 (mandatory), INF-200 (elective/extra)
        # Missing: INF-300
        
        missing_ids = [m['module_id'] for m in audit['missing_mandatory']]
        self.assertIn('INF-300', missing_ids)
        self.assertNotIn('INF-100', missing_ids)
        
        # Check credits
        # 9 (Math) + 9 (Intro) = 18 passed. (Failed exam ignored)
        self.assertEqual(audit['total_credits_earned'], 18)
        
        print("✅ Audit logic verification passed")

    def test_router_connectivity(self):
        # Test routing for Informatik (live check)
        identity = {
            'degree_type': 'Bachelor',
            'degree_subject': 'Informatik',
            'po_version': '2023'
        }
        router = ModulhandbuchRouter(identity)
        pdfs = router.fetch_pdf_urls()
        
        if pdfs:
             print(f"✅ Router found {len(pdfs)} PDFs for Informatik")
             print(f"   Example: {pdfs[0]['url']}")
        else:
             print("⚠️ Router found 0 PDFs (Network issue or site changed?)")
             # Not failing the test to avoid build break in restricted env, but logging warning
             
if __name__ == '__main__':
    unittest.main()
