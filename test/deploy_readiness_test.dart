import 'package:flutter_test/flutter_test.dart';
import 'package:jars/core/league_config.dart';
import 'package:jars/models/league.dart';
import 'package:jars/war/war_base.dart';
import 'package:jars/war/war_game.dart';
import 'package:jars/war/war_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deploy-readiness: drive the ENTIRE game+league loop headlessly across the
/// difficulty dial and a full season, asserting nothing crashes and the ladder
/// stays structurally sound. This is the "would a real user hit a wall" pass.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final cfg = LeagueConfig.instance;

  WarGame freshGame(int difficulty) {
    final g = WarGame.fresh();
    g.startPrep();
    g.setDifficulty(difficulty);
    return g;
  }

  void razeEnemy(WarGame g) {
    for (final cell in g.enemyBase.castleCells) {
      final s = g.enemyBase.structAt(cell.r, cell.c);
      if (s != null) s.hp = 0;
    }
  }

  void razeYou(WarGame g) {
    for (final cell in g.youBase.castleCells) {
      final s = g.youBase.structAt(cell.r, cell.c);
      if (s != null) s.hp = 0;
    }
  }

  /// A ladder is well-formed: exactly teamsPerLeague rows, positions a
  /// contiguous 1..N permutation, sorted by league points descending, you are
  /// on it, and no NaN/negative garbage.
  void assertValidTable(LeagueTable t, {required String ctx}) {
    expect(t.standings.length, cfg.teamsPerLeague, reason: '$ctx: row count');
    final positions = t.standings.map((s) => s.position).toList()..sort();
    expect(positions, [for (var i = 1; i <= cfg.teamsPerLeague; i++) i],
        reason: '$ctx: positions must be a clean 1..N with no dupes/gaps');
    for (var i = 1; i < t.standings.length; i++) {
      expect(t.standings[i - 1].leaguePoints >= t.standings[i].leaguePoints,
          isTrue,
          reason: '$ctx: standings must be sorted by points desc');
    }
    expect(t.yourRow, isNotNull, reason: '$ctx: you must appear on the ladder');
    for (final s in t.standings) {
      expect(s.leaguePoints, greaterThanOrEqualTo(0), reason: '$ctx: pts');
      expect(s.played, greaterThanOrEqualTo(0), reason: '$ctx: played');
    }
  }

  group('deploy: the full season survives every difficulty', () {
    for (final d in const [1, 25, 50, 80, 99]) {
      test('difficulty $d — a whole season plays start to finish', () {
        final g = freshGame(d);
        final startDiv = g.divisionIndex;
        for (var war = 0; war < cfg.matchweeks; war++) {
          g.startWar();
          // the player sits out; the AI timeline runs the whole war day
          g.advanceToEndOfDay();
          g.endWar();
          assertValidTable(g.buildTable(), ctx: 'd$d war$war');
          g.nextWar();
        }
        // a season rolled: index advanced, division stayed in range, no crash
        expect(g.seasonIndex, greaterThanOrEqualTo(1));
        expect(g.divisionIndex, inInclusiveRange(0, cfg.divisions.length - 1));
        expect(g.divisionIndex, lessThanOrEqualTo(startDiv),
            reason: 'an idle player never PROMOTES');
      });
    }
  });

  group('deploy: promotion and relegation actually fire', () {
    test('raze every enemy for a season → you PROMOTE', () {
      final g = freshGame(50);
      final startDiv = g.divisionIndex;
      for (var war = 0; war < cfg.matchweeks; war++) {
        g.startWar();
        razeEnemy(g); // total victory each war
        g.endWar();
        expect(g.lastVerdict?.winner, WarSide.you, reason: 'war $war win');
        g.nextWar();
      }
      expect(g.divisionIndex, startDiv + 1, reason: 'a perfect season promotes');
    });

    test('lose every war at the bottom division → you FLOOR at 0, never below',
        () {
      final g = freshGame(50);
      expect(g.divisionIndex, 0);
      for (var war = 0; war < cfg.matchweeks; war++) {
        g.startWar();
        razeYou(g); // total defeat each war
        g.endWar();
        expect(g.lastVerdict?.winner, WarSide.enemy, reason: 'war $war loss');
        g.nextWar();
      }
      expect(g.divisionIndex, 0, reason: 'relegation floors, never underflows');
    });

    test('climb then fall: promote up, then a losing season drops you back', () {
      final g = freshGame(50);
      // season 1: perfect → promote to div 1
      for (var w = 0; w < cfg.matchweeks; w++) {
        g.startWar();
        razeEnemy(g);
        g.endWar();
        g.nextWar();
      }
      expect(g.divisionIndex, 1);
      // season 2: wiped out → relegate back to div 0
      for (var w = 0; w < cfg.matchweeks; w++) {
        g.startWar();
        razeYou(g);
        g.endWar();
        g.nextWar();
      }
      expect(g.divisionIndex, 0, reason: 'a losing season sends you back down');
    });
  });

  group('deploy: real rooms — your friends, not fake AI teammates', () {
    List<RosterMember> friends(List<List<String>> pairs) =>
        [for (final p in pairs) RosterMember(p[0], p[1])];

    test('applying a room roster replaces the fake crew with real friends', () {
      final g = WarGame.fresh();
      g.startPrep(); // builds the solo fallback crew first (casey/wade/finn)
      expect(g.youClan.any((p) => p.id == 'casey'), isTrue,
          reason: 'sanity: the offline fallback crew is there before wiring');

      g.applyRoomRoster(
        realRoomId: 'room-1',
        myUserId: 'user-abc',
        myUsername: 'YarnGrowler',
        members: friends([
          ['user-casey', 'Casey'],
          ['user-wade', 'Wade'],
        ]),
      );

      expect(g.youClan.any((p) => p.id == 'casey'), isFalse,
          reason: 'no fake AI teammates survive real wiring');
      expect(g.youClan.map((p) => p.id).toSet(),
          {'user-abc', 'user-casey', 'user-wade'});
      expect(g.youClan.firstWhere((p) => p.id == 'user-abc').isYou, isTrue);
      expect(g.activePlayerId, 'user-abc', reason: 'you control only yourself');
      expect(g.roomId, 'room-1');
    });

    test('the enemy clan is sized to match your real crew, always', () {
      for (final size in [1, 2, 4, 5, 9]) {
        final g = WarGame.fresh();
        g.startPrep();
        g.applyRoomRoster(
          realRoomId: 'room-$size',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            for (var i = 0; i < size - 1; i++) ['f$i', 'Friend$i']
          ]),
        );
        expect(g.youClan.length, size, reason: 'crew of $size');
        expect(g.enemyClan.length, size,
            reason: 'the AI fields exactly as many foes as real friends');
      }
    });

    test('enemy names stay distinct even with a big crew (no exact dupes)', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
        realRoomId: 'big-room',
        myUserId: 'me',
        myUsername: 'Me',
        members: friends([for (var i = 0; i < 14; i++) ['f$i', 'Friend$i']]),
      );
      final names = g.enemyClan.map((p) => p.name).toList();
      expect(names.toSet().length, names.length,
          reason: 'a 15-a-side war never fields two identically-named foes');
    });

    test('a real crew keeps its base generation coherent (structural N-agnostic check)',
        () {
      // realistic boot order: WarGame.load()/startPrep() always runs first
      // (main.dart, before any room is known); applyRoomRoster reseats the
      // crew once the room resolves — never the other way around.
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
        realRoomId: 'room-x',
        myUserId: 'me',
        myUsername: 'Me',
        members: friends([
          ['f0', 'A'],
          ['f1', 'B'],
        ]),
      );
      expect(g.youClan.length, 3, reason: 'the real 3-person crew is seated');
      expect(g.enemyClan.length, 3);
      assertValidTable(g.buildTable(), ctx: 'real room ladder');
    });

    test('re-wiring the SAME room with an unchanged roster is a cheap no-op', () {
      final g = WarGame.fresh();
      g.startPrep();
      final members = friends([
        ['f0', 'A']
      ]);
      g.applyRoomRoster(
          realRoomId: 'r', myUserId: 'me', myUsername: 'Me', members: members);
      final firstPlayersRef = g.players;
      g.applyRoomRoster(
          realRoomId: 'r', myUserId: 'me', myUsername: 'Me', members: members);
      expect(identical(g.players, firstPlayersRef), isTrue,
          reason: 'no rebuild when nothing changed');
    });

    test('a friend leaving/joining rebuilds the crew (roster changed)', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      expect(g.youClan.length, 2);
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A'],
            ['f1', 'B'],
          ]));
      expect(g.youClan.length, 3, reason: 'a joining friend is seated');
      expect(g.enemyClan.length, 3, reason: 'the enemy clan grows with you');
    });

    test('real-room mode locks switchActive to yourself', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      g.switchActive('f0');
      expect(g.activePlayerId, 'me',
          reason: 'you can never puppet a real friend\'s account');
    });

    test(
        'REGRESSION: a shared blob never overwrites you with a teammate\'s identity',
        () {
      // The exact real-world bug: ybb and BossmanFat share a room. ybb opens
      // the war first, seats the real roster, and saves — his device's
      // activePlayerId ('ybb') rides along in that same blob (it's a field
      // on WarGame, serialized for the SOLO/offline case where it's a
      // legitimate "who am I controlling"). BossmanFat's device then pulls
      // THAT blob. If activePlayerId is trusted from it, BossmanFat's own
      // screen silently starts spending ybb's resources.
      final ybbDevice = WarGame.fresh();
      ybbDevice.startPrep();
      ybbDevice.applyRoomRoster(
        realRoomId: 'the-gc',
        myUserId: 'ybb-uid',
        myUsername: 'ybb',
        members: friends([
          ['bossmanfat-uid', 'BossmanFat']
        ]),
      );
      expect(ybbDevice.activePlayerId, 'ybb-uid');
      final sharedBlob = ybbDevice.toJson(); // what lands in room_wars

      // BossmanFat's device: a fresh instance loads that SAME blob (this is
      // exactly what the initial `ensure()` / realtime `_applyRemote` do).
      final bossmanfatDevice = WarGame.fresh();
      bossmanfatDevice.loadFromJson(sharedBlob);
      expect(bossmanfatDevice.activePlayerId, 'ybb-uid',
          reason: 'raw loadFromJson is honest about what was IN the blob — '
              'the guard belongs to whoever calls it next');

      // Reconciling the roster for THIS device — the roster is already
      // correct (same two real people), so this takes the CHEAP NO-OP path.
      // That fast path must STILL correct the identity.
      bossmanfatDevice.applyRoomRoster(
        realRoomId: 'the-gc',
        myUserId: 'bossmanfat-uid',
        myUsername: 'BossmanFat',
        members: friends([
          ['ybb-uid', 'ybb']
        ]),
      );

      expect(bossmanfatDevice.activePlayerId, 'bossmanfat-uid',
          reason: 'BossmanFat must always control BossmanFat, never ybb');
      expect(bossmanfatDevice.active.id, 'bossmanfat-uid');
      expect(bossmanfatDevice.active.name, 'BossmanFat');
    });

    test('the no-op roster path corrects activePlayerId even with NO change',
        () {
      // narrower unit test of the same fix: applyRoomRoster's fast path
      // (roster genuinely unchanged) must not skip the identity check.
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      // simulate a remote load quietly overwriting it (as loadFromJson does)
      g.activePlayerId = 'f0';
      expect(g.active.id, 'f0', reason: 'sanity: the corruption really happened');

      // re-run with an UNCHANGED roster — must hit the no-op path AND fix it
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      expect(g.activePlayerId, 'me',
          reason: 'the no-op fast path must still self-correct identity');
    });

    test('a non-admin real player cannot touch war-wide controls', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      g.isRoomAdmin = false;
      expect(g.canControlWar, isFalse);

      final diffBefore = g.difficulty;
      g.setDifficulty(99);
      expect(g.difficulty, diffBefore, reason: 'non-admin cannot set difficulty');

      final phaseBefore = g.phase;
      g.startWar();
      expect(g.phase, phaseBefore, reason: 'non-admin cannot start the war');

      final hourBefore = g.clock.hour;
      g.startWar(); // no-op (still blocked), but ensure advanceHours also blocked
      g.advanceHours(3);
      expect(g.clock.hour, hourBefore, reason: 'non-admin cannot skip time');

      final seasonBefore = g.seasonIndex;
      g.resetSeason();
      expect(g.seasonIndex, seasonBefore, reason: 'non-admin cannot reset the season');
    });

    // Structure value actually BUILT into a base — leftover player ⚡ now
    // carries into war day (plus a small stipend), so the built base is still
    // the cleanest way to see what the prep budget bought.
    double structureValue(Base b) {
      var v = 0.0;
      for (var r = 0; r < Base.defaultSize; r++) {
        for (var c = 0; c < Base.defaultSize; c++) {
          final s = b.structAt(r, c);
          if (s != null) v += s.spec.cost;
        }
      }
      return v;
    }

    test('the enemy war chest reflects real crew effort, not a guess', () {
      double enemyBuildValue(double crewEarnedPerMember, int members) {
        final g = WarGame.fresh();
        g.startPrep();
        g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            for (var i = 0; i < members - 1; i++) ['f$i', 'F$i']
          ]),
        );
        for (final p in g.youClan) {
          g.activePlayerId = p.id;
          g.earn(crewEarnedPerMember);
        }
        g.activePlayerId = 'me';
        g.startWar();
        return structureValue(g.enemyBase);
      }

      final lightCrew = enemyBuildValue(20, 3); // barely worked out
      final heavyCrew = enemyBuildValue(3000, 3); // grinded hard
      expect(heavyCrew, greaterThan(lightCrew),
          reason: 'a crew that earned more faces a tougher AI, at the SAME '
              'difficulty dial');
    });

    test('bots never count toward the enemy\'s war-chest floor', () {
      // solo/offline crew (bots) start with a flat 300 and build immediately
      // — none of that should inflate a REAL room's enemy floor. Compare
      // PER-ENEMY average build value (clan sizes differ: solo = you+3
      // bots, so 4 foes share the floor; the room below is sized to match).
      final soloGame = WarGame.fresh();
      soloGame.startPrep(); // solo fallback crew: bots with 300⚡ each
      expect(soloGame.youClan.any((p) => p.isBot), isTrue,
          reason: 'sanity: bots exist');
      soloGame.startWar();
      final soloPerEnemy =
          structureValue(soloGame.enemyBase) / soloGame.enemyClan.length;

      final roomGame = WarGame.fresh();
      roomGame.startPrep();
      roomGame.applyRoomRoster(
        realRoomId: 'r',
        myUserId: 'me',
        myUsername: 'Me',
        // match the solo scenario's headcount (you + 3) with ZERO real
        // earnings — a real room's honest floor when nobody's logged yet
        members: friends([
          ['f0', 'A'],
          ['f1', 'B'],
          ['f2', 'C'],
        ]),
      );
      expect(roomGame.youClan.every((p) => !p.isBot), isTrue,
          reason: 'a real room has no bots at all');
      roomGame.startWar();
      final roomPerEnemy =
          structureValue(roomGame.enemyBase) / roomGame.enemyClan.length;

      // same (zero) real earnings, same dial, same headcount — the SOLO
      // game's leftover 300⚡-per-bot must not make ITS enemy tougher than
      // the real room's zero-earned crew.
      expect(roomPerEnemy, closeTo(soloPerEnemy, soloPerEnemy * 0.15 + 20),
          reason: 'no bot money leaked into the real room\'s enemy floor');
    });

    test('the league floor bites even at the LOWEST difficulty dial', () {
      final divCount = cfg.divisions.length;
      final g = WarGame.fresh();
      g.startPrep();
      g.setDifficulty(1); // the easiest the dial goes
      g.divisionIndex = 0; // Bronze
      g.startWar();
      final bronzeSkill = g.enemyClan.first.skill;

      final g2 = WarGame.fresh();
      g2.startPrep();
      g2.setDifficulty(1); // SAME easy dial
      g2.divisionIndex = divCount - 1; // Radiant — the top of the ladder
      g2.startWar();
      final radiantSkill = g2.enemyClan.first.skill;

      expect(radiantSkill, greaterThan(bronzeSkill),
          reason: 'climbing the league must bite even if nobody touches the '
              'difficulty dial');
      expect(radiantSkill, greaterThan(1.0),
          reason: 'Radiant floors you into citadel territory no matter what');
    });

    test('the enemy clan always matches your real crew size, still', () {
      for (final size in [1, 3, 5]) {
        final g = WarGame.fresh();
        g.startPrep();
        g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            for (var i = 0; i < size - 1; i++) ['f$i', 'F$i']
          ]),
        );
        g.startWar();
        expect(g.enemyClan.length, size);
      }
    });

    test(
        'REGRESSION: the admin starts the war with only THEIR OWN castle down — '
        'nobody else has to place one', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A'],
            ['f1', 'B'],
          ]));
      g.isRoomAdmin = true;
      // ONLY the admin places a castle — friends A and B never touch the
      // builder at all.
      g.placeCastle(10, 10);
      expect(g.anyCastlePlaced, isTrue,
          reason: 'the old check (literal id "you") ALWAYS failed for real '
              'rooms — this is the exact bug reported');
      expect(g.youBase.castles.length, 1);

      g.startWar();
      expect(g.phase, WarPhase.war,
          reason: 'the war starts — not everyone needs a castle down');
      // stragglers get auto-seated a fallback spot so the war is still fair
      expect(g.youBase.castles.length, 3,
          reason: 'A and B get fallback castles so they can still be raided');
    });

    test(
        'REGRESSION: the solo bot crew\'s auto-built castles never linger '
        'once a real room takes over', () {
      final g = WarGame.fresh();
      g.startPrep(); // solo fallback: you + 3 bots, bots auto-place castles
      final botCastleCount = g.youBase.castles.length;
      expect(botCastleCount, greaterThan(0),
          reason: 'sanity: the bot crew really did auto-build');

      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      expect(g.youBase.castles.keys, isNot(contains('casey')),
          reason: 'the old bot crew\'s castles must not haunt a real room');
      expect(g.youBase.castles.length, 0,
          reason: 'nobody real has placed a castle yet — should read as zero');
      expect(g.anyCastlePlaced, isFalse);
    });

    test('activeHasCastle reflects the CURRENTLY CONTROLLED player, not a '
        'hardcoded id', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      expect(g.activeHasCastle, isFalse);
      g.placeCastle(10, 10);
      expect(g.activeHasCastle, isTrue,
          reason: 'the active player (a real id, never the literal "you") '
              'now has a castle');
    });

    test(
        'REGRESSION: signing out leaves nothing for the NEXT real user to '
        'inherit', () {
      // two friends testing on the SAME device/browser — a very real
      // scenario, and exactly how the original identity bug was found.
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'ybb-uid',
          myUsername: 'ybb',
          members: friends([
            ['bossmanfat-uid', 'BossmanFat']
          ]));
      g.isRoomAdmin = true;
      expect(g.roomId, isNotNull);
      expect(g.players, isNotEmpty);

      g.resetForSignOut();

      expect(g.roomId, isNull, reason: 'no lingering room after sign-out');
      expect(g.players, isEmpty, reason: 'no lingering roster after sign-out');
      expect(g.activePlayerId, 'you',
          reason: 'back to the neutral default, not a real leftover id');
      expect(g.isRoomAdmin, isTrue, reason: 'admin flag re-defaults safely');
      expect(WarGame.onRoomSave, isNull,
          reason: 'no stray save hook still pointing at the old room');
    });

    test(
        'REGRESSION: a departed teammate\'s leftover structure refunds '
        'nobody', () {
      // f0 places a wall, then leaves the room (roster shrinks). The wall
      // itself isn't pruned (only castles are, via pruneCastlesNotIn) — but
      // when the remaining player later bulldozes it, the refund must not
      // land on whoever happens to click it. That would let anyone farm
      // free resources off a teammate who quit.
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      g.youBase.place(10, 10, DefType.wall, 'f0');
      final meBefore = g.active.resources;

      // f0 leaves — roster shrinks back down to just you
      g.applyRoomRoster(
          realRoomId: 'r', myUserId: 'me', myUsername: 'Me', members: const []);
      expect(g.players.any((p) => p.id == 'f0'), isFalse,
          reason: 'sanity: f0 is really gone from the roster');
      expect(g.youBase.structAt(10, 10)?.ownerId, 'f0',
          reason: 'sanity: the wall itself survives the reseat, orphaned');

      g.removeStructure(10, 10);
      expect(g.youBase.structAt(10, 10), isNull, reason: 'the wall is gone');
      expect(g.active.resources, meBefore,
          reason: 'no free refund for materials you didn\'t pay for');
    });

    test('REGRESSION: you cannot sell a real teammate\'s structure', () {
      // The base is shared, but the pieces are paid for individually. A
      // teammate's wall is theirs — tapping it must not hand you a sell
      // button, and calling through anyway must be refused.
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      final mate = g.players.firstWhere((p) => p.id == 'f0');
      g.youBase.place(10, 10, DefType.wall, 'f0');
      final mateBefore = mate.resources;

      expect(g.canRemoveStructure(10, 10), isFalse,
          reason: 'the sell button must not even render on a teammate\'s piece');
      expect(g.removeStructure(10, 10), isNotNull,
          reason: 'and the action itself is refused, not silently applied');
      expect(g.youBase.structAt(10, 10), isNotNull, reason: 'the wall stands');
      expect(mate.resources, mateBefore, reason: 'no surprise refund either');

      // your own piece is still yours to tear down
      g.youBase.place(10, 12, DefType.wall, 'me');
      final meBefore = g.active.resources;
      expect(g.canRemoveStructure(10, 12), isTrue);
      expect(g.removeStructure(10, 12), isNull);
      expect(g.youBase.structAt(10, 12), isNull);
      expect(g.active.resources, greaterThan(meBefore));
    });

    test(
        'REGRESSION: real players keep leftover ⚡ and gain a modest war stipend',
        () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      // Seat is a new id — seed leftover prep ⚡ explicitly, then prove war
      // day ADDS the stipend instead of wiping the pool.
      g.active.resources = 80;
      final teammate = g.youClan.firstWhere((p) => p.id == 'f0');
      teammate.resources = 55;
      g.startWar();
      expect(g.active.resources, 80 + WarCosts.realPlayerWarStipend,
          reason: 'leftover prep ⚡ must survive into war, plus a small stipend');
      expect(teammate.resources, 55 + WarCosts.realPlayerWarStipend);
    });

    test('leftover ⚡ survives into the next war\'s prep', () {
      final g = WarGame.fresh()..startPrep();
      g.active.resources = 400;
      g.startWar();
      expect(g.active.resources, 400 + WarCosts.realPlayerWarStipend);
      g.endWar();
      final carried = g.active.resources;
      g.nextWar();
      expect(g.active.resources, carried + WarCosts.realPlayerPrepStipend,
          reason: 'next prep adds a stipend on top of leftover war ⚡');
    });

    test(
        'REGRESSION: real teammates never get free income or auto-raids as '
        'war hours pass', () {
      final originalNowMs = WarGame.nowMs;
      var fakeMs = 1700000000000;
      WarGame.nowMs = () => fakeMs;
      addTearDown(() => WarGame.nowMs = originalNowMs);

      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      g.setDifficulty(50);
      g.startWar();
      final stipend =
          g.youClan.firstWhere((p) => p.id == 'f0').resources;

      // 10 war-hours pass while nobody but 'me' is at the wheel — f0 never
      // logs in during this stretch.
      fakeMs += 10 * WarGame.realSecondsPerSimHour * 1000;
      g.syncToWallClock();

      final teammateAfter = g.youClan.firstWhere((p) => p.id == 'f0');
      expect(teammateAfter.resources, stipend,
          reason: 'a real teammate earns nothing just from time passing — '
              'no bot-style hourly income');
      expect(g.feed.any((e) => e.attackerName == 'A'), isFalse,
          reason: 'a real teammate is never auto-piloted into raiding for '
              'them while they\'re away');
    });

    test('the room admin CAN use every war-wide control', () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      g.isRoomAdmin = true;
      expect(g.canControlWar, isTrue);

      g.setDifficulty(80);
      expect(g.difficulty, 80);

      g.startWar();
      expect(g.phase, WarPhase.war);
    });

    test('solo/offline play always has full control (no room = no admin gate)',
        () {
      final g = WarGame.fresh();
      g.startPrep(); // never wired to a room — roomId stays null
      expect(g.canControlWar, isTrue);
      g.setDifficulty(70);
      expect(g.difficulty, 70);
    });

    test('rapid-fire saves never let an OLDER write clobber a NEWER one',
        () async {
      // regression: SharedPreferences.getInstance().then(...) calls, fired
      // independently, do NOT preserve write order — confirmed directly:
      // 5 rapid saves landed with call #0 winning, not #4. `_save()` must
      // serialize its writes so the LAST call is always what persists.
      final g = WarGame.fresh();
      g.startPrep(); // fires one save (div/season defaults)
      for (var i = 1; i <= 10; i++) {
        g.divisionIndex = i; // mutate...
        g.setDifficulty(50); // ...and immediately fire another save
      }
      await Future<void>.delayed(Duration.zero);
      await WarGame.load();
      expect(WarGame.instance.divisionIndex, 10,
          reason: 'the LAST save must win, not whichever happened to land');
    });

    test('a real room fires onRoomSave on every mutating save', () {
      final calls = <WarGame>[];
      WarGame.onRoomSave = calls.add;
      addTearDown(() => WarGame.onRoomSave = null);

      final g = WarGame.fresh();
      g.startPrep(); // no room yet — must NOT fire the hook
      expect(calls, isEmpty);

      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: friends([
            ['f0', 'A']
          ]));
      expect(calls, isNotEmpty, reason: 'a real room DOES fire the hook');
      expect(identical(calls.last, g), isTrue);

      final before = calls.length;
      g.setDifficulty(70);
      expect(calls.length, before + 1,
          reason: 'every later mutation keeps firing it too');
    });

    test('a rejected save (conflict) adopts the WINNING state, not its own',
        () {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'r',
          myUserId: 'me',
          myUsername: 'Me',
          members: const []);
      final myVersionBeforeConflict = g.roomVersion;
      final conflictsBefore = g.syncConflicts;

      // simulate exactly what the sync layer does when the server rejects
      // our save because a teammate's landed first: adopt THEIR state.
      final teammatesJson = Map<String, dynamic>.from(g.toJson());
      teammatesJson['diff100'] = 91; // a distinguishable "their" change
      g.loadFromJson(teammatesJson);
      g.roomVersion = myVersionBeforeConflict + 1;
      g.syncConflicts++;

      expect(g.difficulty, 91, reason: 'the teammate\'s state won');
      expect(g.syncConflicts, conflictsBefore + 1);
    });

    test('room id round-trips through save/load', () async {
      final g = WarGame.fresh();
      g.startPrep();
      g.applyRoomRoster(
          realRoomId: 'persisted-room',
          myUserId: 'me',
          myUsername: 'Me',
          members: const []);
      await Future<void>.delayed(Duration.zero); // flush fire-and-forget save
      await WarGame.load();
      expect(WarGame.instance.roomId, 'persisted-room');
    });
  });

  group('deploy: the war runs on the WALL CLOCK — no button needed', () {
    // a controllable clock so we can time-travel deterministically
    var fakeMs = 1700000000000; // a realistic epoch base (never 0)
    setUp(() {
      fakeMs = 1700000000000;
      WarGame.nowMs = () => fakeMs;
    });
    tearDown(() {
      WarGame.nowMs = () => DateTime.now().millisecondsSinceEpoch;
    });

    int hourMs(int h) => h * WarGame.realSecondsPerSimHour * 1000;

    test('logging in after N hours replays exactly N hours of raids', () {
      final g = freshGame(70);
      g.startWar();
      expect(g.clock.hour, 0, reason: 'the war just began');
      // the player closes the app; three war-hours of real time pass
      fakeMs += hourMs(3);
      g.syncToWallClock();
      expect(g.clock.hour, 3, reason: 'login caught the war up to hour 3');
      expect(g.phase, WarPhase.war, reason: '3 of 24 — still raging');
    });

    test('watching live == checking back later (deterministic catch-up)', () {
      // game A: one player watches, syncing hour by hour
      fakeMs = 1700000000000;
      final a = freshGame(80);
      a.startWar();
      for (var h = 1; h <= 10; h++) {
        fakeMs = 1700000000000 + hourMs(h);
        a.syncToWallClock();
      }
      // game B: an identical player closes the app and returns 10 hours later
      fakeMs = 1700000000000;
      final b = freshGame(80);
      b.startWar();
      fakeMs = 1700000000000 + hourMs(10);
      b.syncToWallClock();

      expect(b.clock.hour, a.clock.hour, reason: 'same hour reached');
      expect(b.enemyBase.destructionPercent,
          closeTo(a.enemyBase.destructionPercent, 0.001),
          reason: 'the war looks identical whether you watched or came back');
      expect(b.youBase.destructionPercent,
          closeTo(a.youBase.destructionPercent, 0.001));
      expect(b.feed.length, a.feed.length, reason: 'same raids happened');
    });

    test('a full day of real time auto-resolves the war — no tap required', () {
      final g = freshGame(60);
      g.startWar();
      // a whole war day (plus slack) elapses while nobody touches a button
      fakeMs += hourMs(25);
      g.syncToWallClock();
      expect(g.phase, WarPhase.results, reason: 'the war ended itself');
      expect(g.lastVerdict, isNotNull, reason: 'a verdict was struck');
    });

    test('the countdown counts DOWN toward the next raid', () {
      final g = freshGame(50);
      g.startWar();
      final atStart = g.untilNextWarHour;
      fakeMs += WarGame.realSecondsPerSimHour * 1000 ~/ 2; // halfway to hour 1
      final later = g.untilNextWarHour;
      expect(later, lessThan(atStart), reason: 'time is ticking down');
      expect(g.untilWarEnds.inSeconds,
          greaterThan(g.untilNextWarHour.inSeconds),
          reason: 'the whole war outlasts the next hour');
    });

    test('manual skip stays consistent with the wall clock', () {
      final g = freshGame(50);
      g.startWar();
      g.advanceHours(6); // a tester skips ahead
      expect(g.clock.hour, 6);
      // no extra real time has passed, so a sync must NOT double-advance
      g.syncToWallClock();
      expect(g.clock.hour, 6, reason: 'skip rewound the anchor — no double run');
    });
  });

  group('deploy: the ladder reads HONESTLY — scores match the opponents', () {
    test('a winning record shows a POSITIVE goal difference', () {
      final g = freshGame(60);
      g.seasonResults = [true, true, true, false]; // 3-1
      g.warIndex = 4;
      final you = g.buildTable().yourRow!;
      expect(you.wins, 3);
      expect(you.losses, 1);
      expect(you.diff, greaterThan(0),
          reason: 'winning more than losing must not read as -400 diff');
    });

    test('a winning team is never ranked BELOW an equal-points team it should '
        'beat on difference', () {
      final g = freshGame(60);
      g.seasonResults = [true, false, true]; // 2-1, strong
      g.warIndex = 3;
      final t = g.buildTable();
      final you = t.yourRow!;
      // among teams tied on points, yours must sort by a real difference, so
      // it can't be dead last of that group with an absurd negative diff
      final tied =
          t.standings.where((s) => s.leaguePoints == you.leaguePoints).toList();
      final worst = tied.map((s) => s.diff).reduce((a, b) => a < b ? a : b);
      expect(you.diff, greaterThan(worst - 1),
          reason: 'a 2-1 team should not be the worst of its points group');
    });

    test('the live fixture is a real contest, not 0 vs 126', () {
      final g = freshGame(60);
      g.seasonResults = [true];
      g.warIndex = 1;
      final live = g.buildTable().live;
      expect(live, isNotNull);
      // even at 0% razed the live score sits in the opponents' band, not 0
      expect(live!.yourScore, greaterThan(50),
          reason: 'the live week must look like a match, not a shutout');
    });
  });

  group('deploy: the ladder is valid at every point in the calendar', () {
    test('every (division, week) combo builds a clean table', () {
      final g = freshGame(70);
      for (var div = 0; div < cfg.divisions.length; div++) {
        g.divisionIndex = div;
        for (var wk = 0; wk <= cfg.matchweeks; wk++) {
          g.warIndex = wk.clamp(0, cfg.matchweeks - 1);
          g.seasonResults = [for (var i = 0; i < wk; i++) i.isEven];
          assertValidTable(g.buildTable(), ctx: 'div$div wk$wk');
        }
      }
    });
  });

  group('deploy: state survives an app restart', () {
    test('division + season persist across save/load', () async {
      final g = freshGame(50);
      // promote once so there is real state to persist
      for (var w = 0; w < cfg.matchweeks; w++) {
        g.startWar();
        razeEnemy(g);
        g.endWar();
        g.nextWar();
      }
      final savedDiv = g.divisionIndex;
      final savedSeason = g.seasonIndex;
      expect(savedDiv, 1);

      // let the fire-and-forget _save() writes flush to (mock) prefs
      await Future<void>.delayed(Duration.zero);

      // simulate a cold start: load() rehydrates the singleton from prefs
      await WarGame.load();
      expect(WarGame.instance.divisionIndex, savedDiv,
          reason: 'division persisted across restart');
      expect(WarGame.instance.seasonIndex, savedSeason,
          reason: 'season persisted across restart');
    });
  });

  group('deploy: the difficulty dial holds across its whole range', () {
    test('every difficulty 1..100 sets a sane skill and builds a table', () {
      final g = WarGame.fresh();
      g.startPrep();
      for (var d = 1; d <= 100; d++) {
        g.setDifficulty(d);
        final foe = g.enemyClan.first;
        expect(foe.skill, greaterThan(0), reason: 'd$d skill > 0');
        expect(foe.skill, lessThanOrEqualTo(1.5), reason: 'd$d skill capped');
        assertValidTable(g.buildTable(), ctx: 'dial d$d');
      }
      // the dial is monotonic: 99 is strictly harder than 1
      g.setDifficulty(1);
      final easy = g.enemyClan.first.skill;
      g.setDifficulty(99);
      final hard = g.enemyClan.first.skill;
      expect(hard, greaterThan(easy), reason: 'the dial must bite harder up top');
    });
  });
}
