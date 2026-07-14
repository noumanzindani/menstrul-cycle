import '../common/date_utils.dart';
import 'enums.dart';

/// The role a single day plays on the Home month ring. Precedence when a day
/// could be more than one (highest wins): [period] > [predictedPeriod] >
/// [ovulation] > [fertile] > [normal]. Fertility roles are only ever assigned
/// through the confidence-gated fertility band, so they can't imply a "safe" day.
enum RingDayRole { normal, period, predictedPeriod, fertile, ovulation }

/// One day on the ring: its day-of-month, its [role], and whether it is today.
class RingDay {
  const RingDay({
    required this.day,
    required this.role,
    required this.isToday,
  });

  final int day; // 1-based day of the month
  final RingDayRole role;
  final bool isToday;
}

/// Everything the [MonthRing] widget needs to paint the current month: one
/// [RingDay] per calendar day plus the centre readout (today's date, cycle day,
/// phase). Pure data — no Flutter/colour dependency; colours are resolved at
/// paint time from the theme so the ring adapts to light/dark automatically.
class MonthRingData {
  const MonthRingData({
    required this.year,
    required this.month,
    required this.days,
    required this.todayDay,
    required this.cycleDay,
    required this.phase,
  });

  final int year;
  final int month; // 1..12
  final List<RingDay> days; // length == number of days in [month]

  /// Today's day-of-month when today falls in this month (always the case for
  /// the current-month ring), else null.
  final int? todayDay;

  final int? cycleDay;
  final CyclePhase phase;

  /// True when any day carries a fertility role — the overall "is fertility
  /// coloured at all" flag (false when confidence is too low to colour anything).
  bool get hasFertility => hasFertile || hasOvulation;

  /// Whether any day this month is coloured as fertile / as ovulation. Kept
  /// separate so each legend entry appears only when a matching segment is
  /// actually painted — e.g. a fertile window straddling the month boundary can
  /// put a fertile day in-month while the ovulation day sits in the prior month.
  bool get hasFertile => days.any((d) => d.role == RingDayRole.fertile);
  bool get hasOvulation => days.any((d) => d.role == RingDayRole.ovulation);

  bool get hasPredictedPeriod =>
      days.any((d) => d.role == RingDayRole.predictedPeriod);

  /// An all-normal ring for [today]'s month. A safe, cheap default (e.g. for
  /// tests / harnesses) that paints the frame without any prediction data.
  factory MonthRingData.empty(DateTime today) {
    final t = dateOnly(today);
    final count = DateTime(t.year, t.month + 1, 0).day;
    return MonthRingData(
      year: t.year,
      month: t.month,
      days: [
        for (var d = 1; d <= count; d++)
          RingDay(day: d, role: RingDayRole.normal, isToday: d == t.day),
      ],
      todayDay: t.day,
      cycleDay: null,
      phase: CyclePhase.unknown,
    );
  }
}
