// Velocity Remote Support: the customer's main window.
//
// The app links itself to Velocity on first start (no code). Staff match the computer to the
// customer in the admin dashboard. Nobody can connect without the customer clicking Accept here.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:url_launcher/url_launcher.dart';
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

/// Local flag: the customer already answered the "Start with Windows" question.
const _kAutostartAsked = 'velocity-autostart-asked';

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
  String? _endedShown;
  bool _helpBusy = false;
  bool _askAutostart = false;

  @override
  void initState() {
    super.initState();
    _askAutostart = bind.mainIsInstalled() && bind.mainGetLocalOption(key: _kAutostartAsked) != 'Y';
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
    final ended = _state?['lastEnded'];
    if (ended is Map && ended['sessionId'] != _endedShown) {
      _endedShown = ended['sessionId'] as String?;
      final mins = ended['minutes'] ?? 1;
      velocityCall('notify', {
        'title': 'Velocity disconnected',
        'body': '${ended['technicianName']} is no longer connected. The session lasted $mins minute${mins == 1 ? '' : 's'}.',
      });
    }
  }

  Future<void> _showAuthorization(Map<String, dynamic> req) async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    final ticket = req['ticketNumber'];
    velocityCall('notify', {
      'title': 'Velocity wants to connect',
      'body': ticket != null
          ? '${req['technicianName']} is asking to connect for ticket $ticket. Open Velocity Remote Support to answer.'
          : '${req['technicianName']} is asking to connect. Open Velocity Remote Support to answer.'
    });
    final answer = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AuthorizationDialog(request: req),
    );
    final accepted = answer?['accept'] == true;
    final r = await velocityCall('respond', {
      'requestId': req['id'],
      'accept': accepted,
      'allowFiles': accepted && answer?['allowFiles'] == true,
    });
    if (!mounted) return;
    if (accepted && r.ok) {
      _snack('Approved. Your technician is connecting now.');
    } else if (accepted) {
      _snack(r.error);
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
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
          child: s == null ? _loading() : (s['linked'] == true ? _main(s) : _connecting(s)),
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
              Text(_ipcError, textAlign: TextAlign.center, style: const TextStyle(color: VColors.danger)),
          ]),
        ),
      );

  /// First start: the background service registers this computer with Velocity by itself.
  Widget _connecting(Map<String, dynamic> s) {
    final lastError = (s['lastError'] ?? '').toString();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const VelocityMark(size: 64),
          const SizedBox(height: 20),
          const Text('Connecting to Velocity…', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: VColors.text)),
          const SizedBox(height: 8),
          const Text('This only takes a moment. No code needed.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: VColors.muted)),
          const SizedBox(height: 18),
          if (lastError.isEmpty)
            const CircularProgressIndicator(color: VColors.accent)
          else
            Text(lastError, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: VColors.warn)),
          const SizedBox(height: 18),
          Text('Computer: ${s['hostname'] ?? ''}', style: const TextStyle(fontSize: 12, color: VColors.muted)),
        ]),
      ),
    );
  }

  Widget _main(Map<String, dynamic> s) {
    final online = s['online'] == true;
    final ticket = s['ticket'];
    final active = s['activeSession'];
    final update = s['update'];
    final ended = s['lastEnded'];
    final match = s['match'] is Map ? Map<String, dynamic>.from(s['match']) : <String, dynamic>{};
    final firstName = (match['firstName'] ?? '').toString();
    final helpRequested = s['helpRequested'] == true;
    final lastError = (s['lastError'] ?? '').toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const VelocityHeader(title: 'Velocity Remote Support'),
        const SizedBox(height: 18),
        if (update is Map) ...[
          _Banner(
            icon: Icons.system_update_alt,
            color: VColors.accent,
            background: const Color(0xFFE8EEFC),
            text: 'Version ${update['version']} is available.',
            action: 'Download',
            onAction: () => launchUrl(Uri.parse(update['url'].toString()), mode: LaunchMode.externalApplication),
          ),
          const SizedBox(height: 12),
        ],
        if (active is Map) ...[
          _ActiveBanner(active: Map<String, dynamic>.from(active)),
          const SizedBox(height: 12),
        ] else if (ended is Map) ...[
          _Banner(
            icon: Icons.check_circle_outline,
            color: VColors.ok,
            background: const Color(0xFFE7F5EE),
            text: '${ended['technicianName']} disconnected. The session lasted ${ended['minutes']} minute${ended['minutes'] == 1 ? '' : 's'}.',
            action: 'OK',
            onAction: () => velocityCall('dismiss_ended'),
          ),
          const SizedBox(height: 12),
        ],
        if (_askAutostart) ...[
          _AutostartCard(onDone: () => setState(() => _askAutostart = false)),
          const SizedBox(height: 12),
        ],
        VCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This computer', style: TextStyle(fontSize: 12, color: VColors.muted)),
            const SizedBox(height: 4),
            Text((s['hostname'] ?? '').toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: VColors.text)),
            if (firstName.isNotEmpty)
              Text('Linked to $firstName', style: const TextStyle(fontSize: 12, color: VColors.muted)),
            const SizedBox(height: 10),
            VStatusDot(on: online, label: online ? 'Connected to Velocity, ready for help' : 'Not connected'),
            if (!online && lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(lastError, style: const TextStyle(fontSize: 12, color: VColors.warn)),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        VCard(
          child: ticket is Map
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Your support request', style: TextStyle(fontSize: 12, color: VColors.muted)),
                    const Spacer(),
                    _Pill(text: (ticket['status'] ?? '').toString()),
                  ]),
                  const SizedBox(height: 6),
                  Text(ticket['number']?.toString() ?? '',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: VColors.accent)),
                  Text(ticket['subject']?.toString() ?? '', style: const TextStyle(fontSize: 14, color: VColors.text)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    style: vSecondaryButton(height: 40),
                    onPressed: () => showDialog(context: context, builder: (_) => const _MessagesDialog()),
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('Messages'),
                  ),
                ])
              : const Text('No open support requests.', style: TextStyle(fontSize: 14, color: VColors.muted)),
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          style: vPrimaryButton(height: 58),
          onPressed: online ? () => _requestSupport(match['state'] == 'unmatched') : null,
          icon: const Icon(Icons.support_agent, size: 26),
          label: const Text('Request Support'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: vSecondaryButton(height: 46),
          onPressed: online && !helpRequested && !_helpBusy ? _getHelpNow : null,
          icon: Icon(helpRequested ? Icons.check : Icons.campaign_outlined, size: 20),
          label: Text(helpRequested ? 'Velocity has been notified' : 'Get help now'),
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
            onPressed: () => showDialog(context: context, builder: (_) => _SettingsDialog(state: s)),
            icon: const Icon(Icons.settings_outlined, size: 18, color: VColors.muted),
            label: const Text('Settings', style: TextStyle(color: VColors.muted)),
          ),
          const Spacer(),
          Text('Version ${s['version'] ?? ''}', style: const TextStyle(fontSize: 12, color: VColors.muted)),
        ]),
      ]),
    );
  }

  Future<void> _getHelpNow() async {
    setState(() => _helpBusy = true);
    final r = await velocityCall('help');
    if (!mounted) return;
    setState(() => _helpBusy = false);
    _snack(r.ok ? 'Velocity has been notified. A technician will reach out soon.' : r.error);
    _poll();
  }

  Future<void> _requestSupport(bool askContact) async {
    final result = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _RequestSupportDialog(askContact: askContact));
    if (result == null || !mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: VColors.ok, size: 44),
        title: const Text('Request sent'),
        content: Text(
            'Your ticket number is ${result['number']}.\n\nA Velocity technician will contact you soon. Keep this app running so they can reach you.',
            textAlign: TextAlign.center),
        actions: [
          ElevatedButton(style: vPrimaryButton(height: 40), onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
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
        decoration: BoxDecoration(color: const Color(0xFFE8EEFC), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: const TextStyle(fontSize: 11, color: VColors.accentDark, fontWeight: FontWeight.w600)),
      );
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final String text;
  final String action;
  final VoidCallback onAction;
  const _Banner({required this.icon, required this.color, required this.background, required this.text, required this.action, required this.onAction});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: VColors.text))),
          TextButton(onPressed: onAction, child: Text(action, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
        ]),
      );
}

