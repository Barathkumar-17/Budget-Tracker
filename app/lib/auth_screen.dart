import 'package:flutter/material.dart';

import 'api.dart';
import 'auth.dart';
import 'theme.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9_.-]{3,30}$');

/// Log in or create an account.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _registering = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _usernameError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _switchMode() => setState(() {
        _registering = !_registering;
        _usernameError = _passwordError = _confirmError = _formError = null;
      });

  bool _validate() {
    final name = _username.text.trim();
    final pass = _password.text;
    String? u, p, c;
    if (_registering) {
      if (!_usernamePattern.hasMatch(name)) {
        u = 'Use 3-30 letters, numbers, dots, dashes or underscores';
      }
      if (pass.length < 8) p = 'Use at least 8 characters';
      if (_confirm.text != pass) c = 'The passwords do not match';
    } else {
      if (name.isEmpty) u = 'Enter your username';
      if (pass.isEmpty) p = 'Enter your password';
    }
    setState(() {
      _usernameError = u;
      _passwordError = p;
      _confirmError = c;
      _formError = null;
    });
    return u == null && p == null && c == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    setState(() => _busy = true);
    final auth = AuthScope.read(context);
    try {
      final name = _username.text.trim();
      if (_registering) {
        await auth.register(name, _password.text);
      } else {
        await auth.login(name, _password.text);
      }
      // The gate swaps this screen for the app once the status changes.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (_registering && e.status == 409) {
          _usernameError = e.message;
        } else {
          _formError = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _formError =
          'Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final notice = AuthScope.of(context).notice;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          _Header(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                            _registering ? 'Create your account' : 'Log in',
                            style: t.headlineSmall),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _registering
                            ? 'Your expenses, budgets and goals are private to your account.'
                            : 'Welcome back. Pick up where you left off.',
                        style:
                            t.bodyMedium!.copyWith(color: s.onSurfaceVariant),
                      ),
                      if (notice != null) ...[
                        const SizedBox(height: 16),
                        _Banner(
                            icon: Icons.info_outline,
                            text: notice,
                            bg: s.secondaryContainer,
                            fg: s.onSecondaryContainer),
                      ],
                      const SizedBox(height: 20),
                      TextField(
                        controller: _username,
                        autofocus: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        decoration: InputDecoration(
                          labelText: 'Username',
                          errorText: _usernameError,
                          helperText: _registering
                              ? 'Letters, numbers, dots, dashes, underscores'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: !_showPassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: _registering
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onSubmitted: _registering ? null : (_) => _submit(),
                        autofillHints: [
                          _registering
                              ? AutofillHints.newPassword
                              : AutofillHints.password
                        ],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          errorText: _passwordError,
                          helperText:
                              _registering ? 'At least 8 characters' : null,
                          suffixIcon: IconButton(
                            tooltip: _showPassword
                                ? 'Hide password'
                                : 'Show password',
                            icon: Icon(_showPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                            onPressed: () =>
                                setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                      ),
                      if (_registering) ...[
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirm,
                          obscureText: !_showPassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                              labelText: 'Confirm password',
                              errorText: _confirmError),
                        ),
                      ],
                      if (_formError != null) ...[
                        const SizedBox(height: 16),
                        _Banner(
                            icon: Icons.error_outline,
                            text: _formError!,
                            bg: s.errorContainer,
                            fg: s.onErrorContainer),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5))
                            : Text(_registering ? 'Create account' : 'Log in'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : _switchMode,
                        child: Text(_registering
                            ? 'I already have an account'
                            : 'Create an account'),
                      ),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The navy band with the app's name; a short rail line sets the idea.
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.paddingOf(context).top + 44, 24, 36),
      decoration: BoxDecoration(
        color: headerColor(brightness),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Semantics(
              header: true,
              child: Text('Budget Tracker',
                  style: t.headlineMedium!.copyWith(color: Colors.white)),
            ),
            const SizedBox(height: 6),
            Text('Know where your money goes.',
                style: t.bodyLarge!.copyWith(color: const Color(0xFFC9D4E8))),
            const SizedBox(height: 22),
            const ExcludeSemantics(child: _HeaderLine()),
          ]),
        ),
      ),
    );
  }
}

/// A small rail line on the navy band: a line that has travelled most of the way to its station.
class _HeaderLine extends StatelessWidget {
  const _HeaderLine();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 24,
        child: CustomPaint(size: Size.infinite, painter: _HeaderLinePainter()),
      );
}

class _HeaderLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const ring = 8.0, left = 5.0;
    final right = size.width - ring - 2;
    final cy = size.height / 2;
    Paint line(Color c) => Paint()
      ..color = c
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(left, cy), Offset(right, cy), line(const Color(0xFF2B3F63)));
    canvas.drawLine(Offset(left, cy), Offset(left + (right - left) * 0.64, cy),
        line(const Color(0xFF7FA2FF)));
    canvas.drawCircle(
        Offset(left, cy), 4, Paint()..color = const Color(0xFF7FA2FF));
    canvas.drawCircle(
        Offset(right, cy), ring, Paint()..color = const Color(0xFF12233F));
    canvas.drawCircle(
        Offset(right, cy),
        ring - 1.5,
        Paint()
          ..color = const Color(0xFFC9D4E8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color bg;
  final Color fg;
  const _Banner(
      {required this.icon,
      required this.text,
      required this.bg,
      required this.fg});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium!
                      .copyWith(color: fg))),
        ]),
      ),
    );
  }
}
