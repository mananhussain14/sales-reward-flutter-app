import 'dart:async';
import 'dart:typed_data';

import 'package:sale_reward/core/errors/failure.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_file.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_image_type.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_product.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_shop.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_outcome.dart';
import 'package:sale_reward/features/receipts/domain/entities/receipt_submission_status.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_repository.dart';
import 'package:sale_reward/features/receipts/domain/repositories/receipt_result.dart';
import 'package:sale_reward/features/receipts/domain/services/receipt_image_source.dart';

/// A hand-written [ReceiptRepository] fake.
///
/// Hand-written rather than mocked because these tests care about *what was
/// sent* as much as what came back: [lastSubmittedShopId] and
/// [lastSubmittedFile] are how a test proves that one shop id and one file are
/// the only things that ever leave the client.
class FakeReceiptRepository implements ReceiptRepository {
  ReceiptResult<List<ReceiptShop>> shopsResult =
      ReceiptReadSuccess<List<ReceiptShop>>(<ReceiptShop>[shopA, shopB]);

  ReceiptResult<List<ReceiptProduct>> productsResult =
      ReceiptReadSuccess<List<ReceiptProduct>>(<ReceiptProduct>[
        productA,
        productB,
      ]);

  ReceiptResult<List<ReceiptSubmission>> submissionsResult =
      const ReceiptReadSuccess<List<ReceiptSubmission>>(<ReceiptSubmission>[]);

  ReceiptResult<ReceiptSubmission?> submissionResult =
      ReceiptReadSuccess<ReceiptSubmission?>(submittedRow);

  ReceiptSubmissionOutcome submitOutcome = const ReceiptSubmissionAccepted(
    submissionUuid,
  );

  int assignedShopsCallCount = 0;
  int receiptProductsCallCount = 0;
  int submissionsCallCount = 0;
  int submissionCallCount = 0;
  int submitCallCount = 0;

  String? lastRequestedSubmissionId;
  String? lastSubmittedShopId;
  ReceiptFile? lastSubmittedFile;

  /// When true, every [submitReceipt] stays pending until [completeSubmit] is
  /// called — so "a second tap while one is in flight" is deterministic rather
  /// than a sleep-and-hope.
  bool manualSubmit = false;
  final List<Completer<ReceiptSubmissionOutcome>> _pendingSubmits =
      <Completer<ReceiptSubmissionOutcome>>[];

  int get pendingSubmitCount => _pendingSubmits.length;

  void completeSubmit([ReceiptSubmissionOutcome? override]) {
    _pendingSubmits.removeAt(0).complete(override ?? submitOutcome);
  }

  @override
  Future<ReceiptResult<List<ReceiptShop>>> assignedShops() async {
    assignedShopsCallCount++;
    return shopsResult;
  }

  @override
  Future<ReceiptResult<List<ReceiptProduct>>> receiptProducts() async {
    receiptProductsCallCount++;
    return productsResult;
  }

  @override
  Future<ReceiptResult<List<ReceiptSubmission>>> submissions() async {
    submissionsCallCount++;
    return submissionsResult;
  }

  @override
  Future<ReceiptResult<ReceiptSubmission?>> submission(
    String submissionId,
  ) async {
    submissionCallCount++;
    lastRequestedSubmissionId = submissionId;
    return submissionResult;
  }

  @override
  Future<ReceiptSubmissionOutcome> submitReceipt({
    required String shopId,
    required ReceiptFile file,
  }) {
    submitCallCount++;
    lastSubmittedShopId = shopId;
    lastSubmittedFile = file;

    if (manualSubmit) {
      final Completer<ReceiptSubmissionOutcome> completer =
          Completer<ReceiptSubmissionOutcome>();
      _pendingSubmits.add(completer);
      return completer.future;
    }
    return Future<ReceiptSubmissionOutcome>.value(submitOutcome);
  }
}

/// A scriptable [ReceiptImageSource] that needs no platform channel.
class FakeReceiptImageSource implements ReceiptImageSource {
  FakeReceiptImageSource({this.supportsCamera = true});

  @override
  final bool supportsCamera;

  /// What the next [pick] returns. Null models the person cancelling.
  PickedReceiptImage? nextImage = PickedReceiptImage(
    fileName: 'receipt.png',
    bytes: pngBytes(),
  );

  /// When true, [pick] throws instead of returning.
  bool throwOnPick = false;

  int pickCallCount = 0;
  final List<ReceiptImageOrigin> origins = <ReceiptImageOrigin>[];

