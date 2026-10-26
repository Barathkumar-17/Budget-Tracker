import 'package:flutter/material.dart';

import 'api.dart';
import 'auth.dart';
import 'theme.dart';
import 'ui.dart';

final _usernamePattern = RegExp(r'^[A-Za-z0-9_.-]{3,30}$');

/// Offer the shared demo account on the login screen (set at build time).
const showDemo = bool.fromEnvironment('SHOW_DEMO');
const demoUser = 'demo';
const demoPassword = 'demo-password';

/// Log in or create an account: one glass card on the midnight page.
class AuthScreen extends StatefulWidget {
  final bool registering;
  final ValueChanged<bool> onMode;
  final VoidCallback onBack;
  const AuthScreen(
      {super.key,
      required this.registering,
      required this.onMode,
      required this.onBack});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _errorKey = GlobalKey();
  bool _showPassword = false;
  bool _busy = false;
  String? _usernameError;
  String? _passwordError;
  String? _confirmError;
  String? _formError;

  bool get _registering => widget.registering;

  @override
  void didUpdateWidget(covariant AuthScreen old) {
    super.didUpdateWidget(old);
    if (old.registering != widget.registering) {
      _usernameError = _passwordError = _confirmError = _formError = null;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

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
      // With the keyboard open the message can sit below the visible part.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _errorKey.currentContext;
        if (c != null && mounted) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 200),
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        }
      });
    }
  }

  void _useDemo() {
    widget.onMode(false);
    setState(() {
      _username.text = demoUser;
      _password.text = demoPassword;
      _usernameError = _passwordError = _formError = null;
    });
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final notice = AuthScope.of(context).notice;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: MediaQuery.sizeOf(context).width < 560 ? 16 : 32,
                vertical: 16),
            child: Row(children: [
              Btn('Back to home',
                  kind: BtnKind.ghost,
                  small: true,
                  icon: Icons.arrow_back,
                  onPressed: _busy ? null : widget.onBack),
              const Spacer(),
              const Logo(compact: true),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(children: [
                    Eyebrow(_registering ? 'New account' : 'Welcome',
                        centered: true),
                    const SizedBox(height: 24),
                    Panel(
                      deep: true,
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SegTabs(
                              boxed: false,
                              labels: const ['Log in', 'Create account'],
                              selected: _registering ? 1 : 0,
                              onChanged: (i) => widget.onMode(i == 1),
                            ),
                            const SizedBox(height: 28),
                            Semantics(
                              header: true,
                              container: true,
                              child: GradientText(
                                  _registering
                                      ? 'Create your account'
                                      : 'Welcome back',
                                  style:
                                      t.headlineSmall!.copyWith(fontSize: 28)),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _registering
                                  ? 'Your expenses, budgets and goals are private to your account.'
                                  : 'Log in to pick up where you left off.',
                              style: t.bodyMedium!.copyWith(color: k.ink3),
                            ),
                            if (notice != null) ...[
                              const SizedBox(height: 16),
                              Alert(notice,
                                  kind: TagKind.cobalt,
                                  icon: Icons.info_outline),
                            ],
                            const SizedBox(height: 20),
                            LabeledField(
                              'Username',
                              _username,
                              autofocus: true,
                              error: _usernameError,
                              helper: _registering
                                  ? 'Letters, numbers, dots, dashes, underscores'
                                  : null,
                              action: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                            ),
                            const SizedBox(height: 14),
                            LabeledField(
                              'Password',
                              _password,
                              obscure: !_showPassword,
                              error: _passwordError,
                              helper:
                                  _registering ? 'At least 8 characters' : null,
                              action: _registering
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onSubmitted:
                                  _registering ? null : (_) => _submit(),
                              autofillHints: [
                                _registering
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password
                              ],
                              suffix: IconBtn(
                                icon: _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                tooltip: _showPassword
                                    ? 'Hide password'
                                    : 'Show password',
                                size: 40,
                                onPressed: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                            if (_registering) ...[
                              const SizedBox(height: 14),
                              LabeledField(
                                'Confirm password',
                                _confirm,
                                obscure: !_showPassword,
                                error: _confirmError,
                                action: TextInputAction.done,
                                onSubmitted: (_) => _submit(),
                              ),
                            ],
                            if (_formError != null) ...[
                              const SizedBox(height: 16),
                              KeyedSubtree(
                                  key: _errorKey,
                                  child: Alert(_formError!,
                                      icon: Icons.error_outline)),
                            ],
                            const SizedBox(height: 24),
                            Btn(_registering ? 'Create account' : 'Log in',
                                busy: _busy,
                                expand: true,
                                squared: true,
                                onPressed: _submit),
                            if (showDemo) ...[
                              const SizedBox(height: 16),
                              _OrDivider(),
                              const SizedBox(height: 16),
                              Btn('Use demo account',
                                  kind: BtnKind.ghost,
                                  expand: true,
                                  icon: Icons.play_circle_outline,
                                  onPressed: _busy ? null : _useDemo),
                              const SizedBox(height: 10),
                              Text(
                                'Username $demoUser, password $demoPassword. It comes with a month of sample data.',
                                textAlign: TextAlign.center,
                                style: t.labelSmall,
                              ),
                            ],
                          ]),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed:
                          _busy ? null : () => widget.onMode(!_registering),
                      style: TextButton.styleFrom(foregroundColor: k.link),
                      child: Text(
                          _registering
                              ? 'I already have an account'
                              : 'Create an account',
                          style: t.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w500, color: k.link)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    Widget rule() => Expanded(child: Container(height: 1, color: k.line));
    return Row(children: [
      rule(),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text('OR', style: Theme.of(context).textTheme.labelSmall),
      ),
      rule(),
    ]);
  }
}
