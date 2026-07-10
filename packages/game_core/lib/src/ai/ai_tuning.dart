import '../state/ai_difficulty.dart';
import '../state/troop.dart';

/// Behaviour knobs of the AI script per [AiDifficulty]. The differences
/// between the levels live in this table — `ai_turn.dart` reads the values
/// and never branches on the difficulty itself. Every default equals the
/// [AiDifficulty.mittel] value, which reproduces the pre-difficulty script
/// exactly (pinned by the "mittel tuning" test), so each level lists only
/// its deltas. "0 = off" is the convention for every chance/threshold knob.
class AiTuning {
  const AiTuning({
    this.grainSellMin = 1.6,
    this.cattleSellMin = 2.2,
    this.foodFactor = 1.0,
    this.burgChance = 20,
    this.reinforceDivisor = 1,
    this.capacityTarget = 0,
    this.kavallerieTreasury = 0,
    this.drillMaxQuality = TroopQuality.regular,
    this.warChance = 20,
    this.warStrengthAdvantage = 0,
    this.assassinChance = 40,
    this.assassinateEarly = false,
    this.smartAssassinTarget = false,
    this.assassinTreasuryDivisor = 4,
    this.assassinMaxAgents = 20,
  });

  /// §20.2 market: sell harvests only at or above these prices
  /// (grain rolls in [1.0, 2.0], cattle in [1.5, 2.5]; mittel sells in the
  /// upper ~40% of each range).
  final double grainSellMin;
  final double cattleSellMin;

  /// §20.4 food goal: build fields while `Kornfelder × 9 <
  /// population × foodFactor`. > 1 keeps a buffer, < 1 reacts late.
  final double foodFactor;

  /// Burg/Palast build chance per loop pass: 1/[burgChance] (§20.4 ≈ 1/20).
  final int burgChance;

  /// §20.5 reinforcement `random(free) + 1` is divided by this — 1 = the
  /// original amount, 2 = a sloppy half-hearted levy. (Ignored under
  /// planned recruiting, see [capacityTarget].)
  final int reinforceDivisor;

  /// > 0 switches from the random §20.5 levy to PLANNED recruiting: the AI
  /// fills its army toward this share of its troop capacity, spending at
  /// most half the treasury per turn (the rest stays as a war chest).
  /// 0 = the original random levy.
  final double capacityTarget;

  /// Planned recruiting raises Kavallerie instead of Infanterie once the
  /// treasury reaches this (0 = never).
  final int kavallerieTreasury;

  /// Drill regulars up to this quality (5 T × men × quality per level,
  /// at most a quarter of the treasury per turn). [TroopQuality.regular]
  /// disables drilling.
  final int drillMaxQuality;

  /// Spontaneous war impulse 1/[warChance] per turn (§20.8, then the
  /// original's extra 1/3 gate still applies). 0 = no spontaneous impulse
  /// (a boxed-in AI may still war, §20.4).
  final int warChance;

  /// > 0 makes the war target pick SMART: the weakest reachable neighbour,
  /// and war is only declared with at least this × its army strength —
  /// instead of a random neighbour of another religion. 0 = original pick.
  final double warStrengthAdvantage;

  /// Assassination impulse 1/[assassinChance] per turn; 0 = never.
  final int assassinChance;

  /// When true the assassination is budgeted BEFORE the turn's spending
  /// (build loop, levies, drill, ships) — otherwise the reserve gate almost
  /// never holds for an AI that plans its economy aggressively. Mittel
  /// keeps the original late check.
  final bool assassinateEarly;

  /// When true the target is the strongest bordering rival (the biggest
  /// long-term threat) instead of a random neighbour.
  final bool smartAssassinTarget;

  /// Squad size = (treasury / divisor) / assassinCost, clamped to
  /// [3, assassinMaxAgents] (and never past the action's own cap of 30).
  final int assassinTreasuryDivisor;
  final int assassinMaxAgents;
}

/// The tuning table. Mittel is the faithful pre-difficulty script (all
/// defaults); Leicht plays sloppier on every axis; Schwer plans its economy
/// and military and picks targets deliberately.
AiTuning aiTuningFor(AiDifficulty difficulty) => switch (difficulty) {
      AiDifficulty.leicht => const AiTuning(
          grainSellMin: 0, // sells at any price
          cattleSellMin: 0,
          foodFactor: 0.8, // reacts only to acute shortage
          burgChance: 40,
          reinforceDivisor: 2, // half-hearted levies
          warChance: 40,
          assassinChance: 0, // never assassinates
        ),
      AiDifficulty.mittel => const AiTuning(),
      AiDifficulty.schwer => const AiTuning(
          grainSellMin: 1.8, // holds out for top prices
          cattleSellMin: 2.4,
          foodFactor: 1.2, // food buffer before famine looms
          burgChance: 5,
          capacityTarget: 0.8, // planned recruiting
          kavallerieTreasury: 3000,
          drillMaxQuality: 5,
          warStrengthAdvantage: 1.3,
          assassinChance: 15,
          assassinateEarly: true,
          smartAssassinTarget: true,
          assassinTreasuryDivisor: 3,
          assassinMaxAgents: 30,
        ),
    };
