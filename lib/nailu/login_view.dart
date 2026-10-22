import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'challenge.dart';
import 'config.dart';
import 'session.dart';
import 'registration_view.dart';

class NailuLoginView extends StatefulWidget {
  const NailuLoginView({
    super.key,
    required this.session,
    this.challengeBuilder,
  });
  final NailuSession session;
  final Widget Function(ValueChanged<String?> onToken)? challengeBuilder;

  @override
  State<NailuLoginView> createState() => _NailuLoginViewState();
}

class _NailuLoginViewState extends State<NailuLoginView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _challenge;
  String? _error;
  int _challengeGeneration = 0;
  bool _rememberPassword = false;
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreCredentials());
  }

  Future<void> _restoreCredentials() async {
    try {
      final credentials = await widget.session.rememberedCredentials();
      if (!mounted ||
          credentials == null ||
          _email.text.isNotEmpty ||
          _password.text.isNotEmpty) {
        return;
      }
      setState(() {
        _email.text = credentials.email;
        _password.text = credentials.password;
        _rememberPassword = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.appLocalizations.nailuActionFailed);
      }
    }
  }

  Future<void> _login() async {
    if (widget.session.busy || !_form.currentState!.validate()) return;
    final token = _challenge;
    if (token == null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _challenge = null;
    });
    try {
      await widget.session.login(
        email: _email.text,
        password: _password.text,
        challenge: token,
        rememberPassword: _rememberPassword,
      );
      _password.clear();
    } catch (_) {
      if (mounted) _error = context.appLocalizations.nailuLoginFailed;
    } finally {
      if (mounted) setState(() => _challengeGeneration++);
    }
  }

  Future<void> _open(String url) async {
    if (!await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        ) &&
        mounted) {
      setState(() => _error = context.appLocalizations.nailuActionFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.appLocalizations;
    if (_registering) {
      return NailuRegistrationView(
        onBack: () => setState(() => _registering = false),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    SvgPicture.asset(
                      'assets/images/nailu-giraffe.svg',
                      height: 112,
                    ),
                    Text(
                      NailuConfig.name,
                      textAlign: TextAlign.center,
                      style: AppTextStyle.largeTitle.of(
                        context,
                        emphasized: true,
                      ),
                    ),
                    Text(
                      strings.nailuLoginRequired,
                      textAlign: TextAlign.center,
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      decoration: InputDecoration(
                        labelText: strings.nailuEmail,
                      ),
                      validator: (value) =>
                          value != null &&
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(value.trim())
                          ? null
                          : strings.nailuEmailInvalid,
                    ),
                    SecretTextFormField(
                      controller: _password,
                      decoration: InputDecoration(
                        labelText: strings.nailuPassword,
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => unawaited(_login()),
                      validator: (value) => value == null || value.isEmpty
                          ? strings.nailuPasswordRequired
                          : null,
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _rememberPassword,
                      title: Text(strings.nailuRememberPassword),
                      subtitle: Text(strings.nailuRememberPasswordHint),
                      onChanged: widget.session.busy
                          ? null
                          : (value) async {
                              setState(
                                () => _rememberPassword = value ?? false,
                              );
                              if (_rememberPassword) return;
                              try {
                                await widget.session.forgetCredentials();
                              } catch (_) {
                                if (mounted) {
                                  setState(
                                    () => _error = strings.nailuActionFailed,
                                  );
                                }
                              }
                            },
                    ),
                    KeyedSubtree(
                      key: ValueKey(_challengeGeneration),
                      child:
                          widget.challengeBuilder?.call(_receiveToken) ??
                          NailuChallenge(onToken: _receiveToken),
                    ),
                    if (_error != null) Text(_error!),
                    ListenableBuilder(
                      listenable: widget.session,
                      builder: (context, _) => FilledButton(
                        onPressed: widget.session.busy || _challenge == null
                            ? null
                            : () => unawaited(_login()),
                        child: widget.session.busy
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CommonCircleLoading(),
                              )
                            : Text(strings.nailuLogin),
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _registering = true),
                          child: Text(strings.nailuRegister),
                        ),
                        TextButton(
                          onPressed: () => unawaited(_open(NailuConfig.forgot)),
                          child: Text(strings.nailuForgotPassword),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _receiveToken(String? token) {
    if (mounted) setState(() => _challenge = token);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
}
