import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_state.dart';
import '../../models/product_model.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final List<ProductModel> favProducts = appState.favoriteProducts;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'المنتجات المفضلة ❤️',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
          ),
          iconTheme: const IconThemeData(color: Colors.amber),
        ),
        body: favProducts.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.favorite_border, size: 70, color: Colors.grey[700]),
                    const SizedBox(height: 16),
                    const Text(
                      'ليس لديك أي منتجات في المفضلة حالياً 🛍️',
                      style: TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                  ],
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: favProducts.length,
                itemBuilder: (context, index) {
                  final product = favProducts[index];
                  return Card(
                    color: const Color(0xFF1E1E1E),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.amber.withOpacity(0.2)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(10),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: product.imageUrl.isNotEmpty
                            ? Image.network(product.imageUrl, width: 60, height: 60, fit: BoxFit.cover)
                            : Container(
                                width: 60,
                                height: 60,
                                color: Colors.grey[800],
                                child: const Icon(Icons.fastfood, color: Colors.amber),
                              ),
                      ),
                      title: Text(
                        product.name,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          product.isVariablePrice ? 'حسب الوزن (${product.unit})' : '${product.price} ر.ي',
                          style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.favorite, color: Colors.redAccent),
                        onPressed: () {
                          appState.toggleFavorite(product.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تمت الإزالة من المفضلة 💔')),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
