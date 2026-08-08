@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A guard on the words Sales Staff actually read.
///
/// The system accepts an itemized sales invoice **or** a POS receipt, so copy
/// that calls the uploaded document only "a receipt" tells a seller holding an
/// invoice that this app is not for them. This scans the Sales Staff-visible
/// source for display strings that name the document and fails when one says
/// "receipt" without acknowledging invoices.
///
/// ## Why this is not "the word receipt is banned in lib/"
///
/// Because it would be wrong, and it would be the kind of wrong that gets a
/// guard deleted rather than obeyed. `receipt_*` is the backend's own
/// vocabulary and this client mirrors it deliberately: `submit-receipt`,
/// `list_my_receipt_extraction_line_items`, `ReceiptSubmissionCubit`,
/// `receipt_review_copy.dart`. Every one of those must keep the word. So must
/// the doc comments that explain them, which is why only executable lines are
/// read.
///
/// What is checked is narrower and is the thing that actually matters: a
/// **quoted string literal** that (a) lives in a file a Sales Staff member's
/// screen is built from, (b) contains the word receipt as ordinary prose, and
/// (c) does not pair it with invoice.
///
/// ## What it deliberately does not cover
///
/// Retailer- and Vendor-facing administration copy — staff lifecycle, retailer
/// lifecycle, invitations. Those screens describe the same documents and are
/// worth revisiting, but they are a different audience and a different review,
/// and quietly widening this guard would quietly widen that milestone.
void main() {
  /// The files whose strings a Sales Staff member can read on a screen.
  late List<File> salesStaffSources;

  /// One file's executable lines.
  ///
  /// Doc comments are excluded on purpose. They discuss the backend's
  /// `receipt_*` vocabulary at length and must go on doing so; a scan that
  /// could not tell prose-for-humans from prose-about-the-schema would force
  /// the documentation to stop naming what it describes.
  List<String> codeLines(File file) =>
      file.readAsLinesSync().where((String line) {
        final String t = line.trimLeft();
        return !t.startsWith('//') && !t.startsWith('*');
      }).toList();

  setUpAll(() {
    const List<String> roots = <String>[
      'lib/features/receipts/presentation/sales_staff',
      'lib/features/home/presentation/sales_staff',
      'lib/features/rewards/presentation',
      'lib/features/campaigns/presentation/shared',
    ];
    salesStaffSources = <File>[
      for (final String root in roots)
        if (Directory(root).existsSync())
          ...Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((File f) => f.path.endsWith('.dart')),
    ];
  });

  test('the scan has something to read (it would pass vacuously)', () {
    expect(salesStaffSources, isNotEmpty);
    expect(salesStaffSources.length, greaterThan(20));
  });

  test('no Sales Staff-visible sentence calls the document only a receipt', () {
    // A single-quoted Dart literal. Interpolations are left in place — a label
    // is judged as the sentence a person reads, `$productName` included.
    final RegExp literal = RegExp(r"'([^'\\]|\\.)*'");
    // The word itself, in prose. `receipt_id`, `receipt-image-preview` and
    // `submitReceipts` are identifiers, not sentences, so a word boundary that
    // excludes `_`, `-` and a following capital keeps them out.
    final RegExp prose = RegExp(r'(?<![A-Za-z_\-])[Rr]eceipts?(?![A-Za-z_\-])');
    final RegExp acknowledged = RegExp(r'[Ii]nvoices? / [Rr]eceipts?');

    final List<String> offences = <String>[];

    for (final File file in salesStaffSources) {
      final List<String> lines = codeLines(file);
      for (int i = 0; i < lines.length; i++) {
        final String line = lines[i];
        // Imports and parts are paths, not prose.
        final String trimmed = line.trimLeft();
        if (trimmed.startsWith('import ') ||
            trimmed.startsWith('export ') ||
            trimmed.startsWith('part ')) {
          continue;
        }
        for (final RegExpMatch m in literal.allMatches(line)) {
          final String text = m.group(0)!;
          if (!prose.hasMatch(text)) {
            continue;
          }
          if (acknowledged.hasMatch(text)) {
            continue;
          }
          // A sentence split across adjacent literals: the pairing may live on
          // a neighbouring line, so the two around it are consulted before this
          // is called an offence.
          final String window = <String>[
            if (i > 0) lines[i - 1],
            line,
            if (i + 1 < lines.length) lines[i + 1],
          ].join(' ');
          if (acknowledged.hasMatch(window)) {
            continue;
          }
          offences.add('${file.path}:${i + 1}  $text');
        }
      }
    }

    expect(
      offences,
      isEmpty,
      reason:
          'These Sales Staff-visible strings name the uploaded document as a '
          'receipt without acknowledging invoices. Say "invoice / receipt" '
          '(or a natural plural) instead:\n${offences.join('\n')}',
    );
  });

  test('the backend vocabulary is untouched by the copy change', () {
    // The guard above must never have been satisfied by renaming a contract.
    // These are the names the backend owns, and they are asserted present.
    final String rpc = File(
      'lib/features/receipts/data/datasources/'
      'receipt_extraction_rpc_data_source.dart',
    ).readAsStringSync();
    final String submit = File(
      'lib/features/receipts/data/datasources/'
      'submit_receipt_function_client.dart',
    ).readAsStringSync();
    final String reads = File(
      'lib/features/receipts/data/datasources/receipt_rpc_data_source.dart',
    ).readAsStringSync();

    expect(rpc.contains("'list_my_receipt_extraction_line_items'"), isTrue);
    expect(rpc.contains("'confirm_receipt_extraction'"), isTrue);
    expect(rpc.contains("'confirm_receipt_with_products'"), isTrue);
    expect(rpc.contains("'get_my_receipt_confirmation'"), isTrue);
    expect(rpc.contains("'get_receipt_currency_minor_unit'"), isTrue);
    expect(submit.contains("'submit-receipt'"), isTrue);
    expect(submit.contains("'shop_id'"), isTrue);
    expect(reads.contains("'list_my_assigned_receipt_shops'"), isTrue);
    expect(reads.contains("'list_my_receipt_submissions'"), isTrue);
    expect(reads.contains("'get_my_receipt_submission'"), isTrue);
  });
}
