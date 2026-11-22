import 'package:flutter/material.dart';

enum NetworkNodeType { source, router, destination }

class NetworkNode {
  final String id;
  final String label;

  // Position relative to the board: 0 to 1.
  final Offset position;
  final NetworkNodeType type;

  const NetworkNode({
    required this.id,
    required this.label,
    required this.position,
    this.type = NetworkNodeType.router,
  });
}

class NetworkLink {
  final String a;
  final String b;

  const NetworkLink(this.a, this.b);

  String get key => keyFor(a, b);

  static String keyFor(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('|');
  }
}

class PacketMission {
  final String title;
  final String description;
  final String lesson;
  final String hint;
  final int cableBudget;
  final List<NetworkNode> nodes;
  final List<NetworkLink> allowedLinks;
  final List<String> requiredNodes;
  final List<NetworkLink> failedLinks;

  const PacketMission({
    required this.title,
    required this.description,
    required this.lesson,
    required this.hint,
    required this.cableBudget,
    required this.nodes,
    required this.allowedLinks,
    this.requiredNodes = const [],
    this.failedLinks = const [],
  });
}

const packetMissions = <PacketMission>[
  PacketMission(
    title: 'First delivery',
    description:
        'Connect the laptop to the server. You have three cables.',
    lesson:
        'Devices need a continuous route to exchange data. '
        'A router forwards packets towards their destination.',
    hint: 'Connect Laptop → R1 → R2 → Server.',
    cableBudget: 3,
    nodes: [
      NetworkNode(
        id: 'S',
        label: 'Laptop',
        position: Offset(0.12, 0.5),
        type: NetworkNodeType.source,
      ),
      NetworkNode(
        id: 'A',
        label: 'R1',
        position: Offset(0.37, 0.3),
      ),
      NetworkNode(
        id: 'B',
        label: 'R2',
        position: Offset(0.63, 0.7),
      ),
      NetworkNode(
        id: 'T',
        label: 'Server',
        position: Offset(0.88, 0.5),
        type: NetworkNodeType.destination,
      ),
    ],
    allowedLinks: [
      NetworkLink('S', 'A'),
      NetworkLink('A', 'B'),
      NetworkLink('B', 'T'),
    ],
  ),
  PacketMission(
    title: 'Security checkpoint',
    description:
        'Deliver the packet through the Shield router. '
        'The direct route does not meet this mission’s policy.',
    lesson:
        'A route can be connected but still violate a network policy. '
        'Some traffic must pass through a designated security gateway.',
    hint: 'Use Laptop → R1 → Shield → Server.',
    cableBudget: 3,
    requiredNodes: ['F'],
    nodes: [
      NetworkNode(
        id: 'S',
        label: 'Laptop',
        position: Offset(0.12, 0.5),
        type: NetworkNodeType.source,
      ),
      NetworkNode(
        id: 'A',
        label: 'R1',
        position: Offset(0.36, 0.25),
      ),
      NetworkNode(
        id: 'F',
        label: 'Shield',
        position: Offset(0.64, 0.25),
      ),
      NetworkNode(
        id: 'B',
        label: 'R2',
        position: Offset(0.5, 0.76),
      ),
      NetworkNode(
        id: 'T',
        label: 'Server',
        position: Offset(0.88, 0.5),
        type: NetworkNodeType.destination,
      ),
    ],
    allowedLinks: [
      NetworkLink('S', 'A'),
      NetworkLink('A', 'F'),
      NetworkLink('F', 'T'),
      NetworkLink('S', 'B'),
      NetworkLink('B', 'T'),
    ],
  ),
  PacketMission(
    title: 'Broken connection',
    description:
        'The red connection has failed. Build another route '
        'using no more than three cables.',
    lesson:
        'Alternative paths help maintain connectivity when a link fails. '
        'A failed link cannot carry the packet.',
    hint: 'Try the lower route through R2 and R3.',
    cableBudget: 3,
    failedLinks: [NetworkLink('A', 'T')],
    nodes: [
      NetworkNode(
        id: 'S',
        label: 'Laptop',
        position: Offset(0.12, 0.5),
        type: NetworkNodeType.source,
      ),
      NetworkNode(
        id: 'A',
        label: 'R1',
        position: Offset(0.5, 0.2),
      ),
      NetworkNode(
        id: 'B',
        label: 'R2',
        position: Offset(0.36, 0.76),
      ),
      NetworkNode(
        id: 'C',
        label: 'R3',
        position: Offset(0.66, 0.76),
      ),
      NetworkNode(
        id: 'T',
        label: 'Server',
        position: Offset(0.88, 0.5),
        type: NetworkNodeType.destination,
      ),
    ],
    allowedLinks: [
      NetworkLink('S', 'A'),
      NetworkLink('A', 'T'),
      NetworkLink('S', 'B'),
      NetworkLink('B', 'C'),
      NetworkLink('C', 'T'),
      NetworkLink('A', 'C'),
    ],
  ),
  PacketMission(
    title: 'Network architect',
    description:
        'Find the shortest working route through Shield. '
        'The Shield-to-server connection is down.',
    lesson:
        'Good network design balances connectivity, policy, '
        'failure recovery, and resource use.',
    hint: 'Reach Shield through R1, then use R3 to reach Server.',
    cableBudget: 5,
    requiredNodes: ['F'],
    failedLinks: [NetworkLink('F', 'T')],
    nodes: [
      NetworkNode(
        id: 'S',
        label: 'Laptop',
        position: Offset(0.10, 0.5),
        type: NetworkNodeType.source,
      ),
      NetworkNode(
        id: 'A',
        label: 'R1',
        position: Offset(0.32, 0.22),
      ),
      NetworkNode(
        id: 'B',
        label: 'R2',
        position: Offset(0.32, 0.78),
      ),
      NetworkNode(
        id: 'F',
        label: 'Shield',
        position: Offset(0.56, 0.22),
      ),
      NetworkNode(
        id: 'C',
        label: 'R3',
        position: Offset(0.68, 0.78),
      ),
      NetworkNode(
        id: 'T',
        label: 'Server',
        position: Offset(0.9, 0.5),
        type: NetworkNodeType.destination,
      ),
    ],
    allowedLinks: [
      NetworkLink('S', 'A'),
      NetworkLink('S', 'B'),
      NetworkLink('A', 'F'),
      NetworkLink('B', 'F'),
      NetworkLink('B', 'C'),
      NetworkLink('F', 'C'),
      NetworkLink('F', 'T'),
      NetworkLink('C', 'T'),
    ],
  ),
];