  @override
  Future<PickedReceiptImage?> pick(ReceiptImageOrigin origin) async {
    pickCallCount++;
    origins.add(origin);
    if (throwOnPick) {
      throw const ReceiptImagePickException('test');
    }
    return nextImage;
  }
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const String shopAUuid = '11111111-2222-3333-4444-555555555555';
const String shopBUuid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const String submissionUuid = '99999999-8888-7777-6666-555555555555';
const String productAUuid = '12121212-3434-5656-7878-909090909090';
const String productBUuid = '21212121-4343-6565-8787-090909090909';

const ReceiptShop shopA = ReceiptShop(
  shopId: shopAUuid,
  shopName: 'Marina Mall',
  shopCode: 'MM-01',
);

/// Deliberately code-less: `retailer_shops.code` is nullable, so the client must
/// render a shop without one.
const ReceiptShop shopB = ReceiptShop(
  shopId: shopBUuid,
  shopName: 'Airport Kiosk',
);

const ReceiptProduct productA = ReceiptProduct(
  productId: productAUuid,
  productCode: 'SKU-100',
  productName: 'Chocolate Bar 50g',
  barcode: '01234567',
  brand: 'Northwind',
);

/// Deliberately without a barcode or a brand: both columns are nullable.
const ReceiptProduct productB = ReceiptProduct(
  productId: productBUuid,
  productCode: 'SKU-200',
  productName: 'Sparkling Water 500ml',
);

final ReceiptSubmission submittedRow = ReceiptSubmission(
  submissionId: submissionUuid,
  shopName: 'Marina Mall',
  shopCode: 'MM-01',
  status: ReceiptSubmissionStatus.submitted,
  originalFileName: 'receipt.png',
  mimeType: 'image/png',
  fileSizeBytes: 24576,
  submittedAt: DateTime.utc(2026, 7, 25, 9, 30),
  createdAt: DateTime.utc(2026, 7, 25, 9, 29),
);

/// The eight-byte PNG signature followed by filler, so the client-side sniffer
/// recognises it without a real encoder.
Uint8List pngBytes({int length = 64}) {
  final Uint8List bytes = Uint8List(length);
  const List<int> signature = <int>[
    0x89,
    0x50,
    0x4e,
    0x47,
    0x0d,
    0x0a,
    0x1a,
    0x0a,
  ];
  for (int i = 0; i < signature.length && i < length; i++) {
    bytes[i] = signature[i];
  }
  return bytes;
}

/// `FF D8 FF` — the JPEG signature.
Uint8List jpegBytes({int length = 32}) {
  final Uint8List bytes = Uint8List(length);
  bytes[0] = 0xff;
  bytes[1] = 0xd8;
  bytes[2] = 0xff;
  return bytes;
}

/// `RIFF....WEBP`.
Uint8List webpBytes() {
  final Uint8List bytes = Uint8List(32);
  const List<int> riff = <int>[0x52, 0x49, 0x46, 0x46];
  const List<int> webp = <int>[0x57, 0x45, 0x42, 0x50];
  for (int i = 0; i < 4; i++) {
    bytes[i] = riff[i];
    bytes[8 + i] = webp[i];
  }
  return bytes;
}

/// A PDF, named and sized like a photograph. The whole point of sniffing.
Uint8List pdfBytes() {
  final Uint8List bytes = Uint8List(32);
  const List<int> magic = <int>[0x25, 0x50, 0x44, 0x46]; // %PDF
  for (int i = 0; i < magic.length; i++) {
    bytes[i] = magic[i];
  }
  return bytes;
}

/// A valid, accepted [ReceiptFile] for tests that start after selection.
ReceiptFile testReceiptFile({String fileName = 'receipt.png'}) => ReceiptFile(
  fileName: fileName,
  bytes: pngBytes(),
  imageType: ReceiptImageType.png,
);

/// A `list_my_assigned_receipt_shops()` body, as PostgREST returns it.
List<Map<String, Object?>> shopRows() => <Map<String, Object?>>[
  <String, Object?>{
    'shop_id': shopAUuid,
    'shop_name': 'Marina Mall',
    'shop_code': 'MM-01',
  },
  <String, Object?>{
    'shop_id': shopBUuid,
    'shop_name': 'Airport Kiosk',
    'shop_code': null,
  },
];

/// A `list_my_receipt_products()` body.
List<Map<String, Object?>> productRows() => <Map<String, Object?>>[
  <String, Object?>{
    'product_id': productAUuid,
    'product_code': 'SKU-100',
    'barcode': '01234567',
    'product_name': 'Chocolate Bar 50g',
    'brand': 'Northwind',
  },
  <String, Object?>{
    'product_id': productBUuid,
    'product_code': 'SKU-200',
    'barcode': null,
    'product_name': 'Sparkling Water 500ml',
    'brand': null,
  },
];

/// A submission row, in the shape both submission RPCs return.
Map<String, Object?> submissionRow({
  String status = 'SUBMITTED',
  Object? submittedAt = '2026-07-25T09:30:00+00:00',
  Object? shopCode = 'MM-01',
}) => <String, Object?>{
  'submission_id': submissionUuid,
  'shop_name': 'Marina Mall',
  'shop_code': shopCode,
  'status': status,
  'original_file_name': 'receipt.png',
  'mime_type': 'image/png',
  'file_size_bytes': 24576,
  'submitted_at': submittedAt,
  'created_at': '2026-07-25T09:29:00+00:00',
};

/// A read that failed the way an unreadable body does.
ReceiptResult<T> unavailableRead<T>() =>
    ReceiptReadFailure<T>(const UnavailableFailure());

/// A read the backend refused with `42501`.
ReceiptResult<T> deniedRead<T>() =>
    ReceiptReadFailure<T>(const DeniedFailure());
