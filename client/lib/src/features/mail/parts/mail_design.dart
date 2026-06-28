part of '../mail_home_screen.dart';

class _MailDimens {
  const _MailDimens._();

  static const double sidebarWidth = 288;
  static const double railWidth = 92;
  static const double messageListWidth = 432;
  static const double tabletMessageListWidth = 372;
  static const double messageBodyMaxWidth = 760;
  static const double compactTileHeight = 106;
  static const double regularTileHeight = 124;
  static const double radius = 8;
  static const double panelPadding = 16;
}

class _MailDurations {
  const _MailDurations._();

  static const Duration quick = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 220);
}

class _MailAccent {
  const _MailAccent._();

  static const Color starred = Color(0xFFE2A100);
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _IconSurface extends StatelessWidget {
  const _IconSurface({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(_MailDimens.radius),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
