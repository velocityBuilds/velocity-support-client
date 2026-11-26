// Velocity Remote Support: the customer's main window.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:window_manager/window_manager.dart';

import 'velocity_api.dart';

const kTicketCategories = [
  'PC hardware problems',
  'PC performance issues',
  'Windows and software problems',
  'Virus and malware concerns',
  'Networking and internet problems',
  'PC upgrades',
  'Custom PC build questions',
  'Warranty claims',
  'General questions',
];

class VelocityCustomerHome extends StatefulWidget {
  const VelocityCustomerHome({super.key});

  @override
  State<VelocityCustomerHome> createState() => _VelocityCustomerHomeState();
}

class _VelocityCustomerHomeState extends State<VelocityCustomerHome> {
  Map<String, dynamic>? _state;
  String _ipcError = '';
  Timer? _timer;
  String? _promptedFor;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    final r = await velocityCall('state');
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _state = Map<String, dynamic>.from(r.data as Map);
        _ipcError = '';
      } else {
        _ipcError = r.error;
      }
    });
    final pending = _state?['pendingRequest'];
    if (pending is Map && pending['id'] != null && pending['id'] != _promptedFor) {
      _promptedFor = pending['id'] as String;
      _showAuthorization(Map<String, dynamic>.from(pending));
    }
  }

  Future<void> _showAuthorization(Map<String, dynamic> req) async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    velocityCall('notify', {
      'title': 'Velocity wants to connect',
      'body':
          '${req['technicianName']} is asking to connect for ticket ${req['ticketNumber']}. Open Velocity Remote Support to answer.'
    });
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuthorizationDialog(request: req),
    );
    final r = await velocityCall(
        'respond', {'requestId': req['id'], 'accept': accepted == true});
    if (!mounted) return;
    if (accepted == true && r.ok) {
      _snack('Approved. Your technician is connecting now.');
    } else if (accepted == true) {
      _snack(r.error);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: VColors.accent),
        scaffoldBackgroundColor: VColors.bg,
      ),
      child: Scaffold(
        backgroundColor: VColors.bg,
        body: SafeArea(
          child: s == null
              ? _loading()
              : (s['enrolled'] == true ? _main(s) : _EnrollView(state: s, onDone: _poll)),
        ),
      ),
    );
  }

  Widget _loading() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const VelocityMark(size: 56),
            const SizedBox(height: 16),
            if (_ipcError.isEmpty)
              const CircularProgressIndicator(color: VColors.accent)
            else
              Text(_ipcError,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: VColors.danger)),
          ]),
        ),
      );

  Widget _main(Map<String, dynamic> s) {
    final online = s['online'] == true;
    final ticket = s['ticket'];
    final active = s['activeSession'];
    final lastError = (s['lastError'] ?? '').toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const VelocityHeader(title: 'Velocity Remote Support'),
        const SizedBox(height: 18),
        if (active is Map) ...[
          _ActiveBanner(active: Map<String, dynamic>.from(active)),
          const SizedBox(height: 12),
        ],
        VCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This computer',
                style: TextStyle(fontSize: 12, color: VColors.muted)),
            const SizedBox(height: 4),
            Text(
                (s['computerName'] ?? '').toString().isNotEmpty
                    ? s['computerName']
                    : s['hostname'] ?? '',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: VColors.text)),
            Text('${s['hostname'] ?? ''} · ${s['customerName'] ?? ''}',
                style: const TextStyle(fontSize: 12, color: VColors.muted)),
            const SizedBox(height: 10),
            VStatusDot(on: online, label: online ? 'Connected to Velocity' : 'Not connected'),
            if (!online && lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(lastError,
                    style: const TextStyle(fontSize: 12, color: VColors.warn)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        VCard(
          child: ticket is Map
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Your support request',
                        style: TextStyle(fontSize: 12, color: VColors.muted)),
                    const Spacer(),
                    _Pill(text: (ticket['status'] ?? '').toString()),
                  ]),
                  const SizedBox(height: 6),
                  Text(ticket['number']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700, color: VColors.accent)),
                  Text(ticket['subject']?.toString() ?? '',
                      style: const TextStyle(fontSize: 14, color: VColors.text)),
                ])
              : const Text('No open support requests.',
                  style: TextStyle(fontSize: 14, color: VColors.muted)),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          style: vPrimaryButton(height: 58),
          onPressed: online && !_busy ? _requestSupport : null,
          icon: const Icon(Icons.support_agent, size: 26),
          label: const Text('Get help'),
        ),
        const SizedBox(height: 8),
        const Text(
          'A technician can only connect after you click Accept. You can end the connection at any time.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: VColors.muted),
        ),
        const SizedBox(height: 18),
        Row(children: [
          TextButton.icon(
            onPressed: () => showDialog(
                context: context, builder: (_) => _SettingsDialog(state: s)),
            icon: const Icon(Icons.settings_outlined, size: 18, color: VColors.muted),
            label: const Text('Settings', style: TextStyle(color: VColors.muted)),
          ),
          const Spacer(),
          Text('Version ${s['version'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: VColors.muted)),
        ]),
      ]),
    );
  }

  Future<void> _requestSupport() async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => const _RequestSupportDialog());
    if (result == null || !mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: VColors.ok, size: 44),
        title: const Text('Ticket started'),
        content: Text(
            'Your ticket number is ${result['number']}.\n\nA Velocity technician will contact you soon. Keep this app running so they can reach you.',
            textAlign: TextAlign.center),
        actions: [
          ElevatedButton(
              style: vPrimaryButton(height: 40),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
    _poll();
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: const Color(0xFFE8EEFC), borderRadius: BorderRadius.circular(20)),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, color: VColors.accentDark, fontWeight: FontWeight.w600)),
      );
}

