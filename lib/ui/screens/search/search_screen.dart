import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repo/search_queries.dart';
import '../../format/tr_format.dart';
import '../../providers/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Global arama (SPEC §24).
///
/// Ana sayfadaki büyüteç buraya bağlıydı ama **rota tanımlı değildi** —
/// düğme hiçbir şey yapmıyordu.
///
/// Arama Türkçe normalize edilmiş kopyalar üzerinden yapılır: "sisli"
/// yazınca "Şişli" bulunur, "ı/i" ayrımı sorun çıkarmaz.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Müşteri, tedarikçi, ürün, belge…',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              icon: const Icon(Icons.close),
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: _query.trim().length < 2
          ? const EmptyState(
              icon: Icons.search,
              title: 'Aramak için yazın',
              description:
                  'En az iki harf. Müşteri ve tedarikçi unvanı, ürün adı '
                  'veya belge numarası aranır.',
            )
          : results.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(error: e),
              data: (hits) => hits.isEmpty
                  ? EmptyState(
                      icon: Icons.search_off,
                      title: '"$_query" için sonuç yok',
                      description: 'Farklı bir kelime deneyin.',
                    )
                  : ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final hit = hits[i];
                        return ListTile(
                          leading: Icon(_iconFor(hit.kind)),
                          title: Text(hit.title),
                          subtitle: Text(
                            '${hit.kind} · ${hit.subtitle}',
                            style: context.labelStyle,
                          ),
                          trailing: hit.amount == null
                              ? const Icon(Icons.chevron_right, size: 18)
                              : Text(
                                  TrFormat.moneyWithCurrency(hit.amount!),
                                  style: context.numberStyle,
                                ),
                          onTap: () => context.push(hit.route),
                        );
                      },
                    ),
            ),
    );
  }

  /// `kind` alanı Türkçe geliyor (search_queries.dart).
  static IconData _iconFor(String kind) => switch (kind) {
    'Müşteri' => Icons.person_outline,
    'Tedarikçi' => Icons.local_shipping_outlined,
    'Ürün' => Icons.category_outlined,
    'Satış' => Icons.receipt_long,
    _ => Icons.description_outlined,
  };
}

final searchProvider = FutureProvider.autoDispose
    .family<List<SearchHit>, String>((ref, query) async {
      if (query.trim().length < 2) return const [];
      final db = await ref.watch(databaseProvider.future);
      return db.globalSearch(query);
    });