class _ActiveBanner extends StatelessWidget {
  final Map<String, dynamic> active;
  const _ActiveBanner({required this.active});
  @override
  Widget build(BuildContext context) {
    final ticket = (active['ticketNumber'] ?? '').toString();
    final files = active['allowFiles'] == true;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF2C48D))),
      child: Row(children: [
        const Icon(Icons.screen_share, color: VColors.warn),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${active['technicianName']} is connected to this computer${ticket.isNotEmpty ? ' (ticket $ticket)' : ''}. '
            'File transfer is ${files ? 'allowed' : 'off'}. To end it, click Disconnect in the connection window.',
            style: const TextStyle(fontSize: 13, color: VColors.text),
          ),
        ),
      ]),
    );
  }
}

/// Asked once after install: the spec requires the customer's consent to start with Windows.
class _AutostartCard extends StatelessWidget {
  final VoidCallback onDone;
  const _AutostartCard({required this.onDone});

  Future<void> _answer(bool yes) async {
    await bind.mainSetLocalOption(key: _kAutostartAsked, value: 'Y');
    final stopped = await bind.mainGetOption(key: 'stop-service') == 'Y';
    if (yes == stopped) await start_service(yes);
    onDone();
  }

  @override
  Widget build(BuildContext context) => VCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Start Velocity Remote Support when Windows starts?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: VColors.text)),
          const SizedBox(height: 6),
          const Text(
            'Recommended. Velocity can then ask to connect whenever you need help. Nobody can connect without your Accept. '
            'If you choose No, Velocity can only reach this computer while you turn this on in Settings.',
            style: TextStyle(fontSize: 13, color: VColors.muted, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(style: vSecondaryButton(height: 40), onPressed: () => _answer(false), child: const Text('No'))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(style: vPrimaryButton(height: 40), onPressed: () => _answer(true), child: const Text('Yes, start with Windows'))),
          ]),
        ]),
      );
}

