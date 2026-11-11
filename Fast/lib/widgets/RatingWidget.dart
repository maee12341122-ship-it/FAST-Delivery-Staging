import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RatingDialogWidget extends StatefulWidget {
  final int orderId;
  final String customerPhone;
  final String targetId;
  final String targetType; // 'courier' أو 'restaurant' أو 'app'

  const RatingDialogWidget({
    Key? key,
    required this.orderId,
    required this.customerPhone,
    required this.targetId,
    required this.targetType,
  }) : super(key: key);

  @override
  _RatingDialogWidgetState createState() => _RatingDialogWidgetState();
}

class _RatingDialogWidgetState extends State<RatingDialogWidget> {
  int _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitRating() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;

      await supabase.from('ratings').insert({
        'order_id': widget.orderId,
        'customer_phone': widget.customerPhone,
        'target_id': widget.targetId,
        'target_type': widget.targetType,
        'rating': _rating,
        'comment': _commentController.text.trim(),
      });

      Navigator.of(context).pop(true); // إغلاق النافذة بنجاح
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('شكراً لك! تم إرسال تقييمك بنجاح')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الإرسال: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تقييم الخدمة', textAlign: TextAlign.center),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ما رأيك في جودة الخدمة المقدمة؟'),
            const SizedBox(height: 16),
            // أيقونات النجوم التفاعلية
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return IconButton(
                  icon: Icon(
                    index < _rating ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed: () {
                    setState(() {
                      _rating = index + 1;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب تعليقك هنا (اختياري)...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submitRating,
          child: _isLoading
              ? const CircularProgressIndicator(color: Colors.white)
              : const Text('إرسال التقييم'),
        ),
      ],
    );
  }
}
