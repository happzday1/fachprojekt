"""
Comprehensive Test Script for Backend Modules
Tests: boss_scraper.py, modulhandbuch_router.py, modulhandbuch_parser.py, degree_audit.py
"""

import logging
import json
import sys
from datetime import datetime

# Configure logging at the start
logging.basicConfig(
    level=logging.INFO, 
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def print_separator(title):
    print("\n" + "="*70)
    print(f"  {title}")
    print("="*70 + "\n")

def test_boss_scraper(username, password):
    """Test the BOSS scraper module."""
    print_separator("TEST 1: BOSS SCRAPER")
    
    try:
        from boss_scraper import BossScraper
        
        print(f"Username: {username}")
        print(f"Testing BOSS scraper... (this may take a minute)")
        
        scraper = BossScraper(username, password)
        result = scraper.get_data()
        
        if "error" in result:
            print(f"❌ BOSS Scraper Error: {result['error']}")
            return None
        
        print(f"✅ BOSS Scraper Success!")
        print(f"\n--- Degree Identity ---")
        degree_identity = result.get('degree_identity', {})
        for key, value in degree_identity.items():
            print(f"  {key}: {value}")
        
        print(f"\n--- Summary ---")
        summary = result.get('summary', {})
        print(f"  Total Credits: {summary.get('total_credits', 'N/A')}")
        print(f"  Current GPA: {summary.get('current_gpa', 'N/A')}")
        
        exams = result.get('exams', [])
        print(f"\n--- Exams ({len(exams)} total) ---")
        
        # Show first 10 exams
        for i, exam in enumerate(exams[:10]):
            grade_str = f"{exam.get('grade', 'N/A')}" if exam.get('grade') else "N/A"
            print(f"  {i+1}. {exam.get('title', 'Unknown')[:50]}")
            print(f"     Grade: {grade_str} | Credits: {exam.get('credits', 0)} | Status: {exam.get('status', 'N/A')}")
        
        if len(exams) > 10:
            print(f"  ... and {len(exams) - 10} more exams")
        
        return result
        
    except ImportError as e:
        print(f"❌ Import Error: {e}")
        return None
    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_modulhandbuch_router(degree_identity):
    """Test the Modulhandbuch router module."""
    print_separator("TEST 2: MODULHANDBUCH ROUTER")
    
    try:
        from modulhandbuch_router import get_modulhandbuch_for_degree, ModulhandbuchRouter
        
        if not degree_identity:
            # Use default test data
            degree_identity = {
                'degree_type': 'Bachelor',
                'degree_subject': 'Angewandte Informatik',
                'po_version': '2023'
            }
            print("Using default test degree identity (no BOSS data available)")
        
        print(f"Degree Type: {degree_identity.get('degree_type', 'Unknown')}")
        print(f"Degree Subject: {degree_identity.get('degree_subject', 'Unknown')}")
        print(f"PO Version: {degree_identity.get('po_version', 'Unknown')}")
        
        # Test routing
        router = ModulhandbuchRouter(degree_identity)
        print(f"\nNormalized Subject: {router.normalized_subject}")
        print(f"Page URL: {router.get_modulhandbuch_page_url()}")
        
        # Test full lookup
        print("\nFetching PDF URLs...")
        result = get_modulhandbuch_for_degree(degree_identity)
        
        if result.get('success'):
            print(f"✅ Router Success!")
            print(f"\n--- PDF List ({len(result.get('pdf_list', []))} found) ---")
            for pdf in result.get('pdf_list', []):
                match_str = "✓ PO Match" if pdf.get('po_match') else ""
                print(f"  • {pdf.get('name', 'Unknown')} {match_str}")
                print(f"    URL: {pdf.get('url', 'N/A')[:80]}...")
            
            print(f"\n--- Best PDF URL ---")
            print(f"  {result.get('pdf_url', 'None')}")
        else:
            print(f"⚠️ No PDFs found (this may be expected for some degrees)")
        
        return result
        
    except ImportError as e:
        print(f"❌ Import Error: {e}")
        return None
    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_modulhandbuch_parser(pdf_url=None):
    """Test the Modulhandbuch parser module."""
    print_separator("TEST 3: MODULHANDBUCH PARSER")
    
    try:
        from modulhandbuch_parser import parse_modulhandbuch, PDFPLUMBER_AVAILABLE
        
        print(f"pdfplumber available: {PDFPLUMBER_AVAILABLE}")
        
        if not PDFPLUMBER_AVAILABLE:
            print("⚠️ pdfplumber not installed - parser will not work")
            return None
        
        if not pdf_url:
            # Use a test PDF URL (example TU Dortmund CS Modulhandbuch)
            pdf_url = "https://cs.tu-dortmund.de/storages/cs-nups/r/Studium/Modulhandbucher/Modulhandbuch_BSc_Angewandte_Informatik.pdf"
            print(f"Using test PDF URL: {pdf_url[:60]}...")
        else:
            print(f"Using PDF URL from router: {pdf_url[:60]}...")
        
        print("\nParsing PDF (this may take a moment)...")
        result = parse_modulhandbuch(pdf_url)
        
        if result.get('error'):
            print(f"⚠️ Parser returned error: {result.get('error')}")
            return result
        
        print(f"✅ Parser Success!")
        
        mandatory = result.get('mandatory_modules', [])
        elective_areas = result.get('elective_areas', {})
        
        print(f"\n--- Mandatory Modules ({len(mandatory)} found) ---")
        for i, mod in enumerate(mandatory[:5]):
            print(f"  {i+1}. [{mod.get('module_id', 'N/A')}] {mod.get('name', 'Unknown')[:40]}")
            print(f"     ECTS: {mod.get('ects', 0)} | Category: {mod.get('category', 'N/A')}")
        
        if len(mandatory) > 5:
            print(f"  ... and {len(mandatory) - 5} more modules")
        
        print(f"\n--- Elective Areas ({len(elective_areas)} areas) ---")
        for area, ects in elective_areas.items():
            print(f"  • {area}: {ects} ECTS")
        
        print(f"\n--- Total ECTS: {result.get('total_ects', 'N/A')} ---")
        
        return result
        
    except ImportError as e:
        print(f"❌ Import Error: {e}")
        return None
    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_degree_audit(boss_data, curriculum):
    """Test the degree audit module."""
    print_separator("TEST 4: DEGREE AUDIT")
    
    try:
        from degree_audit import perform_audit, quick_audit
        
        if not boss_data or not boss_data.get('exams'):
            print("No BOSS data available - using mock data for testing")
            # Mock data
            passed_exams = [
                {'title': 'Test Module 1', 'exam_id': 'INF-001', 'grade': 2.0, 'credits': 6, 'status': 'bestanden'},
                {'title': 'Test Module 2', 'exam_id': 'INF-002', 'grade': 1.7, 'credits': 9, 'status': 'bestanden'},
                {'title': 'Test Module 3', 'exam_id': 'INF-003', 'grade': 2.3, 'credits': 6, 'status': 'bestanden'},
            ]
            degree_identity = {'degree_type': 'Bachelor', 'degree_subject': 'Informatik', 'po_version': '2023'}
        else:
            passed_exams = boss_data.get('exams', [])
            degree_identity = boss_data.get('degree_identity', {})
        
        print(f"Passed Exams Count: {len(passed_exams)}")
        print(f"Degree: {degree_identity.get('degree_type', 'Unknown')} {degree_identity.get('degree_subject', 'Unknown')}")
        
        # Test quick audit (without PDF parsing)
        print("\n--- Quick Audit (without curriculum PDF) ---")
        quick_result = quick_audit(passed_exams, degree_identity)
        
        audit = quick_result.get('audit_result', {})
        print(f"  Status: {audit.get('status', 'Unknown')}")
        print(f"  Progress: {audit.get('progress_percentage', 0)}%")
        print(f"  Credits Earned: {audit.get('total_credits_earned', 0)} / {audit.get('total_credits_required', 0)}")
        print(f"  Missing Mandatory: {len(audit.get('missing_mandatory', []))} modules")
        
        # Test full audit with curriculum (if available)
        if curriculum and not curriculum.get('error'):
            print("\n--- Full Audit (with curriculum PDF) ---")
            full_result = perform_audit(passed_exams, curriculum, degree_identity)
            
            audit = full_result.get('audit_result', {})
            print(f"  Status: {audit.get('status', 'Unknown')}")
            print(f"  Progress: {audit.get('progress_percentage', 0)}%")
            print(f"  Credits Earned: {audit.get('total_credits_earned', 0)} / {audit.get('total_credits_required', 0)}")
            
            missing = audit.get('missing_mandatory', [])
            print(f"\n  Missing Mandatory Modules ({len(missing)}):")
            for i, mod in enumerate(missing[:5]):
                print(f"    {i+1}. [{mod.get('module_id', 'N/A')}] {mod.get('name', 'Unknown')[:40]} ({mod.get('ects', 0)} ECTS)")
            
            if len(missing) > 5:
                print(f"    ... and {len(missing) - 5} more")
            
            return full_result
        else:
            print("\n  (Skipping full audit - no valid curriculum data)")
        
        print(f"\n✅ Degree Audit Test Complete!")
        return quick_result
        
    except ImportError as e:
        print(f"❌ Import Error: {e}")
        return None
    except Exception as e:
        print(f"❌ Unexpected Error: {e}")
        import traceback
        traceback.print_exc()
        return None

def main():
    print("\n" + "#"*70)
    print("#" + " "*68 + "#")
    print("#   COMPREHENSIVE BACKEND MODULE TEST".ljust(69) + "#")
    print("#   Testing: boss_scraper, modulhandbuch_router, parser, degree_audit".ljust(69) + "#")
    print("#" + " "*68 + "#")
    print("#"*70)
    print(f"\nTest started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    # Credentials
    username = "smbiberr"
    password = "5Bil4123"
    
    # Track results
    results = {}
    
    # Test 1: BOSS Scraper
    boss_result = test_boss_scraper(username, password)
    results['boss_scraper'] = 'SUCCESS' if boss_result and 'error' not in boss_result else 'FAILED'
    
    # Extract degree identity for next tests
    degree_identity = boss_result.get('degree_identity') if boss_result else None
    
    # Test 2: Modulhandbuch Router
    router_result = test_modulhandbuch_router(degree_identity)
    results['modulhandbuch_router'] = 'SUCCESS' if router_result and router_result.get('success') else 'PARTIAL'
    
    # Get PDF URL for parser test
    pdf_url = router_result.get('pdf_url') if router_result else None
    
    # Test 3: Modulhandbuch Parser
    parser_result = test_modulhandbuch_parser(pdf_url)
    results['modulhandbuch_parser'] = 'SUCCESS' if parser_result and not parser_result.get('error') else 'FAILED'
    
    # Test 4: Degree Audit
    audit_result = test_degree_audit(boss_result, parser_result)
    results['degree_audit'] = 'SUCCESS' if audit_result else 'FAILED'
    
    # Summary
    print_separator("TEST SUMMARY")
    for module, status in results.items():
        icon = "✅" if status == 'SUCCESS' else ("⚠️" if status == 'PARTIAL' else "❌")
        print(f"  {icon} {module}: {status}")
    
    print(f"\nTest completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("\n" + "#"*70 + "\n")
    
    # Save results to JSON
    output = {
        'test_timestamp': datetime.now().isoformat(),
        'results_summary': results,
        'boss_data': boss_result,
        'router_data': router_result,
        'parser_data': parser_result,
        'audit_data': audit_result
    }
    
    with open('/home/bilel0-0/uniapp/backend/test_results.json', 'w') as f:
        json.dump(output, f, indent=2, default=str)
    
    print("📄 Full results saved to: test_results.json\n")

if __name__ == "__main__":
    main()
