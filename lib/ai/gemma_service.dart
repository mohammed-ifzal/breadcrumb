/// Loads Gemma 4 E2B on the phone with flutter_edge_ai (LiteRT-LM) and answers
/// [PlaceChooser] questions with one function-calling tool, `choose_place`.
/// Everything it returns is checked by `GemmaDestinationResolver`.
library;

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

class GemmaService implements PlaceChooser {
  InferenceModel? _model;
  GemmaLoadReport? report;

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
    final chat = await model.createChat(
      topK: 1,
      maxOutputTokens: 64,
      modelType: ModelType.gemma4,
      supportsFunctionCalls: true,
      tools: [
        Tool(
          name: choosePlaceTool,
          description: choosePlaceDescription(places),
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
      systemInstruction:
          'You help someone find a place on an indoor map. The request may be in '
          'English or Hindi. If one place on the map fits the request, call '
          '$choosePlaceTool with its ID. If no place fits, do not call the tool; '
          'reply with the single word none.',
    );
    try {
      await chat.addQueryChunk(Message(text: utterance, isUser: true));
      final response = await chat.generateChatResponse();
      return switch (response) {
        FunctionCallResponse() => _placeId(response),
        ParallelFunctionCallResponse(:final calls) =>
          calls.map(_placeId).firstWhere((id) => id != null, orElse: () => null),
        TextResponse() || ThinkingResponse() => null,
      };
    } finally {
      await chat.close();
    }
  }

  static String? _placeId(FunctionCallResponse call) {
    if (call.name != choosePlaceTool) return null;
    final id = call.args['place_id'];
    return id is String ? id : null;
  }

  Future<void> close() async {
    await _model?.close();
    _model = null;
  }
}
