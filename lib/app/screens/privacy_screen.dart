import 'package:flutter/material.dart';
import '../theme.dart';

/// A simple static screen explaining Breadcrumb's privacy posture.
/// Reached from a small link on HomeScreen.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: const Text('Privacy'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: BreadcrumbTheme.surface,
                  borderRadius: const BorderRadius.all(Radius.circular(14)),
                  border: Border.all(color: BreadcrumbTheme.border),
                  boxShadow: BreadcrumbTheme.accentGlow,
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: BreadcrumbTheme.accent,
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Your data stays here.',
                style: BreadcrumbTheme.heading.copyWith(
                  color: BreadcrumbTheme.accent,
                ),
              ),
              const SizedBox(height: 20),
              const _PrivacyText(
                'No GPS, no internet, no account. '
                'The camera is optional and used only when you tap Scan sign; '
                'images are never stored or sent. '
                'Maps stay on this phone.',
              ),
              const SizedBox(height: 32),
              const _BulletRow(
                icon: Icons.location_off_rounded,
                text: 'No GPS — position comes from steps and turns only.',
              ),
              const SizedBox(height: 16),
              const _BulletRow(
                icon: Icons.wifi_off_rounded,
                text: 'No internet — all AI and map data runs on-device.',
              ),
              const SizedBox(height: 16),
              const _BulletRow(
                icon: Icons.no_accounts_rounded,
                text: 'No account — nothing is sent to any server.',
              ),
              const SizedBox(height: 16),
              const _BulletRow(
                icon: Icons.camera_alt_outlined,
                text:
                    'Camera — optional. Only used when you tap Scan sign. '
                    'Images are never stored or sent.',
              ),
              const SizedBox(height: 16),
              const _BulletRow(
                icon: Icons.phone_android_rounded,
                text: 'Maps stay on this phone and are never uploaded.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyText extends StatelessWidget {
  const _PrivacyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: BreadcrumbTheme.body.copyWith(
        height: 1.5,
        color: BreadcrumbTheme.textSecondary,
      ),
    );
  }
}

class _BulletRow extends StatelessWidget {
  const _BulletRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: BreadcrumbTheme.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: BreadcrumbTheme.body.copyWith(
              color: BreadcrumbTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
