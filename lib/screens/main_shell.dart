import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../utils/constants.dart';
import 'app_drawer.dart';
import 'cart_screen.dart';
import 'home_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  final GlobalKey<ScaffoldState> _shellScaffoldKey = GlobalKey<ScaffoldState>();

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
    _shellScaffoldKey.currentState?.closeDrawer();
  }

  void _openDrawer() => _shellScaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final cartCount = context.select<AppState, int>((state) => state.totalCartItemsCount);
    
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        key: _shellScaffoldKey,
        backgroundColor: const Color(0xFF121212),
        drawer: AppDrawer(onNavigate: _navigateTo),
        body: IndexedStack(
          index: _currentIndex,
          children: const [
            HomeScreen(),
            CartScreen(),
            OrdersScreen(),
            ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF1E1E1E),
          indicatorColor: AppConstants.gold.withOpacity(0.3),
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.storefront, color: Colors.grey),
              selectedIcon: Icon(Icons.storefront, color: AppConstants.gold),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: cartCount > 0, 
                label: Text('$cartCount'), 
                child: const Icon(Icons.shopping_cart, color: Colors.grey),
              ),
              selectedIcon: Badge(
                isLabelVisible: cartCount > 0, 
                label: Text('$cartCount'), 
                child: const Icon(Icons.shopping_cart, color: AppConstants.gold),
              ),
              label: 'السلة',
            ),
            const NavigationDestination(
              icon: Icon(Icons.receipt_long, color: Colors.grey),
              selectedIcon: Icon(Icons.receipt_long, color: AppConstants.gold),
              label: 'طلباتي',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline, color: Colors.grey),
              selectedIcon: Icon(Icons.person, color: AppConstants.gold),
              label: 'حسابي',
            ),
          ],
        ),
      ),
    );
  }
}
