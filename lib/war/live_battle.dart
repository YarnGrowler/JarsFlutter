import 'war_ai.dart';
import 'war_engine.dart';

/// A Clash-style real-time auto-battle over an [AttackState]. You deploy from
/// your trained army; the troops fight on their own. The battle ends ONLY when
/// you concede, the castles fall, or you have nothing left to send.
class LiveBattle {
  final AttackState st;

  /// Can the player still deploy something? (trained troops remaining)
  final bool Function() canDeploy;
  /// Simulation cadence — one round every 0.55s.
  static const double stepPeriod = 0.55;

  /// Clash rules: five minutes on the clock once the first boot lands.
  static const double maxDuration = 300;
  double elapsed = 0;
  double _acc = 0;
  int _emptyRounds = 0;
  int _stallRounds = 0;
  bool over = false;

  /// Mirrors FreeMoveBattle.stopWhenRazed — a hands-on raid keeps going after
  /// the last castle falls so the commander can strip the storehouses.
  final bool stopWhenRazed;

  LiveBattle(this.st, {required this.canDeploy, this.stopWhenRazed = true});

  double get destruction => st.base.destructionPercent;
  int get troopsAlive => st.troops.where((t) => t.alive).length;
  bool get clockRunning => st.troopsSent > 0 && !over;
  double get timeLeft => (maxDuration - elapsed).clamp(0.0, maxDuration);

  /// Advance the battle clock; runs whole rounds on the cadence.
  void tick(double dt) {
    if (over) return;
    if (st.troopsSent > 0) {
      elapsed += dt;
      if (elapsed >= maxDuration) {
        over = true; // time's up, commander
        return;
      }
    }
    _acc += dt;
    while (_acc >= stepPeriod && !over) {
      _acc -= stepPeriod;
      round();
    }
  }

  /// One battle round: every troop acts on AI, then the defense answers.
  void round() {
    if (over) return;
    var acted = false;
    for (final t in st.troops.where((x) => x.alive).toList()) {
      if (WarAi.aiStep(st, t)) acted = true;
    }
    st.defendersReact();
    st.snapshot();
    if (stopWhenRazed && st.base.allCastlesRazed) {
      over = true;
      return;
    }
    final fieldEmpty = st.troops.every((t) => !t.alive);
    if (fieldEmpty) {
      if (canDeploy()) {
        _emptyRounds = 0; // waiting on the commander — the war doesn't rush you
      } else {
        _emptyRounds++;
        if (_emptyRounds >= 4) over = true; // nothing left to send
      }
    } else {
      _emptyRounds = 0;
      // safety valve: a fully wedged army shouldn't spin forever
      _stallRounds = acted ? 0 : _stallRounds + 1;
      if (_stallRounds >= 20) over = true;
    }
  }

  /// Sandbox overtime: wind the clock back and fight on.
  void extend() {
    over = false;
    elapsed = 0;
    _emptyRounds = 0;
    _stallRounds = 0;
  }

  /// A fresh deployment resets the wind-down.
  void notifyDeploy() {
    _emptyRounds = 0;
    _stallRounds = 0;
  }

  /// Headless completion (player left mid-battle): run the remaining rounds.
  void fastResolve() {
    var guard = 0;
    while (!over && guard++ < 150) {
      if (st.troops.every((t) => !t.alive)) {
        over = true;
        break;
      }
      round();
    }
    over = true;
  }
}
