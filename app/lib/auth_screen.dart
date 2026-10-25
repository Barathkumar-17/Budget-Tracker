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

/// Log in or create an account: a dark side panel and a form, as in the reference.
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
    final wide = isWide(context);
    final form = _form(context);
    return Scaffold(
      backgroundColor: k.paper,
      body: wide
          ? Row(children: [
              Expanded(child: _SidePanel(onDemo: showDemo ? _useDemo : null)),
              Expanded(
                child: Container(
                  color: k.paper,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(32),
                  child: SingleChildScrollView(child: form),
                ),
              ),
            ])
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Logo(),
                      const SizedBox(height: 22),
                      Center(child: form),
                      if (showDemo) ...[
                        const SizedBox(height: 22),
                        Center(child: _DemoBox(onUse: _useDemo, dark: false)),
                      ],
                    ]),
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _busy ? null : widget.onBack,
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to home'),
            style: TextButton.styleFrom(
              foregroundColor: k.ink2,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              textStyle: t.bodyMedium!
                  .copyWith(fontWeight: FontWeight.w600, fontSize: 14.4),
            ),
          ),
        ),
        const SizedBox(height: 12),
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
          child: Text(_registering ? 'Create your account' : 'Welcome back',
              style: t.headlineSmall),
        ),
        const SizedBox(height: 4),
        Text(
          _registering
              ? 'Your expenses, budgets and goals are private to your account.'
              : 'Log in to pick up where you left off.',
          style: t.bodyMedium!.copyWith(color: k.ink2),
        ),
        if (AuthScope.of(context).notice != null) ...[
          const SizedBox(height: 16),
          Alert(AuthScope.of(context).notice!,
              kind: TagKind.cobalt, icon: Icons.info_outline),
        ],
        const SizedBox(height: 8),
        const SizedBox(height: 8),
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
          helper: _registering ? 'At least 8 characters' : null,
          action: _registering ? TextInputAction.next : TextInputAction.done,
          onSubmitted: _registering ? null : (_) => _submit(),
          autofillHints: [
            _registering ? AutofillHints.newPassword : AutofillHints.password
          ],
          suffix: IconBtn(
            icon: _showPassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            tooltip: _showPassword ? 'Hide password' : 'Show password',
            size: 40,
            onPressed: () => setState(() => _showPassword = !_showPassword),
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
          Alert(_formError!, icon: Icons.error_outline),
        ],
        const SizedBox(height: 24),
        Btn(_registering ? 'Create account' : 'Log in',
            busy: _busy, expand: true, onPressed: _submit),
        const SizedBox(height: 14),
        Center(
          child: TextButton(
            onPressed: _busy ? null : () => widget.onMode(!_registering),
            style: TextButton.styleFrom(foregroundColor: k.link),
            child: Text(
                _registering
                    ? 'I already have an account'
                    : 'Create an account',
                style: t.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w600, color: k.link)),
          ),
        ),
      ]),
    );
  }
}

/// Dark left panel: logo, a line of the product's promise, the demo account.
class _SidePanel extends StatelessWidget {
  final VoidCallback? onDemo;
  const _SidePanel({required this.onDemo});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final quote = t.headlineMedium!.copyWith(
        fontSize: 34,
        color: k.onStrong,
        height: 1.2,
        letterSpacing: -0.7,
        fontWeight: FontWeight.w700);
    return Container(
      color: k.strong,
      padding: const EdgeInsets.all(56),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Logo(inverted: true),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 448),
          child: Text.rich(TextSpan(style: quote, children: [
            const TextSpan(text: 'Every rupee,\n'),
            TextSpan(
                text: ' accounted for. ',
                style: quote.copyWith(color: k.onHl, backgroundColor: k.hl)),
          ])),
        ),
        const Spacer(),
        if (onDemo != null) _DemoBox(onUse: onDemo!, dark: true),
      ]),
    );
  }
}

class _DemoBox extends StatelessWidget {
  final VoidCallback onUse;
  final bool dark;
  const _DemoBox({required this.onUse, required this.dark});

  @override
  Widget build(BuildContext context) {
    final k = context.tk;
    final t = Theme.of(context).textTheme;
    final muted = dark ? const Color(0xFFB8C0D9) : k.ink2;
    final strong = dark ? k.onStrong : k.ink;
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: dark ? const Color(0xFF4A5470) : k.line2, width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(
            style: t.bodyMedium!.copyWith(color: muted, fontSize: 14.4),
            children: [
              const TextSpan(text: 'Try the demo account: username '),
              TextSpan(
                  text: demoUser,
                  style: TextStyle(color: strong, fontWeight: FontWeight.w700)),
              const TextSpan(text: ', password '),
              TextSpan(
                  text: demoPassword,
                  style: TextStyle(color: strong, fontWeight: FontWeight.w700)),
              const TextSpan(text: '. It comes with a month of sample data.'),
            ])),
        const SizedBox(height: 12),
        Btn('Use demo account',
            kind: BtnKind.hl, small: true, onPressed: onUse),
      ]),
    );
  }
}
