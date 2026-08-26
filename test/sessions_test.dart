import 'package:comandia_app/features/sessions/sessions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SessionSummary.fromJson lee folio, estado y terminal', () {
    final s = SessionSummary.fromJson({
      'ulid': 'S1',
      'folio': 'C-0007',
      'status': 'open',
      'status_label': 'Abierta',
      'terminal': {'name': 'Caja 1'},
      'opened_at': '2026-08-25 09:00',
      'closed_at': null,
    });

    expect(s.folio, 'C-0007');
    expect(s.status, 'open');
    expect(s.statusLabel, 'Abierta');
    expect(s.terminalName, 'Caja 1');
    expect(s.closedAt, isNull);
  });

  test('SessionSummary.fromJson tolera campos ausentes', () {
    final s = SessionSummary.fromJson({'ulid': 'S2'});
    expect(s.folio, '—');
    expect(s.terminalName, isNull);
  });
}
