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
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: vSecondaryButton(height: 46),
          onPressed: online
              ? () => showDialog(context: context, builder: (_) => const _TicketsDialog())
              : null,
          icon: const Icon(Icons.forum_outlined, size: 20),
          label: const Text('My tickets'),
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

  Future<void> _getHelp() async {
    final result = await showDialog<String>(context: context, builder: (_) => const _GuestHelpDialog());
    if (result == null || !mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: VColors.ok, size: 44),
        title: const Text('Ticket started'),
        content: Text(
            '$result\n\nA Velocity technician will contact you soon. If they need to see your screen, they will give you a code to link this computer.',
            textAlign: TextAlign.center),
        actions: [
          ElevatedButton(style: vPrimaryButton(height: 40), onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastError = (widget.state['lastError'] ?? '').toString();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const VelocityHeader(title: 'Velocity Remote Support'),
        const SizedBox(height: 24),
        VCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Need help with this computer?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: VColors.text)),
            const SizedBox(height: 6),
            const Text('Start a support ticket. No account or code needed.',
                style: TextStyle(fontSize: 13, color: VColors.muted, height: 1.4)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: vPrimaryButton(height: 58),
              onPressed: _getHelp,
              icon: const Icon(Icons.support_agent, size: 26),
              label: const Text('Get help'),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        const Text('Link this computer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: VColors.text)),
        const SizedBox(height: 8),
        const Text(
          'Have a code from Velocity? Enter it to link this computer to your account, so a technician can connect when you click Accept.',
          style: TextStyle(fontSize: 14, color: VColors.muted, height: 1.4),
        ),
        if (lastError.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(lastError, style: const TextStyle(fontSize: 13, color: VColors.warn)),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _code,
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

/* ---------------- Ticket viewer (linked PCs: this computer's tickets) ---------------- */

String _when(dynamic iso) {
  final d = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (d == null) return '';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${months[d.month - 1]} ${d.day}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}

class _TicketsDialog extends StatefulWidget {
  const _TicketsDialog();
  @override
  State<_TicketsDialog> createState() => _TicketsDialogState();
}

class _TicketsDialogState extends State<_TicketsDialog> {
  List<Map<String, dynamic>>? _tickets;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await velocityCall('tickets');
    if (!mounted) return;
    setState(() {
      if (r.ok && r.data is Map && (r.data as Map)['tickets'] is List) {
        _tickets = ((r.data as Map)['tickets'] as List).map((t) => Map<String, dynamic>.from(t as Map)).toList();
        _error = '';
      } else {
        _tickets = [];
        _error = r.ok ? 'Unexpected answer from Velocity.' : r.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _tickets;
    return AlertDialog(
      title: const Text('My tickets'),
      content: SizedBox(
        width: 440,
        height: 380,
        child: list == null
            ? const Center(child: CircularProgressIndicator())
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_error.isNotEmpty) _FormError(_error),
                if (list.isEmpty && _error.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('No tickets for this computer yet. Click Get help to start one.',
                        textAlign: TextAlign.center, style: TextStyle(color: VColors.muted)),
                  ),
                Expanded(
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final t = list[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        title: Text('${t['number'] ?? ''} · ${t['subject'] ?? ''}',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text('Updated ${_when(t['updatedAt'])}', style: const TextStyle(fontSize: 12)),
                        trailing: _Pill(text: (t['status'] ?? '').toString()),
                        onTap: () async {
                          await showDialog(context: context, builder: (_) => _TicketView(id: t['id'].toString()));
                          _load();
                        },
                      );
                    },
                  ),
                ),
              ]),
      ),
      actions: [
        TextButton(onPressed: _load, child: const Text('Refresh')),
        ElevatedButton(style: vPrimaryButton(height: 40), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _TicketView extends StatefulWidget {
  final String id;
  const _TicketView({required this.id});
  @override
  State<_TicketView> createState() => _TicketViewState();
}

class _TicketViewState extends State<_TicketView> {
  Map<String, dynamic>? _t;
  String _error = '';
  bool _sending = false;
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // New replies from the shop show up while the ticket is open.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await velocityCall('ticket_view', {'id': widget.id});
    if (!mounted) return;
    setState(() {
      if (r.ok && r.data is Map && (r.data as Map)['ticket'] is Map) {
        final before = (_t?['messages'] as List?)?.length ?? -1;
        _t = Map<String, dynamic>.from((r.data as Map)['ticket'] as Map);
        _error = '';
        final after = (_t!['messages'] as List?)?.length ?? 0;
        if (after != before) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
          });
        }
      } else if (_t == null) {
        _error = r.ok ? 'Unexpected answer from Velocity.' : r.error;
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _sending = true;
      _error = '';
    });
    final r = await velocityCall('ticket_reply', {'id': widget.id, 'body': text});
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.ok) {
      _reply.clear();
      _load();
    } else {
      setState(() => _error = r.error);
    }
  }

  Widget _bubble(Map m) {
    final type = (m['authorType'] ?? '').toString();
    if (type == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('${m['body'] ?? ''}',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: VColors.muted)),
      );
    }
    final mine = type == 'customer';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 360),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFE8EEFC) : const Color(0xFFF4F6FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: VColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${mine ? 'You' : (m['authorName'] ?? 'Velocity')} · ${_when(m['createdAt'])}',
              style: const TextStyle(fontSize: 11, color: VColors.muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          SelectableText('${m['body'] ?? ''}', style: const TextStyle(fontSize: 14, color: VColors.text)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final messages = (t?['messages'] as List?) ?? const [];
    final files = (t?['attachments'] as List?) ?? const [];
    final closed = t?['status'] == 'Closed';
    final resolved = t?['status'] == 'Resolved';
    return AlertDialog(
      title: t == null
          ? const Text('Ticket')
          : Row(children: [
              Expanded(
                child: Text('${t['number']} · ${t['subject']}', overflow: TextOverflow.ellipsis),
              ),
              _Pill(text: (t['status'] ?? '').toString()),
            ]),
      content: SizedBox(
        width: 520,
        height: 460,
        child: t == null
            ? (_error.isNotEmpty ? Center(child: _FormError(_error)) : const Center(child: CircularProgressIndicator()))
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_error.isNotEmpty) _FormError(_error),
                Expanded(
                  child: ListView(controller: _scroll, children: [
                    // The original request first, then the conversation.
                    _bubble({'authorType': 'customer', 'body': t['description'], 'createdAt': t['createdAt']}),
                    ...messages.map((m) => _bubble(m as Map)),
                    if (files.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            'Files: ${files.map((f) => (f as Map)['originalName']).join(', ')} (open them in your Velocity customer portal)',
                            style: const TextStyle(fontSize: 12, color: VColors.muted)),
                      ),
                  ]),
                ),
                const SizedBox(height: 8),
                if (resolved)
                  const Text('This ticket is resolved. Replying reopens it.',
                      style: TextStyle(fontSize: 12, color: VColors.muted)),
                if (closed)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('This ticket is closed. Click Get help to start a new one.',
                        style: TextStyle(fontSize: 13, color: VColors.muted)),
                  )
                else
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 10000,
                      decoration: vInput('Write a reply'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 22),
                    child: ElevatedButton(
                      style: vPrimaryButton(height: 44),
                      onPressed: _sending ? null : _send,
                      child: Text(_sending ? 'Sending…' : 'Send'),
                    ),
                  ),
                ]),
              ]),
      ),
      actions: [
        TextButton(onPressed: _load, child: const Text('Refresh')),
        ElevatedButton(style: vPrimaryButton(height: 40), onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

/// A form's error, shown at the top so it is never scrolled out of sight.
class _FormError extends StatelessWidget {
  final String text;
  const _FormError(this.text);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFFDECEA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF1B5AE))),
        child: Text(text, style: const TextStyle(color: VColors.danger, fontSize: 13)),
      );
}

