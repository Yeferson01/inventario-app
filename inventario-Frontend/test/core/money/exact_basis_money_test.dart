import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/money/exact_basis_money.dart';
import 'package:inventario_frontend/features/inventory/application/purchase_money.dart';

void main() {
  final vectors = <({
    String id,
    BigInt amount,
    BigInt quantity,
    BigInt basis,
    BigInt expected
  })>[
    (
      id: 'unit',
      amount: BigInt.from(350000),
      quantity: BigInt.two,
      basis: BigInt.one,
      expected: BigInt.from(700000)
    ),
    (
      id: 'weight',
      amount: BigInt.from(1200000),
      quantity: BigInt.from(735),
      basis: BigInt.from(500),
      expected: BigInt.from(1764000)
    ),
    (
      id: 'below_half',
      amount: BigInt.one,
      quantity: BigInt.one,
      basis: BigInt.from(3),
      expected: BigInt.zero
    ),
    (
      id: 'half',
      amount: BigInt.one,
      quantity: BigInt.one,
      basis: BigInt.two,
      expected: BigInt.one
    ),
    (
      id: 'above_half',
      amount: BigInt.two,
      quantity: BigInt.one,
      basis: BigInt.from(3),
      expected: BigInt.one
    ),
    (
      id: 'commercial',
      amount: BigInt.from(1200100),
      quantity: BigInt.from(3),
      basis: BigInt.from(500),
      expected: BigInt.from(7201)
    ),
    (
      id: 'zero_quantity',
      amount: BigInt.from(1200000),
      quantity: BigInt.zero,
      basis: BigInt.from(500),
      expected: BigInt.zero
    ),
    (
      id: 'large_safe',
      amount: signedInt64Max,
      quantity: signedInt64Max,
      basis: signedInt64Max,
      expected: signedInt64Max
    ),
    (
      id: 'cost_ratio',
      amount: BigInt.from(2280000),
      quantity: BigInt.from(735),
      basis: BigInt.from(13000),
      expected: BigInt.from(128908)
    ),
  ];

  for (final vector in vectors) {
    test('shared vector ${vector.id}', () {
      expect(
          calculateBasisAmountCents(
            baseAmountCents: vector.amount,
            quantity: vector.quantity,
            basisQuantity: vector.basis,
          ),
          vector.expected);
    });
  }

  test('invalid inputs fail instead of rounding or changing sign', () {
    for (final invalid in [
      (BigInt.from(-1), BigInt.one, BigInt.one),
      (BigInt.one, BigInt.from(-1), BigInt.one),
      (BigInt.one, BigInt.one, BigInt.zero),
      (BigInt.one, BigInt.one, BigInt.from(-1)),
    ]) {
      expect(
        () => calculateBasisAmountCents(
          baseAmountCents: invalid.$1,
          quantity: invalid.$2,
          basisQuantity: invalid.$3,
        ),
        throwsArgumentError,
      );
    }
  });

  test('checked conversion accepts signed BIGINT edges and rejects overflow',
      () {
    expect(checkedSignedInt64(BigInt.from(7201)), 7201);
    expect(checkedSignedInt64(signedInt64Max), 9223372036854775807);
    expect(checkedSignedInt64(signedInt64Min), -9223372036854775808);
    expect(() => checkedSignedInt64(signedInt64Max + BigInt.one),
        throwsRangeError);
    expect(() => checkedSignedInt64(signedInt64Min - BigInt.one),
        throwsRangeError);
    final overflow = calculateBasisAmountCents(
      baseAmountCents: signedInt64Max,
      quantity: BigInt.two,
      basisQuantity: BigInt.one,
    );
    expect(() => checkedSignedInt64(overflow), throwsRangeError);
  });

  test('UNIT purchase result remains identical without changing purchase flow',
      () {
    final cents = BigInt.from(250050);
    final quantity = BigInt.two;
    expect(
      calculateBasisAmountCents(
        baseAmountCents: cents,
        quantity: quantity,
        basisQuantity: BigInt.one,
      ),
      purchaseLineTotalCents(cents, 2),
    );
  });
}