class _ActiveBanner extends StatelessWidget {
  final Map<String, dynamic> active;
  const _ActiveBanner({required this.active});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF4E5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF2C48D))),
        child: Row(children: [
          const Icon(Icons.screen_share, color: VColors.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${active['technicianName']} is connected to this computer (ticket ${active['ticketNumber']}). '
              'To end it, click Disconnect in the connection window.',
              style: const TextStyle(fontSize: 13, color: VColors.text),
            ),
          ),
        ]),
      );
}

/* ---------------- first run: link this PC with a code ---------------- */

class _EnrollView extends StatefulWidget {
  final Map<String, dynamic> state;
  final VoidCallback onDone;
  const _EnrollView({required this.state, required this.onDone});
  @override
  State<_EnrollView> createState() => _EnrollViewState();
}

class _EnrollViewState extends State<_EnrollView> {
  final _code = TextEditingController();
  String _error = '';
  bool _busy = false;

  Future<void> _submit() async {
    if (_code.text.trim().length < 8) {
      setState(() => _error = 'Enter the 8-character code from Velocity.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await velocityCall('enroll', {'code': _code.text.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      widget.onDone();
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastError = (widget.state['lastError'] ?? '').toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const VelocityHeader(title: 'Velocity Remote Support'),
        const SizedBox(height: 28),
        const Text('Link this computer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: VColors.text)),
        const SizedBox(height: 8),
        const Text(
          'Enter the code Velocity gave you. It links this computer to your account so you can ask for help with one click.',
          style: TextStyle(fontSize: 14, color: VColors.muted, height: 1.4),
        ),
        if (lastError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(lastError, style: const TextStyle(fontSize: 13, color: VColors.warn)),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 22, letterSpacing: 4, fontWeight: FontWeight.w700),
          decoration: vInput('Code', hint: 'ABCD-EFGH'),
          onSubmitted: (_) => _submit(),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_error, style: const TextStyle(color: VColors.danger, fontSize: 13)),
        ],
        const SizedBox(height: 16),
        ElevatedButton(
          style: vPrimaryButton(height: 52),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Link computer'),
        ),
        const SizedBox(height: 16),
        Text('Computer: ${widget.state['hostname'] ?? ''}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: VColors.muted)),
        const SizedBox(height: 4),
        const Text("Don't have a code? Call or email Velocity Builds And Repairs.",
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: VColors.muted)),
      ]),
    );
  }
}

/* ---------------- Get help: start a support ticket ---------------- */

class _RequestSupportDialog extends StatefulWidget {
  const _RequestSupportDialog();
  @override
  State<_RequestSupportDialog> createState() => _RequestSupportDialogState();
}

