import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libtorrent/flutter_libtorrent.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Magnet Player (Research)',
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
  final FlutterLibtorrent _lt = FlutterLibtorrent();
  Torrent? _torrent;
  List<TorrentFile> _files = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initLibtorrent();
  }

  Future<void> _initLibtorrent() async {
    final dir = await getApplicationDocumentsDirectory();
    await _lt.init(
      tempPath: dir.path,
      downloadPath: dir.path,
    );
  }

  Future<void> _parseAndLoad(String magnet) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _files.clear();
      _torrent?.dispose();
      _torrent = null;
    });

    final status = await Permission.storage.request();
    if (!status.isGranted) {
      setState(() {
        _error = "需要存储权限才能继续";
        _isLoading = false;
      });
      return;
    }

    try {
      final torrent = await _lt.addTorrent(magnet);
      setState(() => _torrent = torrent);

      // 等待元数据加载（关键：metadataReceived）
      await for (final update in torrent.listen()) {
        if (update is MetadataReceivedUpdate) {
          final files = torrent.getFiles();
          setState(() => _files = files);
          break;
        } else if (update is ErrorUpdate) {
          setState(() => _error = "Torrent error: ${update.error}");
          break;
        }
      }
    } catch (e) {
      setState(() => _error = "Failed: $e");
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

  @override
  void dispose() {
    _magnetCtrl.dispose();
    _torrent?.dispose();
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
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _parseAndLoad(_magnetCtrl.text),
              child: const Text("解析并加载"),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: CircularProgressIndicator(),
              ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: _files.length,
                itemBuilder: (_, i) {
                  final f = _files[i];
                  return ListTile(
                    title: Text(f.name),
                    subtitle: Text("大小: ${_formatSize(f.size)} | 索引: ${f.index}"),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => VideoPlayPage(torrent: _torrent!, fileIndex: f.index),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class VideoPlayPage extends StatefulWidget {
  final Torrent torrent;
  final int fileIndex;

  const VideoPlayPage({super.key, required this.torrent, required this.fileIndex});

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage> {
  VideoPlayerController? _videoCtrl;
  bool _isBuffering = false;

  @override
  void initState() {
    super.initState();
    _initPlay();
  }

  Future<void> _initPlay() async {
    setState(() => _isBuffering = true);
    try {
      // 先确保只下载目标文件（选择性下载）
      await widget.torrent.setFilePriority(widget.fileIndex, 7); // 高优先级
      for (int i = 0; i < widget.torrent.getFiles().length; i++) {
        if (i != widget.fileIndex) {
          await widget.torrent.setFilePriority(i, 0); // 不下载其他文件
        }
      }

      // 这里是关键：你需要拿到“可播放的文件路径/URI”
      // flutter_libtorrent 的用法可能因版本不同而略有差异
      // 如果下面这行不能直接用，你可能需要改用：
      // - 先 download 到本地，再用 file:// 播放
      // - 或用 libtorrent 的 create_torrent_handle + 做一个本地 HTTP 服务供 video_player 播放
      final path = await widget.torrent.getFilePath(widget.fileIndex);
      final file = File(path);

      _videoCtrl = VideoPlayerController.file(file)
        ..addListener(() {
          setState(() {
            _isBuffering = _videoCtrl!.value.isBuffering;
          });
        })
        ..initialize().then((_) {
          setState(() {});
          _videoCtrl!.play();
        });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("播放失败: $e")));
      }
    } finally {
      if (mounted) setState(() => _isBuffering = false);
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("播放")),
      body: Center(
        child: _videoCtrl?.value.isInitialized ?? false
            ? Stack(
                children: [
                  AspectRatio(
                    aspectRatio: _videoCtrl!.value.aspectRatio,
                    child: VideoPlayer(_videoCtrl!),
                  ),
                  if (_isBuffering)
                    const Center(child: CircularProgressIndicator()),
                ],
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: _videoCtrl != null
          ? FloatingActionButton(
              onPressed: () {
                setState(() {
                  _videoCtrl!.value.isPlaying ? _videoCtrl!.pause() : _videoCtrl!.play();
                });
              },
              child: Icon(
                _videoCtrl!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }
}
