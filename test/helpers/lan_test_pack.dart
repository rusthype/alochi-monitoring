// A small in-memory pack + hub harness shared by the LAN tests.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:image/image.dart' as img;

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

/// Id of the i-th extra roster student (see `lanTestPack(extraStudents:)`).
String lanExtraStudent(int i) =>
    '00000000-0000-4000-8000-${(0x1000 + i).toRadixString(16).padLeft(12, '0')}';

LoadedPack lanTestPack(
        {String? mediaRef, int extraStudents = 0, int extraTests = 0}) =>
    LoadedPack(
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
        for (var i = 0; i < extraTests; i++) lanTest('t_extra_$i'),
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
        for (var i = 0; i < extraStudents; i++)
          {
            'id': lanExtraStudent(i),
            'code': 'X-$i',
            'name': 'Extra Student $i',
            'group_id': lanG1
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

final Uint8List _baseJpeg =
    Uint8List.fromList(img.encodeJpg(img.Image(width: 1, height: 1)));

/// A real (codec-parseable) JPEG whose SOF header claims [w]x[h]: a genuine
/// 1x1 baseline file with its frame header patched and a COM segment carrying
/// [marker] (so tests can search for it) inserted after SOI. The hub only
/// reads headers, so the pixels never matter -- but unlike a hand-made stub,
/// the platform codec accepts it, as the hub's codec check requires.
Uint8List lanJpeg({String marker = 'FRAMEMARKER', int w = 640, int h = 360}) {
  final out = Uint8List.fromList(_baseJpeg);
  var i = 2;
  while (i + 8 < out.length) {
    final m = out[i + 1];
    if (out[i] == 0xFF && m >= 0xC0 && m <= 0xC2) {
      out[i + 5] = h >> 8;
      out[i + 6] = h & 0xFF;
      out[i + 7] = w >> 8;
      out[i + 8] = w & 0xFF;
      break;
    }
    i += 2 + ((out[i + 2] << 8) | out[i + 3]);
  }
  final com = marker.codeUnits;
  return Uint8List.fromList([
    ...out.sublist(0, 2),
    0xFF, 0xFE, (com.length + 2) >> 8, (com.length + 2) & 0xFF, ...com, //
    ...out.sublist(2),
  ]);
}
