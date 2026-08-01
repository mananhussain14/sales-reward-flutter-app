import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sale_reward/core/errors/retailer_read_problem.dart';
import 'package:sale_reward/features/campaigns/data/datasources/retailer_campaign_rpc_data_source.dart';
import 'package:sale_reward/features/campaigns/data/datasources/staff_campaign_rpc_data_source.dart';
import 'package:sale_reward/features/campaigns/data/repositories/supabase_retailer_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/data/repositories/supabase_staff_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/retailer_campaign_repository.dart';
import 'package:sale_reward/features/campaigns/domain/repositories/staff_campaign_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/campaign_fakes.dart';

/// Records what each RPC was asked, so a test can prove the client sends the
/// campaign id and **nothing else**.
class _Recorder {
  final List<String> detailIds = <String>[];
  final List<String> productIds = <String>[];
  int listCalls = 0;
}

void main() {
  late _Recorder recorder;

  setUp(() => recorder = _Recorder());

  RetailerCampaignRpcDataSource retailerSource({
    Object? Function()? list,
    Object? Function(String)? detail,
    Object? Function(String)? products,
    Future<Object?> Function()? listFuture,
  }) {
    return RetailerCampaignRpcDataSource(
      campaigns: () {
        recorder.listCalls++;
        if (listFuture != null) {
          return listFuture();
        }
        return Future<Object?>.value(
          list?.call() ?? <Object?>[retailerCampaignRow()],
        );
      },
      detail: (String id) {
        recorder.detailIds.add(id);
        return Future<Object?>.value(
          detail?.call(id) ?? <Object?>[retailerCampaignRow()],
        );
      },
      products: (String id) {
        recorder.productIds.add(id);
        return Future<Object?>.value(
          products?.call(id) ?? <Object?>[campaignProductRow()],
        );
      },
    );
  }

  StaffCampaignRpcDataSource staffSource({
    Object? Function()? list,
    Object? Function(String)? detail,
    Object? Function(String)? products,
  }) {
    return StaffCampaignRpcDataSource(
      campaigns: () {
        recorder.listCalls++;
        return Future<Object?>.value(
          list?.call() ?? <Object?>[staffCampaignRow()],
        );
      },
      detail: (String id) {
        recorder.detailIds.add(id);
        return Future<Object?>.value(
          detail?.call(id) ?? <Object?>[staffCampaignRow()],
        );
      },
      products: (String id) {
        recorder.productIds.add(id);
        return Future<Object?>.value(
          products?.call(id) ?? <Object?>[campaignProductRow()],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  group('the Retailer Owner list read', () {
    test('parses rows into a loaded result', () async {
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(),
          ).campaigns();

      expect(result, isA<RetailerCampaignsLoaded>());
      expect((result as RetailerCampaignsLoaded).campaigns, hasLength(1));
      expect(recorder.listCalls, 1);
    });

    test('an empty list is a success, never a failure', () async {
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(list: () => <Object?>[]),
          ).campaigns();

      expect(result, isA<RetailerCampaignsLoaded>());
      expect((result as RetailerCampaignsLoaded).campaigns, isEmpty);
    });

    test('42501 is a denial, never an empty list', () async {
      // "You may not read this" and "no Vendor targets you" are opposite claims.
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: RetailerCampaignRpcDataSource(
              campaigns: () => Future<Object?>.error(
                const PostgrestException(
                  message: 'Not authorized to view campaigns',
                  code: '42501',
                ),
              ),
              detail: (_) async => null,
              products: (_) async => null,
            ),
          ).campaigns();

      expect(result, isA<RetailerCampaignsFailed>());
      expect(
        (result as RetailerCampaignsFailed).problem,
        RetailerReadProblem.denied,
      );
    });

    test('a transport fault is a network problem, never a denial', () async {
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: RetailerCampaignRpcDataSource(
              campaigns: () =>
                  Future<Object?>.error(http.ClientException('no route')),
              detail: (_) async => null,
              products: (_) async => null,
            ),
          ).campaigns();

      expect(
        (result as RetailerCampaignsFailed).problem,
        RetailerReadProblem.network,
      );
    });

    test('a malformed body is malformed, never an empty list', () async {
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(
              list: () => <Object?>[retailerCampaignRow(derivedState: 'NOPE')],
            ),
          ).campaigns();

      expect(
        (result as RetailerCampaignsFailed).problem,
        RetailerReadProblem.malformed,
      );
    });

    test('a stalled call is abandoned as a timeout', () async {
      final Completer<Object?> never = Completer<Object?>();
      addTearDown(() => never.complete(<Object?>[]));

      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(listFuture: () => never.future),
            timeout: const Duration(milliseconds: 10),
          ).campaigns();

      expect(
        (result as RetailerCampaignsFailed).problem,
        RetailerReadProblem.timeout,
      );
    });

    test('no backend message text survives the boundary', () async {
      final RetailerCampaignsResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: RetailerCampaignRpcDataSource(
              campaigns: () => Future<Object?>.error(
                const PostgrestException(
                  message:
                      'permission denied for table public.campaign_versions',
                  code: '42501',
                  details: 'policy campaign_versions_select',
                ),
              ),
              detail: (_) async => null,
              products: (_) async => null,
            ),
          ).campaigns();

      // A discriminant, and nothing else. No table, column, function or policy
      // name can reach a screen through it.
      expect(result, isA<RetailerCampaignsFailed>());
      expect(
        (result as RetailerCampaignsFailed).problem.toString(),
        isNot(contains('campaign_versions')),
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the Retailer Owner detail read', () {
    test('sends exactly the campaign id, and reads products after', () async {
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(),
          ).campaignDetail(campaignIdA);

      expect(result, isA<RetailerCampaignDetailLoaded>());
      expect(recorder.detailIds, <String>[campaignIdA]);
      expect(recorder.productIds, <String>[campaignIdA]);
      // The list read is not touched by opening a detail.
      expect(recorder.listCalls, 0);
    });

    test('zero rows is Missing, and skips the product read', () async {
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(detail: (_) => <Object?>[]),
          ).campaignDetail(campaignIdA);

      expect(result, isA<RetailerCampaignDetailMissing>());
      // No second round trip for an address that answered nothing.
      expect(recorder.productIds, isEmpty);
    });

    test('a malformed id is Missing, and issues no request at all', () async {
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(),
          ).campaignDetail('not-a-uuid');

      // The same answer an unknown id gets, so a mistyped address cannot be
      // told from a real one — and no malformed selector reaches PostgREST.
      expect(result, isA<RetailerCampaignDetailMissing>());
      expect(recorder.detailIds, isEmpty);
      expect(recorder.productIds, isEmpty);
    });

    test('an empty id is Missing', () async {
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(),
          ).campaignDetail('');

      expect(result, isA<RetailerCampaignDetailMissing>());
      expect(recorder.detailIds, isEmpty);
    });

    test('an unknown id and another Retailer\'s id are one answer', () async {
      // The backend returns zero rows for both, so both land here identically.
      // Distinguishing them would rebuild the existence oracle SQL denies.
      final RetailerCampaignDetailResult unknown =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(detail: (_) => <Object?>[]),
          ).campaignDetail(campaignIdA);
      final RetailerCampaignDetailResult foreign =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(detail: (_) => <Object?>[]),
          ).campaignDetail(campaignIdB);

      expect(unknown.runtimeType, foreign.runtimeType);
      expect(unknown, isA<RetailerCampaignDetailMissing>());
    });

    test('an empty product list is loaded, not a failure', () async {
      // The zero-eligible-product state. A real answer.
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: retailerSource(products: (_) => <Object?>[]),
          ).campaignDetail(campaignIdA);

      expect(result, isA<RetailerCampaignDetailLoaded>());
      expect((result as RetailerCampaignDetailLoaded).products, isEmpty);
    });

    test('a failed product read is a failure, not an empty list', () async {
      // Fabricating an empty list would put the prominent zero-eligible warning
      // on a campaign whose products simply could not be read.
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: RetailerCampaignRpcDataSource(
              campaigns: () async => <Object?>[],
              detail: (_) async => <Object?>[retailerCampaignRow()],
              products: (_) =>
                  Future<Object?>.error(http.ClientException('gone')),
            ),
          ).campaignDetail(campaignIdA);

      expect(result, isA<RetailerCampaignDetailFailed>());
      expect(
        (result as RetailerCampaignDetailFailed).problem,
        RetailerReadProblem.network,
      );
    });

    test('a denial on the detail is a failure, not Missing', () async {
      final RetailerCampaignDetailResult result =
          await SupabaseRetailerCampaignRepository(
            rpc: RetailerCampaignRpcDataSource(
              campaigns: () async => <Object?>[],
              detail: (_) => Future<Object?>.error(
                const PostgrestException(message: 'no', code: '42501'),
              ),
              products: (_) async => <Object?>[],
            ),
          ).campaignDetail(campaignIdA);

      expect(
        (result as RetailerCampaignDetailFailed).problem,
        RetailerReadProblem.denied,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('the Sales Staff reads', () {
    test('the list parses', () async {
      final StaffCampaignsResult result = await SupabaseStaffCampaignRepository(
        rpc: staffSource(),
      ).campaigns();

      expect(result, isA<StaffCampaignsLoaded>());
      expect((result as StaffCampaignsLoaded).campaigns, hasLength(1));
    });

    test('42501 is a denial', () async {
      final StaffCampaignsResult result = await SupabaseStaffCampaignRepository(
        rpc: StaffCampaignRpcDataSource(
          campaigns: () => Future<Object?>.error(
            const PostgrestException(message: 'no', code: '42501'),
          ),
          detail: (_) async => null,
          products: (_) async => null,
        ),
      ).campaigns();

      expect(
        (result as StaffCampaignsFailed).problem,
        RetailerReadProblem.denied,
      );
    });

    test('the detail sends exactly the campaign id', () async {
      await SupabaseStaffCampaignRepository(
        rpc: staffSource(),
      ).campaignDetail(campaignIdB);

      expect(recorder.detailIds, <String>[campaignIdB]);
      expect(recorder.productIds, <String>[campaignIdB]);
    });

    test('a paused campaign is Missing, exactly like an unknown id', () async {
      // `get_my_staff_campaign()` re-applies the ACTIVE/SCHEDULED filter, so a
      // paused campaign returns zero rows. A seller must not be able to learn
      // that it exists but has been paused.
      final StaffCampaignDetailResult paused =
          await SupabaseStaffCampaignRepository(
            rpc: staffSource(detail: (_) => <Object?>[]),
          ).campaignDetail(campaignIdA);

      expect(paused, isA<StaffCampaignDetailMissing>());
    });

    test('a malformed id issues no request', () async {
      final StaffCampaignDetailResult result =
          await SupabaseStaffCampaignRepository(
            rpc: staffSource(),
          ).campaignDetail('../../admin');

      expect(result, isA<StaffCampaignDetailMissing>());
      expect(recorder.detailIds, isEmpty);
    });

    test('a malformed body is malformed, never an empty list', () async {
      final StaffCampaignsResult result = await SupabaseStaffCampaignRepository(
        rpc: staffSource(
          list: () => <Object?>[staffCampaignRow(ruleType: 'PERCENT')],
        ),
      ).campaigns();

      expect(
        (result as StaffCampaignsFailed).problem,
        RetailerReadProblem.malformed,
      );
    });
  });
}
