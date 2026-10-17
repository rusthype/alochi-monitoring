// A small in-memory pack + hub harness shared by the LAN tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/pack_loader.dart';

const lanSchool = '00000000-0000-4000-8000-0000000000b2';
const lanG1 = '00000000-0000-4000-8000-0000000000c1';
const lanG2 = '00000000-0000-4000-8000-0000000000c2';
const lanS1 = '00000000-0000-4000-8000-0000000000d1';
const lanS2 = '00000000-0000-4000-8000-0000000000d2';
const lanPackUuid = '00000000-0000-4000-8000-0000000000a1';

/// Bytes of the one media file; its SHA-256 names it (content addressed).
final Uint8List lanMediaBytes =
    Uint8List.fromList(List.generate(64, (i) => i + 1));

Map<String, dynamic> lanTest(String key,
        {List<String> groupIds = const [], String? mediaRef}) =>
    {
      'type': 'test',
      'key': key,
      'catalog': {
        'title': 'T $key',
        'grade': 5,
        'version': 3,
        'subject': 'english',
        'duration_minutes': 30,
        'runner_type': 'engine',
        'school_buttons': [],
        'group_ids': groupIds,
        'max_attempts': 1,
      },
      'data': {
        'test_key': key,
        'title': 'T $key',
        'grade': 5,
        'version': 3,
        'duration_minutes': 30,
        'variants': {
          '1': {
            'Vocabulary': [
              {
                'type': 'image_choice',
                if (mediaRef != null) 'img': mediaRef,
                'q': 'What?',
                'opts': ['a', 'b']
              }
            ]
          }
        },
      },
    };

LoadedPack lanTestPack({String? mediaRef}) => LoadedPack(
      manifest: PackManifest(
        formatVersion: 1,
        packUuid: lanPackUuid,
        schoolId: lanSchool,
        schoolCode: '999',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2099, 1, 1),
        kdfIter: 1,
        kdfSalt: Uint8List(16),
        files: const {},
      ),
      tests: [
        lanTest('t_all', mediaRef: mediaRef),
        lanTest('t_g1_only', groupIds: [lanG1]),
        {
          'type': 'package',
          'key': 'package:42:v1',
          'catalog': {
            'title': 'Pkg',
            'grade': 5,
            'math_count': 1,
            'eng_count': 1
          },
          'data': {
            'questions': [
              {
                'id': 'q1',
                'subject': 'math',
                'position': 1,
                'prompt': 'p',
                'options': ['x', 'y'],
              }
            ]
          },
        },
        {
          'type': 'diagnostic',
          'key': 'diag:math:g5:uz:v1',
          'catalog': {},
          'data': {
            'questions': [
              {
                'id': 'math-q1',
                'topic': 't',
                'level': 1,
                'question_text': '2+2?',
                'options': ['3', '4', '5', '6'],
                'image': '',
                'svg_visual': '',
              },
            ]
          },
        },
      ],
      groups: [
        {'id': lanG1, 'name': '5-A | Ingliz', 'grade': 5},
        {'id': lanG2, 'name': '6-B', 'grade': null},
      ],
      students: [
        {
          'id': lanS1,
          'code': 'A-0001',
          'name': 'Valiyev Ali',
          'group_id': lanG1
        },
        {
          'id': lanS2,
          'code': 'A-0002',
          'name': 'Karimova Zilola',
          'group_id': lanG2
        },
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

/// A syntactically valid result body for [student] on [testKey].
Map<String, dynamic> lanResultPayload(
        {String student = lanS1,
        String group = lanG1,
        String testKey = 't_all'}) =>
    {
      'name': 'Valiyev Ali',
      'grade': 5,
      'variant': '1',
      'source': 'flutter',
      'student_id': student,
      'group_id': group,
      'school_code': '999',
      'raw_answers': {'Vocabulary/0': 1},
      'detail': {'test_key': testKey},
    };

/// A temp dir with `media/` holding [lanMediaBytes] under its hash name.
Directory makeMediaDir(Directory parent, String sha256Hex) {
  final media = Directory('${parent.path}/media')..createSync(recursive: true);
  File('${media.path}/$sha256Hex.jpg').writeAsBytesSync(lanMediaBytes);
  return media;
}
