import 'collect_models.dart';

part 'collect_group_cover_catalog.dart';

/// Versioned references use the existing persisted image_url field. They are
/// resolved only against this allowlist, never interpreted as arbitrary paths.
class CollectGroupCover {
  const CollectGroupCover({
    required this.id,
    required this.version,
    required this.name,
    required this.family,
    required this.theme,
    required this.types,
    required this.terms,
    required this.context,
    required this.namedGroup,
    required this.generalDefault,
    required this.priority,
    required this.focalX,
    required this.focalY,
  });
  final String id, name, family, theme;
  final int version, priority;
  final List<String> types, terms;
  final String? context, namedGroup;
  final bool generalDefault;
  final double focalX, focalY;
  String get reference => 'collect-cover:$id:v$version';
  String get asset => 'assets/group_covers/rwanda/covers/$id-v$version.webp';
  String get thumbnail =>
      'assets/group_covers/rwanda/thumbs/$id-v$version.webp';

  static CollectGroupCover? resolve(String? reference) {
    for (final cover in collectGroupCovers) {
      if (cover.reference == reference) return cover;
    }
    return null;
  }

  static List<CollectGroupCover> suggestions({
    CollectionType? type,
    String? family,
    String? context,
    String query = '',
    bool browseAll = false,
  }) {
    final active = {?context, if (type == CollectionType.church) 'christian'};
    final search = _words(query);
    final result = collectGroupCovers.where((cover) {
      if (cover.namedGroup != null) return false;
      if (cover.context != null && !active.contains(cover.context)) {
        return false;
      }
      if (family != null && cover.family != family) return false;
      if (!browseAll &&
          type != null &&
          !cover.types.contains(type.storageValue)) {
        return false;
      }
      final terms = _words('${cover.name} ${cover.terms.join(' ')}');
      return search.every(terms.contains);
    }).toList();
    result.sort((a, b) {
      final byPriority = b.priority.compareTo(a.priority);
      return byPriority != 0 ? byPriority : a.id.compareTo(b.id);
    });
    return result;
  }

  /// Governed platform slugs, public approval and sponsorship are all required.
  /// A title match alone never receives a named cover. Saved media wins upstream.
  static CollectGroupCover? fallbackFor(CollectCollection collection) {
    if (collection.isPublic && collection.isPlatformSponsored) {
      final named = switch (collection.slug) {
        'buri-munsi' => 'buri_munsi',
        'gikundiro' => 'gikundiro',
        _ => null,
      };
      if (named != null) {
        return collectGroupCovers.firstWhere((c) => c.namedGroup == named);
      }
    }
    final choices = suggestions(
      type: collection.collectionType,
    ).where((c) => c.generalDefault && c.context == null).toList();
    if (choices.isEmpty) return null;
    final seed = collection.id.codeUnits.fold<int>(
      0,
      (v, u) => ((v * 31) + u) & 0x7fffffff,
    );
    return choices[seed % choices.length];
  }
}

const collectCoverFamilies = <String, String>{
  'savings_livelihoods': 'Savings & livelihoods',
  'weddings': 'Weddings',
  'faith_giving': 'Faith & giving',
  'family_solidarity': 'Family & support',
  'education': 'Education & skills',
  'community_projects': 'Community projects',
  'sport_culture': 'Sport & culture',
  'diaspora': 'Diaspora',
};
const collectCoverContexts = <String, String>{
  'christian': 'Christian giving',
  'muslim': 'Muslim giving',
  'bereavement': 'Bereavement',
  'health': 'Healthcare support',
  'new_baby': 'Welcoming a baby',
};

Set<String> _words(String value) {
  const accents = {
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  var folded = value.toLowerCase();
  accents.forEach((from, to) => folded = folded.replaceAll(from, to));
  return RegExp(
    r'[a-z0-9]+',
  ).allMatches(folded).map((m) => m.group(0)!).toSet();
}
