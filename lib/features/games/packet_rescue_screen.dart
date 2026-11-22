import 'package:flutter/material.dart';

import 'packet_rescue_levels.dart';

class PacketRescueScreen extends StatefulWidget {
  const PacketRescueScreen({super.key});

  @override
  State<PacketRescueScreen> createState() => _PacketRescueScreenState();
}

class _PacketRescueScreenState extends State<PacketRescueScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  int _missionIndex = 0;
  int _attempts = 0;
  bool _hintUsed = false;
  bool _running = false;
  bool _completed = false;

  String? _selectedNode;
  String _message = 'Tap a device, then another device to connect them.';

  final Set<String> _links = {};
  final List<Set<String>> _undoHistory = [];
  List<String> _route = [];

  static const _purple = Color(0xFF6750E8);

  PacketMission get _mission => packetMissions[_missionIndex];

  Set<String> get _failedLinks =>
      _mission.failedLinks.map((link) => link.key).toSet();

  @override
  void initState() {
    super.initState();

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  void _loadMission(int index) {
    _animation.reset();

    setState(() {
      _missionIndex = index;
      _attempts = 0;
      _hintUsed = false;
      _running = false;
      _completed = false;
      _selectedNode = null;
      _links.clear();
      _undoHistory.clear();
      _route = [];
      _message = 'Tap two devices to build a connection.';
    });
  }

  void _tapNode(String id) {
    if (_running || _completed) return;

    if (_selectedNode == null) {
      setState(() {
        _selectedNode = id;
        _message = 'Now tap the device you want to connect to.';
      });
      return;
    }

    if (_selectedNode == id) {
      setState(() {
        _selectedNode = null;
        _message = 'Selection cleared.';
      });
      return;
    }

    final key = NetworkLink.keyFor(_selectedNode!, id);
    final allowed =
        _mission.allowedLinks.any((link) => link.key == key);

    if (!allowed) {
      setState(() {
        _selectedNode = null;
        _message = 'No cable corridor here. Follow the thin guide lines.';
      });
      return;
    }

    if (_failedLinks.contains(key)) {
      setState(() {
        _selectedNode = null;
        _message = 'That connection has failed. Find another route.';
      });
      return;
    }

    if (!_links.contains(key) &&
        _links.length >= _mission.cableBudget) {
      setState(() {
        _selectedNode = null;
        _message = 'Cable budget reached. Remove a cable or tap Undo.';
      });
      return;
    }

    _undoHistory.add(Set<String>.from(_links));

    setState(() {
      if (_links.contains(key)) {
        _links.remove(key);
        _message = 'Cable removed.';
      } else {
        _links.add(key);
        _message = 'Cable connected. Build more or tap Send packet.';
      }

      _selectedNode = null;
      _route = [];
    });
  }

  void _undo() {
    if (_running || _completed || _undoHistory.isEmpty) return;

    final previous = _undoHistory.removeLast();

    setState(() {
      _links
        ..clear()
        ..addAll(previous);
      _selectedNode = null;
      _route = [];
      _message = 'Last cable change undone.';
    });
  }

  void _resetBoard() {
    if (_running) return;

    _animation.reset();

    setState(() {
      _links.clear();
      _undoHistory.clear();
      _selectedNode = null;
      _route = [];
      _completed = false;
      _message = 'Board cleared. Try a new design.';
    });
  }

  void _showHint() {
    if (_running || _completed) return;

    setState(() {
      _hintUsed = true;
      _message = _mission.hint;
    });
  }

  // Breadth-first search over simple paths.
  // These boards are deliberately small.
  List<String>? _findRoute(
    Set<String> links, {
    required bool enforcePolicy,
  }) {
    final queue = <List<String>>[
      ['S'],
    ];

    var cursor = 0;

    while (cursor < queue.length) {
      final path = queue[cursor++];
      final current = path.last;

      if (current == 'T') {
        final meetsPolicy = _mission.requiredNodes
            .every((requiredNode) => path.contains(requiredNode));

        if (!enforcePolicy || meetsPolicy) return path;

        // The destination is the end of a route.
        continue;
      }

      for (final link in _mission.allowedLinks) {
        if (!links.contains(link.key) ||
            _failedLinks.contains(link.key)) {
          continue;
        }

        String? next;

        if (link.a == current) {
          next = link.b;
        } else if (link.b == current) {
          next = link.a;
        }

        if (next != null && !path.contains(next)) {
          queue.add([...path, next]);
        }
      }
    }

    return null;
  }

  int _starsFor(List<String> route) {
    final allWorkingLinks = _mission.allowedLinks
        .where((link) => !_failedLinks.contains(link.key))
        .map((link) => link.key)
        .toSet();

    final optimum = _findRoute(
      allWorkingLinks,
      enforcePolicy: true,
    );

    final efficient =
        optimum != null && _links.length == optimum.length - 1;

    var stars = 1;

    if (efficient) stars++;
    if (!_hintUsed && _attempts == 1) stars++;

    return stars;
  }

  Future<void> _sendPacket() async {
    if (_running || _completed) return;

    setState(() {
      _attempts++;
      _selectedNode = null;
    });

    final route = _findRoute(_links, enforcePolicy: true);

    if (route == null) {
      final connected = _findRoute(
        _links,
        enforcePolicy: false,
      );

      setState(() {
        _message = connected == null
            ? 'Delivery failed: there is no continuous working route '
                'from Laptop to Server.'
            : 'The packet can reach Server, but the route skips '
                'the required Shield router.';
      });
      return;
    }

    setState(() {
      _route = route;
      _running = true;
      _message = 'Packet travelling through your network...';
    });

    _animation.duration = Duration(
      milliseconds: (route.length - 1) * 700,
    );

    try {
      await _animation.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }

    if (!mounted) return;

    final stars = _starsFor(route);

    setState(() {
      _running = false;
      _completed = true;
      _message = 'Delivered! ${route.length - 1} hops, '
          '${_links.length} cables, $_attempts attempts.';
    });

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Packet rescued!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                3,
                (index) => Icon(
                  index < stars ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(_mission.lesson),
            const SizedBox(height: 12),
            const Text(
              'Stars: deliver the packet, use the minimum number '
              'of cables, and succeed on the first attempt without a hint.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('View board'),
          ),
        ],
      ),
    );
  }

  IconData _nodeIcon(NetworkNode node) {
    if (node.id == 'F') return Icons.shield_outlined;

    switch (node.type) {
      case NetworkNodeType.source:
        return Icons.laptop;
      case NetworkNodeType.destination:
        return Icons.dns_outlined;
      case NetworkNodeType.router:
        return Icons.router_outlined;
    }
  }

  Widget _board() {
    return AspectRatio(
      aspectRatio: 1.15,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );

          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFF12182B),
              borderRadius: BorderRadius.circular(24),
            ),
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _NetworkPainter(
                          mission: _mission,
                          activeLinks: Set<String>.from(_links),
                          route: _route,
                          progress: _animation.value,
                        ),
                      ),
                    ),
                    for (final node in _mission.nodes)
                      Positioned(
                        left: node.position.dx * size.width - 30,
                        top: node.position.dy * size.height - 34,
                        width: 60,
                        height: 68,
                        child: Semantics(
                          label: '${node.label}, '
                              '${_selectedNode == node.id ? 'selected' : 'device'}',
                          button: true,
                          child: GestureDetector(
                            onTap: () => _tapNode(node.id),
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: _selectedNode == node.id
                                        ? _purple
                                        : const Color(0xFF26314F),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: _selectedNode == node.id
                                          ? Colors.white
                                          : node.id == 'F'
                                              ? Colors.amber
                                              : Colors.cyanAccent,
                                      width: 2,
                                    ),
                                    boxShadow: _selectedNode == node.id
                                        ? [
                                            BoxShadow(
                                              color: _purple.withAlpha(140),
                                              blurRadius: 18,
                                            ),
                                          ]
                                        : [],
                                  ),
                                  child: Icon(
                                    _nodeIcon(node),
                                    color: Colors.white,
                                    size: 25,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  node.label,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Packet Rescue'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    children: List.generate(
                      packetMissions.length,
                      (index) => ChoiceChip(
                        label: Text('Mission ${index + 1}'),
                        selected: _missionIndex == index,
                        onSelected: _running
                            ? null
                            : (_) => _loadMission(index),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _mission.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mission.description,
                    style: const TextStyle(height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.cable, size: 18),
                        label: Text(
                          '${_links.length}/${_mission.cableBudget} cables',
                        ),
                      ),
                      Chip(
                        avatar: const Icon(Icons.flag_outlined, size: 18),
                        label: Text('$_attempts attempts'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _board(),
                  const SizedBox(height: 12),
                  const Text(
                    'Thin line: available connection • Bright line: cable '
                    '• Red ×: failed connection\n'
                    'Tap connected devices again to remove their cable.',
                    style: TextStyle(fontSize: 12, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _message,
                        style: const TextStyle(height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _running || _completed ? null : _sendPacket,
                    icon: const Icon(Icons.send_rounded),
                    label: Text(
                      _running ? 'Delivering...' : 'Send packet',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _running ||
                                _completed ||
                                _undoHistory.isEmpty
                            ? null
                            : _undo,
                        icon: const Icon(Icons.undo),
                        label: const Text('Undo'),
                      ),
                      TextButton.icon(
                        onPressed: _running ? null : _resetBoard,
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset'),
                      ),
                      TextButton.icon(
                        onPressed:
                            _running || _completed ? null : _showHint,
                        icon: const Icon(Icons.lightbulb_outline),
                        label: const Text('Hint'),
                      ),
                    ],
                  ),
                  if (_completed) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        _loadMission(
                          (_missionIndex + 1) % packetMissions.length,
                        );
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(
                        _missionIndex == packetMissions.length - 1
                            ? 'Play again'
                            : 'Next mission',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Learning simulation: the game selects the shortest '
                    'built route meeting the mission policy. '
                    'It does not simulate real routing protocols.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NetworkPainter extends CustomPainter {
  final PacketMission mission;
  final Set<String> activeLinks;
  final List<String> route;
  final double progress;

  _NetworkPainter({
    required this.mission,
    required this.activeLinks,
    required this.route,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset point(String id) {
      final node = mission.nodes.firstWhere((node) => node.id == id);
      return Offset(
        node.position.dx * size.width,
        node.position.dy * size.height,
      );
    }

    final gridPaint = Paint()
      ..color = Colors.white.withAlpha(12)
      ..strokeWidth = 1;

    for (double x = 0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (double y = 0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final failed = mission.failedLinks.map((link) => link.key).toSet();

    for (final link in mission.allowedLinks) {
      final a = point(link.a);
      final b = point(link.b);
      final broken = failed.contains(link.key);
      final active = activeLinks.contains(link.key);

      final paint = Paint()
        ..color = broken
            ? Colors.redAccent
            : active
                ? Colors.cyanAccent
                : const Color(0xFF46516A)
        ..strokeWidth = active ? 5 : 2
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(a, b, paint);

      if (broken) {
        final middle = Offset.lerp(a, b, 0.5)!;
        final cross = Paint()
          ..color = Colors.redAccent
          ..strokeWidth = 4;

        canvas.drawCircle(
          middle,
          12,
          Paint()..color = const Color(0xFF12182B),
        );

        canvas.drawLine(
          middle + const Offset(-6, -6),
          middle + const Offset(6, 6),
          cross,
        );
        canvas.drawLine(
          middle + const Offset(-6, 6),
          middle + const Offset(6, -6),
          cross,
        );
      }
    }

    if (route.length >= 2) {
      final segments = route.length - 1;
      final position = progress * segments;

      final segment =
          position.floor().clamp(0, segments - 1).toInt();

      final fraction = progress >= 1 ? 1.0 : position - segment;

      final packet = Offset.lerp(
        point(route[segment]),
        point(route[segment + 1]),
        fraction,
      )!;

      canvas.drawCircle(
        packet,
        15,
        Paint()..color = Colors.amber.withAlpha(55),
      );

      canvas.drawCircle(
        packet,
        7,
        Paint()..color = Colors.amber,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter oldDelegate) => true;
}