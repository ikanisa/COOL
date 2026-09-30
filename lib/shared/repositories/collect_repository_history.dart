part of 'collect_repository.dart';

final memberHistoryProvider = StateNotifierProvider.autoDispose
    .family<MemberHistoryController, MemberHistoryState, MemberHistoryQuery>((
      ref,
      query,
    ) {
      // Replacing the repository must dispose the old controller even when the
      // new repository happens to publish an equal state-selection tuple.
      final repository = ref.watch(collectRepositoryProvider.notifier);
      ref.watch(
        collectRepositoryProvider.select(
          (state) => (
            state.currentProfile?.id,
            state.lastSuccessfulSyncAt,
            state.usingStaleCache,
          ),
        ),
      );
      return MemberHistoryController(repository, query);
    });

class MemberHistoryState {
  const MemberHistoryState({this.page, this.loading = false, this.error});
  final MemberHistoryPage? page;
  final bool loading;
  final String? error;
}

class MemberHistoryController extends StateNotifier<MemberHistoryState> {
  MemberHistoryController(this.repository, this.query)
    : _ownerProfileId = repository.state.currentProfile?.id,
      _ownerAuthId = repository._supabase?.auth.currentUser?.id,
      super(const MemberHistoryState()) {
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
  final String? _ownerProfileId;
  final String? _ownerAuthId;
  int _generation = 0;
  Timer? _debounce;
  bool _refreshing = false;
  bool _refreshRequired = false;

  bool _contextCurrent() {
    if (!mounted) return false;
    if (!repository.mounted ||
        repository.state.currentProfile?.id != _ownerProfileId ||
        repository._supabase?.auth.currentUser?.id != _ownerAuthId) {
      ++_generation;
      _debounce?.cancel();
      _refreshing = false;
      _refreshRequired = false;
      // Never retain the old account's records in a stale controller.
      state = const MemberHistoryState(
        error: 'Account changed. Reload history.',
      );
      return false;
    }
    return true;
  }

  bool _canPublish(int generation) =>
      mounted && generation == _generation && _contextCurrent();

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> refresh() async {
    if (!_contextCurrent() || _refreshing) return;
    _debounce?.cancel();
    _refreshing = true;
    _refreshRequired = false;
    final generation = ++_generation;
    state = const MemberHistoryState(loading: true);
    try {
      final page = await repository.fetchHistoryPage(query);
      if (!_canPublish(generation)) return;
      if (repository.isLive) page.validateRequest(query: query);
      state = MemberHistoryState(page: page);
    } catch (_) {
      if (_canPublish(generation)) {
        state = const MemberHistoryState(
          error: 'Connect to load the complete history.',
        );
      }
    } finally {
      if (mounted && generation == _generation) _refreshing = false;
    }
  }

  Future<void> loadMore() async {
    if (!_contextCurrent() || _refreshRequired) return;
    final page = state.page;
    if (state.loading || page?.nextCursor == null) return;
    final generation = ++_generation;
    state = MemberHistoryState(page: page, loading: true);
    try {
      final next = await repository.fetchHistoryPage(
        query,
        cursor: page!.nextCursor,
      );
      if (_canPublish(generation)) {
        state = MemberHistoryState(page: page.append(next, query: query));
      }
    } catch (error) {
      if (_canPublish(generation)) {
        final changed =
            error is FormatException ||
            (error is PostgrestException && error.code == 'P0001');
        _refreshRequired = changed;
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