class _RequestSupportDialogState extends State<_RequestSupportDialog> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String _category = kTicketCategories[1];
  String _error = '';
  bool _busy = false;
  // Same key for every retry of this one request, so a double click never makes two tickets.
  final String _key = 'vrs-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in both boxes.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await velocityCall('ticket', {
      'category': _category,
      'subject': _subject.text.trim(),
      'description': _description.text.trim(),
      'key': _key,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final t = (r.data as Map)['ticket'] as Map;
      Navigator.of(context).pop(<String, dynamic>{'number': t['number']});
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get help'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Start a support ticket. Tell us what is wrong and a Velocity technician will get back to you.',
              style: TextStyle(fontSize: 13, color: VColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: vInput('What kind of problem?'),
              items: kTicketCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _subject,
                maxLength: 200,
                decoration: vInput('Short summary', hint: 'e.g. Computer is very slow')),
            const SizedBox(height: 4),
            TextField(
                controller: _description,
                maxLines: 5,
                maxLength: 10000,
                decoration: vInput('What is happening?',
                    hint: 'When did it start? Any error messages?')),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: VColors.danger, fontSize: 13)),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        ElevatedButton(
          style: vPrimaryButton(height: 40),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Starting…' : 'Start ticket'),
        ),
      ],
    );
  }
}

/* ---------------- authorization prompt ---------------- */

class _AuthorizationDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  const _AuthorizationDialog({required this.request});
  @override
  State<_AuthorizationDialog> createState() => _AuthorizationDialogState();
}

class _AuthorizationDialogState extends State<_AuthorizationDialog> {
  late final DateTime _expires;
  Timer? _timer;
  int _left = 0;

  @override
  void initState() {
    super.initState();
    _expires = DateTime.tryParse(widget.request['expiresAt']?.toString() ?? '') ??
        DateTime.now().add(const Duration(minutes: 2));
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final left = _expires.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _timer?.cancel();
      // Expired: never counts as approval.
      if (mounted) Navigator.of(context).pop(false);
      return;
    }
    if (mounted) setState(() => _left = left);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      title: const Row(children: [
        VelocityMark(size: 36),
        SizedBox(width: 12),
        Expanded(child: Text('Remote access request')),
      ]),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _row('Technician', r['technicianName']),
            _row('Ticket', r['ticketNumber']),
            _row('Reason', r['reason']),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: VColors.bg, borderRadius: BorderRadius.circular(8)),
              child: Text((r['authorizationText'] ?? '').toString(),
                  style: const TextStyle(fontSize: 13, height: 1.4, color: VColors.text)),
            ),
            const SizedBox(height: 10),
            Text('This request expires in $_left seconds.',
                style: const TextStyle(fontSize: 12, color: VColors.muted)),
          ]),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        OutlinedButton(
            style: vSecondaryButton(height: 44),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline')),
        ElevatedButton(
            style: vPrimaryButton(height: 44),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Accept')),
      ],
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(fontSize: 13, color: VColors.muted))),
          Expanded(
              child: Text(value?.toString() ?? '',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: VColors.text))),
        ]),
      );
}

/* ---------------- settings ---------------- */

class _SettingsDialog extends StatefulWidget {
  final Map<String, dynamic> state;
  const _SettingsDialog({required this.state});
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  bool? _autostart;
  bool _installed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _installed = bind.mainIsInstalled();
    final stop = await bind.mainGetOption(key: 'stop-service');
    if (mounted) setState(() => _autostart = stop != 'Y');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_installed)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autostart ?? true,
              title: const Text('Start with Windows'),
              subtitle: const Text(
                  'Keeps Velocity Remote Support running so a technician can ask to connect. Nobody can connect without your Accept.'),
              onChanged: _autostart == null
                  ? null
                  : (v) async {
                      setState(() => _autostart = v);
                      await start_service(v);
                    },
            ),
          const SizedBox(height: 8),
          Text('Device ID: ${widget.state['rustdeskId'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: VColors.muted)),
          Text('Version: ${widget.state['version'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: VColors.muted)),
          const SizedBox(height: 16),
          OutlinedButton(
            style: vSecondaryButton(height: 40),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Unlink this computer?'),
                  content: const Text(
                      'Velocity will no longer see this computer. You will need a new code to link it again.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Unlink')),
                  ],
                ),
              );
              if (ok == true) {
                await velocityCall('unenroll');
                if (mounted) Navigator.of(context).pop();
              }
            },
            child: const Text('Unlink this computer'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