/* ---------------- Get help before linking (the website's public request form) ---------------- */

class _GuestHelpDialog extends StatefulWidget {
  const _GuestHelpDialog();
  @override
  State<_GuestHelpDialog> createState() => _GuestHelpDialogState();
}

class _GuestHelpDialogState extends State<_GuestHelpDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String _category = kTicketCategories[1];
  String _error = '';
  bool _busy = false;

  Future<void> _send() async {
    if ([_name, _email, _subject, _description].any((c) => c.text.trim().isEmpty)) {
      setState(() => _error = 'Please fill in your name, email, summary and what is happening.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await velocityCall('guest_ticket', {
      'name': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'category': _category,
      'subject': _subject.text.trim(),
      'description': _description.text.trim(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final msg = r.data is Map ? (r.data as Map)['message']?.toString() : null;
      Navigator.of(context).pop(msg ?? 'Thanks! We got your request.');
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Get help'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text(
              'Start a support ticket. Tell us how to reach you and what is wrong.',
              style: TextStyle(fontSize: 13, color: VColors.muted, height: 1.4),
            ),
            if (_error.isNotEmpty) _FormError(_error),
            const SizedBox(height: 14),
            TextField(controller: _name, maxLength: 120, decoration: vInput('Your name')),
            const SizedBox(height: 4),
            TextField(controller: _email, maxLength: 254, keyboardType: TextInputType.emailAddress, decoration: vInput('Email')),
            const SizedBox(height: 4),
            TextField(controller: _phone, maxLength: 40, keyboardType: TextInputType.phone, decoration: vInput('Phone (optional)')),
            const SizedBox(height: 4),
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
                maxLength: 9000,
                decoration: vInput('What is happening?', hint: 'When did it start? Any error messages?')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          style: vPrimaryButton(height: 40),
          onPressed: _busy ? null : _send,
          child: Text(_busy ? 'Starting…' : 'Start ticket'),
        ),
      ],
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
            if (_error.isNotEmpty) _FormError(_error),
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
