import 'package:cool_app/core/theme/cool_foundations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoolSpace', () {
    test('spacing scale is monotonically increasing', () {
      const scale = <double>[
        CoolSpace.x0,
        CoolSpace.x1,
        CoolSpace.x2,
        CoolSpace.x3,
        CoolSpace.x4,
        CoolSpace.x5,
        CoolSpace.x6,
        CoolSpace.x7,
        CoolSpace.x8,
        CoolSpace.x9,
        CoolSpace.x10,
      ];
      for (var i = 1; i < scale.length; i++) {
        expect(
          scale[i],
          greaterThan(scale[i - 1]),
          reason: 'x$i should be > x${i - 1}',
        );
      }
    });

    test('spacing values match expected grid', () {
      expect(CoolSpace.x0, 0.0);
      expect(CoolSpace.x1, 4.0);
      expect(CoolSpace.x2, 8.0);
      expect(CoolSpace.x3, 12.0);
      expect(CoolSpace.x4, 16.0);
      expect(CoolSpace.x5, 20.0);
      expect(CoolSpace.x6, 24.0);
      expect(CoolSpace.x7, 32.0);
      expect(CoolSpace.x8, 40.0);
      expect(CoolSpace.x9, 48.0);
      expect(CoolSpace.x10, 64.0);
    });

    test('sectionPadding uses x6 (24)', () {
      expect(CoolSpace.sectionPadding.left, CoolSpace.x6);
      expect(CoolSpace.sectionPadding.top, CoolSpace.x6);
      expect(CoolSpace.sectionPadding.right, CoolSpace.x6);
      expect(CoolSpace.sectionPadding.bottom, CoolSpace.x6);
    });

    test('denseSectionPadding uses x5 (20)', () {
      expect(CoolSpace.denseSectionPadding.left, CoolSpace.x5);
      expect(CoolSpace.denseSectionPadding.top, CoolSpace.x5);
    });
  });

  group('CoolRadii', () {
    test('radius scale is non-decreasing', () {
      const scale = <double>[
        CoolRadii.xs,
        CoolRadii.sm,
        CoolRadii.md,
        CoolRadii.lg,
        CoolRadii.xl,
        CoolRadii.xxl,
        CoolRadii.pill,
      ];

      for (var i = 1; i < scale.length; i++) {
        expect(
          scale[i],
          greaterThanOrEqualTo(scale[i - 1]),
          reason: 'Radii scale must be non-decreasing',
        );
      }
    });

    test('radius values match expected grid', () {
      expect(CoolRadii.xs, 10.0);
      expect(CoolRadii.sm, 14.0);
      expect(CoolRadii.md, 18.0);
      expect(CoolRadii.lg, 22.0);
      expect(CoolRadii.xl, 28.0);
      expect(CoolRadii.xxl, 32.0);
      expect(CoolRadii.pill, 999.0);
    });

    test('pill is significantly larger than xxl for pill shapes', () {
      expect(CoolRadii.pill, greaterThan(CoolRadii.xxl * 10));
    });
  });

  group('CoolBlur', () {
    test('blur scale is ordered', () {
      expect(CoolBlur.subtle, lessThanOrEqualTo(CoolBlur.standard));
      expect(CoolBlur.standard, lessThanOrEqualTo(CoolBlur.overlay));
    });

    test('heavy equals overlay', () {
      expect(CoolBlur.heavy, CoolBlur.overlay);
    });
  });
}
