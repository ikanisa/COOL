part of 'rs_models.dart';

class RsProduct extends Equatable {
  const RsProduct({
    required this.id,
    required this.partnerId,
    required this.name,
    this.description = '',
    required this.category,
    required this.price,
    required this.imageEmoji,
    required this.bgColor,
    required this.stock,
    required this.isActive,
    required this.isNew,
    this.imageUrl,
    this.availableSizes = const <String>[],
    this.badgeLabel,
    this.collection,
    this.sortOrder = 0,
  });

  final String id;
  final String partnerId;
  final String name;
  final String description;
  final ProductCategory category;
  final int price;
  final String imageEmoji;
  final Color bgColor;
  final int stock;
  final bool isActive;
  final bool isNew;
  final String? imageUrl;
  final List<String> availableSizes;
  final String? badgeLabel;
  final String? collection;
  final int sortOrder;

  int discountedPrice(double discountPct) {
    final normalized = discountPct.clamp(0, 100);
    return (price * (1 - normalized / 100)).round();
  }

  factory RsProduct.fromJson(RsJsonMap json) {
    final category = ProductCategoryX.fromValue(
      (json['category'] ?? json['product_category'])?.toString(),
    );

    return RsProduct(
      id: _asString(json['id']),
      partnerId: _asString(json['partner_id'] ?? json['partnerId']),
      name: _asString(json['name'], fallback: 'Shop Item'),
      description: _asString(json['description'] ?? json['short_description']),
      category: category,
      price: _asInt(json['price'] ?? json['price_rwf']),
      imageEmoji: _asString(
        json['image_emoji'] ?? json['imageEmoji'],
        fallback: _defaultEmojiForCategory(category),
      ),
      bgColor: _asColor(
        json['bg_color'] ?? json['bgColor'],
        fallback: category.defaultBackgroundColor,
      ),
      stock: _asInt(
        json['stock'],
        fallback: _asBool(json['in_stock'] ?? json['inStock'], fallback: true)
            ? 99
            : 0,
      ),
      isActive: _asBool(json['is_active'] ?? json['isActive'], fallback: true),
      isNew: _asBool(json['is_new'] ?? json['isNew']),
      imageUrl: _asNullableString(json['image_url'] ?? json['imageUrl']),
      availableSizes:
          _asList(
                json['sizes'] ??
                    json['available_sizes'] ??
                    json['availableSizes'],
              )
              .map((size) => size.toString().trim())
              .where((size) => size.isNotEmpty)
              .toList(growable: false),
      badgeLabel: _asNullableString(json['badge_label'] ?? json['badgeLabel']),
      collection: _asNullableString(json['collection']),
      sortOrder: _asInt(json['sort_order'] ?? json['sortOrder']),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'partner_id': partnerId,
      'name': name,
      'description': description,
      'category': category.value,
      'price': price,
      'image_emoji': imageEmoji,
      'bg_color': bgColor.toARGB32(),
      'stock': stock,
      'is_active': isActive,
      'is_new': isNew,
      'image_url': imageUrl,
      'sizes': availableSizes,
      'badge_label': badgeLabel,
      'collection': collection,
      'sort_order': sortOrder,
    };
  }

