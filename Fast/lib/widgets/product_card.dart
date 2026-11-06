import 'package:flutter/material.dart';

import '../models/product_model.dart';
import '../utils/constants.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onAdd;

  const ProductCard({super.key, required this.product, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final unavailable = !product.available;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          SizedBox(
            width: 108,
            height: 112,
            child: product.imageUrl.isEmpty
                ? const Icon(Icons.shopping_bag_outlined, size: 42, color: AppConstants.gold)
                : Image.network(
                    product.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.image_not_supported_outlined, size: 36, color: Colors.grey),
                    loadingBuilder: (context, child, progress) => progress == null
                        ? child
                        : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(product.restaurantName, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 7),
                  Text('${product.price} ر.ي / ${product.unit}',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  if (unavailable)
                    const Text('غير متوفر حالياً', style: TextStyle(color: Colors.redAccent, fontSize: 12))
                  else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: onAdd,
                        icon: const Icon(Icons.add_shopping_cart, size: 18),
                        label: const Text('إضافة للسلة'),
                        style: TextButton.styleFrom(foregroundColor: AppConstants.gold),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