/* ---------------- Request Support ---------------- */

class _RequestSupportDialog extends StatefulWidget {
  /// This computer is not linked to a customer yet: ask who they are.
  final bool askContact;
  const _RequestSupportDialog({required this.askContact});
  @override
  State<_RequestSupportDialog> createState() => _RequestSupportDialogState();
}

class _RequestSupportDialogState extends State<_RequestSupportDialog> {
  final _subject = TextEditingController();
  final _description = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  String _category = kTicketCategories[1];
  String _error = '';
  bool _busy = false;
  // Same key for every retry of this one request, so a double click never makes two tickets.
  final String _key = 'vrs-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

  Future<void> _send() async {
    if (_subject.text.trim().isEmpty || _description.text.trim().isEmpty) {
      setState(() => _error = 'Please fill in the summary and what is happening.');
      return;
    }
    if (widget.askContact && (_name.text.trim().isEmpty || !_email.text.contains('@'))) {
      setState(() => _error = 'Please enter your name and email so we know who you are.');
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
      if (widget.askContact)
        'contact': {
          'name': _name.text.trim(),
          'email': _email.text.trim(),
          if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
        },
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
      title: const Text('Request Support'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.askContact) ...[
              const Text('First, tell us who you are so we can reach you.', style: TextStyle(fontSize: 13, color: VColors.muted)),
              const SizedBox(height: 10),
              TextField(controller: _name, maxLength: 120, decoration: vInput('Your name')),
              const SizedBox(height: 4),
              TextField(controller: _email, maxLength: 254, keyboardType: TextInputType.emailAddress, decoration: vInput('Email')),
              const SizedBox(height: 4),
              TextField(controller: _phone, maxLength: 40, keyboardType: TextInputType.phone, decoration: vInput('Phone (optional)')),
              const SizedBox(height: 8),
            ],
            DropdownButtonFormField<String>(
              value: _category,
              isExpanded: true,
              decoration: vInput('What kind of problem?'),
              items: kTicketCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(controller: _subject, maxLength: 200, decoration: vInput('Short summary', hint: 'e.g. Computer is very slow')),
            const SizedBox(height: 4),
            TextField(
                controller: _description,
                maxLines: 5,
                maxLength: 10000,
                decoration: vInput('What is happening?', hint: 'When did it start? Any error messages?')),
            if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: VColors.danger, fontSize: 13)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: vPrimaryButton(height: 40),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Sending…' : 'Send request'),
        ),
      ],
    );
  }
}