  RsProduct copyWith({
    String? id,
    String? partnerId,
    String? name,
    String? description,
    ProductCategory? category,
    int? price,
    String? imageEmoji,
    Color? bgColor,
    int? stock,
    bool? isActive,
    bool? isNew,
    Object? imageUrl = _unset,
    List<String>? availableSizes,
    Object? badgeLabel = _unset,
    Object? collection = _unset,
    int? sortOrder,
  }) {
    return RsProduct(
      id: id ?? this.id,
      partnerId: partnerId ?? this.partnerId,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      price: price ?? this.price,
      imageEmoji: imageEmoji ?? this.imageEmoji,
      bgColor: bgColor ?? this.bgColor,
      stock: stock ?? this.stock,
      isActive: isActive ?? this.isActive,
      isNew: isNew ?? this.isNew,
      imageUrl: identical(imageUrl, _unset)
          ? this.imageUrl
          : imageUrl as String?,
      availableSizes: availableSizes ?? this.availableSizes,
      badgeLabel: identical(badgeLabel, _unset)
          ? this.badgeLabel
          : badgeLabel as String?,
      collection: identical(collection, _unset)
          ? this.collection
          : collection as String?,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [
    id,
    partnerId,
    name,
    description,
    category,
    price,
    imageEmoji,
    bgColor,
    stock,
    isActive,
    isNew,
    imageUrl,
    availableSizes,
    badgeLabel,
    collection,
    sortOrder,
  ];
}

class CartItem extends Equatable {
  const CartItem({
    required this.product,
    required this.quantity,
    required this.selectedVariant,
  });

  final RsProduct product;
  final int quantity;
  final String? selectedVariant;

  factory CartItem.fromJson(RsJsonMap json) {
    final rawProduct = _asMap(json['product']);
    final productJson = rawProduct.isNotEmpty
        ? rawProduct
        : <String, Object?>{
            'id': json['product_id'],
            'name': json['name'],
            'description': json['description'],
            'category': json['category'],
            'price': json['unit_price'] ?? json['price'] ?? json['price_rwf'],
            'image_emoji': json['image_emoji'],
            'image_url': json['image_url'],
            'bg_color': json['bg_color'],
            'sizes': json['sizes'],
          };
    return CartItem(
      product: RsProduct.fromJson(productJson),
      quantity: _asInt(json['quantity'], fallback: 1).clamp(1, 9999),
      selectedVariant: _asNullableString(
        json['selected_variant'] ??
            json['selectedVariant'] ??
            json['selected_size'],
      ),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'product': product.toJson(),
      'quantity': quantity,
      'selected_variant': selectedVariant,
    };
  }

  CartItem copyWith({
    RsProduct? product,
    int? quantity,
    Object? selectedVariant = _unset,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      selectedVariant: identical(selectedVariant, _unset)
          ? this.selectedVariant
          : selectedVariant as String?,
    );
  }

  @override
  List<Object?> get props => [product, quantity, selectedVariant];
}

class RsShopOrder extends Equatable {
  const RsShopOrder({
    required this.id,
    required this.userId,
    required this.items,
    required this.subtotal,
    required this.discountAmount,
    required this.deliveryFee,
    required this.total,
    required this.deliveryAddress,
    required this.momoReference,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final List<CartItem> items;
  final int subtotal;
  final int discountAmount;
  final int deliveryFee;
  final int total;
  final String deliveryAddress;
  final String momoReference;
  final OrderStatus status;
  final DateTime createdAt;

  factory RsShopOrder.fromJson(RsJsonMap json) {
    final items = _asList(
      json['items'],
    ).map((item) => CartItem.fromJson(_asMap(item))).toList(growable: false);
    final subtotal = _asInt(json['subtotal']);
    final discountAmount = _asInt(
      json['discount_amount'] ?? json['discountAmount'] ?? json['discount'],
    );
    final deliveryFee = _asInt(json['delivery_fee'] ?? json['deliveryFee']);

    return RsShopOrder(
      id: _asString(json['id']),
      userId: _asString(json['user_id'] ?? json['userId']),
      items: items,
      subtotal: subtotal,
      discountAmount: discountAmount,
      deliveryFee: deliveryFee,
      total: _asInt(
        json['total'],
        fallback: subtotal - discountAmount + deliveryFee,
      ),
      deliveryAddress: _asString(
        json['delivery_address'] ?? json['deliveryAddress'],
      ),
      momoReference: _asString(json['momo_reference'] ?? json['momoReference']),
      status: OrderStatusX.fromValue((json['status'])?.toString()),
      createdAt:
          _asDateTime(json['created_at'] ?? json['createdAt']) ??
          DateTime.now(),
    );
  }

  RsJsonMap toJson() {
    return <String, Object?>{
      'id': id,
      'user_id': userId,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'delivery_fee': deliveryFee,
      'total': total,
      'delivery_address': deliveryAddress,
      'momo_reference': momoReference,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
    };
  }

  RsShopOrder copyWith({
    String? id,
    String? userId,
    List<CartItem>? items,
    int? subtotal,
    int? discountAmount,
    int? deliveryFee,
    int? total,
    String? deliveryAddress,
    String? momoReference,
    OrderStatus? status,
    DateTime? createdAt,
  }) {
    return RsShopOrder(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      subtotal: subtotal ?? this.subtotal,
      discountAmount: discountAmount ?? this.discountAmount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      total: total ?? this.total,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      momoReference: momoReference ?? this.momoReference,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    userId,
    items,
    subtotal,
    discountAmount,
    deliveryFee,
    total,
    deliveryAddress,
    momoReference,
    status,
    createdAt,
  ];
}
