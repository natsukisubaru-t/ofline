import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const OfflineTubeApp());
}

class OfflineTubeApp extends StatelessWidget {
  const OfflineTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OfflineTube',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const ShortsFeedPage(),
    const AutoFetcherPage(),
    const LongVideosPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: Colors.redAccent,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.play_arrow), label: 'Feed'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: 'Auto Fetch'),
          BottomNavigationBarItem(icon: Icon(Icons.link), label: 'Long Video'),
        ],
      ),
    );
  }
}

class ShortsFeedPage extends StatefulWidget {
  const ShortsFeedPage({super.key});

  @override
  State<ShortsFeedPage> createState() => _ShortsFeedPageState();
}

class _ShortsFeedPageState extends State<ShortsFeedPage> {
  List<File> _videos = [];
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final shortsDir = Directory('${dir.path}/shorts');
    if (await shortsDir.exists()) {
      final files = shortsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4'))
          .toList();
      setState(() => _videos = files);
    }
  }

  Future<void> _deleteWatchedVideo(int index) async {
    if (index >= 0 && index < _videos.length) {
      final file = _videos[index];
      if (!file.path.contains('_saved')) {
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> _saveCurrentVideo(int index) async {
    final file = _videos[index];
    if (!file.path.contains('_saved')) {
      final newPath = file.path.replaceAll('.mp4', '_saved.mp4');
      final newFile = await file.rename(newPath);
      setState(() => _videos[index] = newFile);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved permanently!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('No Shorts yet! Go to Auto Fetch tab.'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadVideos, child: const Text('Refresh')),
          ],
        ),
      );
    }

    return PageView.builder(
      scrollDirection: Axis.vertical,
      itemCount: _videos.length,
      onPageChanged: (newIndex) {
        if (newIndex > _lastIndex) {
          _deleteWatchedVideo(_lastIndex);
        }
        _lastIndex = newIndex;
      },
      itemBuilder: (context, index) {
        return Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayerItem(file: _videos[index]),
            Positioned(
              right: 16,
              bottom: 40,
              child: Column(
                children: [
                  FloatingActionButton(
                    backgroundColor: Colors.black54,
                    onPressed: () => _saveCurrentVideo(index),
                    child: Icon(
                      _videos[index].path.contains('_saved')
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.redAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Keep', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class VideoPlayerItem extends StatefulWidget {
  final File file;
  const VideoPlayerItem({super.key, required this.file});

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
          _controller.setLooping(true);
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
    if (!_initialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => _controller.value.isPlaying ? _controller.pause() : _controller.play(),
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}

class AutoFetcherPage extends StatefulWidget {
  const AutoFetcherPage({super.key});

  @override
  State<AutoFetcherPage> createState() => _AutoFetcherPageState();
}

class _AutoFetcherPageState extends State<AutoFetcherPage> {
  final _topicsController = TextEditingController(text: 'anime edits, gaming funny, tech shorts');
  double _count = 10;
  bool _isDownloading = false;
  String _status = 'Ready to fetch';

  Future<void> _startAutoDownload() async {
    setState(() {
      _isDownloading = true;
      _status = 'Searching for new Shorts...';
    });

    final yt = YoutubeExplode();
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenIds = prefs.getStringList('seen_ids') ?? [];
      final dir = await getApplicationDocumentsDirectory();
      final shortsDir = Directory('${dir.path}/shorts');
      if (!await shortsDir.exists()) await shortsDir.create(recursive: true);

      final topics = _topicsController.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      int downloaded = 0;
      int target = _count.toInt();

      for (final topic in topics) {
        if (downloaded >= target) break;
        final searchList = await yt.search.search('$topic #shorts');

        for (final video in searchList) {
          if (downloaded >= target) break;
          if (seenIds.contains(video.id.value)) continue;
          if (video.duration != null && video.duration!.inSeconds > 90) continue;

          setState(() => _status = 'Downloading (${downloaded + 1}/$target):\n${video.title}');

          try {
            final manifest = await yt.videos.streamsClient.getManifest(video.id);
            final streamInfo = manifest.muxed.withHighestBitrate();
            final stream = yt.videos.streamsClient.get(streamInfo);

            final file = File('${shortsDir.path}/${video.id.value}.mp4');
            final fileStream = file.openWrite();
            await stream.pipe(fileStream);
            await fileStream.flush();
            await fileStream.close();

            seenIds.add(video.id.value);
            await prefs.setStringList('seen_ids', seenIds);
            downloaded++;
          } catch (_) {}
        }
      }
      setState(() => _status = 'Done! Downloaded $downloaded new Shorts.');
    } catch (e) {
      setState(() => _status = 'Error: Check internet or VPN connection.');
    } finally {
      yt.close();
      setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Topics (comma separated):', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _topicsController,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Text('Download limit: ${_count.toInt()} videos'),
          Slider(
            value: _count,
            min: 5,
            max: 40,
            divisions: 7,
            label: _count.toInt().toString(),
            onChanged: _isDownloading ? null : (v) => setState(() => _count = v),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: Colors.redAccent),
            onPressed: _isDownloading ? null : _startAutoDownload,
            icon: _isDownloading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.download),
            label: Text(_isDownloading ? 'Downloading...' : 'Start Auto Fetch'),
          ),
          const SizedBox(height: 20),
          Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amberAccent)),
        ],
      ),
    );
  }
}

class LongVideosPage extends StatefulWidget {
  const LongVideosPage({super.key});

  @override
  State<LongVideosPage> createState() => _LongVideosPageState();
}

class _LongVideosPageState extends State<LongVideosPage> {
  final _urlController = TextEditingController();
  bool _downloading = false;
  String _status = '';
  List<File> _longVideos = [];

  @override
  void initState() {
    super.initState();
    _loadLongVideos();
  }

  Future<void> _loadLongVideos() async {
    final dir = await getApplicationDocumentsDirectory();
    final longDir = Directory('${dir.path}/long_videos');
    if (await longDir.exists()) {
      setState(() {
        _longVideos = longDir.listSync().whereType<File>().where((f) => f.path.endsWith('.mp4')).toList();
      });
    }
  }

  Future<void> _downloadByLink() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _downloading = true;
      _status = 'Fetching video info...';
    });

    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(url);
      setState(() => _status = 'Downloading: ${video.title}');

      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final streamInfo = manifest.muxed.withHighestBitrate();
      final stream = yt.videos.streamsClient.get(streamInfo);

      final dir = await getApplicationDocumentsDirectory();
      final longDir = Directory('${dir.path}/long_videos');
      if (!await longDir.exists()) await longDir.create(recursive: true);

      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${longDir.path}/$safeTitle.mp4');
      final fileStream = file.openWrite();
      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      _urlController.clear();
      setState(() => _status = 'Download complete!');
      await _loadLongVideos();
    } catch (e) {
      setState(() => _status = 'Error! Check link and VPN.');
    } finally {
      yt.close();
      setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Paste YouTube Video URL here',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _downloading ? null : _downloadByLink,
            icon: const Icon(Icons.download),
            label: Text(_downloading ? 'Downloading...' : 'Download Video'),
          ),
          if (_status.isNotEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(_status, textAlign: TextAlign.center)),
          const Divider(height: 24),
          const Text('Saved Long Videos:', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              itemCount: _longVideos.length,
              itemBuilder: (context, index) {
                final file = _longVideos[index];
                final name = file.path.split('/').last;
                return ListTile(
                  leading: const Icon(Icons.movie, color: Colors.redAccent),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () async {
                      await file.delete();
                      _loadLongVideos();
                    },
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(name)),
                          body: VideoPlayerItem(file: file),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

