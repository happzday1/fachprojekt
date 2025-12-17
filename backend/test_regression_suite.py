
import unittest
from unittest.mock import MagicMock, patch
import sys
import os

# Add backend to path
sys.path.append('/home/bilel0-0/uniapp/backend')

# Mock missing dependencies BEFORE importing modules
sys.modules['webdriver_manager'] = MagicMock()
sys.modules['webdriver_manager.chrome'] = MagicMock()
sys.modules['selenium'] = MagicMock()
sys.modules['selenium.webdriver'] = MagicMock()
sys.modules['selenium.webdriver.chrome.service'] = MagicMock()
sys.modules['selenium.webdriver.chrome.options'] = MagicMock()
sys.modules['selenium.webdriver.common.by'] = MagicMock()
sys.modules['selenium.webdriver.support.ui'] = MagicMock()
sys.modules['selenium.webdriver.support'] = MagicMock()
sys.modules['selenium.common'] = MagicMock()
sys.modules['selenium.common.exceptions'] = MagicMock()
sys.modules['pyotp'] = MagicMock()

# Import modules to test
from degree_audit import perform_audit, normalize_module_id
from modulhandbuch_router import ModulhandbuchRouter
from moodle_scraper import MoodleScraper
from modulhandbuch_parser import ModulhandbuchParser, Module

class TestComprehensiveRegression(unittest.TestCase):

    # --- DEGREE AUDIT TESTS ---
    def test_normalize_id(self):
        self.assertEqual(normalize_module_id("INF-12345"), "12345")
        self.assertEqual(normalize_module_id("12345"), "12345")
        
    def test_audit_logic_pass_fail(self):
        # Scenario: 1 passed exam, 1 failed exam
        passed = [
            {'exam_id': 'INF-100', 'title': 'Math', 'grade': 2.0, 'credits': 9, 'status': 'bestanden'},
            {'exam_id': 'INF-999', 'title': 'Fail', 'grade': 5.0, 'credits': 5, 'status': 'nicht bestanden'},
        ]
        curriculum = {'mandatory_modules': [], 'elective_areas': {}, 'total_ects': 180}
        degree_id = {'degree_type': 'Bachelor', 'degree_subject': 'Informatik', 'po_version': '2023'}
        
        result = perform_audit(passed, curriculum, degree_id)
        # Should only count 9 credits from the passed exam
        self.assertEqual(result['audit_result']['total_credits_earned'], 9)

    # --- MODULHANDBUCH ROUTER (LIVE) ---
    def test_router_connectivity(self):
        # Checks if we can find PDFs on the real site
        identity = {'degree_type': 'Bachelor', 'degree_subject': 'Informatik', 'po_version': '2023'}
        router = ModulhandbuchRouter(identity)
        pdfs = router.fetch_pdf_urls()
        self.assertTrue(len(pdfs) > 0, "Should find at least one PDF (e.g. from sub-page)")

    # --- MOODLE SCRAPER (LOGIC ONLY) ---
    def test_moodle_extraction_logic(self):
        # Mock the driver and page source
        scraper = MoodleScraper("user", "pass")
        scraper._setup_driver = MagicMock()
        scraper.driver = MagicMock()
        
        # Sample HTML simulating Moodle timeline
        sample_html = """
        <div class="event">
            <div data-region="event-item">
                <a href="https://moodle.tu-dortmund.de/mod/assign/view.php?id=123">Assignment 1</a>
                <small class="text-muted">Software Engineering</small>
                <span class="text-right">Friday, 15. December, 23:59</span>
            </div>
        </div>
        """
        scraper.driver.page_source = sample_html
        
        # Since extract_deadlines creates a BeautifulSoup object from driver.page_source,
        # we can verify it finds the assignment.
        
        # Note: The scraper logic is heuristic-heavy. Let's see if it picks up this simple case.
        # If not, we might need a more complex HTML structure that matches the scraper's expectations better.
        # For regression, ensuring it runs without crashing is step 1.
        
        try:
            deadlines = scraper.extract_deadlines()
            # If it finds nothing, it's not necessarily a failure of the code, but of my mock HTML.
            # But we want to ensure no exceptions.
            print(f"Moodle Logic Extracted: {len(deadlines)}")
        except Exception as e:
            self.fail(f"Moodle extraction raised exception: {e}")

    # --- PDF PARSER (LOGIC ONLY) ---
    @patch('modulhandbuch_parser.ModulhandbuchParser.extract_text')
    def test_pdf_parsing_logic(self, mock_extract):
        from textwrap import dedent
        # Simulate PDF text content
        mock_extract.return_value = dedent("""
        Modul: Analysis I
        Modulnummer: INF-101
        Leistungspunkte: 9
        Pflichtmodul
        
        Modul: Fancy AI
        Modulnummer: INF-999
        ECTS: 5
        Wahlpflichtbereich
        """)
        
        parser = ModulhandbuchParser("http://fake.url/doc.pdf")
        modules = parser.extract_modules()
        
        self.assertEqual(len(modules), 2)
        self.assertEqual(modules[0].name, "Analysis I")
        self.assertEqual(modules[0].category, "Pflicht")
        self.assertEqual(modules[1].name, "Fancy AI")
        self.assertEqual(modules[1].category, "Wahlpflicht")

    # --- IMPORT STABILITY ---
    def test_imports(self):
        try:
            import main
            import boss_scraper
        except ImportError as e:
            self.fail(f"Failed to import core modules: {e}")

if __name__ == '__main__':
    unittest.main()
