
import 'package:flutter_test/flutter_test.dart';
import 'package:app_client/models.dart';
import 'package:app_client/session_service.dart';

void main() {
  group('Regression Test - Session Data Serialization', () {
    test('DetailedGrade should preserve "passed" field in JSON roundtrip', () {
      // 1. Create original object with specific "passed" states
      final passedGrade = DetailedGrade(
        name: 'Passed Exam',
        grade: '1.3',
        ects: '6',
        passed: true,
      );

      final failedGrade = DetailedGrade(
        name: 'Failed Exam',
        grade: '5.0',
        ects: '0',
        passed: false,
      );

      // 2. Serialize to JSON
      final jsonPassed = passedGrade.toJson();
      final jsonFailed = failedGrade.toJson();

      // 3. Deserialize back
      final restoredPassed = DetailedGrade.fromJson(jsonPassed);
      final restoredFailed = DetailedGrade.fromJson(jsonFailed);

      // 4. Verify fields
      expect(restoredPassed.name, 'Passed Exam');
      expect(restoredPassed.passed, true);

      expect(restoredFailed.name, 'Failed Exam');
      expect(restoredFailed.passed, false);
    });

    test('SessionData should preserve detailed_grades and their passed status', () {
      final grades = [
        DetailedGrade(name: 'A', grade: '1.0', ects: '5', passed: true),
        DetailedGrade(name: 'B', grade: '5.0', ects: '0', passed: false),
      ];
      
      final session = SessionData(
        profileName: 'Test Student',
        ectsData: ECTSData(totalEcts: 5, coursesCount: 2),
        moodleDeadlines: [],
        examRequirements: [],
        currentClasses: [],
        detailedGrades: grades,
      );

      final json = session.toJson();
      final restored = SessionData.fromJson(json);

      expect(restored.detailedGrades.length, 2);
      expect(restored.detailedGrades[0].passed, true);
      expect(restored.detailedGrades[1].passed, false);
    });
    
    test('Legacy JSON without passed field should default to safe value', () {
        final json = {
          'name': 'Legacy Exam',
          'grade': '2.0',
          'ects': '5'
          // 'passed' is missing
        };
        
        final grade = DetailedGrade.fromJson(json);
        // We implemented it to default to false if missing, 
        // to be safe, or explicit check.
        // Let's check what we implemented.
        expect(grade.passed, false); 
    });
  });
}
