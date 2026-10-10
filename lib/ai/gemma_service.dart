/// Loads Gemma 4 E2B on the phone with flutter_edge_ai (LiteRT-LM) and answers
/// [PlaceChooser] questions with one function-calling tool, `choose_place`.
/// Everything it returns is checked by `GemmaDestinationResolver`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'package:path_provider/path_provider.dart';

import '../core/contracts.dart';
import 'destination_resolver.dart';

/// D18 (option A): pushed with adb, survives reinstalls.
const String gemmaModelPath = '/data/local/tmp/llm/gemma-4-E2B-it.litertlm';

const String gemmaModelFile = 'gemma-4-E2B-it.litertlm';

/// What [GemmaService.load] found out, for the debug screen and D18.
class GemmaLoadReport {
  const GemmaLoadReport({
    required this.path,
    required this.backend,
    required this.loadMs,
    required this.warmupMs,
    required this.notes,
  });

  final String path;

  /// The backend that actually loaded (`gpu` or `cpu`).
  final String backend;
  final int loadMs;
  final int warmupMs;

  /// Fallbacks taken on the way, oldest first.
  final List<String> notes;
}

/// The system instruction for every place question.
const String gemmaSystemInstruction =
    'You help someone find a place on an indoor map. The request may be in '
    'English or Hindi. It may name a place, describe it, or ask for '
    'something you can get or do somewhere without naming the place; then '
    'pick the place where that is most likely. If one place fits, call '
    '$choosePlaceTool with its ID. If no place fits, do not call the tool; '
    'reply with the single word none.';

class GemmaService implements PlaceChooser {
  GemmaService({this.reuseChat = true});

  /// Keep one chat (system instruction and `choose_place` tool) per set of
  /// places and clear its history after each answer, instead of opening a new
  /// chat per request. The clearing runs after the answer is returned, so the
  /// next request finds a fresh conversation ready. False is the old
  /// chat-per-request path, kept for the benchmark's before/after.
  bool reuseChat;

  InferenceModel? _model;
  GemmaLoadReport? report;

  InferenceChat? _chat;

  /// The [choosePlaceDescription] [_chat] was made for; another map, or a
  /// renamed place, needs a new chat.
  String? _chatPlaces;

  /// Completes when the previous request, and the clearing after it, is done.
  /// Requests run one at a time: the engine holds one live conversation.
  Future<void> _idle = Future.value();

  bool get isLoaded => _model != null;
  /// Registers the model file, loads it (GPU first, CPU if that fails) and
  /// warms it up once. Throws if no path or backend works.
  Future<GemmaLoadReport> load() async {
    final notes = <String>[];
    final watch = Stopwatch()..start();
    await FlutterEdgeAi.initialize(inferenceEngines: [LiteRtLmEngine()]);

    // Option A (D18), then option B from docs/SETUP.md: the app's own
    // Android/data/<package>/files/ folder.
    final candidates = [gemmaModelPath];
    final external = await getExternalStorageDirectory();
    if (external != null) candidates.add('${external.path}/$gemmaModelFile');

    Object? lastError;
    for (final path in candidates) {
      try {
        final model = await _loadFrom(path, notes);
        _model = model;
        final loadMs = watch.elapsedMilliseconds;
        final warm = Stopwatch()..start();
        await _warmUp(model);
        return report = GemmaLoadReport(
          path: path,
          backend: model.activeBackend?.name ?? 'unknown',
          loadMs: loadMs,
          warmupMs: warm.elapsedMilliseconds,
          notes: notes,
        );
      } catch (e) {
        lastError = e;
        notes.add('$path failed: $e');
      }
    }
    throw StateError('Gemma did not load. ${notes.join(' | ')} ($lastError)');
  }

  Future<InferenceModel> _loadFrom(String path, List<String> notes) async {
    final file = File(path);
    // existsSync can be false for an unreadable folder; length() then throws
    // a FileSystemException that names the permission problem.
    await file.length();
    await FlutterEdgeAi.installModel(
      modelType: ModelType.gemma4,
      fileType: ModelFileType.litertlm,
    ).fromFile(path).install();
    try {
      return await FlutterEdgeAi.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.gpu,
      );
    } catch (e) {
      notes.add('GPU load failed, trying CPU: $e');
      return FlutterEdgeAi.getActiveModel(
        maxTokens: 1024,
        preferredBackend: PreferredBackend.cpu,
      );
    }
  }

  Future<void> _warmUp(InferenceModel model) async {
    final session = await model.createSession(maxOutputTokens: 4);
    try {
      await session.addQueryChunk(Message(text: 'Reply with OK.', isUser: true));
      await session.getResponse();
    } finally {
      await session.close();
    }
  }

  @override
  Future<String?> choosePlace(String utterance, List<Place> places) async {
    final model = _model;
    if (model == null) throw StateError('Gemma is not loaded');
    final previous = _idle;
    final turn = Completer<void>();
    _idle = turn.future;
    await previous;

    InferenceChat? chat;
    try {
      chat = await _chatFor(model, places);
      await chat.addQueryChunk(Message(text: utterance, isUser: true));
      final response = await chat.generateChatResponse();
      final id = switch (response) {
        FunctionCallResponse() => _placeId(response),
        ParallelFunctionCallResponse(:final calls) =>
          calls.map(_placeId).firstWhere((id) => id != null, orElse: () => null),
        TextResponse() || ThinkingResponse() => null,
      };
      if (reuseChat) {
        // Not awaited: the answer goes back now, the next request waits.
        unawaited(_clear(chat).whenComplete(turn.complete));
      } else {
        await chat.close();
        turn.complete();
      }
      return id;
    } catch (_) {
      if (chat != null) await _drop(chat);
      turn.complete();
      rethrow;
    }
  }

  Future<InferenceChat> _chatFor(InferenceModel model, List<Place> places) async {
    final description = choosePlaceDescription(places);
    final kept = _chat;
    if (reuseChat && kept != null && _chatPlaces == description) return kept;
    if (kept != null) await _drop(kept);
    final chat = await model.createChat(
      topK: 1,
      maxOutputTokens: 64,
      modelType: ModelType.gemma4,
      supportsFunctionCalls: true,
      tools: [
        Tool(
          name: choosePlaceTool,
          description: description,
          parameters: {
            'type': 'object',
            'properties': {
              'place_id': {
                'type': 'string',
                'enum': [for (final p in places) p.id],
                'description': 'The ID of the place the person wants to go to.',
              },
            },
            'required': ['place_id'],
          },
        ),
      ],
      systemInstruction: gemmaSystemInstruction,
    );
    if (reuseChat) {
      _chat = chat;
      _chatPlaces = description;
    }
    return chat;
  }

  /// Empties [chat] for the next request; a chat that fails to clear is
  /// dropped and the next request opens a new one.
  Future<void> _clear(InferenceChat chat) async {
    try {
      await chat.clearHistory();
    } catch (_) {
      await _drop(chat);
    }
  }

  Future<void> _drop(InferenceChat chat) async {
    if (identical(chat, _chat)) {
      _chat = null;
      _chatPlaces = null;
    }
    try {
      await chat.close();
    } catch (_) {
      // Already closed or the engine is gone; nothing left to free.
    }
  }

  static String? _placeId(FunctionCallResponse call) {
    if (call.name != choosePlaceTool) return null;
    final id = call.args['place_id'];
    return id is String ? id : null;
  }

  Future<void> close() async {
    final chat = _chat;
    if (chat != null) await _drop(chat);
    await _model?.close();
    _model = null;
  }
}
