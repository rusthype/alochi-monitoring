// test/engine/test_spec_parse_test.dart
// Parses real prod fixture (math_diag_3_4) and asserts structural invariants.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';

TestSpec _loadFixture() {
  final file = File('test/fixtures/math_diag_3_4.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return TestSpec.fromJson(json);
}

void main() {
  late TestSpec spec;

  setUpAll(() {
    spec = _loadFixture();
  });

  group('TestSpec.fromJson — math_diag_3_4', () {
    test('parses without exception', () {
      // setUpAll already proves this; explicit assert for clarity
      expect(spec.testKey, isNotEmpty);
    });

    test('testKey is math_diag_3_4', () {
      expect(spec.testKey, 'math_diag_3_4');
    });

    test('grade is 3 or 4', () {
      expect(spec.grade, anyOf(3, 4));
    });

    test('has exactly 30 variants', () {
      expect(spec.variants.length, 30);
    });

    test('has 4 parts', () {
      expect(spec.parts.length, 4);
    });

    test('parts include expected bob names', () {
      for (final p in spec.parts) {
        expect(p, contains('bob'));
      }
    });
  });

  group('Per-variant question counts', () {
    test('every variant has exactly 30 questions', () {
      for (final varKey in spec.variants.keys) {
        final sections = spec.sectionsForVariant(varKey);
        final total = sections.fold(0, (s, sec) => s + sec.questionCount);
        expect(total, 30,
            reason: 'variant $varKey should have 30 questions, got $total');
      }
    });

    test('every variant has exactly 4 sections (matching parts)', () {
      for (final varKey in spec.variants.keys) {
        final sections = spec.sectionsForVariant(varKey);
        expect(sections.length, 4,
            reason: 'variant $varKey should have 4 sections');
      }
    });
  });

  group('Question type checks — variant "1"', () {
    late List<SectionData> sections;

    setUpAll(() {
      sections = spec.sectionsForVariant('1');
    });

    test(
        'all questions are text_choice (math_diag uses only text_choice + fill_blank)',
        () {
      int textChoice = 0;
      int fillBlank = 0;
      int other = 0;
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.type == QuestionType.textChoice) {
            textChoice++;
          } else if (q.type == QuestionType.fillBlank) {
            fillBlank++;
          } else {
            other++;
          }
        }
      }
      // At least 29 text_choice; fill_blank acceptable too
      expect(textChoice + fillBlank, 30);
      expect(other, 0, reason: 'no unexpected question types');
    });

    test('text_choice questions have at least 2 opts', () {
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.type == QuestionType.textChoice) {
            expect(q.opts.length, greaterThanOrEqualTo(2),
                reason: 'text_choice question "${q.q}" must have >= 2 opts');
          }
        }
      }
    });

    test('text_choice ans is in 0..3 range', () {
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.type == QuestionType.textChoice) {
            expect(q.ans, inInclusiveRange(0, 3),
                reason: 'text_choice ans out of range for "${q.q}"');
          }
        }
      }
    });

    test('fill_blank questions have non-empty strAns', () {
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.type == QuestionType.fillBlank) {
            expect(q.strAns, isNotNull);
            expect(q.strAns, isNotEmpty);
          }
        }
      }
    });

    test('variant "1" has at least 7 SVG questions', () {
      int svgCount = 0;
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.svg != null && q.svg!.isNotEmpty) svgCount++;
        }
      }
      expect(svgCount, greaterThanOrEqualTo(7));
    });

    test('SVG strings start with <svg', () {
      for (final sec in sections) {
        for (final q in sec.questions) {
          if (q.svg != null && q.svg!.isNotEmpty) {
            expect(q.svg!.trimLeft(), startsWith('<svg'),
                reason: 'svg field should be raw SVG markup');
          }
        }
      }
    });
  });

  group('SVG presence across all variants', () {
    test('every variant has at least 7 SVG questions', () {
      for (final varKey in spec.variants.keys) {
        final sections = spec.sectionsForVariant(varKey);
        int svgCount = 0;
        for (final sec in sections) {
          for (final q in sec.questions) {
            if (q.svg != null && q.svg!.isNotEmpty) svgCount++;
          }
        }
        expect(svgCount, greaterThanOrEqualTo(7),
            reason: 'variant $varKey has only $svgCount SVG questions');
      }
    });
  });
}
