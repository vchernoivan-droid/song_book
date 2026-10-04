import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class ListenScreen extends StatefulWidget {
  const ListenScreen({super.key});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  final _speech = SpeechToText();
  final _scrollCtrl = ScrollController();

  bool _ready = false;
  bool _wantListen = false;
  String _final = '';
  String _partial = '';
  String _error = '';
  String _status = '';
  List<LocaleName> _locales = [];
  String _localeId = '';
  ListenMode _mode = ListenMode.dictation;
  List<String> _alternates = [];
  DateTime _lastLevelAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _wantListen = false;
    _speech.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final ok = await _speech.initialize(
      onStatus: _onStatus,
      onError: (e) {
        debugPrint('STT error: ${e.errorMsg}');
        if (mounted) setState(() => _error = e.errorMsg);
      },
    );
    if (!mounted) return;
    if (!ok) {
      debugPrint('STT initialize failed');
      setState(() => _error = 'Распознавание речи недоступно');
      return;
    }
    final locales = await _speech.locales();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _locales = locales;
    });
  }

  String _ts() {
    final now = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    String p3(int v) => v.toString().padLeft(3, '0');
    return '${p2(now.hour)}:${p2(now.minute)}:${p2(now.second)}.${p3(now.millisecond)}';
  }

  void _onStatus(String status) {
    debugPrint('STT ${_ts()} status: $status');
    if (!mounted) return;
    setState(() {
      _status = status;
      if (status == SpeechToText.doneStatus) _wantListen = false;
    });
  }

  void _onSoundLevel(double level) {
    final now = DateTime.now();
    if (now.difference(_lastLevelAt).inMilliseconds < 500) return;
    _lastLevelAt = now;
    debugPrint('STT ${_ts()} level: ${level.toStringAsFixed(1)} dB');
  }

  Future<void> _listen() async {
    debugPrint(
      'STT ${_ts()} listen: locale=${_localeId.isEmpty ? 'system' : _localeId} mode=$_mode',
    );
    try {
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: _mode,
          localeId: _localeId.isEmpty ? null : _localeId,
        ),
      );
    } catch (e) {
      debugPrint('STT listen failed: $e');
      if (mounted) {
        setState(() {
          _wantListen = false;
          _error = 'Не удалось начать прослушивание';
        });
      }
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    debugPrint(
      'STT ${_ts()} ${result.finalResult ? 'final' : 'partial'} '
      'conf=${result.confidence.toStringAsFixed(2)} alt=${result.alternates.length}: '
      '${result.recognizedWords}',
    );
    if (!mounted) return;
    setState(() {
      if (result.finalResult) {
        final words = result.recognizedWords.trim();
        if (words.isNotEmpty) _final = '$_final $words'.trim();
        _partial = '';
      } else {
        _partial = result.recognizedWords;
      }
      _alternates = [
        for (final a in result.alternates.skip(1).take(3)) a.recognizedWords,
      ];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
    });
  }

  Future<void> _start() async {
    setState(() {
      _wantListen = true;
      _error = '';
    });
    await _listen();
  }

  Future<void> _stop() async {
    setState(() {
      _wantListen = false;
      _partial = '';
      _alternates = [];
    });
    await _speech.stop();
  }

  Future<void> _toggle() async {
    if (_wantListen) {
      await _stop();
    } else {
      await _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = '$_final $_partial'.trim();
    return Scaffold(
      appBar: AppBar(title: const Text('Проверка микрофона')),
      body: Column(
        children: [
          _buildControls(),
          if (_status.isNotEmpty || _error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_status.isNotEmpty)
                    Text(
                      _status,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  if (_error.isNotEmpty)
                    Text(
                      _error,
                      style: const TextStyle(color: Colors.red),
                    ),
                ],
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: text.isEmpty
                  ? Center(
                      child: Text(
                        _ready
                            ? 'Нажмите на микрофон и говорите'
                            : 'Инициализация…',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scrollCtrl,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText(
                            text,
                            style: const TextStyle(fontSize: 18),
                          ),
                          for (final a in _alternates) ...[
                            const SizedBox(height: 8),
                            Text(
                              a,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.large(
        tooltip: _wantListen ? 'Остановить' : 'Слушать',
        onPressed: _ready ? _toggle : null,
        backgroundColor: _wantListen ? Colors.red : null,
        child: Icon(_wantListen ? Icons.stop : Icons.mic_none),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(child: _localeDropdown()),
          const SizedBox(width: 8),
          Expanded(child: _modeDropdown()),
        ],
      ),
    );
  }

  Widget _localeDropdown() {
    return DropdownButton<String>(
      value: _localeId,
      isExpanded: true,
      items: [
        const DropdownMenuItem(value: '', child: Text('Системный')),
        for (final l in _locales)
          DropdownMenuItem(
            value: l.localeId,
            child: Text(l.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _ready
          ? (v) => setState(() => _localeId = v ?? '')
          : null,
    );
  }

  Widget _modeDropdown() {
    const labels = {
      ListenMode.deviceDefault: 'Авто',
      ListenMode.dictation: 'Диктовка',
      ListenMode.search: 'Поиск',
      ListenMode.confirmation: 'Коротко',
    };
    return DropdownButton<ListenMode>(
      value: _mode,
      isExpanded: true,
      items: [
        for (final m in ListenMode.values)
          DropdownMenuItem(
            value: m,
            child: Text(labels[m] ?? m.name),
          ),
      ],
      onChanged: _ready ? (v) => setState(() => _mode = v!) : null,
    );
  }
}
