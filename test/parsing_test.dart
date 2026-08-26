import 'package:comandia_app/features/supervision/supervision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppContext.fromJson', () {
    test('lee tenant, rol activo y sucursal activa', () {
      final ctx = AppContext.fromJson({
        'tenant': {'name': 'Fonda del Centro'},
        'membership': {'display_name': 'Ana Gómez'},
        'active_role': {'ulid': 'ROLE1', 'name': 'Dueño'},
        'active_branch': {'ulid': 'BR1', 'name': 'Roma Norte'},
        'branches': [
          {'ulid': 'BR1', 'name': 'Roma Norte'},
        ],
        'is_read_only': false,
        'permissions': ['a', 'b', 'c'],
      });

      expect(ctx.tenantName, 'Fonda del Centro');
      expect(ctx.roleName, 'Dueño');
      expect(ctx.branchUlid, 'BR1');
      expect(ctx.permissionsCount, 3);
      expect(ctx.isReadOnly, isFalse);
    });

    test('sin sucursal activa, toma la primera alcanzable', () {
      final ctx = AppContext.fromJson({
        'tenant': {'name': 'Café'},
        'active_role': {'ulid': 'R', 'name': 'Gerente'},
        'active_branch': null,
        'branches': [
          {'ulid': 'BR9', 'name': 'Matriz'},
        ],
        'permissions': <String>[],
      });

      expect(ctx.branchUlid, 'BR9');
      expect(ctx.branchName, 'Matriz');
    });
  });

  test('OpenSession.fromJson lee folio y terminal', () {
    final s = OpenSession.fromJson({
      'ulid': 'S1',
      'folio': 'C-0001',
      'terminal': {'name': 'Caja 1'},
      'branch': {'name': 'Roma Norte'},
      'opened_at': '2026-08-25 10:00',
    });

    expect(s.folio, 'C-0001');
    expect(s.terminalName, 'Caja 1');
  });

  test('CutMethod.fromJson lee esperado y diferencia', () {
    final c = CutMethod.fromJson({
      'method': 'Efectivo',
      'expected': '1000.00',
      'declared': '980.00',
      'difference': '-20.00',
    });

    expect(c.method, 'Efectivo');
    expect(c.difference, '-20.00');
  });
}
