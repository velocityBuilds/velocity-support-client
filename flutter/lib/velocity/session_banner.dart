// Velocity Remote Technician: shows whose computer this is in the remote window.
import 'package:flutter/material.dart';

import 'velocity_api.dart';

class VelocitySessionBanner extends StatefulWidget {
  final String peerId;
  const VelocitySessionBanner({super.key, required this.peerId});

  @override
  State<VelocitySessionBanner> createState() => _VelocitySessionBannerState();
}

class _VelocitySessionBannerState extends State<VelocitySessionBanner> {
  Map<String, dynamic>? _info;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    if (isVelocityTechnician) _load();
  }

  Future<void> _load() async {
    final r = await velocityCall('tech_session_info', {'peerId': widget.peerId});
    if (!mounted || !r.ok || r.data is! Map) return;
    setState(() => _info = Map<String, dynamic>.from(r.data as Map));
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final title = '${info['customerName'] ?? ''} · ${info['hostname'] ?? ''}';
    final ticket = '${info['ticketNumber'] ?? ''} — ${info['ticketSubject'] ?? ''}';
    return Positioned(
      left: 12,
      bottom: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: VColors.navy.withOpacity(0.88),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: VColors.accent.withOpacity(0.6)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const VelocityMark(size: 22),
              const SizedBox(width: 10),
              if (_collapsed)
                Text(info['ticketNumber']?.toString() ?? '',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
              else
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(ticket,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFC9D6F2), fontSize: 12)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
