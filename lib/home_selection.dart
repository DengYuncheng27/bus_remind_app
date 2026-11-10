import 'api.dart';

/// Missing schedule metadata (older servers) preserves the fixed favorite.
bool isCurrentReminder(Json reminder) =>
    isOn(reminder['schedule_active']) &&
    isOn(reminder['active']) &&
    !pausedToday(reminder);

String? selectHomeReminder(
  List<Json> reminders, {
  String? currentId,
  String? favoriteId,
}) {
  if (reminders.isEmpty) return null;
  final ordered = [...reminders]
    ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
  final current = ordered.where(isCurrentReminder).toList();
  if (current.isNotEmpty) {
    for (final id in [currentId, favoriteId]) {
      if (current.any((r) => '${r['id']}' == id)) return id;
    }
    return '${current.first['id']}';
  }
  return fixedHomeReminder(ordered, favoriteId);
}

String? fixedHomeReminder(List<Json> reminders, String? favoriteId) {
  if (reminders.isEmpty) return null;
  if (reminders.any((r) => '${r['id']}' == favoriteId)) return favoriteId;
  final ordered = [...reminders]
    ..sort((a, b) => (a['id'] as num).compareTo(b['id'] as num));
  return '${ordered.firstWhere((r) => isOn(r['active']), orElse: () => ordered.first)['id']}';
}
