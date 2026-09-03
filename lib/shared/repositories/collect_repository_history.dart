part of 'collect_repository.dart';

final memberHistoryProvider = StateNotifierProvider.autoDispose
    .family<MemberHistoryController, MemberHistoryState, MemberHistoryQuery>((
      ref,
      query,
    ) {
      ref.watch(
        collectRepositoryProvider.select(
          (state) => (
            state.currentProfile?.id,
            state.lastSuccessfulSyncAt,
            state.usingStaleCache,
          ),
        ),
      );
      return MemberHistoryController(
        ref.read(collectRepositoryProvider.notifier),
        query,
      );
    });

class MemberHistoryState {
  const MemberHistoryState({this.page, this.loading = false, this.error});
  final MemberHistoryPage? page;
  final bool loading;
  final String? error;
}

class MemberHistoryController extends StateNotifier<MemberHistoryState> {
  MemberHistoryController(this.repository, this.query)
    : super(const MemberHistoryState()) {
    final initial = repository.state.historyPage;
    if (!repository.isLive && initial == null) {
      state = MemberHistoryState(page: repository.localHistoryPage(query));
    } else if (query.isDefault && initial != null) {
      state = MemberHistoryState(page: initial);
    } else {
      if (query.search.isNotEmpty && repository.isLive) {
        state = const MemberHistoryState(loading: true);
        _debounce = Timer(const Duration(milliseconds: 300), refresh);
      } else {
        unawaited(refresh());
      }
    }
  }

  final CollectRepository repository;
  final MemberHistoryQuery query;
  int _generation = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    _debounce?.cancel();
    final generation = ++_generation;
    state = const MemberHistoryState(loading: true);
    try {
      final page = await repository.fetchHistoryPage(query);
      if (mounted && generation == _generation) {
        state = MemberHistoryState(page: page);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        state = const MemberHistoryState(
          error: 'Connect to load the complete history.',
        );
      }
    }
  }

  Future<void> loadMore() async {
    final page = state.page;
    if (state.loading || page?.nextCursor == null) return;
    final generation = ++_generation;
    state = MemberHistoryState(page: page, loading: true);
    try {
      final next = await repository.fetchHistoryPage(
        query,
        cursor: page!.nextCursor,
      );
      if (mounted && generation == _generation) {
        state = MemberHistoryState(page: page.append(next));
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        final changed =
            error is FormatException ||
            (error is PostgrestException && error.code == 'P0001');
        state = MemberHistoryState(
          page: page,
          error: changed
              ? 'History changed. Refresh to continue.'
              : 'Could not load more. Try again.',
        );
      }
    }
  }
}
