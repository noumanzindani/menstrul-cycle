import 'package:flutter_test/flutter_test.dart';
import 'package:menstrul_track/services/media_analysis.dart';

/// The pure layer of photo descriptions: request shape, response parsing, the
/// daily-cap arithmetic, and the safety strings.
///
/// None of this needs a network, which is the point of keeping it out of
/// `media_analyzer.dart` — see that file for why a real `HttpClient` call
/// inside `flutter_test` silently returns 400 rather than failing.
void main() {
  group('buildAnalysisRequest', () {
    final request = buildAnalysisRequest(
      base64Image: 'QUJD',
      mimeType: 'image/jpeg',
      question: 'what is this',
    );

    test('sends the image as snake_case inline_data', () {
      // REST spelling, not the SDK's camelCase `inlineData`. The API ignores
      // the wrong key silently and answers from the text alone, which looks
      // like a bad answer rather than an error — so this is pinned.
      final parts = (request['contents']! as List).first as Map;
      final first = (parts['parts']! as List).first as Map;
      expect(first.containsKey('inline_data'), isTrue);
      final inline = first['inline_data']! as Map;
      expect(inline['mime_type'], 'image/jpeg');
      expect(inline['data'], 'QUJD');
    });

    test('carries the question after the image', () {
      final parts = (request['contents']! as List).first as Map;
      final second = (parts['parts']! as List)[1] as Map;
      expect(second['text'], 'what is this');
    });

    test('disables thinking', () {
      // Not a preference. With thinking on, reasoning tokens are drawn from the
      // same allowance as the reply and a 400-token budget returned a sentence
      // cut off at 16 tokens. See kAnalysisThinkingBudget.
      final gen = request['generationConfig']! as Map;
      final thinking = gen['thinkingConfig']! as Map;
      expect(thinking['thinkingBudget'], 0);
      expect(kAnalysisThinkingBudget, 0);
    });

    test('sends the system instruction', () {
      final sys = request['systemInstruction']! as Map;
      final text = ((sys['parts']! as List).first as Map)['text'] as String;
      expect(text, kAnalysisSystemInstruction);
    });
  });

  group('buildAnalysisRequest, multi-turn', () {
    final request = buildAnalysisRequest(
      base64Image: 'QUJD',
      mimeType: 'image/jpeg',
      question: 'how many are there',
      history: const [
        AnalysisTurn.user('what colour is it'),
        AnalysisTurn.model('It is pink.'),
      ],
    );
    final contents = (request['contents']! as List).cast<Map<Object?, Object?>>();

    List<Object?> partsOf(int i) => contents[i]['parts']! as List<Object?>;

    test('sends the whole conversation, oldest first', () {
      // generateContent holds no session: a conversation IS the transcript,
      // resent every call. Drop this and every follow-up is a cold start.
      expect(contents.length, 3);
      expect(
        contents.map((c) => c['role']).toList(),
        ['user', 'model', 'user'],
      );
    });

    test("echoes the model's own reply back to it", () {
      expect((partsOf(1).first as Map)['text'], 'It is pink.');
    });

    test('puts the new question last', () {
      expect((partsOf(2).first as Map)['text'], 'how many are there');
    });

    test('attaches the image to the first turn and only that one', () {
      // The array is resent whole, so one copy is in context for every answer.
      // Repeating it per turn would bill several copies of the same picture in
      // a single request.
      expect((partsOf(0).first as Map).containsKey('inline_data'), isTrue);
      for (final part in [...partsOf(1), ...partsOf(2)]) {
        expect((part as Map).containsKey('inline_data'), isFalse);
      }
    });

    test('an opening question is still a user turn', () {
      final opening = buildAnalysisRequest(
        base64Image: 'QUJD',
        mimeType: 'image/jpeg',
        question: 'what is this',
      );
      final first = (opening['contents']! as List).first as Map;
      expect(first['role'], 'user');
    });

    test('the role strings are the ones the API defines', () {
      // enum .name is what is serialised, so a rename here is a wire change.
      expect(AnalysisRole.user.name, 'user');
      expect(AnalysisRole.model.name, 'model');
    });
  });

  group('kAnalysisSystemInstruction', () {
    // This string is the safety control that makes the feature shippable in a
    // health app. Each clause below was verified against a live model with a
    // deliberately bad question; losing one is a behaviour change, not a
    // wording change.
    test('forbids diagnosis, naming a condition, severity and treatment', () {
      final text = kAnalysisSystemInstruction.toLowerCase();
      expect(text, contains('never diagnose'));
      expect(text, contains('never name a condition'));
      expect(text, contains('never estimate severity'));
      expect(text, contains('never advise treatment'));
    });

    test('redirects to a professional rather than just refusing', () {
      expect(
        kAnalysisSystemInstruction.toLowerCase(),
        contains('healthcare professional'),
      );
    });

    test('asks for plain prose, because the sheet cannot render Markdown', () {
      // Device-found: the model answered a real photo in Markdown and the
      // result sheet, a SelectableText, showed literal `*   **On the left:**`.
      final text = kAnalysisSystemInstruction.toLowerCase();
      expect(text, contains('no markdown'));
      expect(text, contains('no bullet points'));
    });
  });

  group('kAnalysisCaveat', () {
    test('disclaims medical meaning', () {
      expect(kAnalysisCaveat.toLowerCase(), contains('not a medical opinion'));
    });

    test('claims nothing about safety or privacy', () {
      // The bytes are unencrypted in Cloud Storage AND sent to a third party.
      // Any reassuring adjective here would be a false claim.
      final text = kAnalysisCaveat.toLowerCase();
      for (final banned in ['safe', 'private', 'secure', 'encrypted']) {
        expect(text, isNot(contains(banned)), reason: 'banned word: $banned');
      }
    });
  });

  group('parseAnalysisResponse', () {
    Map<String, Object?> reply(String text, {String finish = 'STOP'}) => {
          'candidates': [
            {
              'finishReason': finish,
              'content': {
                'parts': [
                  {'text': text},
                ],
              },
            },
          ],
        };

    test('returns the prose', () {
      final result = parseAnalysisResponse(reply('A pink diamond pattern.'));
      expect(result.prose, 'A pink diamond pattern.');
      expect(result.isEmpty, isFalse);
    });

    test('joins multiple parts', () {
      final result = parseAnalysisResponse({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'one '},
                {'text': 'two'},
              ],
            },
          },
        ],
      });
      expect(result.prose, 'one two');
    });

    test('throws the API error message on an error envelope', () {
      // HTTP 200 is not a promise of success.
      expect(
        () => parseAnalysisResponse({
          'error': {'message': 'API key not valid.'},
        }),
        throwsA(
          isA<AnalysisException>().having(
            (e) => e.message,
            'message',
            'API key not valid.',
          ),
        ),
      );
    });

    test('flags a prompt blocked before generation as a safety refusal', () {
      expect(
        () => parseAnalysisResponse({
          'promptFeedback': {'blockReason': 'SAFETY'},
        }),
        throwsA(
          isA<AnalysisException>()
              .having((e) => e.isSafetyRefusal, 'isSafetyRefusal', isTrue),
        ),
      );
    });

    test('flags a candidate stopped by the safety filter', () {
      expect(
        () => parseAnalysisResponse(reply('', finish: 'SAFETY')),
        throwsA(
          isA<AnalysisException>()
              .having((e) => e.isSafetyRefusal, 'isSafetyRefusal', isTrue),
        ),
      );
    });

    test('refuses a truncated answer rather than showing it', () {
      // A description of a body photo cut off mid-sentence is worse than none.
      // This is also what a non-zero thinking budget looks like from outside.
      expect(
        () => parseAnalysisResponse(reply('This image sh', finish: 'MAX_TOKENS')),
        throwsA(isA<AnalysisException>()),
      );
    });

    test('throws on no candidates', () {
      expect(
        () => parseAnalysisResponse({'candidates': <Object?>[]}),
        throwsA(isA<AnalysisException>()),
      );
    });

    test('throws on an empty answer', () {
      expect(
        () => parseAnalysisResponse(reply('   ')),
        throwsA(isA<AnalysisException>()),
      );
    });
  });

  group('decodeAnalysisBody', () {
    test('decodes JSON', () {
      expect(decodeAnalysisBody('{"a":1}'), {'a': 1});
    });

    test('turns a non-JSON error page into copy', () {
      // A captive portal or gateway answers with HTML. jsonDecode would throw a
      // FormatException whose message quotes the page — which would then be
      // shown to the user.
      expect(
        () => decodeAnalysisBody('<html>502 Bad Gateway</html>'),
        throwsA(isA<AnalysisException>()),
      );
    });
  });

  group('normalizeQuestion', () {
    test('falls back to the default when blank', () {
      expect(normalizeQuestion(null), kDefaultAnalysisQuestion);
      expect(normalizeQuestion('   '), kDefaultAnalysisQuestion);
    });

    test('trims', () {
      expect(normalizeQuestion('  what is this  '), 'what is this');
    });

    test('bounds a long question', () {
      final long = 'a' * (kMaxQuestionLength + 50);
      expect(normalizeQuestion(long).length, kMaxQuestionLength);
    });
  });

  group('daily cap', () {
    test('the day key is local, not UTC', () {
      // Explained to the user as "today", so a UTC day would reset mid
      // afternoon for some of them.
      expect(analysisDayKey(DateTime(2026, 8, 12, 23, 59)), '2026-08-12');
      expect(analysisDayKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('a stored count from another day reads as zero', () {
      // This is what makes the counter roll over with no midnight timer.
      expect(
        analysisCountForDay(
          storedDay: '2026-08-11',
          storedCount: 20,
          now: DateTime(2026, 8, 12, 9),
        ),
        0,
      );
    });

    test("today's count is returned", () {
      expect(
        analysisCountForDay(
          storedDay: '2026-08-12',
          storedCount: 7,
          now: DateTime(2026, 8, 12, 9),
        ),
        7,
      );
    });

    test('never used reads as zero', () {
      expect(
        analysisCountForDay(
          storedDay: null,
          storedCount: null,
          now: DateTime(2026, 8, 12),
        ),
        0,
      );
    });
  });

  group('messageForAnalysisBlock', () {
    test('every reason has copy', () {
      for (final block in AnalysisBlock.values) {
        expect(messageForAnalysisBlock(block), isNotEmpty);
      }
    });

    test('the cap message names the number and says it resets', () {
      final text = messageForAnalysisBlock(AnalysisBlock.dailyCap);
      expect(text, contains('$kMaxAnalysesPerDay'));
      expect(text.toLowerCase(), contains('tomorrow'));
    });

    test('the daily cap counts messages, not photos', () {
      // Every turn of a conversation bills, so the counter counts turns. It
      // said "photos" when this was one description per tap; that is no longer
      // what it measures, and copy must describe what the code does.
      final text = messageForAnalysisBlock(AnalysisBlock.dailyCap);
      expect(text.toLowerCase(), contains('messages'));
      expect(text.toLowerCase(), isNot(contains('photos')));
    });

    test('the turn cap names the number and says how to start over', () {
      final text = messageForAnalysisBlock(AnalysisBlock.turnCap);
      expect(text, contains('$kMaxChatTurns'));
      expect(text.toLowerCase(), contains('again'));
    });

    test('no reason claims the photo is safe, private or encrypted', () {
      for (final block in AnalysisBlock.values) {
        final text = messageForAnalysisBlock(block).toLowerCase();
        for (final banned in ['safe', 'private', 'secure', 'encrypted']) {
          expect(text, isNot(contains(banned)), reason: '$block: $banned');
        }
      }
    });
  });
}
