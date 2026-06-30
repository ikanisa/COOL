import 'package:flutter/material.dart';

import 'collect_icons.dart';

class CollectSemanticIcons {
  const CollectSemanticIcons._();

  static const Map<String, IconData> keywordIconMap = {
    'active': CollectIcons.activity,
    'amount': CollectIcons.money,
    'balance': CollectIcons.wallet,
    'blocked': CollectIcons.lock,
    'church': CollectIcons.church,
    'collection': CollectIcons.collections,
    'contribution': CollectIcons.money,
    'football': CollectIcons.sport,
    'group': CollectIcons.collections,
    'group_savings': CollectIcons.savings,
    'ikimina': CollectIcons.savings,
    'member': CollectIcons.people,
    'members': CollectIcons.people,
    'momo': CollectIcons.momo,
    'money': CollectIcons.money,
    'owner': CollectIcons.profile,
    'pending': CollectIcons.pending,
    'private': CollectIcons.lock,
    'public': CollectIcons.public,
    'qr': CollectIcons.qr,
    'receiver': CollectIcons.momo,
    'share': CollectIcons.share,
    'sport': CollectIcons.sport,
    'sports': CollectIcons.sport,
    'support': CollectIcons.support,
    'supporter': CollectIcons.people,
    'supporters': CollectIcons.people,
    'visibility': CollectIcons.visibility,
    'wedding': CollectIcons.wedding,
  };

  static IconData forKeyword(String keyword) {
    final normalized = keyword.trim().toLowerCase().replaceAll(' ', '_');
    return keywordIconMap[normalized] ?? CollectIcons.info;
  }
}
