import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/theme/rs_colors.dart';
import 'cool_card.dart';

class RsLeagueTeam {
  const RsLeagueTeam({
    required this.position,
    required this.name,
    required this.played,
    required this.won,
    required this.points,
    required this.form,
    this.isHighlighted = false,
  });

  final int position;
  final String name;
  final int played;
  final int won;
  final int points;
  final List<String> form;
  final bool isHighlighted;
}

class RsLeagueTable extends StatelessWidget {
  const RsLeagueTable({
    required this.teams,
    this.seasonTitle = 'League Standings',
    super.key,
  });

  final List<RsLeagueTeam> teams;
  final String seasonTitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final theme = Theme.of(context);

    return CoolCard(
      gradient: RsColors.rsCardGradient,
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEAGUE STANDINGS',
            style: text.rayonCondensed(
              theme.textTheme.titleLarge,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
              letterSpacing: 0.4,
            ),
          ),
          if (seasonTitle.isNotEmpty) ...[
            SizedBox(height: space.x1),
            Text(
              seasonTitle,
              style: text.rayon(
                theme.textTheme.labelSmall,
                fontWeight: FontWeight.w600,
                color: colors.tertiaryText,
              ),
            ),
          ],
          SizedBox(height: space.x4),
          _TableRow(
            position: '#',
            name: 'Team',
            played: 'P',
            won: 'W',
            points: 'Pts',
            form: null,
            isHeader: true,
            isHighlighted: false,
          ),
          Divider(color: colors.border, height: 1),
          SizedBox(height: space.x2),
          for (var i = 0; i < teams.length; i++) ...[
            _TableRow(
              position: '${teams[i].position}',
              name: teams[i].name,
              played: '${teams[i].played}',
              won: '${teams[i].won}',
              points: '${teams[i].points}',
              form: teams[i].form,
              isHighlighted: teams[i].isHighlighted,
            ),
            if (i < teams.length - 1) SizedBox(height: space.x2),
          ],
        ],
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.position,
    required this.name,
    required this.played,
    required this.won,
    required this.points,
    required this.form,
    required this.isHighlighted,
    this.isHeader = false,
  });

  final String position;
  final String name;
  final String played;
  final String won;
  final String points;
  final List<String>? form;
  final bool isHighlighted;
  final bool isHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    final theme = Theme.of(context);

    final bg = isHighlighted
        ? RsColors.rsBlue.withValues(alpha: 0.18)
        : Colors.transparent;
    final border = isHighlighted ? RsColors.rsBlueBorder : Colors.transparent;
    final textColor = isHeader
        ? colors.tertiaryText
        : isHighlighted
        ? RsColors.rsWhite
        : colors.secondaryText;
    final textStyle = isHeader
        ? text.rayon(
            theme.textTheme.labelSmall,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: 0.5,
          )
        : text.rayon(
            theme.textTheme.bodySmall,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
            color: textColor,
          );
    final pointsStyle = isHeader
        ? textStyle
        : text.mono(
            theme.textTheme.bodySmall,
            fontWeight: FontWeight.w700,
            color: isHighlighted ? RsColors.rsGoldLight : colors.primaryText,
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: space.x2 + 2,
        vertical: space.x2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radii.sm),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          SizedBox(width: 22, child: Text(position, style: textStyle)),
          Expanded(child: Text(name, style: textStyle)),
          SizedBox(
            width: 24,
            child: Text(played, textAlign: TextAlign.center, style: textStyle),
          ),
          SizedBox(
            width: 24,
            child: Text(won, textAlign: TextAlign.center, style: textStyle),
          ),
          SizedBox(
            width: 28,
            child: Text(
              points,
              textAlign: TextAlign.center,
              style: pointsStyle,
            ),
          ),
          SizedBox(width: space.x1 + 2),
          if (form != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: form!
                  .map((entry) => _FormDot(result: entry))
                  .toList(growable: false),
            )
          else
            SizedBox(
              width: 5 * 12.0,
              child: Text(
                'Form',
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ),
        ],
      ),
    );
  }
}

class _FormDot extends StatelessWidget {
  const _FormDot({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final color = switch (result) {
      'W' => colors.success,
      'D' => colors.warning,
      _ => colors.danger,
    };

    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
