/// A trade-ship voyage that has set out but not yet come home (§9.2).
///
/// Sent during a realm's turn ("Handelsschiffe aussenden"), the voyage
/// resolves at the START of that realm's next turn ([returnYear]): the
/// [returned] Taler land in the treasury and a `shipsReturned` event
/// reports the haul. The outcome is rolled the moment the ships depart
/// (so the result stays deterministic/replayable), but it stays hidden
/// from the player until they return — a one-round voyage with a return
/// notice instead of the original's instant 50/50 gamble.
class PendingShipReturn {
  PendingShipReturn({
    required this.invested,
    required this.returned,
    required this.returnYear,
  });

  factory PendingShipReturn.fromJson(Map<String, dynamic> json) =>
      PendingShipReturn(
        invested: json['invested'] as int,
        returned: json['returned'] as int,
        returnYear: json['returnYear'] as int,
      );

  /// Taler staked when the ships departed.
  final int invested;

  /// Taler the ships bring home (0 .. 2 × [invested]).
  final int returned;

  /// Game year the voyage resolves — the realm's next turn.
  final int returnYear;

  PendingShipReturn copy() => PendingShipReturn(
        invested: invested,
        returned: returned,
        returnYear: returnYear,
      );

  Map<String, dynamic> toJson() => {
        'invested': invested,
        'returned': returned,
        'returnYear': returnYear,
      };
}