/* ---------------- Messages on the open ticket ---------------- */

class _MessagesDialog extends StatefulWidget {
  const _MessagesDialog();
  @override
  State<_MessagesDialog> createState() => _MessagesDialogState();
}

class _MessagesDialogState extends State<_MessagesDialog> {
  List<Map<String, dynamic>> _messages = [];
  Map<String, dynamic>? _ticket;
  String _error = '';
  bool _loading = true;
  bool _sending = false;
  final _reply = TextEditingController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await velocityCall('messages');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r.ok) {
        final d = Map<String, dynamic>.from(r.data as Map);
        _ticket = d['ticket'] is Map ? Map<String, dynamic>.from(d['ticket']) : null;
        _messages = ((d['messages'] as List?) ?? []).map((m) => Map<String, dynamic>.from(m as Map)).toList();
        _error = '';
      } else {
        _error = r.error;
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final r = await velocityCall('reply', {'body': text});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _reply.clear();
      _load();
    } else {
      setState(() => _error = r.error);
    }
  }

  String _when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.month}/${t.day} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_ticket != null ? 'Messages · ${_ticket!['number']}' : 'Messages'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: VColors.accent))
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet.', style: TextStyle(color: VColors.muted)))
                    : ListView(
                        reverse: true,
                        children: _messages.reversed.map((m) {
                          final mine = m['authorType'] == 'customer';
                          final who = mine ? 'You' : (m['authorType'] == 'staff' ? (m['authorName'] ?? 'Velocity').toString() : 'Velocity');
                          return Align(
                            alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(10),
                              constraints: const BoxConstraints(maxWidth: 340),
                              decoration: BoxDecoration(
                                color: mine ? const Color(0xFFE8EEFC) : VColors.bg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('$who · ${_when(m['createdAt']?.toString() ?? '')}', style: const TextStyle(fontSize: 11, color: VColors.muted)),
                                const SizedBox(height: 3),
                                SelectableText((m['body'] ?? '').toString(), style: const TextStyle(fontSize: 14, color: VColors.text)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
          ),
          if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: VColors.danger, fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: _reply, minLines: 1, maxLines: 4, maxLength: 10000, decoration: vInput('Write a reply'))),
            const SizedBox(width: 8),
            ElevatedButton(style: vPrimaryButton(height: 44), onPressed: _sending ? null : _send, child: Text(_sending ? '…' : 'Send')),
          ]),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
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
  bool _allowFiles = false;

  @override
  void initState() {
    super.initState();
    _expires = DateTime.tryParse(widget.request['expiresAt']?.toString() ?? '') ?? DateTime.now().add(const Duration(minutes: 2));
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    final left = _expires.difference(DateTime.now()).inSeconds;
    if (left <= 0) {
      _timer?.cancel();
      // Expired: never counts as approval.
      if (mounted) Navigator.of(context).pop(<String, dynamic>{'accept': false});
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
    final ticket = r['ticketNumber'];
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
            _row('Ticket', ticket ?? 'A new support ticket will be opened'),
            _row('Reason', r['reason']),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: VColors.bg, borderRadius: BorderRadius.circular(8)),
              child: Text((r['authorizationText'] ?? '').toString(), style: const TextStyle(fontSize: 13, height: 1.4, color: VColors.text)),
            ),
            const SizedBox(height: 6),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _allowFiles,
              onChanged: (v) => setState(() => _allowFiles = v ?? false),
              title: const Text('Also allow file transfer for this session', style: TextStyle(fontSize: 14)),
              subtitle: const Text('Leave this off unless the technician asked for it.', style: TextStyle(fontSize: 12)),
            ),
            Text('This request expires in $_left seconds.', style: const TextStyle(fontSize: 12, color: VColors.muted)),
          ]),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        OutlinedButton(
            style: vSecondaryButton(height: 44),
            onPressed: () => Navigator.of(context).pop(<String, dynamic>{'accept': false}),
            child: const Text('Decline')),
        ElevatedButton(
            style: vPrimaryButton(height: 44),
            onPressed: () => Navigator.of(context).pop(<String, dynamic>{'accept': true, 'allowFiles': _allowFiles}),
            child: const Text('Accept')),
      ],
    );
  }

  Widget _row(String label, dynamic value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13, color: VColors.muted))),
          Expanded(child: Text(value?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: VColors.text))),
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
  List<Map<String, dynamic>>? _sessions;
  Map<String, dynamic> _hardware = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _installed = bind.mainIsInstalled();
    final stop = await bind.mainGetOption(key: 'stop-service');
    if (mounted) setState(() => _autostart = stop != 'Y');
    final hw = await velocityCall('hardware');
    final ss = await velocityCall('sessions');
    if (!mounted) return;
    setState(() {
      if (hw.ok && hw.data is Map) _hardware = Map<String, dynamic>.from(hw.data as Map);
      _sessions = ss.ok ? (((ss.data as Map)['sessions'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList() : [];
    });
  }

  String _date(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.month}/${t.day}/${t.year} $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final ramGb = _hardware['ramGb'];
    final info = <String>[
      'Computer name: ${s['hostname'] ?? ''}',
      if (_hardware['manufacturer'] != null || _hardware['model'] != null)
        'Make and model: ${[_hardware['manufacturer'], _hardware['model']].where((x) => x != null).join(' ')}',
      if (_hardware['serialNumber'] != null) 'Serial number: ${_hardware['serialNumber']}',
      if (_hardware['cpu'] != null) 'Processor: ${_hardware['cpu']}',
      if (ramGb != null) 'Memory: $ramGb GB',
      'Device ID: ${s['rustdeskId'] ?? ''}',
    ];
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_installed)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autostart ?? true,
                title: const Text('Start with Windows'),
                subtitle: const Text('Keeps Velocity Remote Support running so a technician can ask to connect. Nobody can connect without your Accept.'),
                onChanged: _autostart == null
                    ? null
                    : (v) async {
                        setState(() => _autostart = v);
                        await bind.mainSetLocalOption(key: _kAutostartAsked, value: 'Y');
                        await start_service(v);
                      },
              ),
            const SizedBox(height: 12),
            const Text('Every time Velocity connected', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: VColors.text)),
            const SizedBox(height: 6),
            if (_sessions == null)
              const LinearProgressIndicator(color: VColors.accent)
            else if (_sessions!.isEmpty)
              const Text('Velocity has never connected to this computer.', style: TextStyle(fontSize: 13, color: VColors.muted))
            else
              ..._sessions!.map((x) {
                final secs = x['durationSeconds'];
                final len = secs is int ? '${max(1, (secs / 60).round())} min' : 'still connected';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${_date(x['startedAt']?.toString())} · ${x['technicianName'] ?? 'Technician'} · $len${x['ticketNumber'] != null ? ' · ${x['ticketNumber']}' : ''}',
                    style: const TextStyle(fontSize: 13, color: VColors.text),
                  ),
                );
              }),
            const SizedBox(height: 14),
            const Text('Information this app sends to Velocity', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: VColors.text)),
            const SizedBox(height: 6),
            ...info.map((t) => Text(t, style: const TextStyle(fontSize: 13, color: VColors.muted))),
            const SizedBox(height: 4),
            const Text('Plus your Windows version and the app version.',
                style: TextStyle(fontSize: 12, color: VColors.muted)),
            const SizedBox(height: 12),
            Text('Version: ${s['version'] ?? ''}', style: const TextStyle(fontSize: 13, color: VColors.muted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}
