import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_go_torrent_streamer/flutter_go_torrent_streamer.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '磁力解析播放器',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MagnetHomePage(),
    );
  }
}

class MagnetHomePage extends StatefulWidget {
  const MagnetHomePage({super.key});

  @override
  State<MagnetHomePage> createState() => _MagnetHomePageState();
}

class _MagnetHomePageState extends State<MagnetHomePage> {
  final TextEditingController _magnetCtrl = TextEditingController();
  final FlutterGoTorrentStreamer _torrent = FlutterGoTorrentStreamer();
  List<TorrentFileInfo> _files = [];
  bool _isLoading = false;
  String? _error;
  String? _playUrl;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.internet,
      Permission.wakeLock,
    ].request();
  }

  Future<void> _parseMagnet(String magnet) async {
    if (magnet.isEmpty) {
      setState(() => _error = "请输入磁力链接");
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _files.clear();
      _playUrl = null;
    });

    try {
      final dir = await getApplicationDocumentsDirectory();
      await _torrent.initTorrent(
        magnetUri: magnet,
        savePath: dir.path,
      );

      _torrent.torrentStatusStream.listen((status) {
        if (mounted) {
          setState(() {
            if (status is TorrentMetadataLoaded) {
              _files = status.files;
            } else if (status is TorrentError) {
              _error = status.message;
            } else if (status is TorrentStreamReady) {
              _playUrl = status.streamUrl;
            }
          });
        }
      });
    } catch (e) {
      setState(() => _error = "解析失败: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return "$bytes B";
    if (bytes < 1024 * 1024) return "${(bytes / 1024).toStringAsFixed(2)} KB";
    if (bytes < 1024 * 1024 * 1024) return "${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB";
    return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
  }

  String _getFileType(String fileName) {
    final videoExts = ['.mp4', '.mkv', '.avi', '.mov', '.flv'];
    final imageExts = ['.jpg', '.png', '.gif', '.jpeg'];
    final docExts = ['.pdf', '.doc', '.docx', '.txt', '.xls'];

    final ext = fileName.substring(fileName.lastIndexOf('.'));
    if (videoExts.contains(ext)) return "视频";
    if (imageExts.contains(ext)) return "图片";
    if (docExts.contains(ext)) return "文档";
    return "其他";
  }

  @override
  void dispose() {
    _magnetCtrl.dispose();
    _torrent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("磁力解析播放器（研究）")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _magnetCtrl,
              decoration: const InputDecoration(
                labelText: "输入磁力链接",
                border: OutlineInputBorder(),
                hintText: "例：magnet:?xt=urn:btih:xxx",
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _parseMagnet(_magnetCtrl.text),
              child: const Text("解析磁力链接"),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: CircularProgressIndicator(),
              ),
            if (_playUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ElevatedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => VideoPlayPage(url: _playUrl!)),
                  ),
                  child: const Text("播放视频流"),
                ),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: _files.isEmpty
                  ? const Center(child: Text("解析后将显示文件列表"))
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (_, i) {
                        final f = _files[i];
                        return ListTile(
                          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            "类型：${_getFileType(f.name)} | 大小：${_formatSize(f.size)}",
                            style: const TextStyle(fontSize: 12),
                          ),
                          leading: Icon(
                            _getFileType(f.name) == "视频"
                                ? Icons.video_library
                                : _getFileType(f.name) == "图片"
                                    ? Icons.image
                                    : _getFileType(f.name) == "文档"
                                        ? Icons.description
                                        : Icons.file_copy,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayPage extends StatefulWidget {
  final String url;
  const VideoPlayPage({super.key, required this.url});

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> {
  late VideoPlayerController _controller;
  bool _isInit = false;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    _controller = VideoPlayerController.network(widget.url)
      ..addListener(() {
        if (mounted) {
          setState(() {
            _isBuffering = _controller.value.isBuffering;
          });
        }
      })
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInit = true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("视频播放")),
      body: Center(
        child: _isInit
            ? Stack(
                children: [
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  if (_isBuffering)
                    const Center(child: CircularProgressIndicator(color: Colors.white)),
                ],
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _controller.value.isPlaying ? _controller.pause() : _controller.play();
          });
        },
        child: Icon(_controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
