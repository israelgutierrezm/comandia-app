import 'package:comandia_app/core/device_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatDeviceName', () {
    test('marca + modelo + sistema + versión, con la marca capitalizada', () {
      expect(
        formatDeviceName(brand: 'motorola', model: 'moto g32', osName: 'Android', osVersion: '14'),
        'Motorola moto g32 · Android 14',
      );
      expect(
        formatDeviceName(brand: 'Apple', model: 'iPhone 13', osName: 'iOS', osVersion: '17.5'),
        'Apple iPhone 13 · iOS 17.5',
      );
    });

    test('no repite la marca cuando el modelo ya empieza con ella', () {
      expect(
        formatDeviceName(brand: 'Redmi', model: 'Redmi Note 8 Pro', osName: 'Android', osVersion: '11'),
        'Redmi Note 8 Pro · Android 11',
      );
      // Sin importar mayúsculas.
      expect(
        formatDeviceName(brand: 'OnePlus', model: 'ONEPLUS A6003', osName: 'Android', osVersion: '10'),
        'ONEPLUS A6003 · Android 10',
      );
      // Sólo como palabra completa: en «LGM-V300K» las letras son parte del código del modelo.
      expect(
        formatDeviceName(brand: 'LG', model: 'LGM-V300K', osName: 'Android', osVersion: '9'),
        'LG LGM-V300K · Android 9',
      );
    });

    test('limpia espacios en las orillas y repetidos', () {
      expect(
        formatDeviceName(brand: '  samsung ', model: '  SM-A515F  ', osName: ' Android ', osVersion: ' 13 '),
        'Samsung SM-A515F · Android 13',
      );
      expect(
        formatDeviceName(brand: 'motorola\t', model: 'moto   g32', osName: 'Android', osVersion: '14'),
        'Motorola moto g32 · Android 14',
      );
    });

    test('respeta la marca que ya trae su propio estilo', () {
      expect(
        formatDeviceName(brand: 'iQOO', model: 'I2011', osName: 'Android', osVersion: '13'),
        'iQOO I2011 · Android 13',
      );
    });

    test('con datos vacíos arma lo que haya', () {
      // Sin marca.
      expect(formatDeviceName(brand: '', model: 'Pixel 7', osName: 'Android', osVersion: '14'), 'Pixel 7 · Android 14');
      // Sin modelo.
      expect(formatDeviceName(brand: 'google', osName: 'Android', osVersion: '14'), 'Google · Android 14');
      // Sin aparato: sólo el sistema.
      expect(formatDeviceName(osName: 'Android', osVersion: '14'), 'Android 14');
      // Sin versión.
      expect(formatDeviceName(brand: 'motorola', model: 'moto g32', osName: 'Android'), 'Motorola moto g32 · Android');
      // Sin nombre de sistema, un «14» suelto no dice nada: se omite.
      expect(formatDeviceName(brand: 'motorola', model: 'moto g32', osName: '', osVersion: '14'), 'Motorola moto g32');
    });

    test('sin ningún dato cae en «App Comandia»', () {
      expect(formatDeviceName(), fallbackDeviceName);
      expect(formatDeviceName(brand: '  ', model: '', osName: ' ', osVersion: '14'), 'App Comandia');
    });

    test('recorta a 120 caracteres con «…»', () {
      final long = formatDeviceName(brand: 'samsung', model: 'SM-${'X' * 200}', osName: 'Android', osVersion: '14');
      expect(long.runes.length, maxDeviceNameLength);
      expect(long, startsWith('Samsung SM-XXX'));
      expect(long, endsWith('…'));

      // Justo en el límite no se toca: 6 + 105 + 9 = 120.
      final exact = formatDeviceName(brand: 'Apple', model: 'M' * 105, osName: 'iOS', osVersion: '17');
      expect(exact, 'Apple ${'M' * 105} · iOS 17');
      expect(exact.runes.length, 120);

      // Si el corte cae en el separador, no queda colgando «·».
      expect(
        formatDeviceName(brand: 'Apple', model: 'M' * 111, osName: 'iOS', osVersion: '17.5'),
        'Apple ${'M' * 111}…',
      );

      // Se cuenta por puntos de código (como el servidor): un carácter fuera del plano básico no se parte a la mitad.
      final emoji = formatDeviceName(brand: 'Apple', model: '📱' * 130, osName: 'iOS', osVersion: '17');
      expect(emoji.runes.length, maxDeviceNameLength);
      expect(emoji.runes.where((r) => r >= 0xD800 && r <= 0xDFFF), isEmpty);
    });
  });

  test('readDeviceName cae en «App Comandia» si la plataforma no responde', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // En la prueba no hay implementación nativa de device_info_plus: la lectura falla y no debe impedir entrar.
    expect(await readDeviceName(), fallbackDeviceName);
  });
}
