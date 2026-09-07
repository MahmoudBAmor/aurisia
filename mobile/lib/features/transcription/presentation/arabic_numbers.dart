const _arabicDigits = <String>[
  '٠',
  '١',
  '٢',
  '٣',
  '٤',
  '٥',
  '٦',
  '٧',
  '٨',
  '٩',
];

String toArabicDigits(int value) {
  return value.toString().split('').map((digit) {
    if (digit == '-') {
      return digit;
    }
    return _arabicDigits[int.parse(digit)];
  }).join();
}

String speakerDisplayName(int zeroBasedIndex) {
  return 'المتحدث ${toArabicDigits(zeroBasedIndex + 1)}';
}
