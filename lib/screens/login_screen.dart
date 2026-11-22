import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../core/ssu_brand.dart';
import '../services/app_controller.dart';

const _authNavy = AppTheme.navy;
const _authBlue = Color(0xFF1458AC);
const _authLine = Color(0xFFD2DDEB);
const _authTint = Color(0xFFEAF2FC);

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
    if (widget.controller.busy || !_loginFormKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    await widget.controller.signIn(_loginEmail.text, _loginPassword.text);
  }

  void _submitPasswordReset() {
    if (!_forgotPasswordFormKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
  }

  Future<void> _submitSignUp() async {
    if (widget.controller.busy || !_signUpFormKey.currentState!.validate()) {
      return;
    }
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
    backgroundColor: _authTint,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const _AuthBackdrop(),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final inset = compact ? 20.0 : 28.0;
              final verticalInset = compact ? 36.0 : 42.0;
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: inset,
                  vertical: verticalInset,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 2 * verticalInset)
                        .clamp(0.0, double.infinity),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AuthBrand(compact: compact),
                          SizedBox(height: compact ? 22 : 28),
                          _authPanel(compact ? 18 : 26),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _authPanel(double inset) => Container(
    padding: EdgeInsets.fromLTRB(inset, 8, inset, 0),
    decoration: BoxDecoration(
      color: const Color(0xF0FFFFFF),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: _authNavy.withValues(alpha: .17),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    ),
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
                onPressed: widget.controller.busy
                    ? null
                    : () => _setView(_AuthView.login),
              ),
              _AuthTabButton(
                label: 'Sign Up',
                selected: _view == _AuthView.signUp,
                onPressed: widget.controller.busy
                    ? null
                    : () => _setView(_AuthView.signUp),
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
    padding: const EdgeInsets.only(top: 20, bottom: 12),
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
            const SizedBox(height: 12),
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
          const SizedBox(height: 12),
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
                  size: 21,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Enter your password.' : null,
          ),
          const SizedBox(height: 16),
          _primaryButton(
            label: widget.controller.busy ? 'Logging in' : 'Log In',
            busy: widget.controller.busy,
            onPressed: _submitLogin,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.controller.busy
                  ? null
                  : () => _setView(_AuthView.forgotPassword),
              style: TextButton.styleFrom(
                foregroundColor: _authNavy,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 2),
                textStyle: const TextStyle(
                  fontSize: 14,
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
    padding: const EdgeInsets.only(top: 18, bottom: 12),
    child: Form(
      key: _forgotPasswordFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Forgot password',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _authNavy,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _resetEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            onFieldSubmitted: (_) => _submitPasswordReset(),
            decoration: _authDecoration('Email', Icons.mail_outline_rounded),
            validator: _validateEmail,
          ),
          const SizedBox(height: 16),
          _primaryButton(
            label: 'Send Reset Link',
            busy: false,
            onPressed: _submitPasswordReset,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: () => _setView(_AuthView.login),
              style: TextButton.styleFrom(
                foregroundColor: _authNavy,
                minimumSize: const Size(0, 44),
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
      padding: const EdgeInsets.only(top: 18, bottom: 24),
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
              const SizedBox(height: 12),
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
              style: SegmentedButton.styleFrom(
                foregroundColor: AppTheme.muted,
                selectedForegroundColor: _authNavy,
                backgroundColor: Colors.white,
                selectedBackgroundColor: _authTint,
                minimumSize: const Size(0, 44),
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                side: const BorderSide(color: _authLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (student)
              const Text(
                'Student accounts are created from the official school roster. Open your invitation email to set your password, then sign in. Contact your coordinator if you need an invitation.',
                style: TextStyle(color: AppTheme.muted, height: 1.55),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _staffId,
                enabled: !widget.controller.busy,
                textInputAction: TextInputAction.next,
                decoration: _authDecoration('Faculty ID', Icons.badge_outlined),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter your faculty ID.'
                    : null,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
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
                      size: 21,
                    ),
                  ),
                ),
                validator: (value) => value == null || value.length < 6
                    ? 'Use at least six characters.'
                    : null,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 16),
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
  }) => FilledButton(
    onPressed: busy ? null : onPressed,
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      backgroundColor: _authNavy,
      foregroundColor: Colors.white,
      disabledBackgroundColor: _authNavy.withValues(alpha: .75),
      disabledForegroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    child: busy
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: Text(label)),
            ],
          )
        : Text(label),
  );
}

class _AuthBrand extends StatelessWidget {
  const _AuthBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SsuSeal(size: compact ? 104 : 132),
      SizedBox(height: compact ? 16 : 20),
      Semantics(
        header: true,
        child: Text(
          'Practicum Connect',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
            color: _authNavy,
            fontSize: compact ? 33 : 44,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: compact ? -.65 : -1,
          ),
        ),
      ),
    ],
  );
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Image.asset(
        'assets/ssu-photo.jpg',
        fit: BoxFit.cover,
        alignment: const Alignment(.3, -.25),
        excludeFromSemantics: true,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x9FEAF4FF), Color(0xB8F4F8FE), Color(0x62E6EFFA)],
            stops: [0, .44, 1],
          ),
        ),
      ),
      const CustomPaint(painter: _AuthCornerPainter()),
    ],
  );
}

class _AuthCornerPainter extends CustomPainter {
  const _AuthCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final topWidth = (size.width * .56).clamp(0.0, 610.0);
    final bottomWidth = (size.width * .66).clamp(0.0, 730.0);

    const SsuRibbonPainter().paint(
      canvas,
      Size(topWidth, (topWidth * .37).clamp(0.0, 164.0)),
    );
    final bottomHeight = (bottomWidth * .33).clamp(0.0, 148.0);
    canvas.save();
    canvas.translate(size.width - bottomWidth, size.height - bottomHeight);
    const SsuRibbonPainter(
      bottomRight: true,
    ).paint(canvas, Size(bottomWidth, bottomHeight));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AuthCornerPainter oldDelegate) => false;
}

class _AuthTabButton extends StatelessWidget {
  const _AuthTabButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          focusColor: _authTint,
          hoverColor: _authTint.withValues(alpha: .55),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? _authBlue : AppTheme.muted,
                      fontSize: 16,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? _authBlue : _authLine,
                  borderRadius: BorderRadius.circular(2),
                ),
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
        borderRadius: BorderRadius.circular(10),
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
              style: const TextStyle(color: AppTheme.text, fontSize: 14),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    ),
  );
}

InputDecoration _authDecoration(String label, IconData icon, {Widget? suffix}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(11),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, size: 21),
    prefixIconColor: _authNavy,
    prefixIconConstraints: const BoxConstraints(minWidth: 52, minHeight: 54),
    suffixIcon: suffix,
    suffixIconColor: _authNavy,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 16),
    floatingLabelStyle: const TextStyle(color: _authBlue, fontSize: 15),
    border: border(_authLine),
    enabledBorder: border(_authLine),
    focusedBorder: border(_authBlue, 1.7),
    errorBorder: border(AppTheme.danger),
    focusedErrorBorder: border(AppTheme.danger, 1.2),
  );
}

String? _validateEmail(String? value) =>
    value == null || !value.contains('@') ? 'Enter a valid email.' : null;
