import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/rs_colors.dart';
import 'cool_card.dart';

// ── Model ───────────────────────────────────────────────────────────────

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
  final List<String> form; // 'W', 'D', 'L'
  final bool isHighlighted;
}

// ── Widget ───────────────────────────────────────────────────────────────

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
    return CoolCard(
      gradient: AppColors.cardGradient,
      borderColor: RsColors.rsBlueBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '🏆 League Standings',
            style: GoogleFonts.barlowCondensed(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: RsColors.rsWhite,
            ),
          ),
          if (seasonTitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              seasonTitle,
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.text3,
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Header
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
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 6),

          // Rows
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
            if (i < teams.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

// ── Table Row ────────────────────────────────────────────────────────────

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
    final bg = isHighlighted
        ? RsColors.rsBlue.withValues(alpha: 0.18)
        : Colors.transparent;
    final border = isHighlighted ? RsColors.rsBlueBorder : Colors.transparent;
    final textColor = isHeader
        ? AppColors.text3
        : isHighlighted
        ? RsColors.rsWhite
        : AppColors.text2;
    final textStyle = isHeader
        ? GoogleFonts.barlow(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textColor,
            letterSpacing: 0.5,
          )
        : GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w600,
            color: textColor,
          );
    final pointsStyle = isHeader
        ? textStyle
        : GoogleFonts.dmMono(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isHighlighted ? RsColors.rsGoldLight : AppColors.text,
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(width: 6),
          if (form != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: form!
                  .map((f) => _FormDot(result: f))
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

// ── Form Dot ─────────────────────────────────────────────────────────────

class _FormDot extends StatelessWidget {
  const _FormDot({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'W' => AppColors.accent,
      'D' => AppColors.orange,
      _ => AppColors.red,
    };

    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
