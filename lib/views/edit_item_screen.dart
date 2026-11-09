import 'package:flutter/material.dart';

import '../models/pantry_item.dart';
import 'widgets/pantry_item_form_screen.dart';

class EditItemScreen extends StatelessWidget {
  const EditItemScreen({super.key, required this.item});

  final PantryItem item;

  @override
  Widget build(BuildContext context) => PantryItemFormScreen(item: item);
}
