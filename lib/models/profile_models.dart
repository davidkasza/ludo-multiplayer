import 'package:cloud_firestore/cloud_firestore.dart';

String _string(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int _integer(Object? value) => value is num ? value.toInt() : 0;

List<String> _strings(Object? value) => value is Iterable
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

class PlayerProfile {
  final String uid;
  final String displayName;
  final bool isAnonymous;
  final String activeGameId;
  final int xp;
  final int coins;
  final int rewardedMatches;
  final int rewardedWins;
  final int rewardedPodiums;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const PlayerProfile({
    required this.uid,
    required this.displayName,
    required this.isAnonymous,
    required this.activeGameId,
    required this.xp,
    required this.coins,
    required this.rewardedMatches,
    required this.rewardedWins,
    required this.rewardedPodiums,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlayerProfile.fromMap(String uid, Map<String, dynamic> map) {
    return PlayerProfile(
      uid: uid,
      displayName: _string(map['displayName']),
      isAnonymous: map['isAnonymous'] is bool
          ? map['isAnonymous'] as bool
          : true,
      activeGameId: _string(map['activeGameId']),
      xp: _integer(map['xp']).clamp(0, 1 << 31).toInt(),
      coins: _integer(map['coins']).clamp(0, 1 << 31).toInt(),
      rewardedMatches: _integer(map['rewardedMatches']).clamp(0, 1 << 31).toInt(),
      rewardedWins: _integer(map['rewardedWins']).clamp(0, 1 << 31).toInt(),
      rewardedPodiums: _integer(map['rewardedPodiums']).clamp(0, 1 << 31).toInt(),
      createdAt: map['createdAt'] is Timestamp
          ? map['createdAt'] as Timestamp
          : null,
      updatedAt: map['updatedAt'] is Timestamp
          ? map['updatedAt'] as Timestamp
          : null,
    );
  }
}

class MatchHistoryEntry {
  final String id;
  final List<String> participantIds;
  final List<String> ranking;
  final Map<String, String> playerNames;
  final String boardId;
  final int playerCount;
  final int humanPlayerCount;
  final int botPlayerCount;
  final Timestamp? startedAt;
  final Timestamp? finishedAt;

  const MatchHistoryEntry({
    required this.id,
    required this.participantIds,
    required this.ranking,
    required this.playerNames,
    required this.boardId,
    required this.playerCount,
    required this.humanPlayerCount,
    required this.botPlayerCount,
    required this.startedAt,
    required this.finishedAt,
  });

  factory MatchHistoryEntry.fromDocument(
      QueryDocumentSnapshot<Map<String, dynamic>> document,
      ) {
    final map = document.data();
    final names = <String, String>{};
    final rawNames = map['playerNames'];

    if (rawNames is Map) {
      Map<String, dynamic>.from(rawNames).forEach((key, value) {
        names[key] = value.toString();
      });
    }

    return MatchHistoryEntry(
      id: document.id,
      participantIds: _strings(map['participantIds']),
      ranking: _strings(map['ranking']),
      playerNames: names,
      boardId: _string(map['boardId'], 'classic'),
      playerCount: _integer(map['playerCount']).clamp(0, 4).toInt(),
      humanPlayerCount: _integer(map['humanPlayerCount']).clamp(0, 4).toInt(),
      botPlayerCount: _integer(map['botPlayerCount']).clamp(0, 4).toInt(),
      startedAt: map['startedAt'] is Timestamp
          ? map['startedAt'] as Timestamp
          : null,
      finishedAt: map['finishedAt'] is Timestamp
          ? map['finishedAt'] as Timestamp
          : null,
    );
  }

  int placementFor(String playerId) {
    final index = ranking.indexOf(playerId);
    return index < 0 ? 0 : index + 1;
  }

  String playerName(String playerId) {
    return playerNames[playerId] ?? 'Player';
  }

  Duration? get duration {
    if (startedAt == null || finishedAt == null) return null;
    final result = finishedAt!.toDate().difference(startedAt!.toDate());
    return result.isNegative ? Duration.zero : result;
  }
}

class PlayerMatchStats {
  final int gamesPlayed;
  final int wins;
  final int podiums;
  final double winRate;

  const PlayerMatchStats({
    required this.gamesPlayed,
    required this.wins,
    required this.podiums,
    required this.winRate,
  });

  factory PlayerMatchStats.fromHistory(
      String playerId,
      List<MatchHistoryEntry> history,
      ) {
    final games = history.where(
          (entry) => entry.ranking.contains(playerId),
    ).toList();

    final wins = games.where(
          (entry) => entry.placementFor(playerId) == 1,
    ).length;

    final podiums = games.where((entry) {
      final placement = entry.placementFor(playerId);
      return placement > 0 && placement <= 3;
    }).length;

    return PlayerMatchStats(
      gamesPlayed: games.length,
      wins: wins,
      podiums: podiums,
      winRate: games.isEmpty ? 0 : wins / games.length,
    );
  }
}
