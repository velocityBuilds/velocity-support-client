// Velocity Remote Technician: staff sign-in and the "ready" screen.
// Technicians pick a computer and click Connect in the admin dashboard; this app waits for the
// customer's Accept, fetches the single-use connection token and opens the remote window.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';

import 'velocity_api.dart';

class VelocityTechHome extends StatefulWidget {
  const VelocityTechHome({super.key});
  @override
  State<VelocityTechHome> createState() => _VelocityTechHomeState();
}

class _VelocityTechHomeState extends State<VelocityTechHome> {
  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _requests = [];
  String _status = '';
  Timer? _timer;
  final Set<String> _opened = {};

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadMe() async {
    final r = await velocityCall('tech_me');
    if (!mounted) return;
    setState(() => _me = r.ok ? Map<String, dynamic>.from(r.data as Map) : {'signedIn': false});
    if (_me?['signedIn'] == true) _startPolling();
  }

  void _startPolling() {
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  Future<void> _poll() async {
    final r = await velocityCall('tech_ready');
    if (!mounted) return;
    if (!r.ok) {
      if (r.error == 'signed_out') {
        _timer?.cancel();
        setState(() => _me = {'signedIn': false});
      } else {
        setState(() => _status = r.error);
      }
      return;
    }
    final list = ((r.data as Map)['requests'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    setState(() {
      _requests = list;
      _status = '';
    });
    for (final req in list) {
      final id = req['id'] as String;
      if (req['readyToConnect'] == true && !_opened.contains(id)) {
        _opened.add(id);
        _openSession(req);
      }
    }
  }

  Future<void> _openSession(Map<String, dynamic> req) async {
    final r = await velocityCall('tech_token', {
      'requestId': req['id'],
      'info': {
        'customerName': req['customerName'],
        'ticketNumber': req['ticketNumber'],
        'ticketSubject': req['ticketSubject'],
        'hostname': req['hostname'],
      },
    });
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _status = r.error);
      return;
    }
    final peerId = (r.data as Map)['peerId'] as String;
    connect(context, peerId);
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: VColors.accent),
      ),
      child: Container(
        color: VColors.bg,
        child: me == null
            ? const Center(child: CircularProgressIndicator(color: VColors.accent))
            : (me['signedIn'] == true ? _ready(me) : _SignIn(onSignedIn: _loadMe)),
      ),
    );
  }

  Widget _ready(Map<String, dynamic> me) {
    final user = me['user'] is Map ? me['user'] as Map : const {};
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(padding: const EdgeInsets.all(28), children: [
          Row(children: [
            const Expanded(child: VelocityHeader(title: 'Velocity Remote Technician')),
            TextButton(
              onPressed: () async {
                _timer?.cancel();
                await velocityCall('tech_logout');
                _opened.clear();
                if (mounted) setState(() => _me = {'signedIn': false});
              },
              child: const Text('Sign out'),
            ),
          ]),
          const SizedBox(height: 20),
          VCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              VStatusDot(on: _status.isEmpty, label: _status.isEmpty ? 'Ready to connect' : 'Problem'),
              const SizedBox(height: 6),
              Text('Signed in as ${user['name'] ?? ''} (${user['email'] ?? ''})',
                  style: const TextStyle(color: VColors.text)),
              if (_status.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(_status, style: const TextStyle(color: VColors.danger, fontSize: 13))),
              const SizedBox(height: 10),
              const Text(
                'Keep this app open. In the admin dashboard, open a ticket or computer and click Connect. '
                'When the customer clicks Accept, the remote window opens here automatically.',
                style: TextStyle(fontSize: 13, color: VColors.muted, height: 1.4),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          const Text('Your requests',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: VColors.muted)),
          const SizedBox(height: 8),
          if (_requests.isEmpty)
            const VCard(child: Text('No open requests.', style: TextStyle(color: VColors.muted)))
          else
            ..._requests.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: VCard(
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['customerName'] ?? 'Customer'} · ${r['hostname']}',
                              style: const TextStyle(fontWeight: FontWeight.w700, color: VColors.text)),
                          Text(r['ticketNumber'] != null ? '${r['ticketNumber']} — ${r['ticketSubject']}' : 'No ticket yet: one opens when the customer accepts',
                              style: const TextStyle(fontSize: 13, color: VColors.muted)),
                        ]),
                      ),
                      Text(
                        r['status'] == 'pending' ? 'Waiting for customer…' : 'Approved',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: r['status'] == 'pending' ? VColors.warn : VColors.ok),
                      ),
                    ]),
                  ),
                )),
          const SizedBox(height: 16),
          Text('This PC\'s ID: ${me['rustdeskId'] ?? ''} · Version ${me['version'] ?? ''}',
              style: const TextStyle(fontSize: 12, color: VColors.muted)),
        ]),
      ),
    );
  }
}

class _SignIn extends StatefulWidget {
  final VoidCallback onSignedIn;
  const _SignIn({required this.onSignedIn});
  @override
  State<_SignIn> createState() => _SignInState();
}

class _SignInState extends State<_SignIn> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _error = '';
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await velocityCall('tech_login', {'email': _email.text.trim(), 'password': _password.text});
    if (!mounted) return;
    setState(() => _busy = false);
    _password.clear();
    if (r.ok) {
      widget.onSignedIn();
    } else {
      setState(() => _error = r.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: VCard(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const VelocityHeader(title: 'Velocity Remote Technician'),
            const SizedBox(height: 24),
            const Text('Sign in with your Velocity staff account.',
                style: TextStyle(color: VColors.muted)),
            const SizedBox(height: 16),
            TextField(controller: _email, decoration: vInput('Email'), autofocus: true),
            const SizedBox(height: 12),
            TextField(
                controller: _password,
                obscureText: true,
                decoration: vInput('Password'),
                onSubmitted: (_) => _submit()),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(_error, style: const TextStyle(color: VColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            ElevatedButton(
              style: vPrimaryButton(height: 48),
              onPressed: _busy ? null : _submit,
              child: Text(_busy ? 'Signing in…' : 'Sign in'),
            ),
          ]),
        ),
      ),
    );
  }
}
