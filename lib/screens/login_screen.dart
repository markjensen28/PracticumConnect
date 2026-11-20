import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../services/app_controller.dart';

const _authBlue = Color(0xFF0866F5);
const _authInk = Color(0xFF14233D);
const _authLine = Color(0xFFDDE3EB);

enum _AuthView { login, signUp, forgotPassword }

enum _SignUpRole { student, coordinator }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();
  final _forgotPasswordFormKey = GlobalKey<FormState>();
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _resetEmail = TextEditingController();
  final _name = TextEditingController();
  final _staffId = TextEditingController();
  final _department = TextEditingController();
  final _signUpEmail = TextEditingController();
  final _signUpPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  _AuthView _view = _AuthView.login;
  _SignUpRole _signUpRole = _SignUpRole.student;
  bool _hideLoginPassword = true;
  bool _hideSignUpPassword = true;

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _resetEmail.dispose();
    _name.dispose();
    _staffId.dispose();
    _department.dispose();
    _signUpEmail.dispose();
    _signUpPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _setView(_AuthView view) {
    if (_view == view) return;
    if (view == _AuthView.forgotPassword && _resetEmail.text.isEmpty) {
      _resetEmail.text = _loginEmail.text;
    }
    widget.controller.clearError();
    setState(() => _view = view);
  }

  void _setSignUpRole(_SignUpRole role) {
    if (_signUpRole == role) return;
    _staffId.clear();
    _department.clear();
    _signUpFormKey.currentState?.reset();
    widget.controller.clearError();
    setState(() => _signUpRole = role);
  }

  Future<void> _submitLogin() async {
    if (!_loginFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await widget.controller.signIn(_loginEmail.text, _loginPassword.text);
  }

  void _submitPasswordReset() {
    if (!_forgotPasswordFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _submitSignUp() async {
    if (!_signUpFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final success = await widget.controller.registerCoordinatorRequest(
      email: _signUpEmail.text,
      password: _signUpPassword.text,
      displayName: _name.text,
      staffId: _staffId.text,
      department: _department.text,
    );

    if (!mounted || !success) return;

    _loginEmail.text = _signUpEmail.text;
    _signUpPassword.clear();
    _confirmPassword.clear();
    setState(() => _view = _AuthView.login);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Request sent for review.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight > 36
              ? constraints.maxHeight - 36
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _AuthBrand(),
                        const SizedBox(height: 32),
                        _authPanel(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _authPanel() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: _authInk.withValues(alpha: .08),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_view != _AuthView.forgotPassword)
          Row(
            children: [
              _AuthTabButton(
                label: 'Log In',
                selected: _view == _AuthView.login,
                onPressed: () => _setView(_AuthView.login),
              ),
              _AuthTabButton(
                label: 'Sign Up',
                selected: _view == _AuthView.signUp,
                onPressed: () => _setView(_AuthView.signUp),
              ),
            ],
          ),
        if (_view == _AuthView.login) _loginForm(),
        if (_view == _AuthView.signUp) _signUpForm(),
        if (_view == _AuthView.forgotPassword) _forgotPasswordForm(),
      ],
    ),
  );

  Widget _loginForm() => Padding(
    padding: const EdgeInsets.fromLTRB(15, 16, 15, 15),
    child: Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.controller.error != null) ...[
            _AuthError(
              message: widget.controller.error!,
              onDismiss: widget.controller.clearError,
            ),
            const SizedBox(height: 11),
          ],
          TextFormField(
            controller: _loginEmail,
            enabled: !widget.controller.busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            decoration: _authDecoration('Email', Icons.mail_outline_rounded),
            validator: _validateEmail,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _loginPassword,
            enabled: !widget.controller.busy,
            obscureText: _hideLoginPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.password],
            onFieldSubmitted: (_) => _submitLogin(),
            decoration: _authDecoration(
              'Password',
              Icons.lock_outline_rounded,
              suffix: IconButton(
                tooltip: _hideLoginPassword ? 'Show password' : 'Hide password',
                onPressed: widget.controller.busy
                    ? null
                    : () => setState(
                        () => _hideLoginPassword = !_hideLoginPassword,
                      ),
                icon: Icon(
                  _hideLoginPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password.' : null,
          ),
          const SizedBox(height: 12),
          _primaryButton(
            label: 'Log In',
            busy: widget.controller.busy,
            onPressed: _submitLogin,
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _setView(_AuthView.forgotPassword),
              style: TextButton.styleFrom(
                foregroundColor: _authBlue,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(vertical: 5),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
              child: const Text('Forgot your password?'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _forgotPasswordForm() => Padding(
    padding: const EdgeInsets.fromLTRB(15, 16, 15, 14),
    child: Form(
      key: _forgotPasswordFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Forgot password',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _authInk,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 13),
          TextFormField(
            controller: _resetEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _submitPasswordReset(),
            decoration: _authDecoration('Email', Icons.mail_outline_rounded),
            validator: _validateEmail,
          ),
          const SizedBox(height: 12),
          _primaryButton(
            label: 'Send Reset Link',
            busy: false,
            onPressed: _submitPasswordReset,
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => _setView(_AuthView.login),
              style: TextButton.styleFrom(
                foregroundColor: _authBlue,
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(vertical: 5),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Back to Log In'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _signUpForm() {
    final student = _signUpRole == _SignUpRole.student;
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
      child: Form(
        key: _signUpFormKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.error != null) ...[
              _AuthError(
                message: widget.controller.error!,
                onDismiss: widget.controller.clearError,
              ),
              const SizedBox(height: 11),
            ],
            SegmentedButton<_SignUpRole>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _SignUpRole.student,
                  label: Text('Student'),
                ),
                ButtonSegment(
                  value: _SignUpRole.coordinator,
                  label: Text('Coordinator'),
                ),
              ],
              selected: {_signUpRole},
              onSelectionChanged: widget.controller.busy
                  ? null
                  : (selection) => _setSignUpRole(selection.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                textStyle: const WidgetStatePropertyAll(
                  TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                side: const WidgetStatePropertyAll(
                  BorderSide(color: _authLine),
                ),
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 11),
            if (student)
              const Text(
                'Student accounts are created from the official school roster. Open your invitation email to set your password, then sign in. Contact your coordinator if you need an invitation.',
              )
            else ...[
              TextFormField(
                controller: _name,
                enabled: !widget.controller.busy,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                decoration: _authDecoration(
                  'Full name',
                  Icons.person_outline_rounded,
                ),
                validator: (value) => value == null || value.trim().length < 2
                    ? 'Enter your full name.'
                    : null,
              ),
              const SizedBox(height: 10),
              Column(
                children: [
                  TextFormField(
                    controller: _staffId,
                    enabled: !widget.controller.busy,
                    textInputAction: TextInputAction.next,
                    decoration: _authDecoration(
                      'Faculty ID',
                      Icons.badge_outlined,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your faculty ID.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _department,
                    enabled: !widget.controller.busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    decoration: _authDecoration(
                      'Department',
                      Icons.account_balance_outlined,
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your department.'
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _signUpEmail,
                enabled: !widget.controller.busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: _authDecoration(
                  'Email',
                  Icons.mail_outline_rounded,
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _signUpPassword,
                enabled: !widget.controller.busy,
                obscureText: _hideSignUpPassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: _authDecoration(
                  'Password',
                  Icons.lock_outline_rounded,
                  suffix: IconButton(
                    tooltip: _hideSignUpPassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: widget.controller.busy
                        ? null
                        : () => setState(
                            () => _hideSignUpPassword = !_hideSignUpPassword,
                          ),
                    icon: Icon(
                      _hideSignUpPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.length < 6
                    ? 'Use at least six characters.'
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirmPassword,
                enabled: !widget.controller.busy,
                obscureText: _hideSignUpPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submitSignUp(),
                autofillHints: const [AutofillHints.newPassword],
                decoration: _authDecoration(
                  'Confirm password',
                  Icons.lock_outline_rounded,
                ),
                validator: (value) => value != _signUpPassword.text
                    ? 'Passwords do not match.'
                    : null,
              ),
              const SizedBox(height: 12),
              _primaryButton(
                label: widget.controller.busy
                    ? 'Sending request'
                    : 'Request Access',
                busy: widget.controller.busy,
                onPressed: _submitSignUp,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required bool busy,
    required VoidCallback onPressed,
  }) => SizedBox(
    height: 42,
    child: FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _authBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _authBlue.withValues(alpha: .65),
        disabledForegroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      child: busy
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label),
    ),
  );
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.hub_outlined, color: _authBlue, size: 38),
      const SizedBox(height: 8),
      Text(
        'Practicum Connect',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: _authInk,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          letterSpacing: -.45,
        ),
      ),
    ],
  );
}

class _AuthTabButton extends StatelessWidget {
  const _AuthTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 41,
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected ? _authBlue : AppTheme.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                height: 2,
                color: selected ? _authBlue : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3F3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.danger,
            size: 17,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppTheme.text, fontSize: 11.5),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 16),
          ),
        ],
      ),
    ),
  );
}

InputDecoration _authDecoration(String label, IconData icon, {Widget? suffix}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 17),
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    suffixIcon: suffix,
    suffixIconConstraints: suffix == null
        ? null
        : const BoxConstraints(minWidth: 40, minHeight: 40),
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
    floatingLabelStyle: const TextStyle(color: _authBlue, fontSize: 11),
    border: border(_authLine),
    enabledBorder: border(_authLine),
    focusedBorder: border(_authBlue, 1.3),
    errorBorder: border(AppTheme.danger),
    focusedErrorBorder: border(AppTheme.danger, 1.2),
  );
}

String? _validateEmail(String? value) =>
    value == null || !value.contains('@') ? 'Enter a valid email.' : null;
