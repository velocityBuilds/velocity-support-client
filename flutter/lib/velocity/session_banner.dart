// Velocity Remote Technician: shows whose computer this is in the remote window, plus how the
// connection is doing (direct or through the server, video type, live fps) so a slow session
// explains itself.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/model.dart';

import 'velocity_api.dart';

class VelocitySessionBanner extends StatefulWidget {
  final String peerId;
  final FFI ffi;
  const VelocitySessionBanner({super.key, required this.peerId, required this.ffi});

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

  /// "Direct · H.265 (graphics card) · 60 fps" from the session's own quality reports.
  String _connectionLine() {
    final direct = widget.ffi.ffiModel.direct;
    final q = widget.ffi.qualityMonitorModel.data;
    final parts = <String>[];
    if (direct != null) parts.add(direct ? 'Direct' : 'Through server');
    final codec = (q.codecFormat ?? '').toUpperCase();
    if (codec.isNotEmpty) {
      // RustDesk only sends H.264/H.265 from a hardware encoder; VP8/VP9/AV1 are software.
      final hw = codec.contains('264') || codec.contains('265');
      final name = codec.replaceAll('H264', 'H.264').replaceAll('H265', 'H.265');
      parts.add(hw ? '$name (graphics card)' : '$name (software)');
    }
    final fps = (q.fps ?? '').trim();
    if (fps.isNotEmpty) parts.add('$fps fps');
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    final title = '${info['customerName'] ?? ''} · ${info['hostname'] ?? ''}';
    final ticket = info['ticketNumber'] != null ? '${info['ticketNumber']} — ${info['ticketSubject'] ?? ''}' : 'Remote session';
    return Positioned(
      left: 12,
      bottom: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
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
                Text(info['ticketNumber']?.toString() ?? 'Velocity',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))
              else
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(ticket, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFFC9D6F2), fontSize: 12)),
                    // Refreshes about once a second, whenever the session reports its quality.
                    ListenableBuilder(
                      listenable: Listenable.merge([widget.ffi.ffiModel, widget.ffi.qualityMonitorModel]),
                      builder: (_, __) {
                        final line = _connectionLine();
                        if (line.isEmpty) return const SizedBox.shrink();
                        final relayed = widget.ffi.ffiModel.direct == false;
                        return Text(line,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: relayed ? const Color(0xFFFFD08A) : const Color(0xFF9FE3BF), fontSize: 12));
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
